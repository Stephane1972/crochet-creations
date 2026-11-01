import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder;
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/sauvegarde/export_csv.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_donnees.dart';

/// Les lignes d'un CSV (sans la ligne vide finale).
List<String> _lignes(String csv) {
  final List<String> lignes = csv.split('\r\n');
  expect(lignes.last, '', reason: 'chaque ligne, la dernière comprise, se termine par \\r\\n');
  return lignes.sublist(0, lignes.length - 1);
}

void main() {
  late AppDatabase db;
  late ExportCsv export;

  setUp(() {
    db = creerBaseEnMemoire();
    export = ExportCsv(db, horloge: () => DateTime(2026, 10, 31, 13, 49));
  });

  tearDown(() async {
    await db.close();
  });

  test('un CSV par type de données, dans l’ordre prévu', () async {
    final Map<String, String> textes = await export.fabriquerTextes();
    expect(textes.keys.toList(), ExportCsv.fichiers);
    expect(ExportCsv.fichiers, <String>[
      'produits.csv',
      'clients.csv',
      'ventes.csv',
      'factures.csv',
      'devis.csv',
      'cours.csv',
      'inscriptions.csv',
      'depenses.csv',
    ]);
  });

  test('sans données : chaque fichier ne contient que ses en-têtes', () async {
    final Map<String, String> textes = await export.fabriquerTextes();
    for (final MapEntry<String, String> t in textes.entries) {
      expect(_lignes(t.value), hasLength(1), reason: t.key);
    }
    expect(_lignes(textes['produits.csv']!).single, startsWith('Référence;Nom;Catégorie;Statut;Prix de vente (€);'));
    expect(_lignes(textes['depenses.csv']!).single, 'Date;Catégorie;Montant (€);Fournisseur;Description;Produit concerné;Archivée le');
  });

  group('avec des données', () {
    late Map<String, String> textes;

    setUp(() async {
      await remplirBase(db);
      textes = await export.fabriquerTextes();
    });

    test('produits : montants en euros, variantes, accents et point-virgule protégé', () {
      final List<String> lignes = _lignes(textes['produits.csv']!);
      expect(lignes, hasLength(2));
      expect(
        lignes[1],
        startsWith(
          'PRD-0001;Doudou lapin « Noisette »;Doudou;Disponible;25,00;0,00;4;0;Rose – taille M (2);Oui;;;'
          '"Coton; laine mérinos";;;',
        ),
      );
    });

    test('clients : les guillemets d’une note sont doublés', () {
      final List<String> lignes = _lignes(textes['clients.csv']!);
      expect(lignes, hasLength(2));
      expect(lignes[1], startsWith('Particulier;;Marie;Dupont;;;marie@example.fr;;;;;"Préfère les couleurs ""pastel""";'));
    });

    test('ventes : par date, avec les articles, le client (ou « de passage ») et l’argent encaissé', () {
      final List<String> lignes = _lignes(textes['ventes.csv']!);
      expect(lignes, hasLength(3));
      expect(lignes[1], '1;20/10/2026;Marie Dupont;Validée;Payée;2 × Doudou lapin « Noisette »;50,00;0,00;0,00;50,00;50,00;');
      expect(lignes[2], '2;25/10/2026;Client de passage;Validée;Partiellement payée;;12,00;0,00;0,00;12,00;5,00;"Marché; stand 3"');
    });

    test('factures : numéro, dates, client recopié, statut, mention de TVA', () {
      final List<String> lignes = _lignes(textes['factures.csv']!);
      expect(lignes, hasLength(2));
      expect(lignes[1], 'FACT-2026-0001;20/10/2026;20/10/2026;;Marie Dupont;50,00;Émise;1;TVA non applicable, article 293 B du CGI');
    });

    test('devis : validité, acompte, délai', () {
      final List<String> lignes = _lignes(textes['devis.csv']!);
      expect(lignes, hasLength(2));
      expect(lignes[1], 'DEVIS-2026-0001;22/10/2026;22/11/2026;Marie Dupont;Envoyé;60,00;0,00;0,00;60,00;0,00;3 semaines;;');
    });

    test('cours : date et heure dans deux colonnes que le tableur reconnaît', () {
      final List<String> lignes = _lignes(textes['cours.csv']!);
      expect(lignes, hasLength(2));
      expect(lignes[1], startsWith('Initiation au crochet;14/11/2026;14:00;150;Atelier de Camille;45,00;4;'));
    });

    test('inscriptions : le cours et le client en toutes lettres', () {
      final List<String> lignes = _lignes(textes['inscriptions.csv']!);
      expect(lignes, hasLength(2));
      expect(lignes[1], 'Initiation au crochet;14/11/2026;Marie Dupont;Confirmée;26/10/2026;45,00;;');
    });

    test('dépenses : catégorie, montant, fournisseur et produit concerné', () {
      final List<String> lignes = _lignes(textes['depenses.csv']!);
      expect(lignes, hasLength(2));
      expect(lignes[1], '05/10/2026;Laine / fil;24,90;Mercerie du Port;;Doudou lapin « Noisette »;');
    });

    test('un élément archivé reste dans l’export, avec sa date d’archivage', () async {
      await db.update(db.clients).write(ClientsCompanion(archiveLe: Value(DateTime(2026, 10, 30))));
      final String csv = (await export.fabriquerTextes())['clients.csv']!;
      expect(_lignes(csv)[1], endsWith(';30/10/2026'));
    });
  });

  group('le .zip', () {
    test('contient les huit fichiers, chacun en UTF-8 avec la marque d’ordre des octets', () async {
      await remplirBase(db);
      final Uint8List octets = await export.fabriquerArchive();
      final Archive archive = ZipDecoder().decodeBytes(octets);
      expect(archive.map((ArchiveFile f) => f.name).toList(), ExportCsv.fichiers);

      final Map<String, String> textes = await export.fabriquerTextes();
      for (final ArchiveFile f in archive) {
        final Uint8List contenu = f.content;
        expect(contenu.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF], reason: f.name);
        expect(utf8.decode(contenu.sublist(3)), textes[f.name], reason: f.name);
      }
    });

    test('est écrit sous un nom daté, qu’un nouvel export du jour remplace', () async {
      final Directory dossier = await Directory.systemTemp.createTemp('export_csv_');
      addTearDown(() => dossier.delete(recursive: true));

      expect(export.nomArchive(), 'crochet-creations-export-csv-2026-10-31.zip');
      final File premier = await export.ecrireArchive(dossier);
      expect(premier.uri.pathSegments.last, 'crochet-creations-export-csv-2026-10-31.zip');

      await remplirBase(db);
      final File second = await export.ecrireArchive(dossier);
      expect(second.path, premier.path);
      expect(await dossier.list().length, 1);
      final Archive archive = ZipDecoder().decodeBytes(await second.readAsBytes());
      expect(utf8.decode(archive.find('produits.csv')!.content.sublist(3)), contains('PRD-0001'));
    });
  });
}
