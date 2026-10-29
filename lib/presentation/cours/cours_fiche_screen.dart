import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_vues.dart';
import '../../data/repositories/cours_repository.dart';
import '../../data/repositories/cours_vues.dart';
import '../../domain/enums.dart';
import '../clients/client_widgets.dart';
import '../ventes/recap_widgets.dart';
import 'cours_providers.dart';
import 'cours_widgets.dart';

enum _ActionCours { modifier, annuler, retablir, archiver, restaurer }

enum _ActionInscrit { vente, confirmer, annuler }

/// Fiche d'un cours (écran 17) : informations, inscrits avec leur paiement, liste d'attente et inscriptions
/// annulées. De là, on inscrit quelqu'un, on confirme la première personne en attente, on annule une inscription.
class CoursFicheScreen extends ConsumerStatefulWidget {
  const CoursFicheScreen({super.key, required this.coursId});

  final int coursId;

  @override
  ConsumerState<CoursFicheScreen> createState() => _CoursFicheScreenState();
}

class _CoursFicheScreenState extends ConsumerState<CoursFicheScreen> {
  CoursRepository get _repo => ref.read(coursRepositoryProvider);

  /// Exécute une action et affiche l'erreur éventuelle en français.
  Future<void> _executer(Future<void> Function() action) async {
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Action sur le cours impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    }
  }

  // --- Le cours ---------------------------------------------------------------

  Future<void> _annulerCours(CoursDetail detail) async {
    final bool ok = await confirmer(
      context,
      titre: 'Annuler ce cours ?',
      message:
          'Plus personne ne pourra s’y inscrire. Les inscriptions déjà prises restent affichées : '
          'annulez-les une par une, avec ou sans remboursement. Vous pourrez rétablir le cours.',
      libelleConfirmer: 'Annuler le cours',
      libelleAnnuler: 'Garder le cours',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await _repo.annulerCours(detail.cours.id);
      if (mounted) afficherMessage(context, 'Cours annulé.');
    });
  }

  Future<void> _retablirCours(CoursDetail detail) => _executer(() async {
    await _repo.retablirCours(detail.cours.id);
    if (mounted) afficherMessage(context, 'Cours rétabli.');
  });

  Future<void> _archiverCours(CoursDetail detail) async {
    final String? refus = detail.refusArchivageCours(DateTime.now());
    if (refus != null) {
      afficherMessage(context, refus);
      return;
    }
    final bool ok = await confirmer(
      context,
      titre: 'Archiver ce cours ?',
      message:
          'Il quittera les listes « À venir » et « Passés », mais ses inscriptions et ses ventes restent '
          'conservées. Vous le retrouverez dans « Archivés » et pourrez le restaurer.',
      libelleConfirmer: 'Archiver',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await _repo.archiver(detail.cours.id);
      if (mounted) afficherMessage(context, 'Cours archivé.');
    });
  }

  Future<void> _restaurerCours(CoursDetail detail) => _executer(() async {
    await _repo.restaurer(detail.cours.id);
    if (mounted) afficherMessage(context, 'Cours restauré dans la liste.');
  });

  void _inscrire() {
    Navigator.of(context).pushNamed(
      AppRoutes.coursInscription,
      arguments: ArgumentsInscription(coursId: widget.coursId),
    );
  }

  // --- Une personne -----------------------------------------------------------

  Future<void> _ouvrirPersonne(CoursDetail detail, InscriptionDetail personne) async {
    final _ActionInscrit? action = await showModalBottomSheet<_ActionInscrit>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext contexteFeuille) => _FeuillePersonne(detail: detail, personne: personne),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ActionInscrit.vente:
        Navigator.of(context).pushNamed(AppRoutes.venteConfirmation, arguments: personne.vente!.id);
      case _ActionInscrit.confirmer:
        Navigator.of(context).pushNamed(
          AppRoutes.coursInscription,
          arguments: ArgumentsInscription(coursId: widget.coursId, inscriptionId: personne.inscription.id),
        );
      case _ActionInscrit.annuler:
        await _annulerInscription(personne);
    }
  }

  Future<void> _annulerInscription(InscriptionDetail personne) async {
    final String nom = libelleClient(personne.client);
    final bool argentRecu = personne.vente?.statut == StatutVente.validee && personne.encaisseCentimes > 0;

    bool rembourser = true;
    if (argentRecu) {
      // De l'argent a été reçu : on choisit à chaque fois ce qu'il devient.
      final bool? choix = await showDialog<bool>(
        context: context,
        builder: (BuildContext contexteDialogue) => AlertDialog(
          title: const Text('Annuler cette inscription ?'),
          content: Text(
            '$nom a déjà réglé ${formatEuros(personne.encaisseCentimes)}. '
            'Que faire de ce paiement ?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(),
              child: const Text('Retour'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(false),
              child: const Text('Annuler en gardant le paiement'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(true),
              child: const Text('Annuler et rembourser'),
            ),
          ],
        ),
      );
      if (choix == null || !mounted) return;
      rembourser = choix;
    } else {
      final bool enAttente = personne.statut == StatutInscription.listeAttente;
      final bool ok = await confirmer(
        context,
        titre: 'Annuler cette inscription ?',
        message: enAttente
            ? '$nom quittera la liste d’attente.'
            : personne.vente == null
            ? 'L’inscription de $nom sera annulée.'
            : 'L’inscription de $nom sera annulée, ainsi que sa vente (rien n’a été encaissé).',
        libelleConfirmer: 'Annuler l’inscription',
        libelleAnnuler: 'Retour',
      );
      if (!ok || !mounted) return;
    }

    await _executer(() async {
      await _repo.annulerInscription(personne.inscription.id, rembourser: rembourser);
      if (!mounted) return;
      afficherMessage(
        context,
        !argentRecu
            ? 'Inscription annulée.'
            : rembourser
            ? 'Inscription annulée, paiement remboursé.'
            : 'Inscription annulée, paiement conservé.',
      );
    });
  }

  // --- Interface --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CoursDetail?> fiche = ref.watch(coursDetailProvider(widget.coursId));
    final CoursDetail? detail = fiche.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail == null ? 'Cours' : detail.cours.titre, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (detail != null)
            PopupMenuButton<_ActionCours>(
              tooltip: 'Plus d’actions',
              onSelected: (_ActionCours action) {
                switch (action) {
                  case _ActionCours.modifier:
                    Navigator.of(context).pushNamed(AppRoutes.coursModifier, arguments: widget.coursId);
                  case _ActionCours.annuler:
                    _annulerCours(detail);
                  case _ActionCours.retablir:
                    _retablirCours(detail);
                  case _ActionCours.archiver:
                    _archiverCours(detail);
                  case _ActionCours.restaurer:
                    _restaurerCours(detail);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<_ActionCours>>[
                const PopupMenuItem<_ActionCours>(
                  value: _ActionCours.modifier,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Modifier'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (detail.annule)
                  const PopupMenuItem<_ActionCours>(
                    value: _ActionCours.retablir,
                    child: ListTile(
                      leading: Icon(Icons.event_available_outlined),
                      title: Text('Rétablir le cours'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else
                  const PopupMenuItem<_ActionCours>(
                    value: _ActionCours.annuler,
                    child: ListTile(
                      leading: Icon(Icons.event_busy_outlined),
                      title: Text('Annuler le cours'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (detail.archive)
                  const PopupMenuItem<_ActionCours>(
                    value: _ActionCours.restaurer,
                    child: ListTile(
                      leading: Icon(Icons.unarchive_outlined),
                      title: Text('Restaurer'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else
                  const PopupMenuItem<_ActionCours>(
                    value: _ActionCours.archiver,
                    child: ListTile(
                      leading: Icon(Icons.archive_outlined),
                      title: Text('Archiver'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: fiche.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger ce cours.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(coursDetailProvider(widget.coursId)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (CoursDetail? d) {
          if (d == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Ce cours n’existe plus.', textAlign: TextAlign.center),
              ),
            );
          }
          return _Contenu(detail: d, onOuvrirPersonne: (InscriptionDetail p) => _ouvrirPersonne(d, p));
        },
      ),
      bottomNavigationBar: detail == null || detail.refusInscriptionCours != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _inscrire,
                  icon: Icon(detail.complet ? Icons.hourglass_empty : Icons.person_add_alt_1_outlined),
                  label: Text(detail.complet ? 'Ajouter en liste d’attente' : 'Inscrire quelqu’un'),
                ),
              ),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Contenu
// -----------------------------------------------------------------------------

class _Contenu extends StatelessWidget {
  const _Contenu({required this.detail, required this.onOuvrirPersonne});

  final CoursDetail detail;
  final ValueChanged<InscriptionDetail> onOuvrirPersonne;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final CoursFiche cours = detail.cours;
    final DateTime maintenant = DateTime.now();
    final bool inscriptionsEnCours = detail.confirmees.isNotEmpty || detail.enAttente.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        ImageCours(chemin: cours.photoChemin, largeur: double.infinity, hauteur: 180, rayon: 16, tailleIcone: 64),
        const SizedBox(height: 16),
        Text(cours.titre, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            if (detail.annule) const EtiquetteCoursAnnule(),
            if (detail.archive) const EtiquetteCoursArchive(),
            if (!detail.annule && detail.termine(maintenant) && !detail.archive)
              _Pastille('Terminé', Icons.event_available_outlined),
          ],
        ),
        if (detail.annule && inscriptionsEnCours) ...<Widget>[
          const SizedBox(height: 12),
          _Bandeau(
            'Ce cours est annulé. Les inscriptions restent affichées : annulez-les une par une '
            '(avec ou sans remboursement).',
          ),
        ],
        const SizedBox(height: 16),
        CarteRubrique(
          titre: 'Informations',
          child: Column(
            children: <Widget>[
              _LigneInfo(Icons.event_outlined, creneauCours(cours.debutLe, cours.dureeMinutes)),
              if (cours.lieu != null) _LigneInfo(Icons.place_outlined, cours.lieu!),
              _LigneInfo(Icons.stairs_outlined, 'Niveau : ${cours.niveau.libelle}'),
              _LigneInfo(
                Icons.inventory_2_outlined,
                cours.materielInclus ? 'Matériel inclus' : 'Matériel non inclus',
              ),
              _LigneInfo(
                Icons.sell_outlined,
                cours.prixCentimes == 0 ? 'Gratuit' : '${formatEuros(cours.prixCentimes)} par personne',
              ),
              _LigneInfo(
                Icons.group_outlined,
                '${textePlaces(confirmes: detail.confirmees.length, places: cours.places)}'
                '${detail.complet ? '' : ' · ${detail.placesLibres} libre${detail.placesLibres > 1 ? 's' : ''}'}',
              ),
            ],
          ),
        ),
        if (cours.description != null) ...<Widget>[
          const SizedBox(height: 12),
          CarteRubrique(titre: 'Description', child: Text(cours.description!)),
        ],
        const SizedBox(height: 12),
        _SectionPersonnes(
          titre: 'Inscrits',
          vide: 'Personne n’est encore inscrit.',
          personnes: detail.confirmees,
          onOuvrir: onOuvrirPersonne,
        ),
        if (detail.enAttente.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _SectionPersonnes(
            titre: 'Liste d’attente',
            vide: '',
            personnes: detail.enAttente,
            onOuvrir: onOuvrirPersonne,
            aide:
                'Quand une place se libère, confirmez la première personne : '
                'l’inscription est alors enregistrée avec son paiement.',
          ),
        ],
        if (detail.annulees.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _SectionPersonnes(
            titre: 'Inscriptions annulées',
            vide: '',
            personnes: detail.annulees,
            onOuvrir: onOuvrirPersonne,
          ),
        ],
        if (detail.refusInscriptionCours != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(detail.refusInscriptionCours!, style: theme.textTheme.bodyMedium?.copyWith(color: discret)),
        ],
      ],
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille(this.texte, this.icone);

  final String texte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Etiquette(texte, fond: c.secondaryContainer, couleurTexte: c.onSecondaryContainer, icone: icone);
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: c.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texte, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  const _LigneInfo(this.icone, this.texte);

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(texte)),
        ],
      ),
    );
  }
}

/// Une rubrique de personnes : inscrits, liste d'attente ou inscriptions annulées.
class _SectionPersonnes extends StatelessWidget {
  const _SectionPersonnes({
    required this.titre,
    required this.vide,
    required this.personnes,
    required this.onOuvrir,
    this.aide,
  });

  final String titre;
  final String vide;
  final List<InscriptionDetail> personnes;
  final ValueChanged<InscriptionDetail> onOuvrir;
  final String? aide;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;

    return CarteRubrique(
      titre: '$titre (${personnes.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (aide != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(aide!, style: theme.textTheme.bodySmall?.copyWith(color: discret)),
            ),
          if (personnes.isEmpty) Text(vide, style: theme.textTheme.bodyMedium?.copyWith(color: discret)),
          for (final InscriptionDetail p in personnes) _LignePersonne(personne: p, onTap: () => onOuvrir(p)),
        ],
      ),
    );
  }
}

class _LignePersonne extends StatelessWidget {
  const _LignePersonne({required this.personne, required this.onTap});

  final InscriptionDetail personne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? solde = personne.soldeCentimes;
    final bool aPayer = personne.statut == StatutInscription.confirmee && solde != null && solde > 0;
    final String prix = personne.inscription.prixCentimes == 0
        ? 'Gratuit'
        : formatEuros(personne.inscription.prixCentimes);

    final String detail = switch (personne.statut) {
      StatutInscription.confirmee => aPayer ? '$prix · reste ${formatEuros(solde)}' : prix,
      StatutInscription.listeAttente => '$prix · depuis le ${formatDateCourte(personne.inscription.dateInscription)}',
      StatutInscription.annulee => prix,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: PastilleClient(client: personne.client, taille: 40),
      title: Text(libelleClient(personne.client), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail, style: theme.textTheme.bodySmall),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (personne.statut == StatutInscription.listeAttente)
            EtiquetteStatutInscription(personne)
          else if (personne.vente != null)
            EtiquettePaiementInscription(personne)
          else
            EtiquetteStatutInscription(personne),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Feuille d'actions sur une personne : voir sa vente et sa facture, confirmer, annuler.
class _FeuillePersonne extends StatelessWidget {
  const _FeuillePersonne({required this.detail, required this.personne});

  final CoursDetail detail;
  final InscriptionDetail personne;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? refusConfirmation = personne.statut == StatutInscription.listeAttente
        ? detail.refusConfirmationDe(personne)
        : null;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: PastilleClient(client: personne.client, taille: 40),
            title: Text(libelleClient(personne.client), style: theme.textTheme.titleMedium),
            subtitle: Text(personne.statut.libelle),
          ),
          const Divider(height: 1),
          if (personne.vente != null)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Voir la vente et la facture'),
              subtitle: personne.facture == null ? null : Text('Facture ${personne.facture!.numero}'),
              onTap: () => Navigator.of(context).pop(_ActionInscrit.vente),
            ),
          if (personne.statut == StatutInscription.listeAttente)
            ListTile(
              enabled: refusConfirmation == null,
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Confirmer l’inscription'),
              subtitle: refusConfirmation == null ? null : Text(refusConfirmation),
              onTap: refusConfirmation == null ? () => Navigator.of(context).pop(_ActionInscrit.confirmer) : null,
            ),
          if (personne.statut != StatutInscription.annulee)
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
              title: Text('Annuler l’inscription', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () => Navigator.of(context).pop(_ActionInscrit.annuler),
            ),
        ],
      ),
    );
  }
}
