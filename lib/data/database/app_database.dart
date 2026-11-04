import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/categories_produit.dart';
import '../../domain/enums.dart';
import 'tables.dart';

// Fichier généré par `dart run build_runner build` (la CI le fait automatiquement).
part 'app_database.g.dart';

/// Base de données de l'application : un fichier SQLite sur le téléphone,
/// entièrement hors ligne.
@DriftDatabase(
  tables: [
    ParametresEntreprise,
    NumerotationDocuments,
    CategoriesProduit,
    Produits,
    VariantesProduit,
    PhotosProduit,
    Clients,
    Ventes,
    LignesVente,
    Paiements,
    Factures,
    Devis,
    LignesDevis,
    Cours,
    InscriptionsCours,
    Depenses,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Sans argument : ouvre le vrai fichier de l'application.
  /// Les tests passent `NativeDatabase.memory()` pour une base temporaire en mémoire.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: AppConstants.nomBaseDeDonnees));

  /// Version du schéma. **À augmenter à chaque modification de `tables.dart`**,
  /// avec l'étape de migration correspondante dans [migration] (voir ARCHITECTURE.md).
  static const int versionSchema = 3;

  @override
  int get schemaVersion => versionSchema;

  /// Crée les cinq catégories de départ (celles qui existent déjà, par clé ou par nom, sont laissées telles quelles).
  /// Sert à la première installation, à la mise à jour vers le schéma 3 et à la restauration d'une sauvegarde ancienne.
  Future<void> insererCategoriesDeDepart() async {
    for (int i = 0; i < categoriesDeDepart.length; i++) {
      final CategorieDeDepart c = categoriesDeDepart[i];
      await into(categoriesProduit).insert(
        CategoriesProduitCompanion.insert(cle: c.cle, nom: c.nom, position: Value(i)),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Première installation : création de toutes les tables et index.
    onCreate: (Migrator m) async {
      await m.createAll();
      await insererCategoriesDeDepart();
    },

    // Mise à jour de l'application avec un schéma plus récent.
    // Chaque nouvelle version ajoute son bloc `if (from < N)` ; ils s'exécutent dans l'ordre,
    // ce qui permet de passer de n'importe quelle ancienne version à la dernière.
    //
    //   if (from < 2) { await m.addColumn(produits, produits.nouvelleColonne); }
    //   if (from < 3) { await m.createTable(nouvelleTable); }
    onUpgrade: (Migrator m, int from, int to) async {
      // Version 2 : le nom du client est copié dans les ventes et les devis quand sa fiche est supprimée.
      if (from < 2) {
        await m.addColumn(ventes, ventes.clientNom);
        await m.addColumn(devis, devis.clientNom);
      }
      // Version 3 : les catégories de produits deviennent modifiables. Les produits gardent leur valeur
      // (`crochet`, `doudou`...) : ce sont les clés des cinq catégories de départ, créées ici.
      if (from < 3) {
        await m.createTable(categoriesProduit);
        await insererCategoriesDeDepart();
      }
    },

    beforeOpen: (OpeningDetails details) async {
      // SQLite n'applique pas les clés étrangères tant qu'on ne le demande pas.
      await customStatement('PRAGMA foreign_keys = ON');

      // La ligne unique des réglages doit toujours exister (idempotent).
      await customStatement('INSERT OR IGNORE INTO parametres_entreprise (id) VALUES (1)');

      // Après une migration, on vérifie qu'aucune liaison n'a été cassée.
      if (details.hadUpgrade) {
        final List<QueryRow> anomalies = await customSelect('PRAGMA foreign_key_check').get();
        if (anomalies.isNotEmpty) {
          throw StateError(
            'Migration de la base : ${anomalies.length} liaison(s) incohérente(s) détectée(s).',
          );
        }
      }
    },
  );
}
