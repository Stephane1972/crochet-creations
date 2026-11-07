import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/categorie_note_repository.dart';
import '../../domain/notes.dart';
import 'categorie_note_dialogues.dart';
import 'notes_providers.dart';

/// Catégories de notes : ajouter, renommer et supprimer les catégories qui rangent les notes (« Futures commandes »,
/// « Documents entreprise », les vôtres...).
///
/// Supprimer une catégorie qui a des notes demande où les déplacer (une autre catégorie, ou « Sans catégorie ») :
/// aucune note n'est jamais supprimée ni perdue.
class CategoriesNoteScreen extends ConsumerWidget {
  const CategoriesNoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategorieNote>> categories = ref.watch(categoriesNoteProvider);
    final Map<int, int> comptes = ref.watch(nombreNotesParCategorieProvider).valueOrNull ?? const <int, int>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Catégories de notes')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'bouton-ajouter-categorie-note',
        onPressed: () => _ajouter(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle catégorie'),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Les catégories de notes n’ont pas pu être chargées. Quittez cet écran et rouvrez-le.'),
          ),
        ),
        data: (List<CategorieNote> liste) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            Text(
              'Chaque note peut être rangée dans une catégorie. Renommer une catégorie change son nom partout ; '
              'en supprimer une déplace ses notes dans une autre catégorie, ou dans « $libelleSansCategorieNote ». '
              'Aucune note n’est jamais supprimée.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (liste.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Aucune catégorie. Créez-en une avec « Nouvelle catégorie ».')),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < liste.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _LigneCategorie(
                        categorie: liste[i],
                        nombreNotes: comptes[liste[i].id] ?? 0,
                        onRenommer: () => _renommer(context, ref, liste[i]),
                        onSupprimer: () => _supprimer(context, ref, liste[i], liste),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _ajouter(BuildContext context, WidgetRef ref) async {
    final CategorieNote? creee = await demanderNomCategorieNote<CategorieNote>(
      context,
      titre: 'Nouvelle catégorie de notes',
      libelleValider: 'Créer',
      enregistrer: (String nom) => ref.read(categorieNoteRepositoryProvider).creer(nom),
    );
    if (creee != null && context.mounted) afficherMessage(context, 'Catégorie « ${creee.nom} » créée.');
  }

  Future<void> _renommer(BuildContext context, WidgetRef ref, CategorieNote categorie) async {
    final CategorieNote? renommee = await demanderNomCategorieNote<CategorieNote>(
      context,
      titre: 'Renommer la catégorie',
      libelleValider: 'Enregistrer',
      nomInitial: categorie.nom,
      enregistrer: (String nom) => ref.read(categorieNoteRepositoryProvider).renommer(categorie.id, nom),
    );
    if (renommee != null && context.mounted) afficherMessage(context, 'Catégorie renommée « ${renommee.nom} ».');
  }

  Future<void> _supprimer(
    BuildContext context,
    WidgetRef ref,
    CategorieNote categorie,
    List<CategorieNote> toutes,
  ) async {
    final CategorieNoteRepository repo = ref.read(categorieNoteRepositoryProvider);
    try {
      // Le nombre exact se lit en base au moment de supprimer (la liste affichée peut avoir une seconde de retard).
      final int nombre = await repo.nombreNotes(categorie.id);
      if (!context.mounted) return;

      DestinationNotes? destination;
      if (nombre == 0) {
        final bool ok = await confirmer(
          context,
          titre: 'Supprimer cette catégorie ?',
          message: 'La catégorie « ${categorie.nom} » ne contient aucune note. Elle sera supprimée.',
          libelleConfirmer: 'Supprimer',
        );
        if (!ok) return;
      } else {
        final List<CategorieNote> autres = toutes.where((CategorieNote c) => c.id != categorie.id).toList();
        destination = await showDialog<DestinationNotes>(
          context: context,
          builder: (BuildContext contexteDialogue) =>
              _DialogueDeplacement(categorie: categorie, nombreNotes: nombre, destinations: autres),
        );
        if (destination == null) return;
      }

      final int deplacees = await repo.supprimer(categorie.id, deplacerVers: destination);

      if (!context.mounted) return;
      if (deplacees > 0) {
        final int? versId = destination?.categorieId;
        final String nomDestination = versId == null
            ? libelleSansCategorieNote
            : toutes.firstWhere((CategorieNote c) => c.id == versId).nom;
        afficherMessage(
          context,
          'Catégorie « ${categorie.nom} » supprimée. ${_notes(deplacees)} '
          '${deplacees > 1 ? 'déplacées' : 'déplacée'} vers « $nomDestination ».',
        );
      } else {
        afficherMessage(context, 'Catégorie « ${categorie.nom} » supprimée.');
      }
    } catch (erreur) {
      if (context.mounted) afficherMessage(context, messageErreur(erreur));
    }
  }
}

String _notes(int n) => n > 1 ? '$n notes' : '1 note';

class _LigneCategorie extends StatelessWidget {
  const _LigneCategorie({
    required this.categorie,
    required this.nombreNotes,
    required this.onRenommer,
    required this.onSupprimer,
  });

  final CategorieNote categorie;
  final int nombreNotes;
  final VoidCallback onRenommer;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.label_outline, color: scheme.primary),
      title: Text(categorie.nom),
      subtitle: Text(nombreNotes == 0 ? 'Aucune note' : _notes(nombreNotes)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Renommer ${categorie.nom}',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onRenommer,
          ),
          IconButton(
            tooltip: 'Supprimer ${categorie.nom}',
            icon: const Icon(Icons.delete_outline),
            onPressed: onSupprimer,
          ),
        ],
      ),
    );
  }
}

/// Où déplacer les notes d'une catégorie qu'on supprime : une autre catégorie, ou « Sans catégorie ». Aucune
/// destination n'est présélectionnée : il faut choisir, pour ne pas déplacer des notes par mégarde.
class _DialogueDeplacement extends StatefulWidget {
  const _DialogueDeplacement({required this.categorie, required this.nombreNotes, required this.destinations});

  final CategorieNote categorie;
  final int nombreNotes;
  final List<CategorieNote> destinations;

  @override
  State<_DialogueDeplacement> createState() => _DialogueDeplacementState();
}

class _DialogueDeplacementState extends State<_DialogueDeplacement> {
  /// `null` = pas encore choisi ; sinon la destination retenue.
  DestinationNotes? _choix;

  bool _estChoisie(int? categorieId) => _choix != null && _choix!.categorieId == categorieId;

  @override
  Widget build(BuildContext context) {
    final int n = widget.nombreNotes;
    return AlertDialog(
      title: const Text('Supprimer cette catégorie ?'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'La catégorie « ${widget.categorie.nom} » contient ${_notes(n)}. '
              'Choisissez où ${n > 1 ? 'les' : 'la'} déplacer : aucune note n’est supprimée.',
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (final CategorieNote c in widget.destinations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: _estChoisie(c.id),
                        leading: Icon(_estChoisie(c.id) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        title: Text(c.nom),
                        onTap: () => setState(() => _choix = DestinationNotes.categorie(c.id)),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: _estChoisie(null),
                      leading: Icon(_estChoisie(null) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      title: const Text(libelleSansCategorieNote),
                      subtitle: const Text('Les notes n’auront plus de catégorie'),
                      onTap: () => setState(() => _choix = const DestinationNotes.sansCategorie()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _choix == null ? null : () => Navigator.of(context).pop(_choix),
          child: const Text('Déplacer et supprimer'),
        ),
      ],
    );
  }
}
