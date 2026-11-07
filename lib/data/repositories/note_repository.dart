import 'package:drift/drift.dart';

import '../../domain/erreurs.dart';
import '../../domain/notes.dart';
import '../database/app_database.dart';

/// Notes du bloc-notes : lister, lire, créer, modifier, supprimer.
///
/// Une note a un titre (obligatoire), un texte (facultatif) et une catégorie (facultative : « Sans catégorie »).
class NoteRepository {
  NoteRepository(this._db);

  final AppDatabase _db;

  // --- Lecture -----------------------------------------------------------------

  /// Toutes les notes, la plus récemment modifiée en premier.
  Future<List<Note>> lister() => _requete().get();

  /// Les notes, mises à jour automatiquement.
  Stream<List<Note>> observer() => _requete().watch();

  Future<Note?> obtenir(int id) => (_db.select(_db.notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Une note, mise à jour automatiquement (`null` si elle a été supprimée).
  Stream<Note?> observerNote(int id) =>
      (_db.select(_db.notes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  // --- Écriture ----------------------------------------------------------------

  /// Crée une note. Lance [DonneeInvalide] si le titre est vide ou trop long, [ElementIntrouvable] si la catégorie
  /// choisie n'existe plus.
  Future<Note> creer({required String titre, String contenu = '', int? categorieId}) {
    return _db.transaction(() async {
      final String propre = _titreValide(titre);
      await _verifierCategorie(categorieId);
      final int id = await _db
          .into(_db.notes)
          .insert(
            NotesCompanion.insert(
              titre: propre,
              contenu: Value(nettoyerContenuNote(contenu)),
              categorieId: Value(categorieId),
            ),
          );
      return (await obtenir(id))!;
    });
  }

  /// Modifie une note (titre, texte, catégorie). Sa date de modification n'est mise à jour que si quelque chose a
  /// changé : ouvrir puis enregistrer sans rien changer ne la fait pas remonter dans la liste.
  Future<Note> modifier(int id, {required String titre, String contenu = '', int? categorieId}) {
    return _db.transaction(() async {
      final Note note = await _note(id);
      final String titrePropre = _titreValide(titre);
      final String contenuPropre = nettoyerContenuNote(contenu);
      if (categorieId != note.categorieId) await _verifierCategorie(categorieId);

      final bool change =
          titrePropre != note.titre || contenuPropre != note.contenu || categorieId != note.categorieId;
      if (change) {
        await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
          NotesCompanion(
            titre: Value(titrePropre),
            contenu: Value(contenuPropre),
            categorieId: Value(categorieId),
            modifieLe: Value(DateTime.now()),
          ),
        );
      }
      return (await obtenir(id))!;
    });
  }

  /// Supprime une note, définitivement (l'écran demande une confirmation avant).
  /// Lance [ElementIntrouvable] si elle n'existe plus.
  Future<void> supprimer(int id) {
    return _db.transaction(() async {
      await _note(id);
      await (_db.delete(_db.notes)..where((t) => t.id.equals(id))).go();
    });
  }

  // --- Aides -------------------------------------------------------------------

  SimpleSelectStatement<$NotesTable, Note> _requete() => _db.select(_db.notes)
    ..orderBy([(t) => OrderingTerm.desc(t.modifieLe), (t) => OrderingTerm.desc(t.id)]);

  Future<Note> _note(int id) async {
    final Note? note = await obtenir(id);
    if (note == null) throw const ElementIntrouvable('Cette note n’existe plus.');
    return note;
  }

  String _titreValide(String titre) {
    final String? probleme = erreurTitreNote(titre);
    if (probleme != null) throw DonneeInvalide(probleme);
    return nettoyerTitreNote(titre);
  }

  Future<void> _verifierCategorie(int? categorieId) async {
    if (categorieId == null) return;
    final CategorieNote? categorie = await (_db.select(
      _db.categoriesNote,
    )..where((t) => t.id.equals(categorieId))).getSingleOrNull();
    if (categorie == null) throw const ElementIntrouvable('La catégorie choisie n’existe plus.');
  }
}
