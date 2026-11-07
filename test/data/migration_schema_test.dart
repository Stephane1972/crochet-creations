import 'dart:io';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/lieux_vente.dart';
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
    // La vente choisit un lieu : la mise à jour d'une base plus ancienne retire cette colonne, puis la recrée vide.
    final int marche = (await (neuve.select(neuve.lieuxVente)..where((t) => t.nom.equals('Marché'))).getSingle()).id;
    await neuve
        .into(neuve.ventes)
        .insert(
          VentesCompanion.insert(
            sousTotalCentimes: 1000,
            totalCentimes: 1000,
            clientId: Value(clientId),
            lieuId: Value(marche),
          ),
        );
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

  Future<void> verifierLieuxDeDepart(AppDatabase db) async {
    final List<LieuVente> lieux = await (db.select(
      db.lieuxVente,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    expect(lieux.map((LieuVente l) => l.nom), <String>['Marché', 'Salon', 'Boutique', 'Vente en ligne']);
  }

  /// Ramène une base du schéma actuel à l'état d'une base du schéma 3 : sans les lieux de vente.
  void retirerLesLieux(dynamic raw) {
    raw.execute('DROP INDEX idx_ventes_lieu_id');
    raw.execute('ALTER TABLE ventes DROP COLUMN lieu_id');
    raw.execute('DROP TABLE lieux_vente');
  }

  test('du schéma 1 au schéma 4 : les données restent, « client_nom », les catégories et les lieux apparaissent', () async {
    // 1. Une base créée avec le schéma actuel, remplie de quelques lignes.
    final int clientId = await remplirBase();

    // 2. On la ramène à l'état d'une base du schéma 1 : sans les deux colonnes, sans les catégories ni les lieux, version 1.
    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          retirerLesLieux(raw);
          raw.execute('ALTER TABLE ventes DROP COLUMN client_nom');
          raw.execute('ALTER TABLE devis DROP COLUMN client_nom');
          raw.execute('DROP TABLE categories_produit');
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    // La première requête déclenche la mise à jour, puis le test relit le résultat.
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 4);
    for (final String table in <String>['ventes', 'devis']) {
      expect(await colonnes(rouverte, table), contains('client_nom'), reason: table);
    }

    // 3. Les données sont intactes, et le nouveau champ est vide.
    final Vente vente = (await rouverte.select(rouverte.ventes).get()).single;
    expect(vente.clientId, clientId);
    expect(vente.totalCentimes, 1000);
    expect(vente.clientNom, isNull);
    expect(vente.lieuId, isNull); // « Non renseigné »
    final DevisFiche devis = (await rouverte.select(rouverte.devis).get()).single;
    expect(devis.numero, 'DEVIS-2026-0001');
    expect(devis.clientNom, isNull);
    expect((await rouverte.select(rouverte.clients).get()).single.nom, 'Dupont');

    // 4. Les catégories et les lieux de départ sont là, et le produit existant est toujours dans sa catégorie.
    await verifierCategoriesDeDepart(rouverte);
    await verifierLieuxDeDepart(rouverte);
    expect((await rouverte.select(rouverte.produits).get()).single.categorie, CleCategorie.doudou);

    // 5. Et l'application sait s'en servir : supprimer le client copie son nom.
    await rouverte.update(rouverte.ventes).write(const VentesCompanion(clientNom: Value('Dupont')));
    expect((await rouverte.select(rouverte.ventes).get()).single.clientNom, 'Dupont');
    await rouverte.close();
  });

  test('du schéma 2 au schéma 4 : les catégories et les lieux apparaissent avec ceux de départ, rien d’autre ne bouge', () async {
    await remplirBase();

    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          retirerLesLieux(raw);
          raw.execute('DROP TABLE categories_produit');
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 4);
    await verifierLieuxDeDepart(rouverte);

    await verifierCategoriesDeDepart(rouverte);
    final Produit produit = (await rouverte.select(rouverte.produits).get()).single;
    expect(produit.nom, 'Doudou lapin');
    expect(produit.categorie, CleCategorie.doudou);
    expect(produit.prixVenteCentimes, 2500);
    expect((await rouverte.select(rouverte.ventes).get()).single.totalCentimes, 1000);
    await rouverte.close();
  });

  test('du schéma 3 au schéma 4 : les lieux de vente apparaissent, toutes les ventes restent « Non renseigné »', () async {
    final int clientId = await remplirBase();
    // Une deuxième vente, pour vérifier qu'aucune n'est touchée.
    final AppDatabase preparee = AppDatabase(NativeDatabase(fichier));
    await preparee
        .into(preparee.ventes)
        .insert(VentesCompanion.insert(sousTotalCentimes: 700, totalCentimes: 700, clientId: Value(clientId)));
    await preparee.close();

    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          retirerLesLieux(raw);
          raw.execute('PRAGMA user_version = 3');
        },
      ),
    );
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 4);

    // Les quatre lieux de départ sont là, la colonne et son index aussi.
    await verifierLieuxDeDepart(rouverte);
    expect(await colonnes(rouverte, 'ventes'), contains('lieu_id'));
    final List<String> index = (await rouverte
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ventes'")
            .get())
        .map((r) => r.read<String>('name'))
        .toList();
    expect(index, contains('idx_ventes_lieu_id'));

    // Les deux ventes sont intactes et n'ont pas de lieu.
    final List<Vente> ventes = await (rouverte.select(rouverte.ventes)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(ventes.map((Vente v) => v.totalCentimes), <int>[1000, 700]);
    expect(ventes.every((Vente v) => v.lieuId == null), isTrue);
    expect(ventes.every((Vente v) => v.clientId == clientId), isTrue);

    // Et l'application sait s'en servir : une vente peut maintenant choisir un lieu.
    final int salon = (await (rouverte.select(rouverte.lieuxVente)..where((t) => t.nom.equals('Salon'))).getSingle()).id;
    await (rouverte.update(rouverte.ventes)..where((t) => t.id.equals(ventes.first.id))).write(
      VentesCompanion(lieuId: Value(salon)),
    );
    expect((await rouverte.select(rouverte.ventes).get()).where((Vente v) => v.lieuId == salon), hasLength(1));
    await rouverte.close();
  });

  test('rouvrir une base déjà au schéma 4 ne recrée pas les lieux supprimés ou renommés', () async {
    final AppDatabase premiere = AppDatabase(NativeDatabase(fichier));
    await (premiere.update(premiere.lieuxVente)..where((t) => t.nom.equals('Marché'))).write(
      const LieuxVenteCompanion(nom: Value('Marché de Noël')),
    );
    await (premiere.delete(premiere.lieuxVente)..where((t) => t.nom.equals('Salon'))).go();
    await premiere.close();

    final AppDatabase deuxieme = AppDatabase(NativeDatabase(fichier));
    final List<LieuVente> lieux = await deuxieme.select(deuxieme.lieuxVente).get();
    expect(lieux.map((LieuVente l) => l.nom).toSet(), <String>{'Marché de Noël', 'Boutique', 'Vente en ligne'});
    await deuxieme.close();
  });

  test('rouvrir une base déjà au schéma 4 ne recrée pas les catégories de départ supprimées ou renommées', () async {
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
