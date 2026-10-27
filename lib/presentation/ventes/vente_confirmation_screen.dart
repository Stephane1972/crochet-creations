import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/utils/validateurs.dart';
import '../../core/widgets/dialogues.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_vues.dart';
import '../../data/repositories/vente_vues.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../entreprise/profil_incomplet.dart';
import '../shell/nav_provider.dart';
import 'recap_widgets.dart';
import 'ventes_providers.dart';

/// Confirmation de vente (écran 10), aussi utilisée pour consulter une vente passée :
/// articles, totaux, paiements, encaissement du solde et annulation.
class VenteConfirmationScreen extends ConsumerStatefulWidget {
  const VenteConfirmationScreen({super.key, required this.venteId});

  final int venteId;

  @override
  ConsumerState<VenteConfirmationScreen> createState() => _VenteConfirmationScreenState();
}

class _VenteConfirmationScreenState extends ConsumerState<VenteConfirmationScreen> {
  /// La facture est en cours de création : le bouton est bloqué pour ne pas la créer deux fois.
  bool _creationFacture = false;

  /// Exécute une action sur la vente en affichant l'erreur éventuelle en français.
  Future<void> _executer(Future<void> Function() action) async {
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Action sur la vente impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    }
  }

  Future<void> _encaisser(VenteDetail detail) async {
    final _Encaissement? saisie = await showDialog<_Encaissement>(
      context: context,
      builder: (BuildContext contexteDialogue) => _DialogueEncaissement(solde: detail.soldeDuCentimes),
    );
    if (saisie == null || !mounted) return;
    await _executer(() async {
      await ref
          .read(venteRepositoryProvider)
          .encaisser(venteId: widget.venteId, mode: saisie.mode, montantCentimes: saisie.montantCentimes);
      if (mounted) afficherMessage(context, 'Paiement enregistré.');
    });
  }

  Future<void> _annuler(VenteDetail detail) async {
    final int encaisse = detail.encaisseCentimes;
    final bool ok = await confirmer(
      context,
      titre: 'Annuler cette vente ?',
      message:
          'Le stock des articles sera remis'
          '${encaisse > 0 ? ' et un remboursement de ${formatEuros(encaisse)} sera enregistré' : ''}. '
          'La vente reste dans l’historique, marquée « annulée ». Cette action est définitive.',
      libelleConfirmer: 'Annuler la vente',
      libelleAnnuler: 'Garder la vente',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await ref.read(venteRepositoryProvider).annuler(widget.venteId);
      if (mounted) afficherMessage(context, 'Vente annulée : le stock a été remis.');
    });
  }

  /// Établit la facture de la vente puis l'ouvre. Si « Mon entreprise » est incomplet, dit ce qui manque et
  /// propose de l'ouvrir : aucun numéro n'est consommé.
  Future<void> _creerFacture() async {
    if (_creationFacture) return;
    setState(() => _creationFacture = true);
    try {
      final Facture facture = await ref.read(factureRepositoryProvider).creer(widget.venteId);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(AppRoutes.factureDetail, arguments: facture.id);
    } on ProfilIncomplet catch (manque) {
      if (!mounted) return;
      await proposerProfilComplet(context, manque);
    } catch (erreur, pile) {
      debugPrint('Création de la facture impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _creationFacture = false);
    }
  }

  void _ouvrirFacture(Facture facture) {
    Navigator.of(context).pushNamed(AppRoutes.factureDetail, arguments: facture.id);
  }

  void _nouvelleVente() {
    ref.read(navIndexProvider.notifier).aller(OngletsNav.vente);
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<VenteDetail?> vente = ref.watch(venteDetailProvider(widget.venteId));

    return Scaffold(
      appBar: AppBar(title: const Text('Vente')),
      body: vente.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger cette vente.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(venteDetailProvider(widget.venteId)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (VenteDetail? d) {
          if (d == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Cette vente n’existe plus.', textAlign: TextAlign.center),
              ),
            );
          }
          return _Contenu(
            detail: d,
            onEncaisser: () => _encaisser(d),
            onAnnuler: () => _annuler(d),
            onNouvelleVente: _nouvelleVente,
            creationFactureEnCours: _creationFacture,
            onCreerFacture: _creerFacture,
            onOuvrirFacture: _ouvrirFacture,
          );
        },
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.detail,
    required this.onEncaisser,
    required this.onAnnuler,
    required this.onNouvelleVente,
    required this.creationFactureEnCours,
    required this.onCreerFacture,
    required this.onOuvrirFacture,
  });

  final VenteDetail detail;
  final VoidCallback onEncaisser;
  final VoidCallback onAnnuler;
  final VoidCallback onNouvelleVente;
  final bool creationFactureEnCours;
  final VoidCallback onCreerFacture;
  final void Function(Facture facture) onOuvrirFacture;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color discret = scheme.onSurfaceVariant;
    final Vente vente = detail.vente;
    final Client? client = detail.client;
    final bool annulee = detail.estAnnulee;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              annulee ? Icons.cancel_outlined : Icons.check_circle_outline,
              size: 48,
              color: annulee ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(annulee ? 'Vente annulée' : 'Vente enregistrée', style: theme.textTheme.headlineSmall),
                  Text(
                    'Le ${formatDateCourte(vente.dateVente)} · '
                    '${client == null ? 'Client de passage' : libelleClient(client)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: discret),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: _EtiquettePaiement(detail: detail)),
        const SizedBox(height: 16),
        CarteRubrique(
          titre: 'Articles',
          child: Column(
            children: <Widget>[
              for (final LigneVente l in detail.lignes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.designation),
                  subtitle: Text('${l.quantite} × ${formatEuros(l.prixUnitaireCentimes)}'),
                  trailing: Text(formatEuros(l.totalLigneCentimes), style: theme.textTheme.titleSmall),
                ),
              const Divider(),
              LigneMontant(libelle: 'Sous-total', montant: formatEuros(vente.sousTotalCentimes)),
              if (vente.remiseCentimes > 0)
                LigneMontant(libelle: 'Remise', montant: '−${formatEuros(vente.remiseCentimes)}'),
              if (vente.fraisPortCentimes > 0)
                LigneMontant(libelle: 'Frais de port', montant: formatEuros(vente.fraisPortCentimes)),
              LigneMontant(libelle: 'Total', montant: formatEuros(vente.totalCentimes), fort: true),
              if (!annulee && detail.encaisseCentimes > 0)
                LigneMontant(libelle: 'Déjà encaissé', montant: formatEuros(detail.encaisseCentimes)),
              if (detail.soldeDuCentimes > 0)
                LigneMontant(
                  libelle: 'Reste à payer',
                  montant: formatEuros(detail.soldeDuCentimes),
                  fort: true,
                  couleur: scheme.error,
                ),
            ],
          ),
        ),
        if (detail.paiements.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          CarteRubrique(
            titre: 'Paiements',
            child: Column(
              children: <Widget>[
                for (final Paiement p in detail.paiements)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(p.montantCentimes < 0 ? 'Remboursement' : 'Encaissement'),
                    subtitle: Text('${formatDateCourte(p.datePaiement)} · ${p.modePaiement.libelle}'),
                    trailing: Text(formatEuros(p.montantCentimes), style: theme.textTheme.titleSmall),
                  ),
              ],
            ),
          ),
        ],
        if (vente.notes != null) ...<Widget>[
          const SizedBox(height: 12),
          CarteRubrique(titre: 'Note', child: Text(vente.notes!)),
        ],
        if (!annulee || detail.factures.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _BlocFacture(
            detail: detail,
            enCours: creationFactureEnCours,
            onCreer: onCreerFacture,
            onOuvrir: onOuvrirFacture,
          ),
        ],
        const SizedBox(height: 20),
        if (detail.peutEncaisser) ...<Widget>[
          FilledButton.icon(
            onPressed: onEncaisser,
            icon: const Icon(Icons.payments_outlined),
            label: Text('Encaisser le solde · ${formatEuros(detail.soldeDuCentimes)}'),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.tonalIcon(
          onPressed: onNouvelleVente,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: const Text('Nouvelle vente'),
        ),
        if (!annulee) ...<Widget>[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onAnnuler,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            icon: const Icon(Icons.undo),
            label: const Text('Annuler la vente'),
          ),
        ],
      ],
    );
  }
}

/// La facture de la vente : la facture en cours (qui s'ouvre), ou le bouton pour la créer. Les factures
/// annulées de la vente sont rappelées en dessous.
class _BlocFacture extends StatelessWidget {
  const _BlocFacture({
    required this.detail,
    required this.enCours,
    required this.onCreer,
    required this.onOuvrir,
  });

  final VenteDetail detail;
  final bool enCours;
  final VoidCallback onCreer;
  final void Function(Facture facture) onOuvrir;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Facture? emise = detail.factureEmise;
    final List<Facture> annulees = detail.factures
        .where((Facture f) => f.statut == StatutFacture.annulee)
        .toList();

    return CarteRubrique(
      titre: 'Facture',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (emise != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(emise.numero),
              subtitle: Text('Émise le ${formatDateCourte(emise.dateEmission)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOuvrir(emise),
            )
          else if (!detail.estAnnulee) ...<Widget>[
            Text(
              'Cette vente n’a pas encore de facture.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: enCours ? null : onCreer,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Créer la facture'),
            ),
          ],
          for (final Facture f in annulees)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Facture annulée : ${f.numero}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// « Payée », « Partiellement payée », « Impayée », « Remboursée » ou « Annulée ».
class _EtiquettePaiement extends StatelessWidget {
  const _EtiquettePaiement({required this.detail});

  final VenteDetail detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (detail.estAnnulee) {
      return Etiquette(
        detail.vente.statutPaiement == StatutPaiement.remboursee ? 'Annulée · remboursée' : 'Annulée',
        fond: scheme.surfaceContainerHighest,
        couleurTexte: scheme.onSurfaceVariant,
        icone: Icons.cancel_outlined,
      );
    }
    switch (detail.vente.statutPaiement) {
      case StatutPaiement.payee:
        return Etiquette(
          'Payée',
          fond: scheme.primaryContainer,
          couleurTexte: scheme.onPrimaryContainer,
          icone: Icons.check,
        );
      case StatutPaiement.partiellementPayee:
        return Etiquette(
          'Partiellement payée',
          fond: scheme.tertiaryContainer,
          couleurTexte: scheme.onTertiaryContainer,
          icone: Icons.hourglass_bottom,
        );
      case StatutPaiement.impayee:
        return Etiquette(
          'Impayée',
          fond: scheme.errorContainer,
          couleurTexte: scheme.onErrorContainer,
          icone: Icons.error_outline,
        );
      case StatutPaiement.remboursee:
        return Etiquette(
          'Remboursée',
          fond: scheme.surfaceContainerHighest,
          couleurTexte: scheme.onSurfaceVariant,
          icone: Icons.undo,
        );
    }
  }
}

class _Encaissement {
  const _Encaissement({required this.mode, required this.montantCentimes});

  final ModePaiement mode;
  final int montantCentimes;
}

/// Mode de paiement et montant d'un encaissement (par défaut : tout le solde).
class _DialogueEncaissement extends StatefulWidget {
  const _DialogueEncaissement({required this.solde});

  final int solde;

  @override
  State<_DialogueEncaissement> createState() => _DialogueEncaissementState();
}

class _DialogueEncaissementState extends State<_DialogueEncaissement> {
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  late final TextEditingController _montant = TextEditingController(text: formatMontantSaisie(widget.solde));
  ModePaiement _mode = ModePaiement.especes;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  void _valider() {
    if (!_formulaire.currentState!.validate()) return;
    Navigator.of(context).pop(_Encaissement(mode: _mode, montantCentimes: parseMontantEuros(_montant.text)!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Encaisser un paiement'),
      content: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Reste à payer : ${formatEuros(widget.solde)}'),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _montant,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant encaissé (€)'),
              validator: (String? v) {
                final String? probleme = validerMontantObligatoire(v, 'Indiquez le montant.');
                if (probleme != null) return probleme;
                final int montant = parseMontantEuros(v!)!;
                if (montant <= 0) return 'Le montant doit être supérieur à 0.';
                if (montant > widget.solde) return 'Le montant dépasse le solde (${formatEuros(widget.solde)}).';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _valider, child: const Text('Encaisser')),
      ],
    );
  }
}
