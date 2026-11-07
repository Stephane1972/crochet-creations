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

  Future<void> verifierCategoriesNoteDeDepart(AppDatabase db) async {
    final List<CategorieNote> categories = await (db.select(
      db.categoriesNote,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    expect(categories.map((CategorieNote c) => c.nom), <String>['Futures commandes', 'Documents entreprise']);
  }

  /// Ramène une base du schéma actuel à l'état d'une base du schéma 4 : sans le bloc-notes.
  void retirerLeBlocNotes(dynamic raw) {
    raw.execute('DROP INDEX idx_notes_categorie_id');
    raw.execute('DROP INDEX idx_notes_modifie_le');
    raw.execute('DROP TABLE notes');
    raw.execute('DROP TABLE categories_note');
  }

  /// Ramène une base du schéma actuel à l'état d'une base du schéma 3 : sans les lieux de vente (ni le bloc-notes).
  void retirerLesLieux(dynamic raw) {
    retirerLeBlocNotes(raw);
    raw.execute('DROP INDEX idx_ventes_lieu_id');
    raw.execute('ALTER TABLE ventes DROP COLUMN lieu_id');
    raw.execute('DROP TABLE lieux_vente');
  }

  test('du schéma 1 au schéma 5 : les données restent, « client_nom », les catégories, les lieux et le bloc-notes apparaissent', () async {
    // 1. Une base créée avec le schéma actuel, remplie de quelques lignes.
    final int clientId = await remplirBase();

    // 2. On la ramène à l'état d'une base du schéma 1 : sans les deux colonnes, sans les catégories, les lieux ni le bloc-notes, version 1.
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
    expect(version, 5);
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
    await verifierCategoriesNoteDeDepart(rouverte);
    expect(await rouverte.select(rouverte.notes).get(), isEmpty);
    expect((await rouverte.select(rouverte.produits).get()).single.categorie, CleCategorie.doudou);

    // 5. Et l'application sait s'en servir : supprimer le client copie son nom.
    await rouverte.update(rouverte.ventes).write(const VentesCompanion(clientNom: Value('Dupont')));
    expect((await rouverte.select(rouverte.ventes).get()).single.clientNom, 'Dupont');
    await rouverte.close();
  });

  test('du schéma 2 au schéma 5 : catégories, lieux et bloc-notes apparaissent avec ceux de départ, rien d’autre ne bouge', () async {
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
    expect(version, 5);
    await verifierLieuxDeDepart(rouverte);
    await verifierCategoriesNoteDeDepart(rouverte);

    await verifierCategoriesDeDepart(rouverte);
    final Produit produit = (await rouverte.select(rouverte.produits).get()).single;
    expect(produit.nom, 'Doudou lapin');
    expect(produit.categorie, CleCategorie.doudou);
    expect(produit.prixVenteCentimes, 2500);
    expect((await rouverte.select(rouverte.ventes).get()).single.totalCentimes, 1000);
    await rouverte.close();
  });

  test('du schéma 3 au schéma 5 : les lieux de vente apparaissent, toutes les ventes restent « Non renseigné »', () async {
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
    expect(version, 5);
    await verifierCategoriesNoteDeDepart(rouverte);

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

  test('rouvrir une base déjà au schéma 5 ne recrée pas les lieux supprimés ou renommés', () async {
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

  test('rouvrir une base déjà au schéma 5 ne recrée pas les catégories de départ supprimées ou renommées', () async {
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

  test('du schéma 4 au schéma 5 : le bloc-notes apparaît avec ses deux catégories de départ, rien d’autre ne bouge', () async {
    final int clientId = await remplirBase();

    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          retirerLeBlocNotes(raw);
          raw.execute('PRAGMA user_version = 4');
        },
      ),
    );
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 5);

    // Deux catégories de départ, aucune note, et les index.
    await verifierCategoriesNoteDeDepart(rouverte);
    expect(await rouverte.select(rouverte.notes).get(), isEmpty);
    final List<String> index = (await rouverte
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'notes'")
            .get())
        .map((r) => r.read<String>('name'))
        .toList();
    expect(index, containsAll(<String>['idx_notes_categorie_id', 'idx_notes_modifie_le']));

    // Tout le reste est intact : ventes (avec leur lieu), devis, client, produit, lieux de vente.
    final Vente vente = (await rouverte.select(rouverte.ventes).get()).single;
    expect(vente.clientId, clientId);
    expect(vente.totalCentimes, 1000);
    expect(vente.lieuId, isNotNull);
    expect((await rouverte.select(rouverte.devis).get()).single.numero, 'DEVIS-2026-0001');
    expect((await rouverte.select(rouverte.produits).get()).single.nom, 'Doudou lapin');
    await verifierLieuxDeDepart(rouverte);

    // Et l'application sait s'en servir : une note peut être rangée dans une catégorie.
    final int categorie = (await rouverte.select(rouverte.categoriesNote).get()).first.id;
    await rouverte
        .into(rouverte.notes)
        .insert(NotesCompanion.insert(titre: 'Doudou pour Léa', categorieId: Value(categorie)));
    expect((await rouverte.select(rouverte.notes).get()).single.categorieId, categorie);
    await rouverte.close();
  });

  test('rouvrir une base déjà au schéma 5 ne recrée pas les catégories de notes supprimées ou renommées, et garde les notes', () async {
    final AppDatabase premiere = AppDatabase(NativeDatabase(fichier));
    final CategorieNote futures = (await premiere.select(premiere.categoriesNote).get()).firstWhere(
      (CategorieNote c) => c.nom == 'Futures commandes',
    );
    await (premiere.update(premiere.categoriesNote)..where((t) => t.id.equals(futures.id))).write(
      const CategoriesNoteCompanion(nom: Value('À faire')),
    );
    await (premiere.delete(premiere.categoriesNote)..where((t) => t.nom.equals('Documents entreprise'))).go();
    await premiere.into(premiere.notes).insert(NotesCompanion.insert(titre: 'Bonnet', categorieId: Value(futures.id)));
    await premiere.close();

    final AppDatabase deuxieme = AppDatabase(NativeDatabase(fichier));
    final List<CategorieNote> categories = await deuxieme.select(deuxieme.categoriesNote).get();
    expect(categories.map((CategorieNote c) => c.nom), <String>['À faire']);
    final Note note = (await deuxieme.select(deuxieme.notes).get()).single;
    expect(note.titre, 'Bonnet');
    expect(note.categorieId, futures.id);
    await deuxieme.close();
  });
}
