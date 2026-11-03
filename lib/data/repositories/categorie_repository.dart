import 'package:drift/drift.dart';

import '../../domain/categories_produit.dart';
import '../../domain/erreurs.dart';
import '../database/app_database.dart';

/// Catégories de produits : lister, créer, renommer, supprimer (en déplaçant les produits qu'elles contiennent).
///
/// Un produit enregistre la **clé** de sa catégorie, jamais son nom : renommer ne touche à aucun produit.
class CategorieRepository {
  CategorieRepository(this._db);

  final AppDatabase _db;

  // --- Lecture -----------------------------------------------------------------

  /// Toutes les catégories, dans l'ordre d'affichage (création, sauf changement).
  Future<List<CategorieProduit>> lister() => _requete().get();

  /// Les catégories, mises à jour automatiquement.
  Stream<List<CategorieProduit>> observer() => _requete().watch();

  Future<CategorieProduit?> obtenir(int id) =>
      (_db.select(_db.categoriesProduit)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<CategorieProduit?> parCle(String cle) =>
      (_db.select(_db.categoriesProduit)..where((t) => t.cle.equals(cle))).getSingleOrNull();

  /// Nombre de produits de chaque catégorie (archivés compris), par clé. Les catégories vides n'y figurent pas.
  Future<Map<String, int>> nombreProduitsParCategorie() async {
    final List<Produit> produits = await _db.select(_db.produits).get();
    final Map<String, int> comptes = <String, int>{};
    for (final Produit p in produits) {
      comptes[p.categorie] = (comptes[p.categorie] ?? 0) + 1;
    }
    return comptes;
  }

  Future<int> nombreProduits(String cle) async => (await nombreProduitsParCategorie())[cle] ?? 0;

  // --- Écriture ----------------------------------------------------------------

  /// Crée une catégorie, à la fin de la liste. Lance [DonneeInvalide] si le nom est vide, trop long ou déjà pris
  /// (sans tenir compte des majuscules, des accents ni des espaces).
  Future<CategorieProduit> creer(String nom) {
    return _db.transaction(() async {
      final String propre = await _nomValide(nom);
      final List<CategorieProduit> existantes = await lister();
      final int position = existantes.isEmpty
          ? 0
          : existantes.map((CategorieProduit c) => c.position).reduce((int a, int b) => a > b ? a : b) + 1;
      final String cle = await _nouvelleCle();
      final int id = await _db
          .into(_db.categoriesProduit)
          .insert(CategoriesProduitCompanion.insert(cle: cle, nom: propre, position: Value(position)));
      return (await obtenir(id))!;
    });
  }

  /// Change le nom d'une catégorie ; sa clé, et donc ses produits, ne bougent pas.
  Future<CategorieProduit> renommer(int id, String nom) {
    return _db.transaction(() async {
      final CategorieProduit categorie = await _categorie(id);
      final String propre = await _nomValide(nom, sauf: id);
      if (propre != categorie.nom) {
        await (_db.update(_db.categoriesProduit)..where((t) => t.id.equals(id))).write(
          CategoriesProduitCompanion(nom: Value(propre), modifieLe: Value(DateTime.now())),
        );
      }
      return (await obtenir(id))!;
    });
  }

  /// Supprime une catégorie. Si elle contient des produits (archivés compris), [deplacerVersCle] est obligatoire : la
  /// clé de la catégorie qui les reçoit. Retourne le nombre de produits déplacés.
  ///
  /// Lance [ElementIntrouvable] si la catégorie (ou celle qui reçoit) n'existe pas, [DonneeInvalide] si les produits
  /// n'ont nulle part où aller. Tout ou rien : en cas de refus, rien n'est déplacé ni supprimé.
  Future<int> supprimer(int id, {String? deplacerVersCle}) {
    return _db.transaction(() async {
      final CategorieProduit categorie = await _categorie(id);
      final int nombre = await nombreProduits(categorie.cle);

      if (nombre > 0) {
        if (deplacerVersCle == null) {
          throw DonneeInvalide(
            'Cette catégorie contient ${nombre > 1 ? '$nombre produits' : '1 produit'} : '
            'choisissez la catégorie où ${nombre > 1 ? 'les' : 'le'} déplacer.',
          );
        }
        if (deplacerVersCle == categorie.cle) {
          throw const DonneeInvalide('Choisissez une autre catégorie que celle qu’on supprime.');
        }
        if (await parCle(deplacerVersCle) == null) {
          throw const ElementIntrouvable('La catégorie choisie n’existe plus.');
        }
        await (_db.update(_db.produits)..where((t) => t.categorie.equals(categorie.cle))).write(
          ProduitsCompanion(categorie: Value(deplacerVersCle), modifieLe: Value(DateTime.now())),
        );
      }

      await (_db.delete(_db.categoriesProduit)..where((t) => t.id.equals(id))).go();
      return nombre;
    });
  }

  // --- Aides -------------------------------------------------------------------

  SimpleSelectStatement<$CategoriesProduitTable, CategorieProduit> _requete() => _db.select(_db.categoriesProduit)
    ..orderBy([(t) => OrderingTerm.asc(t.position), (t) => OrderingTerm.asc(t.id)]);

  Future<CategorieProduit> _categorie(int id) async {
    final CategorieProduit? categorie = await obtenir(id);
    if (categorie == null) throw const ElementIntrouvable('Cette catégorie n’existe plus.');
    return categorie;
  }

  /// Le nom nettoyé, ou [DonneeInvalide]. [sauf] : la catégorie qu'on renomme, qui peut garder son propre nom.
  Future<String> _nomValide(String nom, {int? sauf}) async {
    final String? probleme = erreurNomCategorie(nom);
    if (probleme != null) throw DonneeInvalide(probleme);
    final String propre = nettoyerNomCategorie(nom);
    for (final CategorieProduit autre in await lister()) {
      if (autre.id != sauf && memeNomCategorie(autre.nom, propre)) {
        throw DonneeInvalide('Une catégorie « ${autre.nom} » existe déjà.');
      }
    }
    return propre;
  }

  /// Une clé interne inédite (`cat_` et des chiffres et lettres tirés de l'heure).
  Future<String> _nouvelleCle() async {
    final String base = 'cat_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    String cle = base;
    int numero = 2;
    while (await parCle(cle) != null) {
      cle = '${base}_$numero';
      numero++;
    }
    return cle;
  }
}
