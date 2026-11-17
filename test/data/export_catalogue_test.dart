import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder;
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/sauvegarde/export_catalogue.dart';
import 'package:crochet_creations/data/stockage/stockage_photos.dart';
import 'package:crochet_creations/domain/catalogue_export.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_donnees.dart';

String _texte(Archive archive, String nom) {
  final ArchiveFile? f = archive.find(nom);
  expect(f, isNotNull, reason: 'Fichier attendu dans l’archive : $nom');
  return utf8.decode(f!.content);
}

void main() {
  late AppDatabase db;
  late Directory racine;
  late Directory dossierPhotos;
  late Directory sortie;
  late ExportCatalogue export;

  setUp(() {
    db = creerBaseEnMemoire();
    racine = Directory.systemTemp.createTempSync('crochet_catalogue_');
    dossierPhotos = Directory('${racine.path}/photos_produits')..createSync();
    sortie = Directory('${racine.path}/exports');
    export = ExportCatalogue(db, StockagePhotos(dossierPhotos), horloge: () => DateTime(2026, 11, 16, 9, 30));
  });

  tearDown(() async {
    await db.close();
    racine.deleteSync(recursive: true);
  });

  void poserPhoto(String nom, String contenu) => File('${dossierPhotos.path}/$nom').writeAsStringSync(contenu);

  Future<Archive> lire(ResultatCatalogue r) async => ZipDecoder().decodeBytes(await r.fichier.readAsBytes());

  test('le nom de l’archive porte la date du jour', () {
    expect(export.nomArchive(), 'crochet-creations-catalogue-2026-11-16.zip');
  });

  test('sans produit : une archive avec le tableau vide et le mode d’emploi', () async {
    final ResultatCatalogue r = await export.ecrireArchive(sortie);
    expect(r.produits, 0);
    expect(r.photos, 0);
    expect(r.photosManquantes, isEmpty);
    expect(r.fichier.existsSync(), isTrue);
    final Archive archive = await lire(r);
    expect(archive.map((ArchiveFile f) => f.name).toSet(), <String>{'LISEZMOI.txt', 'catalogue.csv', 'catalogue.json'});
    expect(_texte(archive, 'catalogue.csv').split('\r\n'), hasLength(2)); // en-têtes + fin de ligne
  });

  group('avec une boutique', () {
    setUp(() async {
      await remplirBase(db);
      poserPhoto(photoPrincipale, 'photo un');
      poserPhoto(photoSecondaire, 'photo deux');
    });

    test('lireProduits : nom de catégorie, statut, variantes et photos (la principale d’abord)', () async {
      final List<ProduitCatalogue> produits = await export.lireProduits();
      expect(produits, hasLength(1));
      final ProduitCatalogue p = produits.single;
      expect(p.reference, 'PRD-0001');
      expect(p.nom, 'Doudou lapin « Noisette »');
      expect(p.categorie, 'Doudou');
      expect(p.statut, StatutProduit.disponible.libelle);
      expect(p.prixVenteCentimes, 2500);
      expect(p.matieres, 'Coton; laine mérinos');
      expect(p.variantes, <String>['Rose – taille M']);
      expect(p.photos, <String>[photoPrincipale, photoSecondaire]);
    });

    test('l’archive contient le CSV, le JSON, le mode d’emploi et les photos renommées', () async {
      final ResultatCatalogue r = await export.ecrireArchive(sortie);
      expect(r.produits, 1);
      expect(r.photos, 2);
      expect(r.photosManquantes, isEmpty);
      expect(r.fichier.path, endsWith('crochet-creations-catalogue-2026-11-16.zip'));

      final Archive archive = await lire(r);
      expect(archive.map((ArchiveFile f) => f.name).toSet(), <String>{
        'LISEZMOI.txt',
        'catalogue.csv',
        'catalogue.json',
        'photos/PRD-0001_1.jpg',
        'photos/PRD-0001_2.jpg',
      });
      expect(_texte(archive, 'photos/PRD-0001_1.jpg'), 'photo un');
      expect(_texte(archive, 'photos/PRD-0001_2.jpg'), 'photo deux');

      // La marque UTF-8 (BOM) est bien en tête du fichier (utf8.decode l'enlève : on regarde les octets).
      expect(archive.find('catalogue.csv')!.content.take(3).toList(), <int>[0xEF, 0xBB, 0xBF]);
      final List<String> lignes = _texte(archive, 'catalogue.csv').split('\r\n');
      expect(lignes[0], startsWith('Référence;Nom;'));
      expect(lignes[1], contains('PRD-0001;Doudou lapin « Noisette »;Doudou;'));
      expect(lignes[1], endsWith('Rose – taille M;photos/PRD-0001_1.jpg, photos/PRD-0001_2.jpg'));

      final Map<String, Object?> json = jsonDecode(_texte(archive, 'catalogue.json')) as Map<String, Object?>;
      expect(json['nombreProduits'], 1);
      expect(json['exporteLe'], '2026-11-16T09:30:00.000');

      expect(_texte(archive, 'LISEZMOI.txt'), contains('16 novembre 2026'));
    });

    test('jamais de coût, de stock, de client ni de vente dans l’archive', () async {
      final ResultatCatalogue r = await export.ecrireArchive(sortie);
      final Archive archive = await lire(r);
      final String tout = <String>[
        _texte(archive, 'catalogue.csv'),
        _texte(archive, 'catalogue.json'),
      ].join('\n');
      expect(tout, isNot(contains('Dupont')));
      expect(tout, isNot(contains('marie@example.fr')));
      expect(tout, isNot(contains('FACT-2026-0001')));
      expect(tout, isNot(contains('quantiteStock')));
      expect(tout, isNot(contains('Atelier de Camille')));
    });

    test('une photo introuvable est signalée, jamais inventée', () async {
      File('${dossierPhotos.path}/$photoSecondaire').deleteSync();
      final ResultatCatalogue r = await export.ecrireArchive(sortie);
      expect(r.photos, 1);
      expect(r.photosManquantes, <String>['PRD-0001 : $photoSecondaire']);
      final Archive archive = await lire(r);
      expect(archive.find('photos/PRD-0001_2.jpg'), isNull);
      expect(_texte(archive, 'catalogue.csv'), isNot(contains('PRD-0001_2')));
      expect(_texte(archive, 'LISEZMOI.txt'), contains('- PRD-0001 : $photoSecondaire'));
    });

    test('un produit archivé n’est pas dans le catalogue', () async {
      await (db.update(db.produits)).write(ProduitsCompanion(archiveLe: Value<DateTime?>(DateTime(2026, 11, 1))));
      expect(await export.lireProduits(), isEmpty);
      final ResultatCatalogue r = await export.ecrireArchive(sortie);
      expect(r.produits, 0);
      expect(r.photos, 0);
    });

    test('refaire l’export le même jour remplace l’archive, sans fichier provisoire', () async {
      await export.ecrireArchive(sortie);
      final ResultatCatalogue r = await export.ecrireArchive(sortie);
      final List<String> noms = sortie.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last).toList();
      expect(noms, <String>[r.fichier.uri.pathSegments.last]);
    });
  });
}
