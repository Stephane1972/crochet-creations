import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../data/database/app_database.dart';
import '../../domain/notes.dart';
import 'notes_providers.dart';

/// Ce qu'on affiche dans la liste : toutes les notes, celles d'une catégorie, ou celles qui n'en ont pas.
enum _GenreFiltre { toutes, categorie, sansCategorie }

class _Filtre {
  const _Filtre.toutes() : genre = _GenreFiltre.toutes, categorieId = null;
  const _Filtre.categorie(int this.categorieId) : genre = _GenreFiltre.categorie;
  const _Filtre.sansCategorie() : genre = _GenreFiltre.sansCategorie, categorieId = null;

  final _GenreFiltre genre;
  final int? categorieId;

  bool garde(Note note) {
    switch (genre) {
      case _GenreFiltre.toutes:
        return true;
      case _GenreFiltre.categorie:
        return note.categorieId == categorieId;
      case _GenreFiltre.sansCategorie:
        return note.categorieId == null;
    }
  }

  @override
  bool operator ==(Object other) => other is _Filtre && other.genre == genre && other.categorieId == categorieId;

  @override
  int get hashCode => Object.hash(genre, categorieId);
}

/// Bloc-notes : la liste des notes, la dernière modifiée en premier, filtrable par catégorie.
/// Un appui sur une note l'ouvre pour la lire, la modifier ou la supprimer. L'icône d'étiquette de la barre du haut
/// mène aux catégories (ajouter, renommer, supprimer).
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  _Filtre _filtre = const _Filtre.toutes();

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Note>> notes = ref.watch(notesProvider);
    final AsyncValue<List<CategorieNote>> categories = ref.watch(categoriesNoteProvider);
    final List<CategorieNote> listeCategories = categories.valueOrNull ?? const <CategorieNote>[];

    // Une catégorie supprimée pendant qu'elle était choisie : on revient à « Toutes ».
    final _Filtre filtre =
        _filtre.genre == _GenreFiltre.categorie &&
            categories.hasValue &&
            categorieNoteParId(listeCategories, _filtre.categorieId) == null
        ? const _Filtre.toutes()
        : _filtre;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bloc-notes'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Catégories de notes',
            icon: const Icon(Icons.label_outline),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.categoriesNote),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'bouton-nouvelle-note',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.noteNouvelle),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle note'),
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 52,
            child: ListView(
              key: const Key('filtres-notes'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: <Widget>[
                _PuceFiltre(
                  libelle: 'Toutes',
                  choisie: filtre == const _Filtre.toutes(),
                  onChoisie: () => setState(() => _filtre = const _Filtre.toutes()),
                ),
                for (final CategorieNote c in listeCategories) ...<Widget>[
                  const SizedBox(width: 8),
                  _PuceFiltre(
                    libelle: c.nom,
                    choisie: filtre == _Filtre.categorie(c.id),
                    onChoisie: () => setState(() => _filtre = _Filtre.categorie(c.id)),
                  ),
                ],
                const SizedBox(width: 8),
                _PuceFiltre(
                  libelle: libelleSansCategorieNote,
                  choisie: filtre == const _Filtre.sansCategorie(),
                  onChoisie: () => setState(() => _filtre = const _Filtre.sansCategorie()),
                ),
              ],
            ),
          ),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object erreur, StackTrace pile) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('Impossible de charger les notes.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(notesProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (List<Note> toutes) {
                // Tant que les catégories se chargent, on n'affiche pas « Sans catégorie » pour une note qui en a une.
                if (!categories.hasValue && !categories.hasError) {
                  return const Center(child: CircularProgressIndicator());
                }
                final List<Note> affichees = toutes.where(filtre.garde).toList();
                if (affichees.isEmpty) {
                  return _AucuneNote(
                    avecNotes: toutes.isNotEmpty,
                    filtre: filtre,
                    categorie: categorieNoteParId(listeCategories, filtre.categorieId),
                  );
                }
                return ListView.separated(
                  // De la place sous la dernière note pour que le bouton « Nouvelle note » ne la masque pas.
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: affichees.length,
                  separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final Note note = affichees[index];
                    return _LigneNote(
                      note: note,
                      categorie: categorieNoteParId(listeCategories, note.categorieId),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PuceFiltre extends StatelessWidget {
  const _PuceFiltre({required this.libelle, required this.choisie, required this.onChoisie});

  final String libelle;
  final bool choisie;
  final VoidCallback onChoisie;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(libelle), selected: choisie, onSelected: (bool _) => onChoisie());
  }
}

class _LigneNote extends StatelessWidget {
  const _LigneNote({required this.note, required this.categorie});

  final Note note;
  final CategorieNote? categorie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? discret = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: const Icon(Icons.sticky_note_2_outlined),
      ),
      title: Text(note.titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (note.contenu.isNotEmpty) Text(note.contenu, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            '${categorie?.nom ?? libelleSansCategorieNote} · modifiée le ${formatDateCourte(note.modifieLe)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: discret,
          ),
        ],
      ),
      isThreeLine: note.contenu.isNotEmpty,
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.noteModifier, arguments: note.id),
    );
  }
}

class _AucuneNote extends StatelessWidget {
  const _AucuneNote({required this.avecNotes, required this.filtre, required this.categorie});

  /// Faux : le bloc-notes est vide. Vrai : il a des notes, mais aucune ne correspond au filtre.
  final bool avecNotes;
  final _Filtre filtre;
  final CategorieNote? categorie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String titre, String? conseil) = !avecNotes
        ? ('Aucune note pour le moment.', 'Appuyez sur « Nouvelle note » pour écrire la première.')
        : switch (filtre.genre) {
            _GenreFiltre.categorie => ('Aucune note dans « ${categorie?.nom ?? ''} ».', null),
            _GenreFiltre.sansCategorie => ('Aucune note sans catégorie.', null),
            _GenreFiltre.toutes => ('Aucune note.', null),
          };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.sticky_note_2_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(titre, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (conseil != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                conseil,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
