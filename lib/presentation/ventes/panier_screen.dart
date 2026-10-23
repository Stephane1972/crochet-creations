import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/calculs/totaux.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import 'panier_provider.dart';
import 'recap_widgets.dart';
import 'selecteur_client.dart';

/// Comment la vente est réglée au moment de la validation.
enum FormulePaiement {
  tout('Payée'),
  acompte('Acompte'),
  plusTard('Plus tard');

  const FormulePaiement(this.libelle);
  final String libelle;
}

/// Panier et récapitulatif (écran 9) : articles et quantités, remise, frais de port, paiement,
/// puis validation de la vente.
class PanierScreen extends ConsumerStatefulWidget {
  const PanierScreen({super.key});

  @override
  ConsumerState<PanierScreen> createState() => _PanierScreenState();
}

class _PanierScreenState extends ConsumerState<PanierScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  final TextEditingController _remise = TextEditingController();
  final TextEditingController _frais = TextEditingController();
  final TextEditingController _acompte = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  FormulePaiement _formule = FormulePaiement.tout;
  ModePaiement _mode = ModePaiement.especes;
  bool _enCours = false;

  /// La vente est enregistrée et le panier vidé : en attendant que la confirmation s'affiche,
  /// l'écran ne montre pas « Le panier est vide ».
  bool _validee = false;

  @override
  void initState() {
    super.initState();
    // Le panier survit à la fermeture de l'écran : on reprend ce qui a déjà été saisi.
    final VenteEnCours vente = ref.read(venteEnCoursProvider);
    final Panier panier = vente.panier;
    if (panier.remiseType != RemiseType.aucune && panier.remiseValeur > 0) {
      _remise.text = formatMontantSaisie(panier.remiseValeur);
    }
    if (panier.fraisPortCentimes > 0) _frais.text = formatMontantSaisie(panier.fraisPortCentimes);
    _notes.text = vente.notes;
  }

  @override
  void dispose() {
    _remise.dispose();
    _frais.dispose();
    _acompte.dispose();
    _notes.dispose();
    super.dispose();
  }

  VenteEnCoursNotifier get _actions => ref.read(venteEnCoursProvider.notifier);

  /// Exécute un changement du panier ; un refus (stock...) est affiché sans rien changer.
  void _essayer(void Function() action) {
    try {
      action();
    } on ErreurMetier catch (erreur) {
      afficherMessage(context, erreur.message);
    }
  }

  void _surRemise() {
    final RemiseType type = ref.read(venteEnCoursProvider).panier.remiseType;
    final String texte = _remise.text.trim();
    final int? valeur = texte.isEmpty ? 0 : parseMontantEuros(texte);
    if (valeur != null) _actions.definirRemise(type, valeur);
  }

  void _choisirTypeRemise(RemiseType type) {
    if (type == RemiseType.aucune) _remise.clear();
    final String texte = _remise.text.trim();
    final int valeur = type == RemiseType.aucune ? 0 : (texte.isEmpty ? 0 : (parseMontantEuros(texte) ?? 0));
    _actions.definirRemise(type, valeur);
  }

  void _surFrais() {
    final String texte = _frais.text.trim();
    final int? centimes = texte.isEmpty ? 0 : parseMontantEuros(texte);
    if (centimes != null) _essayer(() => _actions.definirFraisPort(centimes));
  }

  /// Le paiement à enregistrer ; `null` = vente à payer plus tard. Lance [DonneeInvalide] si l'acompte est incorrect.
  PaiementSaisi? _paiement(int totalCentimes) {
    if (totalCentimes <= 0) return null;
    switch (_formule) {
      case FormulePaiement.tout:
        return PaiementSaisi(mode: _mode, montantCentimes: totalCentimes);
      case FormulePaiement.acompte:
        final int? montant = parseMontantEuros(_acompte.text);
        if (montant == null || montant <= 0) {
          throw const DonneeInvalide('Indiquez le montant de l’acompte.');
        }
        return PaiementSaisi(mode: _mode, montantCentimes: montant);
      case FormulePaiement.plusTard:
        return null;
    }
  }

  /// Totaux et paiement de la vente ; `null` (avec un message) si quelque chose est incorrect.
  ({TotauxDocument totaux, PaiementSaisi? paiement})? _preparer(VenteEnCours vente) {
    try {
      final TotauxDocument totaux = vente.panier.totaux;
      return (totaux: totaux, paiement: _paiement(totaux.totalCentimes));
    } on ErreurMetier catch (erreur) {
      afficherMessage(context, erreur.message);
      return null;
    }
  }

  Future<void> _valider() async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    final VenteEnCours vente = ref.read(venteEnCoursProvider);
    final ({TotauxDocument totaux, PaiementSaisi? paiement})? preparation = _preparer(vente);
    if (preparation == null) return;
    final TotauxDocument totaux = preparation.totaux;
    final PaiementSaisi? paiement = preparation.paiement;

    final int articles = vente.panier.nombreArticles;
    final bool ok = await confirmer(
      context,
      titre: 'Valider cette vente ?',
      message:
          '${articles == 1 ? '1 article' : '$articles articles'} pour ${formatEuros(totaux.totalCentimes)}. '
          'Le stock sera mis à jour. Une vente validée ne se modifie plus : en cas d’erreur, '
          'vous pourrez l’annuler.',
      libelleConfirmer: 'Valider la vente',
      libelleAnnuler: 'Revenir au panier',
    );
    if (!ok || !mounted) return;

    setState(() => _enCours = true);
    try {
      final Vente validee = await ref
          .read(venteRepositoryProvider)
          .valider(
            clientId: vente.client?.id,
            panier: vente.panier,
            paiement: paiement,
            notes: vente.notes,
          );
      if (!mounted) return;
      setState(() => _validee = true);
      _actions.vider();
      await Navigator.of(context).pushReplacementNamed(AppRoutes.venteConfirmation, arguments: validee.id);
    } catch (erreur, pile) {
      debugPrint('Validation de la vente impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VenteEnCours vente = ref.watch(venteEnCoursProvider);
    final Panier panier = vente.panier;
    if (_validee) return Scaffold(appBar: AppBar(title: const Text('Panier')));

    return Scaffold(
      appBar: AppBar(title: const Text('Panier')),
      body: panier.estVide ? _PanierVide(onRetour: () => Navigator.of(context).pop()) : _corps(context, panier),
      bottomNavigationBar: panier.estVide ? null : _barreValidation(context, panier),
    );
  }

  Widget _corps(BuildContext context, Panier panier) {
    final ThemeData theme = Theme.of(context);
    final String? problemeRemise = panier.problemeRemise;
    final TotauxDocument? totaux = problemeRemise == null ? panier.totaux : null;

    return Form(
      key: _formulaire,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          const SelecteurClient(),
          const SizedBox(height: 16),
          Text('Articles', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final LignePanier ligne in panier.lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CarteLigne(
                ligne: ligne,
                onQuantite: (int q) => _essayer(() => _actions.changerQuantite(ligne.idLigne, q)),
                onRetirer: () => _actions.retirer(ligne.idLigne),
              ),
            ),
          const SizedBox(height: 8),
          CarteRubrique(
            titre: 'Remise et frais de port',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SegmentedButton<RemiseType>(
                  segments: const <ButtonSegment<RemiseType>>[
                    ButtonSegment<RemiseType>(value: RemiseType.aucune, label: Text('Pas de remise')),
                    ButtonSegment<RemiseType>(value: RemiseType.pourcentage, label: Text('En %')),
                    ButtonSegment<RemiseType>(value: RemiseType.montant, label: Text('En €')),
                  ],
                  selected: <RemiseType>{panier.remiseType},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<RemiseType> choix) => _choisirTypeRemise(choix.first),
                ),
                if (panier.remiseType != RemiseType.aucune) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _remise,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: panier.remiseType == RemiseType.pourcentage
                          ? 'Remise (%)'
                          : 'Remise (€)',
                    ),
                    onChanged: (String _) => _surRemise(),
                    validator: (String? v) => validerMontantFacultatif(v) == null
                        ? null
                        : 'Valeur invalide (exemple : 10 ou 12,5).',
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _frais,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Frais de port (€)', hintText: '0'),
                  onChanged: (String _) => _surFrais(),
                  validator: validerMontantFacultatif,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CarteRubrique(
            titre: 'Paiement',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SegmentedButton<FormulePaiement>(
                  segments: <ButtonSegment<FormulePaiement>>[
                    for (final FormulePaiement f in FormulePaiement.values)
                      ButtonSegment<FormulePaiement>(value: f, label: Text(f.libelle)),
                  ],
                  selected: <FormulePaiement>{_formule},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<FormulePaiement> choix) => setState(() => _formule = choix.first),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (_formule) {
                    FormulePaiement.tout => 'La vente est réglée en totalité maintenant.',
                    FormulePaiement.acompte => 'Une partie est réglée maintenant, le solde sera encaissé plus tard.',
                    FormulePaiement.plusTard => 'Rien n’est encaissé : la vente reste impayée jusqu’au règlement.',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (_formule != FormulePaiement.plusTard) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ModePaiement>(
                    initialValue: _mode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Mode de paiement'),
                    items: <DropdownMenuItem<ModePaiement>>[
                      for (final ModePaiement m in ModePaiement.values)
                        DropdownMenuItem<ModePaiement>(value: m, child: Text(m.libelle)),
                    ],
                    onChanged: (ModePaiement? valeur) {
                      if (valeur != null) setState(() => _mode = valeur);
                    },
                  ),
                ],
                if (_formule == FormulePaiement.acompte) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _acompte,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Montant de l’acompte (€)'),
                    validator: (String? v) => validerMontantObligatoire(v, 'Indiquez le montant de l’acompte.'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Note sur la vente (facultatif)'),
            onChanged: _actions.definirNotes,
          ),
          const SizedBox(height: 16),
          CarteRubrique(
            titre: 'Récapitulatif',
            child: Column(
              children: <Widget>[
                LigneMontant(
                  libelle: 'Sous-total',
                  montant: formatEuros(
                    totaux?.sousTotalCentimes ??
                        panier.lignes.fold(0, (int somme, LignePanier l) => somme + l.totalCentimes),
                  ),
                ),
                if (totaux != null && totaux.remiseCentimes > 0)
                  LigneMontant(libelle: 'Remise', montant: '−${formatEuros(totaux.remiseCentimes)}'),
                if (totaux != null && totaux.fraisPortCentimes > 0)
                  LigneMontant(libelle: 'Frais de port', montant: formatEuros(totaux.fraisPortCentimes)),
                const Divider(),
                if (totaux != null)
                  LigneMontant(libelle: 'Total', montant: formatEuros(totaux.totalCentimes), fort: true)
                else
                  Text(
                    problemeRemise!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Pas de TVA : ces prix sont des prix nets (TVA non applicable, article 293 B du CGI).',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreValidation(BuildContext context, Panier panier) {
    final String? probleme = panier.problemeRemise;
    final String libelle = probleme == null
        ? 'Valider la vente · ${formatEuros(panier.totaux.totalCentimes)}'
        : 'Valider la vente';
    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_enCours || probleme != null) ? null : _valider,
              icon: _enCours
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(libelle),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanierVide extends StatelessWidget {
  const _PanierVide({required this.onRetour});

  final VoidCallback onRetour;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.shopping_basket_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Le panier est vide', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Ajoutez des articles depuis l’onglet Vente.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetour, child: const Text('Ajouter des articles')),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du panier : désignation, quantité (− / +), total, bouton « retirer ».
class _CarteLigne extends StatelessWidget {
  const _CarteLigne({required this.ligne, required this.onQuantite, required this.onRetirer});

  final LignePanier ligne;
  final void Function(int quantite) onQuantite;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final int? stock = ligne.stockDisponible;
    final bool stockAtteint = stock != null && ligne.quantite >= stock;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(ligne.designation, style: theme.textTheme.titleSmall),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Retirer « ${ligne.designation} » du panier',
                  onPressed: onRetirer,
                ),
              ],
            ),
            if (ligne.description != null)
              Text(ligne.description!, style: theme.textTheme.bodySmall?.copyWith(color: discret)),
            Row(
              children: <Widget>[
                IconButton.outlined(
                  icon: const Icon(Icons.remove),
                  tooltip: 'Une de moins',
                  onPressed: ligne.quantite > 1 ? () => onQuantite(ligne.quantite - 1) : null,
                ),
                SizedBox(
                  width: 40,
                  child: Text('${ligne.quantite}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                ),
                IconButton.outlined(
                  icon: const Icon(Icons.add),
                  tooltip: 'Une de plus',
                  onPressed: stockAtteint ? null : () => onQuantite(ligne.quantite + 1),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(formatEuros(ligne.totalCentimes), style: theme.textTheme.titleSmall),
                      Text(
                        '${formatEuros(ligne.prixUnitaireCentimes)} l’unité',
                        style: theme.textTheme.bodySmall?.copyWith(color: discret),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (stockAtteint)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Tout le stock est dans le panier.',
                  style: theme.textTheme.bodySmall?.copyWith(color: discret),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
