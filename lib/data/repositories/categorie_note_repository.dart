import 'package:drift/drift.dart';

import '../../domain/erreurs.dart';
import '../../domain/notes.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';

/// Où vont les notes d'une catégorie qu'on supprime : vers une autre catégorie, ou vers « Sans catégorie ».
class DestinationNotes {
  /// Les notes passent dans la catégorie [categorieId].
  const DestinationNotes.categorie(int this.categorieId);

  /// Les notes n'ont plus de catégorie : « Sans catégorie ».
  const DestinationNotes.sansCategorie() : categorieId = null;

  /// `null` = « Sans catégorie ».
  final int? categorieId;
}

/// Catégories de notes : lister, créer, renommer, supprimer (en déplaçant les notes qu'elles contiennent).
///
/// Une note enregistre l'**identifiant** de sa catégorie, jamais son nom : renommer ne touche à aucune note.
/// Supprimer une catégorie ne supprime jamais une note : elles passent dans une autre catégorie ou dans
/// « Sans catégorie ».
class CategorieNoteRepository {
  CategorieNoteRepository(this._db);

  final AppDatabase _db;

  // --- Lecture -----------------------------------------------------------------

  /// Toutes les catégories, dans l'ordre d'affichage (création, sauf changement).
  Future<List<CategorieNote>> lister() => _requete().get();

  /// Les catégories, mises à jour automatiquement.
  Stream<List<CategorieNote>> observer() => _requete().watch();

  Future<CategorieNote?> obtenir(int id) =>
      (_db.select(_db.categoriesNote)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Nombre de notes de chaque catégorie, par identifiant. Les catégories sans note n'y figurent pas.
  Future<Map<int, int>> nombreNotesParCategorie() async {
    final List<QueryRow> lignes = await _db
        .customSelect(
          'SELECT categorie_id AS categorie, COUNT(*) AS n FROM notes WHERE categorie_id IS NOT NULL '
          'GROUP BY categorie_id',
          readsFrom: <ResultSetImplementation>{_db.notes},
        )
        .get();
    return <int, int>{for (final QueryRow l in lignes) l.read<int>('categorie'): l.read<int>('n')};
  }

  Future<int> nombreNotes(int categorieId) async => (await nombreNotesParCategorie())[categorieId] ?? 0;

  /// Le nombre de notes de chaque catégorie, mis à jour automatiquement (note écrite, déplacée, supprimée...).
  Stream<Map<int, int>> observerNombreNotesParCategorie() => observerTables(
    _db,
    <ResultSetImplementation>{_db.notes, _db.categoriesNote},
    nombreNotesParCategorie,
  );

  // --- Écriture ----------------------------------------------------------------

  /// Crée une catégorie, à la fin de la liste. Lance [DonneeInvalide] si le nom est vide, trop long, réservé ou déjà
  /// pris (sans tenir compte des majuscules, des accents ni des espaces).
  Future<CategorieNote> creer(String nom) {
    return _db.transaction(() async {
      final String propre = await _nomValide(nom);
      final List<CategorieNote> existantes = await lister();
      final int position = existantes.isEmpty
          ? 0
          : existantes.map((CategorieNote c) => c.position).reduce((int a, int b) => a > b ? a : b) + 1;
      final int id = await _db
          .into(_db.categoriesNote)
          .insert(CategoriesNoteCompanion.insert(nom: propre, position: Value(position)));
      return (await obtenir(id))!;
    });
  }

  /// Change le nom d'une catégorie ; son identifiant, et donc ses notes, ne bougent pas.
  Future<CategorieNote> renommer(int id, String nom) {
    return _db.transaction(() async {
      final CategorieNote categorie = await _categorie(id);
      final String propre = await _nomValide(nom, sauf: id);
      if (propre != categorie.nom) {
        await (_db.update(_db.categoriesNote)..where((t) => t.id.equals(id))).write(
          CategoriesNoteCompanion(nom: Value(propre), modifieLe: Value(DateTime.now())),
        );
      }
      return (await obtenir(id))!;
    });
  }

  /// Supprime une catégorie. Si elle a des notes, [deplacerVers] est obligatoire : la catégorie qui les reçoit, ou
  /// [DestinationNotes.sansCategorie]. Retourne le nombre de notes déplacées.
  ///
  /// Lance [ElementIntrouvable] si la catégorie (ou celle qui reçoit) n'existe pas, [DonneeInvalide] si les notes n'ont
  /// nulle part où aller. Tout ou rien : en cas de refus, rien n'est déplacé ni supprimé. Aucune note n'est jamais
  /// supprimée ni modifiée autrement que par sa catégorie (son titre, son texte et sa date de modification restent).
  Future<int> supprimer(int id, {DestinationNotes? deplacerVers}) {
    return _db.transaction(() async {
      final CategorieNote categorie = await _categorie(id);
      final int nombre = await nombreNotes(id);

      if (nombre > 0) {
        if (deplacerVers == null) {
          throw DonneeInvalide(
            'Cette catégorie contient ${nombre > 1 ? '$nombre notes' : '1 note'} : '
            'choisissez où ${nombre > 1 ? 'les' : 'la'} déplacer.',
          );
        }
        final int? destination = deplacerVers.categorieId;
        if (destination == id) {
          throw const DonneeInvalide('Choisissez une autre catégorie que celle qu’on supprime.');
        }
        if (destination != null && await obtenir(destination) == null) {
          throw const ElementIntrouvable('La catégorie choisie n’existe plus.');
        }
        // Seule la catégorie change : la date de modification de la note (qui sert à les ranger) ne bouge pas.
        await (_db.update(_db.notes)..where((t) => t.categorieId.equals(categorie.id))).write(
          NotesCompanion(categorieId: Value(destination)),
        );
      }

      await (_db.delete(_db.categoriesNote)..where((t) => t.id.equals(id))).go();
      return nombre;
    });
  }

  // --- Aides -------------------------------------------------------------------

  SimpleSelectStatement<$CategoriesNoteTable, CategorieNote> _requete() => _db.select(_db.categoriesNote)
    ..orderBy([(t) => OrderingTerm.asc(t.position), (t) => OrderingTerm.asc(t.id)]);

  Future<CategorieNote> _categorie(int id) async {
    final CategorieNote? categorie = await obtenir(id);
    if (categorie == null) throw const ElementIntrouvable('Cette catégorie de notes n’existe plus.');
    return categorie;
  }

  /// Le nom nettoyé, ou [DonneeInvalide]. [sauf] : la catégorie qu'on renomme, qui peut garder son propre nom.
  Future<String> _nomValide(String nom, {int? sauf}) async {
    final String? probleme = erreurNomCategorieNote(nom);
    if (probleme != null) throw DonneeInvalide(probleme);
    final String propre = nettoyerNomCategorieNote(nom);
    for (final CategorieNote autre in await lister()) {
      if (autre.id != sauf && memeNomCategorieNote(autre.nom, propre)) {
        throw DonneeInvalide('Une catégorie « ${autre.nom} » existe déjà.');
      }
    }
    return propre;
  }
}
