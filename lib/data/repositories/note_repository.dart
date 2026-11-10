import 'package:drift/drift.dart';

import '../../domain/erreurs.dart';
import '../../domain/notes.dart';
import '../../domain/pieces_jointes.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import '../stockage/stockage_pieces_jointes.dart';

/// Notes du bloc-notes : lister, lire, créer, modifier, supprimer.
///
/// Une note a un titre (obligatoire), un texte (facultatif), une catégorie (facultative : « Sans catégorie ») et des
/// **pièces jointes** (photos, vidéos, documents : 20 au plus, voir `pieces_jointes.dart`).
///
/// Les fichiers des pièces jointes sont rangés par [StockagePiecesJointes] **avant** d'appeler [creer] ou [modifier] ;
/// le repository n'enregistre que leurs lignes. Les fichiers retirés d'une note, ou d'une note supprimée, sont effacés
/// une fois la base à jour (un fichier oublié par un incident reste simplement orphelin : aucune donnée n'est perdue).
class NoteRepository {
  NoteRepository(this._db, {StockagePiecesJointes? stockagePiecesJointes}) : _stockage = stockagePiecesJointes;

  final AppDatabase _db;
  final StockagePiecesJointes? _stockage;

  // --- Lecture -----------------------------------------------------------------

  /// Toutes les notes, la plus récemment modifiée en premier.
  Future<List<Note>> lister() => _requete().get();

  /// Les notes, mises à jour automatiquement.
  Stream<List<Note>> observer() => _requete().watch();

  Future<Note?> obtenir(int id) => (_db.select(_db.notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Une note, mise à jour automatiquement (`null` si elle a été supprimée).
  Stream<Note?> observerNote(int id) =>
      (_db.select(_db.notes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  // --- Pièces jointes (lecture) ------------------------------------------------

  /// Les pièces jointes d'une note, dans l'ordre où elles ont été ajoutées.
  Future<List<PieceJointeNote>> listerPiecesJointes(int noteId) => _requetePieces(noteId).get();

  /// Les pièces jointes d'une note, mises à jour automatiquement.
  Stream<List<PieceJointeNote>> observerPiecesJointes(int noteId) => _requetePieces(noteId).watch();

  /// Nombre de pièces jointes de chaque note, par identifiant. Les notes sans pièce jointe n'y figurent pas.
  Future<Map<int, int>> nombrePiecesJointesParNote() async {
    final List<QueryRow> lignes = await _db
        .customSelect(
          'SELECT note_id AS note, COUNT(*) AS n FROM pieces_jointes_note GROUP BY note_id',
          readsFrom: <ResultSetImplementation>{_db.piecesJointesNote},
        )
        .get();
    return <int, int>{for (final QueryRow l in lignes) l.read<int>('note'): l.read<int>('n')};
  }

  /// Le nombre de pièces jointes de chaque note, mis à jour automatiquement.
  Stream<Map<int, int>> observerNombrePiecesJointesParNote() =>
      observerTables(_db, <ResultSetImplementation>{_db.piecesJointesNote}, nombrePiecesJointesParNote);

  // --- Écriture ----------------------------------------------------------------

  /// Crée une note, avec ses [piecesJointes] (déjà rangées par [StockagePiecesJointes]). Lance [DonneeInvalide] si le
  /// titre est vide ou trop long ou s'il y a trop de pièces jointes, [ElementIntrouvable] si la catégorie choisie
  /// n'existe plus. En cas d'erreur, rien n'est enregistré (les fichiers déjà rangés restent à celui qui les a rangés).
  Future<Note> creer({
    required String titre,
    String contenu = '',
    int? categorieId,
    List<PieceRangee> piecesJointes = const <PieceRangee>[],
  }) {
    return _db.transaction(() async {
      final String propre = _titreValide(titre);
      await _verifierCategorie(categorieId);
      _verifierNombre(piecesJointes.length);
      final int id = await _db
          .into(_db.notes)
          .insert(
            NotesCompanion.insert(
              titre: propre,
              contenu: Value(nettoyerContenuNote(contenu)),
              categorieId: Value(categorieId),
            ),
          );
      await _ajouterPieces(id, piecesJointes);
      return (await obtenir(id))!;
    });
  }

  /// Modifie une note (titre, texte, catégorie) et ses pièces jointes : [ajouts] (déjà rangées) et [retraits]
  /// (identifiants des pièces à retirer ; ceux qui ne sont pas à cette note sont ignorés). Sa date de modification
  /// n'est mise à jour que si quelque chose a changé : ouvrir puis enregistrer sans rien changer ne la fait pas
  /// remonter dans la liste. Les fichiers retirés sont effacés une fois la base à jour.
  Future<Note> modifier(
    int id, {
    required String titre,
    String contenu = '',
    int? categorieId,
    List<PieceRangee> ajouts = const <PieceRangee>[],
    Set<int> retraits = const <int>{},
  }) async {
    final List<String> fichiersRetires = <String>[];
    final Note resultat = await _db.transaction(() async {
      final Note note = await _note(id);
      final String titrePropre = _titreValide(titre);
      final String contenuPropre = nettoyerContenuNote(contenu);
      if (categorieId != note.categorieId) await _verifierCategorie(categorieId);

      final List<PieceJointeNote> actuelles = await listerPiecesJointes(id);
      final List<PieceJointeNote> aRetirer = actuelles.where((PieceJointeNote p) => retraits.contains(p.id)).toList();
      _verifierNombre(actuelles.length - aRetirer.length + ajouts.length);

      final bool change =
          titrePropre != note.titre ||
          contenuPropre != note.contenu ||
          categorieId != note.categorieId ||
          aRetirer.isNotEmpty ||
          ajouts.isNotEmpty;
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
      if (aRetirer.isNotEmpty) {
        await (_db.delete(_db.piecesJointesNote)..where((t) => t.id.isIn(aRetirer.map((PieceJointeNote p) => p.id)))).go();
        fichiersRetires.addAll(aRetirer.map((PieceJointeNote p) => p.nomFichier));
      }
      await _ajouterPieces(id, ajouts);
      return (await obtenir(id))!;
    });
    await _stockage?.supprimerTous(fichiersRetires);
    return resultat;
  }

  /// Supprime une note et ses pièces jointes, définitivement (l'écran demande une confirmation avant).
  /// Lance [ElementIntrouvable] si elle n'existe plus.
  Future<void> supprimer(int id) async {
    final List<String> fichiers = await _db.transaction(() async {
      await _note(id);
      final List<String> noms = (await listerPiecesJointes(id)).map((PieceJointeNote p) => p.nomFichier).toList();
      // Les lignes des pièces jointes partent avec la note (clé étrangère « CASCADE »).
      await (_db.delete(_db.notes)..where((t) => t.id.equals(id))).go();
      return noms;
    });
    await _stockage?.supprimerTous(fichiers);
  }

  // --- Aides -------------------------------------------------------------------

  SimpleSelectStatement<$PiecesJointesNoteTable, PieceJointeNote> _requetePieces(int noteId) =>
      _db.select(_db.piecesJointesNote)
        ..where((t) => t.noteId.equals(noteId))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]);

  void _verifierNombre(int total) {
    final String? probleme = erreurNombrePiecesJointes(total);
    if (probleme != null) throw DonneeInvalide(probleme);
  }

  /// Enregistre les lignes des pièces jointes d'une note, après avoir vérifié leur type et leur taille.
  Future<void> _ajouterPieces(int noteId, List<PieceRangee> pieces) async {
    for (final PieceRangee piece in pieces) {
      final String? probleme = erreurTaillePieceJointe(piece.type, piece.octets, nom: piece.nomAffiche);
      if (probleme != null) throw DonneeInvalide(probleme);
      await _db
          .into(_db.piecesJointesNote)
          .insert(
            PiecesJointesNoteCompanion.insert(
              noteId: noteId,
              nomFichier: piece.nomFichier,
              nomAffiche: nettoyerNomPieceJointe(piece.nomAffiche),
              typeFichier: piece.type,
              octets: piece.octets,
            ),
          );
    }
  }

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
