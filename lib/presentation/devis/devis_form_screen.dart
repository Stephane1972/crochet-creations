import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/devis_repository.dart';
import '../../data/repositories/devis_vues.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/calculs/totaux.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_devis.dart';
import '../ventes/ajout_panier.dart';
import '../ventes/recap_widgets.dart';
import '../ventes/selecteur_client.dart';

/// Création et modification d'un devis (écran 14) : client, lignes libres (description, quantité, prix),
/// remise, frais de port, validité, délai de réalisation, acompte demandé et notes.
///
/// Sans [devisId] : nouveau devis (il prend son numéro à l'enregistrement). Avec [devisId] : modification.
class DevisFormScreen extends ConsumerStatefulWidget {
  const DevisFormScreen({super.key, this.devisId});

  final int? devisId;

  @override
  ConsumerState<DevisFormScreen> createState() => _DevisFormScreenState();
}

class _DevisFormScreenState extends ConsumerState<DevisFormScreen> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  final TextEditingController _delai = TextEditingController();
  final TextEditingController _acompte = TextEditingController();
  final TextEditingController _remise = TextEditingController();
  final TextEditingController _frais = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  Panier _panier = const Panier();
  Client? _client;
  late DateTime _emission;
  late DateTime _validite;

  /// Le devis modifié est expiré : choisir une nouvelle date de validité le remet en brouillon.
  bool _etaitExpire = false;

  bool _chargement = true;
  bool _erreurChargement = false;
  bool _modifie = false;
  bool _enregistre = false;
  bool _enCours = false;

  bool get _nouveau => widget.devisId == null;

  List<TextEditingController> get _champs => <TextEditingController>[_delai, _acompte, _remise, _frais, _notes];

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = DateTime.now();
    _emission = debutDeJour(maintenant);
    _validite = dateValiditeParDefaut(maintenant);
    if (_nouveau) {
      _chargement = false;
    } else {
      _charger(maintenant);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _champs) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger(DateTime maintenant) async {
    try {
      final DevisDetail? detail = await ref.read(devisRepositoryProvider).detail(widget.devisId!);
      if (!mounted) return;
      if (detail == null) {
        setState(() {
          _erreurChargement = true;
          _chargement = false;
        });
        return;
      }
      final DevisFiche devis = detail.devis;
      Panier panier = const Panier();
      for (final LigneDevis l in detail.lignes) {
        panier = panier.ajouter(
          designation: l.designation,
          description: l.description,
          nature: l.nature,
          prixUnitaireCentimes: l.prixUnitaireCentimes,
          quantite: l.quantite,
        );
      }
      panier = panier.avecRemise(devis.remiseType, devis.remiseValeur).avecFraisPort(devis.fraisPortCentimes);

      final bool expire = detail.statut(maintenant) == StatutDevis.expire;
      setState(() {
        _panier = panier;
        _client = detail.client;
        _emission = debutDeJour(devis.dateEmission);
        _etaitExpire = expire;
        // Un devis expiré repart sur une nouvelle durée de validité, à confirmer.
        _validite = (expire || devis.dateValidite == null)
            ? dateValiditeParDefaut(maintenant)
            : debutDeJour(devis.dateValidite!);
        _delai.text = devis.delaiRealisation ?? '';
        if (devis.acompteCentimes > 0) _acompte.text = formatMontantSaisie(devis.acompteCentimes);
        if (devis.remiseType != RemiseType.aucune && devis.remiseValeur > 0) {
          _remise.text = formatMontantSaisie(devis.remiseValeur);
        }
        if (devis.fraisPortCentimes > 0) _frais.text = formatMontantSaisie(devis.fraisPortCentimes);
        _notes.text = devis.notes ?? '';
        _chargement = false;
      });
    } catch (erreur, pile) {
      debugPrint('Chargement du devis impossible : $erreur\n$pile');
      if (!mounted) return;
      setState(() {
        _erreurChargement = true;
        _chargement = false;
      });
    }
  }

  void _marquerModifie() {
    if (!_modifie) setState(() => _modifie = true);
  }

  /// Applique un changement du panier ; un refus est affiché sans rien changer.
  void _changerPanier(Panier Function(Panier panier) changement) {
    try {
      setState(() {
        _panier = changement(_panier);
        _modifie = true;
      });
    } on ErreurMetier catch (erreur) {
      afficherMessage(context, erreur.message);
    }
  }

  Future<void> _ajouterLigne() async {
    final LigneLibreSaisie? saisie = await demanderLigneLibre(context);
    if (saisie == null || !mounted) return;
    _changerPanier(
      (Panier p) => p.ajouter(
        designation: saisie.designation,
        description: saisie.description,
        nature: saisie.nature,
        prixUnitaireCentimes: saisie.prixCentimes,
        quantite: saisie.quantite,
      ),
    );
  }

  Future<void> _modifierLigne(LignePanier ligne) async {
    final LigneLibreSaisie? saisie = await demanderLigneLibre(
      context,
      initiale: LigneLibreSaisie(
        designation: ligne.designation,
        description: ligne.description,
        nature: ligne.nature,
        prixCentimes: ligne.prixUnitaireCentimes,
        quantite: ligne.quantite,
      ),
    );
    if (saisie == null || !mounted) return;
    _changerPanier(
      (Panier p) => p.avecLigneModifiee(
        ligne.idLigne,
        designation: saisie.designation,
        description: saisie.description,
        nature: saisie.nature,
        prixUnitaireCentimes: saisie.prixCentimes,
        quantite: saisie.quantite,
      ),
    );
  }

  void _surRemise() {
    final String texte = _remise.text.trim();
    final int? valeur = texte.isEmpty ? 0 : parseMontantEuros(texte);
    if (valeur != null) _changerPanier((Panier p) => p.avecRemise(p.remiseType, valeur));
  }

  void _choisirTypeRemise(RemiseType type) {
    if (type == RemiseType.aucune) _remise.clear();
    final String texte = _remise.text.trim();
    final int valeur = type == RemiseType.aucune ? 0 : (texte.isEmpty ? 0 : (parseMontantEuros(texte) ?? 0));
    _changerPanier((Panier p) => p.avecRemise(type, valeur));
  }

  void _surFrais() {
    final String texte = _frais.text.trim();
    final int? centimes = texte.isEmpty ? 0 : parseMontantEuros(texte);
    if (centimes != null) _changerPanier((Panier p) => p.avecFraisPort(centimes));
  }

  /// Acompte saisi en centimes (0 si le champ est vide).
  int _acompteCentimes() {
    final String texte = _acompte.text.trim();
    return texte.isEmpty ? 0 : (parseMontantEuros(texte) ?? 0);
  }

  /// Premier jour où la validité peut être fixée : aujourd'hui (un devis ne peut pas être déjà périmé).
  DateTime get _premierJourPossible {
    final DateTime aujourdhui = debutDeJour(DateTime.now());
    return _emission.isAfter(aujourdhui) ? _emission : aujourdhui;
  }

  Future<void> _choisirValidite() async {
    final DateTime premier = _premierJourPossible;
    final DateTime? choisie = await showDatePicker(
      context: context,
      initialDate: _validite.isBefore(premier) ? premier : _validite,
      firstDate: premier,
      lastDate: DateTime(premier.year + 5, 12, 31),
      helpText: 'Valable jusqu’au',
    );
    if (choisie == null || !mounted) return;
    setState(() {
      _validite = debutDeJour(choisie);
      _modifie = true;
    });
  }

  Future<void> _enregistrer() async {
    if (_enCours) return;
    if (!_formulaire.currentState!.validate()) {
      afficherMessage(context, 'Corrigez les champs signalés en rouge.');
      return;
    }
    if (_panier.estVide) {
      afficherMessage(context, 'Ajoutez au moins une ligne au devis.');
      return;
    }
    final DevisSaisi saisie = DevisSaisi(
      clientId: _client?.id,
      panier: _panier,
      dateEmission: _nouveau ? _emission : null,
      dateValidite: _validite,
      delaiRealisation: _delai.text,
      acompteCentimes: _acompteCentimes(),
      notes: _notes.text,
    );

    setState(() => _enCours = true);
    try {
      final DevisRepository depot = ref.read(devisRepositoryProvider);
      final DevisFiche devis = _nouveau
          ? await depot.creer(saisie)
          : await depot.modifier(widget.devisId!, saisie);
      if (!mounted) return;
      _enregistre = true;
      if (_nouveau) {
        afficherMessage(context, 'Devis ${devis.numero} créé.');
        // On ouvre directement l'aperçu : on peut le partager tout de suite.
        await Navigator.of(context).pushReplacementNamed(AppRoutes.devisDetail, arguments: devis.id);
      } else {
        afficherMessage(context, 'Devis ${devis.numero} enregistré.');
        Navigator.of(context).pop();
      }
    } catch (erreur, pile) {
      debugPrint('Enregistrement du devis impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  Future<void> _demanderAbandon() async {
    final bool abandonner = await confirmer(
      context,
      titre: 'Abandonner les modifications ?',
      message: 'Ce que vous avez saisi ne sera pas enregistré.',
      libelleConfirmer: 'Abandonner',
      libelleAnnuler: 'Continuer la saisie',
    );
    if (!abandonner || !mounted) return;
    setState(() => _enregistre = true); // plus rien à protéger : on peut quitter
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _enregistre || !_modifie,
      onPopInvokedWithResult: (bool didPop, Object? resultat) {
        if (!didPop) _demanderAbandon();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_nouveau ? 'Nouveau devis' : 'Modifier le devis')),
        body: _corps(context),
        bottomNavigationBar: (_chargement || _erreurChargement) ? null : _barreEnregistrement(context),
      ),
    );
  }

  Widget _corps(BuildContext context) {
    if (_chargement) return const Center(child: CircularProgressIndicator());
    if (_erreurChargement) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Impossible de charger ce devis.', textAlign: TextAlign.center),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? problemeRemise = _panier.problemeRemise;
    final TotauxDocument? totaux = problemeRemise == null ? _panier.totaux : null;

    return Form(
      key: _formulaire,
      onChanged: _marquerModifie,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          if (_etaitExpire) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Ce devis est expiré. Vérifiez la nouvelle date de validité proposée : en enregistrant, '
                'il redevient un brouillon.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
              ),
            ),
            const SizedBox(height: 12),
          ],
          LigneChoixClient(
            client: _client,
            titreAucun: 'Aucun client',
            sousTitreAucun: 'Devis sans destinataire',
            onChoisi: (Client? choisi) => setState(() {
              _client = choisi;
              _modifie = true;
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: Text('Lignes du devis', style: theme.textTheme.titleMedium)),
              FilledButton.tonalIcon(
                onPressed: _ajouterLigne,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ligne'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_panier.estVide)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Aucune ligne pour le moment : ajoutez une création, une prestation ou un cours.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final LignePanier ligne in _panier.lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CarteLigneDevis(
                ligne: ligne,
                onModifier: () => _modifierLigne(ligne),
                onRetirer: () => _changerPanier((Panier p) => p.sans(ligne.idLigne)),
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
                  selected: <RemiseType>{_panier.remiseType},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<RemiseType> choix) => _choisirTypeRemise(choix.first),
                ),
                if (_panier.remiseType != RemiseType.aucune) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _remise,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _panier.remiseType == RemiseType.pourcentage ? 'Remise (%)' : 'Remise (€)',
                    ),
                    onChanged: (String _) => _surRemise(),
                    validator: (String? v) =>
                        validerMontantFacultatif(v) == null ? null : 'Valeur invalide (exemple : 10 ou 12,5).',
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
            titre: 'Conditions du devis',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Date du devis : ${formatDateCourte(_emission)}', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _choisirValidite,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Valable jusqu’au ${formatDateCourte(_validite)}'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _delai,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Délai de réalisation (facultatif)',
                    hintText: 'Exemple : 3 semaines',
                  ),
                  validator: (String? v) => validerLongueurMax(v, 200, 'Le délai'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _acompte,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Acompte demandé (€, facultatif)', hintText: '0'),
                  validator: (String? v) {
                    final String? probleme = validerMontantFacultatif(v);
                    if (probleme != null) return probleme;
                    final int acompte = _acompteCentimes();
                    if (totaux != null && acompte > totaux.totalCentimes) {
                      return 'L’acompte ne peut pas dépasser le total (${formatEuros(totaux.totalCentimes)}).';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes pour moi (non imprimées)'),
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
                        _panier.lignes.fold(0, (int somme, LignePanier l) => somme + l.totalCentimes),
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
                  Text(problemeRemise!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
                const SizedBox(height: 4),
                Text(
                  'Pas de TVA : ces prix sont des prix nets (TVA non applicable, article 293 B du CGI).',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreEnregistrement(BuildContext context) {
    final String? probleme = _panier.problemeRemise;
    final String libelle = probleme == null && !_panier.estVide
        ? 'Enregistrer le devis · ${formatEuros(_panier.totaux.totalCentimes)}'
        : 'Enregistrer le devis';
    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_enCours || probleme != null) ? null : _enregistrer,
              child: _enCours
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(libelle),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une ligne du devis : désignation, description, quantité × prix, total, boutons « modifier » et « retirer ».
class _CarteLigneDevis extends StatelessWidget {
  const _CarteLigneDevis({required this.ligne, required this.onModifier, required this.onRetirer});

  final LignePanier ligne;
  final VoidCallback onModifier;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onModifier,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(ligne.designation, style: theme.textTheme.titleSmall),
                    if (ligne.description != null)
                      Text(ligne.description!, style: theme.textTheme.bodySmall?.copyWith(color: discret)),
                    const SizedBox(height: 4),
                    Text(
                      '${ligne.quantite} × ${formatEuros(ligne.prixUnitaireCentimes)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: discret),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(formatEuros(ligne.totalCentimes), style: theme.textTheme.titleSmall),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Retirer « ${ligne.designation} » du devis',
                onPressed: onRetirer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
