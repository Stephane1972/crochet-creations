import 'dart:io';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mise à jour d'une base créée par une version plus ancienne de l'application : rien ne se perd.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = await Directory.systemTemp.createTemp('migration_');
    fichier = File('${dossier.path}/base.sqlite');
  });

  tearDown(() async {
    if (await dossier.exists()) await dossier.delete(recursive: true);
  });

  /// Une base du schéma actuel, remplie de quelques lignes, puis refermée. Retourne l'identifiant du client.
  Future<int> remplirBase() async {
    final AppDatabase neuve = AppDatabase(NativeDatabase(fichier));
    final int clientId = await neuve.into(neuve.clients).insert(ClientsCompanion.insert(nom: const Value('Dupont')));
    await neuve
        .into(neuve.ventes)
        .insert(VentesCompanion.insert(sousTotalCentimes: 1000, totalCentimes: 1000, clientId: Value(clientId)));
    await neuve
        .into(neuve.devis)
        .insert(
          DevisCompanion.insert(
            numero: 'DEVIS-2026-0001',
            sousTotalCentimes: 6000,
            totalCentimes: 6000,
            clientId: Value(clientId),
          ),
        );
    await neuve
        .into(neuve.produits)
        .insert(
          ProduitsCompanion.insert(
            reference: 'PRD-0001',
            nom: 'Doudou lapin',
            categorie: CleCategorie.doudou,
            prixVenteCentimes: 2500,
          ),
        );
    await neuve.close();
    return clientId;
  }

  Future<Set<String>> colonnes(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info("$table")').get()).map((r) => r.read<String>('name')).toSet();

  Future<void> verifierCategoriesDeDepart(AppDatabase db) async {
    final List<CategorieProduit> categories = await (db.select(
      db.categoriesProduit,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    expect(categories.map((CategorieProduit c) => c.cle), <String>[
      CleCategorie.crochet,
      CleCategorie.doudou,
      CleCategorie.bouclesOreilles,
      CleCategorie.accessoire,
      CleCategorie.surMesure,
    ]);
    expect(categories.map((CategorieProduit c) => c.nom), <String>[
      'Crochet',
      'Doudou',
      'Boucles d’oreilles',
      'Accessoire',
      'Sur mesure',
    ]);
  }

  test('du schéma 1 au schéma 3 : les données restent, « client_nom » et les catégories apparaissent', () async {
    // 1. Une base créée avec le schéma actuel, remplie de quelques lignes.
    final int clientId = await remplirBase();

    // 2. On la ramène à l'état d'une base du schéma 1 : sans les deux colonnes ni la table des catégories, version 1.
    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          raw.execute('ALTER TABLE ventes DROP COLUMN client_nom');
          raw.execute('ALTER TABLE devis DROP COLUMN client_nom');
          raw.execute('DROP TABLE categories_produit');
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    // La première requête déclenche la mise à jour, puis le test relit le résultat.
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 3);
    for (final String table in <String>['ventes', 'devis']) {
      expect(await colonnes(rouverte, table), contains('client_nom'), reason: table);
    }

    // 3. Les données sont intactes, et le nouveau champ est vide.
    final Vente vente = (await rouverte.select(rouverte.ventes).get()).single;
    expect(vente.clientId, clientId);
    expect(vente.totalCentimes, 1000);
    expect(vente.clientNom, isNull);
    final DevisFiche devis = (await rouverte.select(rouverte.devis).get()).single;
    expect(devis.numero, 'DEVIS-2026-0001');
    expect(devis.clientNom, isNull);
    expect((await rouverte.select(rouverte.clients).get()).single.nom, 'Dupont');

    // 4. Les catégories de départ sont là, et le produit existant est toujours dans sa catégorie.
    await verifierCategoriesDeDepart(rouverte);
    expect((await rouverte.select(rouverte.produits).get()).single.categorie, CleCategorie.doudou);

    // 5. Et l'application sait s'en servir : supprimer le client copie son nom.
    await rouverte.update(rouverte.ventes).write(const VentesCompanion(clientNom: Value('Dupont')));
    expect((await rouverte.select(rouverte.ventes).get()).single.clientNom, 'Dupont');
    await rouverte.close();
  });

  test('du schéma 2 au schéma 3 : la table des catégories apparaît avec les cinq de départ, rien d’autre ne bouge', () async {
    await remplirBase();

    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          raw.execute('DROP TABLE categories_produit');
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 3);

    await verifierCategoriesDeDepart(rouverte);
    final Produit produit = (await rouverte.select(rouverte.produits).get()).single;
    expect(produit.nom, 'Doudou lapin');
    expect(produit.categorie, CleCategorie.doudou);
    expect(produit.prixVenteCentimes, 2500);
    expect((await rouverte.select(rouverte.ventes).get()).single.totalCentimes, 1000);
    await rouverte.close();
  });

  test('rouvrir une base déjà au schéma 3 ne recrée pas les catégories de départ supprimées ou renommées', () async {
    final AppDatabase premiere = AppDatabase(NativeDatabase(fichier));
    await (premiere.update(premiere.categoriesProduit)..where((t) => t.cle.equals(CleCategorie.crochet))).write(
      const CategoriesProduitCompanion(nom: Value('Mes créations')),
    );
    await (premiere.delete(premiere.categoriesProduit)..where((t) => t.cle.equals(CleCategorie.surMesure))).go();
    await premiere.close();

    final AppDatabase deuxieme = AppDatabase(NativeDatabase(fichier));
    final List<CategorieProduit> categories = await deuxieme.select(deuxieme.categoriesProduit).get();
    expect(categories, hasLength(4));
    expect(categories.firstWhere((CategorieProduit c) => c.cle == CleCategorie.crochet).nom, 'Mes créations');
    expect(categories.any((CategorieProduit c) => c.cle == CleCategorie.surMesure), isFalse);
    await deuxieme.close();
  });
}
