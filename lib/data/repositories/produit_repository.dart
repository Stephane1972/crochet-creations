import 'package:drift/drift.dart';

import '../../core/utils/texte.dart';
import '../../domain/calculs/stock.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../database/app_database.dart';
import 'numerotation_repository.dart';

/// Données saisies pour créer ou modifier un produit.
class DonneesProduit {
  const DonneesProduit({
    required this.nom,
    required this.categorie,
    required this.prixVenteCentimes,
    this.description,
    this.matieres,
    this.couleur,
    this.dimensions,
    this.tempsFabricationMinutes,
    this.coutMatiereCentimes = 0,
    this.quantiteStock = 0,
    this.seuilAlerteStock = 0,
    this.statut = StatutProduit.disponible,
    this.personnalisable = false,
    this.photoPrincipaleChemin,
  });

  final String nom;
  final CategorieProduit categorie;
  final int prixVenteCentimes;
  final String? description;
  final String? matieres;
  final String? couleur;
  final String? dimensions;
  final int? tempsFabricationMinutes;
  final int coutMatiereCentimes;
  final int quantiteStock;
  final int seuilAlerteStock;
  final StatutProduit statut;
  final bool personnalisable;
  final String? photoPrincipaleChemin;

  /// Lance [DonneeInvalide] (message en français) si une valeur est impossible.
  void valider() {
    if (nom.trim().isEmpty) {
      throw const DonneeInvalide('Le nom du produit est obligatoire.');
    }
    if (prixVenteCentimes < 0) {
      throw const DonneeInvalide('Le prix de vente ne peut pas être négatif.');
    }
    if (coutMatiereCentimes < 0) {
      throw const DonneeInvalide('Le coût des matières ne peut pas être négatif.');
    }
    if (quantiteStock < 0) {
      throw const DonneeInvalide('Le stock ne peut pas être négatif.');
    }
    if (seuilAlerteStock < 0) {
      throw const DonneeInvalide('Le seuil d’alerte ne peut pas être négatif.');
    }
    if ((tempsFabricationMinutes ?? 0) < 0) {
      throw const DonneeInvalide('Le temps de fabrication ne peut pas être négatif.');
    }
  }
}

/// Données saisies pour créer ou modifier une variante (couleur, taille...).
class DonneesVariante {
  const DonneesVariante({
    required this.libelle,
    this.couleur,
    this.taille,
    this.prixCentimes,
    this.quantiteStock = 0,
    this.seuilAlerteStock,
  });

  final String libelle;
  final String? couleur;
  final String? taille;

  /// Vide = prix du produit.
  final int? prixCentimes;
  final int quantiteStock;

  /// Vide = seuil du produit.
  final int? seuilAlerteStock;

  void valider() {
    if (libelle.trim().isEmpty) {
      throw const DonneeInvalide('Le nom de la variante est obligatoire.');
    }
    if ((prixCentimes ?? 0) < 0) {
      throw const DonneeInvalide('Le prix ne peut pas être négatif.');
    }
    if (quantiteStock < 0) {
      throw const DonneeInvalide('Le stock ne peut pas être négatif.');
    }
    if ((seuilAlerteStock ?? 0) < 0) {
      throw const DonneeInvalide('Le seuil d’alerte ne peut pas être négatif.');
    }
  }
}

/// Catalogue : produits, variantes, photos secondaires et mouvements de stock.
///
/// Les recherches, filtres, alertes et la duplication arrivent à l'étape 3 (écrans produits).
class ProduitRepository {
  ProduitRepository(this._db, this._numerotation);

  final AppDatabase _db;
  final NumerotationRepository _numerotation;

  // --- Produits -------------------------------------------------------------

  /// Crée un produit avec sa référence automatique (`PRD-0001`...).
  Future<Produit> creer(DonneesProduit donnees) async {
    donnees.valider();
    return _db.transaction(() async {
      final String reference = await _numerotation.prochaineReferenceProduit();
      final int id = await _db
          .into(_db.produits)
          .insert(
            ProduitsCompanion.insert(
              reference: reference,
              nom: donnees.nom.trim(),
              categorie: donnees.categorie,
              prixVenteCentimes: donnees.prixVenteCentimes,
              description: Value(nullSiVide(donnees.description)),
              matieres: Value(nullSiVide(donnees.matieres)),
              couleur: Value(nullSiVide(donnees.couleur)),
              dimensions: Value(nullSiVide(donnees.dimensions)),
              tempsFabricationMinutes: Value(donnees.tempsFabricationMinutes),
              coutMatiereCentimes: Value(donnees.coutMatiereCentimes),
              quantiteStock: Value(donnees.quantiteStock),
              seuilAlerteStock: Value(donnees.seuilAlerteStock),
              statut: Value(donnees.statut),
              personnalisable: Value(donnees.personnalisable),
              photoPrincipaleChemin: Value(nullSiVide(donnees.photoPrincipaleChemin)),
            ),
          );
      return _produit(id);
    });
  }

  /// Remplace les informations d'un produit (la référence ne change jamais).
  Future<Produit> modifier(int id, DonneesProduit donnees) async {
    donnees.valider();
    final int lignes = await (_db.update(_db.produits)..where((t) => t.id.equals(id))).write(
      ProduitsCompanion(
        nom: Value(donnees.nom.trim()),
        categorie: Value(donnees.categorie),
        prixVenteCentimes: Value(donnees.prixVenteCentimes),
        description: Value(nullSiVide(donnees.description)),
        matieres: Value(nullSiVide(donnees.matieres)),
        couleur: Value(nullSiVide(donnees.couleur)),
        dimensions: Value(nullSiVide(donnees.dimensions)),
        tempsFabricationMinutes: Value(donnees.tempsFabricationMinutes),
        coutMatiereCentimes: Value(donnees.coutMatiereCentimes),
        quantiteStock: Value(donnees.quantiteStock),
        seuilAlerteStock: Value(donnees.seuilAlerteStock),
        statut: Value(donnees.statut),
        personnalisable: Value(donnees.personnalisable),
        photoPrincipaleChemin: Value(nullSiVide(donnees.photoPrincipaleChemin)),
        modifieLe: Value(DateTime.now()),
      ),
    );
    if (lignes == 0) throw const ElementIntrouvable('Ce produit n’existe plus.');
    return _produit(id);
  }

  Future<Produit?> obtenir(int id) =>
      (_db.select(_db.produits)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Produits triés par nom ; les produits archivés sont exclus sauf demande contraire.
  Future<List<Produit>> lister({bool inclureArchives = false}) => _requeteListe(inclureArchives).get();

  Stream<List<Produit>> observerCatalogue({bool inclureArchives = false}) =>
      _requeteListe(inclureArchives).watch();

  /// Archive un produit : il disparaît du catalogue mais reste dans l'historique des ventes.
  Future<void> archiver(int id) => _marquerArchive(id, DateTime.now());

  Future<void> restaurer(int id) => _marquerArchive(id, null);

  // --- Variantes ------------------------------------------------------------

  Future<List<VarianteProduit>> variantes(int produitId, {bool inclureArchivees = false}) {
    final SimpleSelectStatement<$VariantesProduitTable, VarianteProduit> requete =
        _db.select(_db.variantesProduit)
          ..where((t) => t.produitId.equals(produitId))
          ..orderBy([(t) => OrderingTerm(expression: t.libelle.collate(Collate.noCase))]);
    if (!inclureArchivees) {
      requete.where((t) => t.archiveLe.isNull());
    }
    return requete.get();
  }

  Future<VarianteProduit> ajouterVariante(int produitId, DonneesVariante donnees) async {
    donnees.valider();
    if (await obtenir(produitId) == null) {
      throw const ElementIntrouvable('Ce produit n’existe plus.');
    }
    final int id = await _db
        .into(_db.variantesProduit)
        .insert(
          VariantesProduitCompanion.insert(
            produitId: produitId,
            libelle: donnees.libelle.trim(),
            couleur: Value(nullSiVide(donnees.couleur)),
            taille: Value(nullSiVide(donnees.taille)),
            prixCentimes: Value(donnees.prixCentimes),
            quantiteStock: Value(donnees.quantiteStock),
            seuilAlerteStock: Value(donnees.seuilAlerteStock),
          ),
        );
    return _variante(id);
  }

  Future<VarianteProduit> modifierVariante(int id, DonneesVariante donnees) async {
    donnees.valider();
    final int lignes = await (_db.update(_db.variantesProduit)..where((t) => t.id.equals(id))).write(
      VariantesProduitCompanion(
        libelle: Value(donnees.libelle.trim()),
        couleur: Value(nullSiVide(donnees.couleur)),
        taille: Value(nullSiVide(donnees.taille)),
        prixCentimes: Value(donnees.prixCentimes),
        quantiteStock: Value(donnees.quantiteStock),
        seuilAlerteStock: Value(donnees.seuilAlerteStock),
        modifieLe: Value(DateTime.now()),
      ),
    );
    if (lignes == 0) throw const ElementIntrouvable('Cette variante n’existe plus.');
    return _variante(id);
  }

  Future<void> archiverVariante(int id) => _marquerVarianteArchivee(id, DateTime.now());

  Future<void> restaurerVariante(int id) => _marquerVarianteArchivee(id, null);

  // --- Photos secondaires ---------------------------------------------------

  Future<List<PhotoProduit>> photosSecondaires(int produitId) =>
      (_db.select(_db.photosProduit)
            ..where((t) => t.produitId.equals(produitId))
            ..orderBy([(t) => OrderingTerm(expression: t.position), (t) => OrderingTerm(expression: t.id)]))
          .get();

  /// Ajoute une photo à la fin de la liste.
  Future<PhotoProduit> ajouterPhoto(int produitId, String chemin) async {
    if (chemin.trim().isEmpty) throw const DonneeInvalide('Le chemin de la photo est vide.');
    final List<PhotoProduit> existantes = await photosSecondaires(produitId);
    final int position = existantes.isEmpty ? 0 : existantes.last.position + 1;
    final int id = await _db
        .into(_db.photosProduit)
        .insert(
          PhotosProduitCompanion.insert(
            produitId: produitId,
            chemin: chemin.trim(),
            position: Value(position),
          ),
        );
    return (_db.select(_db.photosProduit)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> supprimerPhoto(int photoId) async {
    await (_db.delete(_db.photosProduit)..where((t) => t.id.equals(photoId))).go();
  }

  // --- Stock ----------------------------------------------------------------

  /// Ajoute ([delta] > 0) ou retire ([delta] < 0) des articles en stock : réapprovisionnement,
  /// inventaire, correction. Retourne le nouveau stock.
  ///
  /// Si le produit a des variantes, indiquer [varianteId] : le stock est alors celui de la variante.
  /// Lance [StockInsuffisant] si le stock deviendrait négatif (rien n'est modifié).
  Future<int> ajusterStock({required int produitId, int? varianteId, required int delta}) {
    return _db.transaction(() async {
      final Produit produit = await _produit(produitId);

      if (varianteId == null) {
        final int nouveau = produit.quantiteStock + delta;
        if (nouveau < 0) {
          throw StockInsuffisant(
            designation: produit.nom,
            disponible: produit.quantiteStock,
            demande: -delta,
          );
        }
        await (_db.update(_db.produits)..where((t) => t.id.equals(produitId))).write(
          ProduitsCompanion(quantiteStock: Value(nouveau), modifieLe: Value(DateTime.now())),
        );
        return nouveau;
      }

      final VarianteProduit variante = await _variante(varianteId);
      if (variante.produitId != produitId) {
        throw const DonneeInvalide('Cette variante n’appartient pas à ce produit.');
      }
      final int nouveau = variante.quantiteStock + delta;
      if (nouveau < 0) {
        throw StockInsuffisant(
          designation: '${produit.nom} – ${variante.libelle}',
          disponible: variante.quantiteStock,
          demande: -delta,
        );
      }
      await (_db.update(_db.variantesProduit)..where((t) => t.id.equals(varianteId))).write(
        VariantesProduitCompanion(quantiteStock: Value(nouveau), modifieLe: Value(DateTime.now())),
      );
      return nouveau;
    });
  }

  /// Décrémente le stock lors d'une vente. Un produit « sur commande » n'est pas suivi en stock :
  /// dans ce cas il ne se passe rien. Lance [StockInsuffisant] si le stock ne suffit pas.
  Future<void> consommerStock({
    required int produitId,
    int? varianteId,
    required int quantite,
  }) async {
    if (quantite < 1) throw const DonneeInvalide('La quantité doit être d’au moins 1.');
    await _db.transaction(() async {
      final Produit produit = await _produit(produitId);
      if (!suitLeStock(produit.statut)) return;
      await ajusterStock(produitId: produitId, varianteId: varianteId, delta: -quantite);
    });
  }

  // --- Interne --------------------------------------------------------------

  SimpleSelectStatement<$ProduitsTable, Produit> _requeteListe(bool inclureArchives) {
    final SimpleSelectStatement<$ProduitsTable, Produit> requete = _db.select(_db.produits)
      ..orderBy([(t) => OrderingTerm(expression: t.nom.collate(Collate.noCase))]);
    if (!inclureArchives) {
      requete.where((t) => t.archiveLe.isNull());
    }
    return requete;
  }

  Future<Produit> _produit(int id) async {
    final Produit? produit = await obtenir(id);
    if (produit == null) throw const ElementIntrouvable('Ce produit n’existe plus.');
    return produit;
  }

  Future<VarianteProduit> _variante(int id) async {
    final VarianteProduit? variante = await (_db.select(_db.variantesProduit)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (variante == null) throw const ElementIntrouvable('Cette variante n’existe plus.');
    return variante;
  }

  Future<void> _marquerArchive(int id, DateTime? date) async {
    final int lignes = await (_db.update(_db.produits)..where((t) => t.id.equals(id))).write(
      ProduitsCompanion(archiveLe: Value(date), modifieLe: Value(DateTime.now())),
    );
    if (lignes == 0) throw const ElementIntrouvable('Ce produit n’existe plus.');
  }

  Future<void> _marquerVarianteArchivee(int id, DateTime? date) async {
    final int lignes = await (_db.update(_db.variantesProduit)..where((t) => t.id.equals(id))).write(
      VariantesProduitCompanion(archiveLe: Value(date), modifieLe: Value(DateTime.now())),
    );
    if (lignes == 0) throw const ElementIntrouvable('Cette variante n’existe plus.');
  }
}
