import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';

/// Les notes, la plus récemment modifiée en premier, mises à jour automatiquement.
final notesProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => ref.watch(noteRepositoryProvider).observer(),
);

/// Les catégories de notes, dans l'ordre d'affichage, mises à jour automatiquement.
final categoriesNoteProvider = StreamProvider.autoDispose<List<CategorieNote>>(
  (ref) => ref.watch(categorieNoteRepositoryProvider).observer(),
);

/// Nombre de notes de chaque catégorie, par identifiant. Les catégories vides n'y figurent pas, ni les notes
/// « Sans catégorie ».
final nombreNotesParCategorieProvider = StreamProvider.autoDispose<Map<int, int>>(
  (ref) => ref.watch(categorieNoteRepositoryProvider).observerNombreNotesParCategorie(),
);

/// La catégorie d'identifiant [id] dans [categories], ou `null` (« Sans catégorie ») si [id] est vide ou n'existe plus.
CategorieNote? categorieNoteParId(List<CategorieNote> categories, int? id) {
  if (id == null) return null;
  for (final CategorieNote c in categories) {
    if (c.id == id) return c;
  }
  return null;
}
