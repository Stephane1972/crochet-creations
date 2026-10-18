import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants/app_constants.dart';
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
  static const int versionSchema = 1;

  @override
  int get schemaVersion => versionSchema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Première installation : création de toutes les tables et index.
    onCreate: (Migrator m) async {
      await m.createAll();
    },

    // Mise à jour de l'application avec un schéma plus récent.
    // Chaque nouvelle version ajoute son bloc `if (from < N)` ; ils s'exécutent dans l'ordre,
    // ce qui permet de passer de n'importe quelle ancienne version à la dernière.
    //
    //   if (from < 2) { await m.addColumn(produits, produits.nouvelleColonne); }
    //   if (from < 3) { await m.createTable(nouvelleTable); }
    onUpgrade: (Migrator m, int from, int to) async {
      // Version 1 : rien à migrer pour l'instant.
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
