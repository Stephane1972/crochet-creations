import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/categories_produit.dart';
import '../../domain/enums.dart';
import '../../domain/lieux_vente.dart';
import '../../domain/notes.dart';
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
    LieuxVente,
    Ventes,
    LignesVente,
    Paiements,
    Factures,
    Devis,
    LignesDevis,
    Cours,
    InscriptionsCours,
    Depenses,
    CategoriesNote,
    Notes,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Sans argument : ouvre le vrai fichier de l'application.
  /// Les tests passent `NativeDatabase.memory()` pour une base temporaire en mémoire.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: AppConstants.nomBaseDeDonnees));

  /// Version du schéma. **À augmenter à chaque modification de `tables.dart`**,
  /// avec l'étape de migration correspondante dans [migration] (voir ARCHITECTURE.md).
  static const int versionSchema = 5;

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

  /// Crée les quatre lieux de vente de départ (celui qui existe déjà, par nom, est laissé tel quel).
  /// Sert à la première installation, à la mise à jour vers le schéma 4 et à la restauration d'une sauvegarde ancienne.
  Future<void> insererLieuxDeDepart() async {
    for (int i = 0; i < lieuxDeDepart.length; i++) {
      await into(lieuxVente).insert(
        LieuxVenteCompanion.insert(nom: lieuxDeDepart[i].nom, position: Value(i)),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  /// Crée les deux catégories de notes de départ (celle qui existe déjà, par nom, est laissée telle quelle).
  /// Sert à la première installation, à la mise à jour vers le schéma 5 et à la restauration d'une sauvegarde ancienne.
  Future<void> insererCategoriesNoteDeDepart() async {
    for (int i = 0; i < categoriesNoteDeDepart.length; i++) {
      await into(categoriesNote).insert(
        CategoriesNoteCompanion.insert(nom: categoriesNoteDeDepart[i].nom, position: Value(i)),
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
      await insererLieuxDeDepart();
      await insererCategoriesNoteDeDepart();
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
      // Version 4 : les lieux de vente. Toutes les ventes existantes gardent `lieu_id` vide : « Non renseigné ».
      // L'index est créé en SQL pour ne pas dépendre du nom que Drift donne à l'objet généré.
      if (from < 4) {
        await m.createTable(lieuxVente);
        await m.addColumn(ventes, ventes.lieuId);
        await customStatement('CREATE INDEX IF NOT EXISTS idx_ventes_lieu_id ON ventes (lieu_id)');
        await insererLieuxDeDepart();
      }
      // Version 5 : le bloc-notes (catégories de notes et notes). Deux nouvelles tables, aucune donnée existante touchée.
      // Les index sont créés en SQL pour ne pas dépendre du nom que Drift donne aux objets générés.
      if (from < 5) {
        await m.createTable(categoriesNote);
        await m.createTable(notes);
        await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_categorie_id ON notes (categorie_id)');
        await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_modifie_le ON notes (modifie_le)');
        await insererCategoriesNoteDeDepart();
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
