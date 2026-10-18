import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Base de données temporaire en mémoire, avec toutes les tables, contraintes et index réels.
AppDatabase creerBaseEnMemoire() {
  // Plusieurs bases dans le même test suite : ce n'est pas une erreur.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Raccourcis pour préparer des lignes valides dans les tests.
extension PreparationBase on AppDatabase {
  Future<int> insererClient({String nom = 'Dupont'}) =>
      into(clients).insert(ClientsCompanion.insert(nom: Value(nom)));

  Future<int> insererProduit({String reference = 'PRD-0001', int prix = 1000, int stock = 5}) =>
      into(produits).insert(
        ProduitsCompanion.insert(
          reference: reference,
          nom: 'Produit $reference',
          categorie: CategorieProduit.crochet,
          prixVenteCentimes: prix,
          quantiteStock: Value(stock),
        ),
      );

  Future<int> insererVente({int sousTotal = 1000, int total = 1000, int? clientId}) =>
      into(ventes).insert(
        VentesCompanion.insert(
          sousTotalCentimes: sousTotal,
          totalCentimes: total,
          clientId: Value(clientId),
        ),
      );
}
