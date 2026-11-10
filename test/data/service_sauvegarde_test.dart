import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:crypto/crypto.dart' show sha256;
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/categorie_note_repository.dart';
import 'package:crochet_creations/data/repositories/categorie_repository.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/lieu_vente_repository.dart';
import 'package:crochet_creations/data/repositories/note_repository.dart';
import 'package:crochet_creations/data/sauvegarde/espace_libre.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/data/sauvegarde/service_sauvegarde.dart';
import 'package:crochet_creations/data/stockage/stockage_pieces_jointes.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_donnees.dart';

/// Place libre réglable : `null` = « on ne sait pas » (aucun contrôle).
class _FauxEspaceLibre implements ControleEspaceLibre {
  int? octets;

  @override
  Future<int?> octetsLibres(Directory dossier) async => octets;
}

/// Un « téléphone » de test : une base en mémoire, des dossiers temporaires et une horloge qu'on règle.
class _Banc {
  _Banc._(this.db, this.racine);

  static Future<_Banc> creer() async => _Banc._(creerBaseEnMemoire(), await Directory.systemTemp.createTemp('sauvegarde_'));

  final AppDatabase db;
  final Directory racine;
  DateTime maintenant = DateTime(2026, 10, 31, 13, 49, 12);
  final _FauxEspaceLibre espace = _FauxEspaceLibre();
  int _numeroArchive = 0;

  Directory get photos => Directory('${racine.path}/photos_produits');
  Directory get factures => Directory('${racine.path}/factures');
  Directory get devis => Directory('${racine.path}/devis');
  Directory get piecesJointes => Directory('${racine.path}/notes_pieces_jointes');

  late final ServiceSauvegarde service = ServiceSauvegarde(
    base: db,
    dossierSauvegardes: Directory('${racine.path}/sauvegardes'),
    dossierExports: Directory('${racine.path}/exports'),
    dossierPhotos: photos,
    dossierFactures: factures,
    dossierDevis: devis,
    dossierPiecesJointes: piecesJointes,
    horloge: () => maintenant,
    espaceLibre: espace,
  );

  /// Une sauvegarde du moment, sortie du dossier des sauvegardes comme un fichier reçu d'ailleurs.
  Future<File> archive() async {
    final SauvegardeLocale faite = await service.creer(TypeSauvegarde.manuelle);
    final Directory dossier = await Directory('${racine.path}/archives').create(recursive: true);
    return faite.fichier.rename('${dossier.path}/archive_${++_numeroArchive}.zip');
  }

  Future<Uint8List> octetsArchive() async => (await archive()).readAsBytes();

  /// Écrit [octets] dans un fichier (une archive abîmée, par exemple).
  Future<File> ecrire(Uint8List octets) async {
    final Directory dossier = await Directory('${racine.path}/archives').create(recursive: true);
    final File fichier = File('${dossier.path}/archive_${++_numeroArchive}.zip');
    await fichier.writeAsBytes(octets);
    return fichier;
  }

  Future<ResultatRestauration> restaurer(Uint8List octets, {SurProgression? surProgression}) async =>
      service.restaurer(await ecrire(octets), surProgression: surProgression);

  Future<ManifesteSauvegarde> examiner(Uint8List octets) async => service.examiner(await ecrire(octets));

  Future<void> fermer() async {
    await db.close();
    if (await racine.exists()) await racine.delete(recursive: true);
  }

  /// Écrit les quatre fichiers cités par [remplirBase].
  Future<void> ecrireFichiers() async {
    await _ecrire(photos, photoPrincipale, 'photo 1');
    await _ecrire(photos, photoSecondaire, 'photo 2');
    await _ecrire(factures, pdfFacture, '%PDF facture');
    await _ecrire(devis, pdfDevis, '%PDF devis');
  }

  Future<void> _ecrire(Directory dossier, String nom, String contenu) async {
    await dossier.create(recursive: true);
    await File('${dossier.path}/$nom').writeAsString(contenu);
  }

  Future<void> ajouterFichier(Directory dossier, String nom, String contenu) => _ecrire(dossier, nom, contenu);

  /// « nom → contenu » de chaque fichier d'un dossier (vide si le dossier n'existe pas).
  Future<Map<String, String>> contenuDe(Directory dossier) async {
    final Map<String, String> resultat = <String, String>{};
    if (!await dossier.exists()) return resultat;
    await for (final FileSystemEntity e in dossier.list()) {
      if (e is File) resultat[e.uri.pathSegments.last] = await e.readAsString();
    }
    return resultat;
  }

  /// Aucun dossier de travail (`.restauration`, `.ancien`) ne doit rester après une restauration.
  Future<void> verifierPropre() async {
    final List<String> noms = <String>[
      await for (final FileSystemEntity e in racine.list()) e.uri.pathSegments.where((String s) => s.isNotEmpty).last,
    ];
    expect(noms.where((String n) => n.endsWith('.restauration') || n.endsWith('.ancien')), isEmpty);
  }
}

Uint8List _zip(Map<String, List<int>> entrees) {
  final Archive archive = Archive();
  entrees.forEach((String nom, List<int> octets) => archive.add(ArchiveFile.bytes(nom, octets)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, dynamic> _lireDonnees(Uint8List archive) {
  final ArchiveFile entree = ZipDecoder().decodeBytes(archive).find('donnees.json')!;
  return jsonDecode(utf8.decode(entree.content)) as Map<String, dynamic>;
}

/// Recopie [archive] en changeant son `donnees.json` : sert à fabriquer des sauvegardes abîmées.
Uint8List _modifierDonnees(Uint8List archive, void Function(Map<String, dynamic> document) modifier) {
  final Archive source = ZipDecoder().decodeBytes(archive);
  final Map<String, dynamic> document = _lireDonnees(archive);
  modifier(document);
  final Archive copie = Archive();
  for (final ArchiveFile f in source) {
    if (f.name != 'donnees.json') copie.add(ArchiveFile.bytes(f.name, f.content));
  }
  copie.add(ArchiveFile.bytes('donnees.json', utf8.encode(jsonEncode(document))));
  return Uint8List.fromList(ZipEncoder().encode(copie));
}

/// Recopie [archive] en remplaçant (ou ajoutant) des entrées ; une valeur `null` retire l'entrée.
Uint8List _retoucher(Uint8List archive, Map<String, List<int>?> changements) {
  final Archive source = ZipDecoder().decodeBytes(archive);
  final Archive copie = Archive();
  for (final ArchiveFile f in source) {
    if (!changements.containsKey(f.name)) copie.add(ArchiveFile.bytes(f.name, f.content));
  }
  changements.forEach((String nom, List<int>? contenu) {
    if (contenu != null) copie.add(ArchiveFile.bytes(nom, contenu));
  });
  return Uint8List.fromList(ZipEncoder().encode(copie));
}

String _empreinteDe(String texte) => sha256.convert(utf8.encode(texte)).toString();

Matcher _erreurAvecMessage(String morceau) =>
    isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains(morceau));

void main() {
  late _Banc banc;

  setUp(() async {
    banc = await _Banc.creer();
  });

  tearDown(() async {
    await banc.fermer();
  });

  group('les tables d’une sauvegarde', () {
    test('sont exactement celles de la base, dans un ordre qui respecte les clés étrangères', () async {
      final Set<String> reelles = banc.db.allTables.map((t) => t.actualTableName).toSet();
      expect(FormatSauvegarde.tables.toSet(), reelles);
      expect(FormatSauvegarde.tables, hasLength(reelles.length));

      for (int i = 0; i < FormatSauvegarde.tables.length; i++) {
        final String table = FormatSauvegarde.tables[i];
        final cles = await banc.db.customSelect('PRAGMA foreign_key_list("$table")').get();
        for (final cle in cles) {
          final String reference = cle.read<String>('table');
          expect(
            FormatSauvegarde.tables.indexOf(reference),
            lessThan(i),
            reason: '« $table » est remplie avant « $reference », qu’elle référence.',
          );
        }
      }
    });
  });

  group('les colonnes qui citent des fichiers', () {
    test('existent toutes dans la base, et aucune colonne « chemin » n’est oubliée', () async {
      final Set<String> declarees = <String>{};
      for (final ColonneFichier c in FormatSauvegarde.colonnesFichiers) {
        declarees.add('${c.table}.${c.colonne}');
        expect(FormatSauvegarde.dossiersFichiers, contains(c.dossier));
      }
      for (final String table in FormatSauvegarde.tables) {
        final infos = await banc.db.customSelect('PRAGMA table_info("$table")').get();
        for (final String colonne in infos.map((r) => r.read<String>('name'))) {
          if (declarees.remove('$table.$colonne')) continue;
          expect(colonne, isNot(contains('chemin')), reason: '« $table.$colonne » cite-t-elle un fichier ? Ajoutez-la à FormatSauvegarde.colonnesFichiers.');
        }
      }
      expect(declarees, isEmpty, reason: 'colonnes déclarées mais absentes de la base');
    });

    test('les photos citées par les données de test sont reconnues, pas les PDF', () async {
      await remplirBase(banc.db);
      final Set<String> citees = FormatSauvegarde.fichiersIrremplacablesCites(await instantane(banc.db));
      expect(citees, <String>{'photos_produits/$photoPrincipale', 'photos_produits/$photoSecondaire'});
    });

    test('un chemin est ramené à son nom de fichier', () {
      expect(FormatSauvegarde.nomDeFichier('/data/user/0/app/photos_produits/photo_9.jpg'), 'photo_9.jpg');
      expect(FormatSauvegarde.nomDeFichier(r'C:\photos\photo_9.jpg'), 'photo_9.jpg');
      expect(FormatSauvegarde.nomDeFichier('photo_9.jpg'), 'photo_9.jpg');
      expect(FormatSauvegarde.nomDeFichier('  '), '');
    });
  });

  group('créer une sauvegarde', () {
    test('l’archive contient les données, les photos et les PDF', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      final Uint8List octets = await banc.octetsArchive();
      final Archive archive = ZipDecoder().decodeBytes(octets);
      expect(archive.map((ArchiveFile f) => f.name).toSet(), <String>{
        'donnees.json',
        'fichiers.json',
        'fichiers/photos_produits/$photoPrincipale',
        'fichiers/photos_produits/$photoSecondaire',
        'fichiers/factures/$pdfFacture',
        'fichiers/devis/$pdfDevis',
      });

      final Map<String, dynamic> document = _lireDonnees(octets);
      final Map<String, dynamic> manifeste = document['manifeste'] as Map<String, dynamic>;
      expect(manifeste['application'], 'crochet-creations');
      expect(manifeste['format'], FormatSauvegarde.version);
      expect(manifeste['versionSchema'], AppDatabase.versionSchema);
      expect(manifeste['nombreFichiers'], 4);
      expect((document['tables'] as Map<String, dynamic>).keys.toList(), FormatSauvegarde.tables);
    });

    test('le manifeste se lit sans rien modifier', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List octets = await banc.octetsArchive();

      final ManifesteSauvegarde manifeste = await banc.examiner(octets);
      expect(manifeste.creeLe, banc.maintenant);
      expect(manifeste.nombreFichiers, 4);
      expect(manifeste.lignesDe('produits'), 1);
      expect(manifeste.lignesDe('ventes'), 2);
      expect(manifeste.lignesDe('depenses'), 1);
      expect(manifeste.lignesDe('categories_note'), 2);
      expect(manifeste.lignesDe('notes'), 2);
      expect(manifeste.lignes.keys.toList(), FormatSauvegarde.tables);
      expect(await banc.service.lister(), isEmpty); // examiner ne fabrique aucune copie de sécurité
    });

    test('le fichier est rangé dans le dossier des sauvegardes, nommé d’après son type et l’heure', () async {
      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(s.nom, 'crochet-creations-manuelle-2026-10-31-134912.zip');
      expect(s.type, TypeSauvegarde.manuelle);
      expect(s.date, DateTime(2026, 10, 31, 13, 49, 12));
      expect(await s.fichier.exists(), isTrue);
      expect(s.octets, await s.fichier.length());
      expect(s.fichier.parent.path, banc.service.dossierSauvegardes.path);
    });

    test('deux sauvegardes dans la même seconde ne s’écrasent pas', () async {
      final SauvegardeLocale a = await banc.service.creer(TypeSauvegarde.manuelle);
      final SauvegardeLocale b = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(a.nom, 'crochet-creations-manuelle-2026-10-31-134912.zip');
      expect(b.nom, 'crochet-creations-manuelle-2026-10-31-134912-2.zip');
      expect(await banc.service.lister(), hasLength(2));
    });

    test('les fichiers provisoires (.tmp) ne partent pas dans l’archive', () async {
      await banc.ecrireFichiers();
      await banc.ajouterFichier(banc.photos, 'photo_3.jpg.tmp', 'à moitié écrite');
      final Archive archive = ZipDecoder().decodeBytes(await banc.octetsArchive());
      expect(archive.find('fichiers/photos_produits/photo_3.jpg.tmp'), isNull);
      expect(archive.find('fichiers/photos_produits/$photoPrincipale'), isNotNull);
    });
  });

  group('liste des fichiers et empreintes', () {
    test('fichiers.json donne la taille et l’empreinte SHA-256 de chaque photo et PDF', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Archive archive = ZipDecoder().decodeBytes(await banc.octetsArchive());

      final Map<String, dynamic> liste =
          jsonDecode(utf8.decode(archive.find('fichiers.json')!.content)) as Map<String, dynamic>;
      expect(liste['format'], FormatSauvegarde.version);
      final List<Map<String, dynamic>> fichiers = (liste['fichiers'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(fichiers.map((Map<String, dynamic> f) => f['chemin']).toList(), <String>[
        'photos_produits/$photoPrincipale',
        'photos_produits/$photoSecondaire',
        'factures/$pdfFacture',
        'devis/$pdfDevis',
      ]);
      expect(fichiers.first['octets'], 'photo 1'.length);
      expect(fichiers.first['sha256'], _empreinteDe('photo 1'));
      for (final Map<String, dynamic> f in fichiers) {
        final ArchiveFile entree = archive.find('fichiers/${f['chemin']}')!;
        expect(f['octets'], entree.size);
        expect(f['sha256'], sha256.convert(entree.content).toString());
      }
    });

    test('un gros fichier est sauvegardé puis restauré à l’identique', () async {
      final List<int> gros = List<int>.generate(3 * 1024 * 1024, (int i) => (i * 31 + i ~/ 7) % 251);
      await banc.photos.create(recursive: true);
      final File photo = File('${banc.photos.path}/gros.jpg');
      await photo.writeAsBytes(gros);

      final File archive = await banc.archive();
      expect(await archive.length(), greaterThan(gros.length), reason: 'rangé tel quel, sans recompression');
      await photo.delete();

      final ResultatRestauration resultat = await banc.service.restaurer(archive);
      expect(resultat.fichiers, 1);
      expect(await photo.readAsBytes(), gros);
    });
  });

  group('sauvegarde complète ou incomplète', () {
    test('toutes les photos citées sont là : la sauvegarde est complète', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(s.complete, isTrue);
      expect(s.fichiersAbsents, isEmpty);
      expect(s.nom, 'crochet-creations-manuelle-2026-10-31-134912.zip');
      expect((await banc.service.examiner(s.fichier)).complete, isTrue);
      expect((await banc.service.lister()).single.complete, isTrue);
      final Map<String, dynamic> manifeste = _lireDonnees(await s.fichier.readAsBytes())['manifeste'] as Map<String, dynamic>;
      expect(manifeste['complete'], isTrue);
      expect(manifeste['fichiersAbsents'], isEmpty);
    });

    test('une photo citée mais absente : incomplète, et on le voit au nom, dans la liste et dans le manifeste', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      await File('${banc.photos.path}/$photoSecondaire').delete();

      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(s.complete, isFalse);
      expect(s.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
      expect(s.nom, 'crochet-creations-manuelle-2026-10-31-134912-incomplete.zip');

      final List<SauvegardeLocale> liste = await banc.service.lister();
      expect(liste.single.complete, isFalse);
      expect(liste.single.type, TypeSauvegarde.manuelle);
      expect(liste.single.date, banc.maintenant);

      final ManifesteSauvegarde manifeste = await banc.service.examiner(s.fichier);
      expect(manifeste.complete, isFalse);
      expect(manifeste.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
      expect(manifeste.nombreFichiers, 3);

      final Map<String, dynamic> dansArchive = _lireDonnees(await s.fichier.readAsBytes())['manifeste'] as Map<String, dynamic>;
      expect(dansArchive['complete'], isFalse);
      expect(dansArchive['fichiersAbsents'], <String>['photos_produits/$photoSecondaire']);
    });

    test('une sauvegarde incomplète reste restaurable, et la restauration dit ce qui manquait', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      await File('${banc.photos.path}/$photoSecondaire').delete();
      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      await banc.db.insererClient(nom: 'Martin'); // ajouté depuis la sauvegarde
      final ResultatRestauration resultat = await banc.service.restaurer(s.fichier);
      expect(resultat.fichiers, 3);
      expect(resultat.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
      expect(await instantane(banc.db), avant);
      expect(await banc.contenuDe(banc.photos), <String, String>{photoPrincipale: 'photo 1'});
    });

    test('un PDF absent n’empêche pas la sauvegarde d’être complète : il se refabrique', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      await File('${banc.factures.path}/$pdfFacture').delete();
      await File('${banc.devis.path}/$pdfDevis').delete();

      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(s.complete, isTrue);
      expect((await banc.service.examiner(s.fichier)).nombreFichiers, 2);
    });

    test('deux sauvegardes dans la même seconde, dont une incomplète, ne s’écrasent pas', () async {
      final SauvegardeLocale a = await banc.service.creer(TypeSauvegarde.manuelle);
      await remplirBase(banc.db); // des photos citées, mais aucune sur le téléphone
      final SauvegardeLocale b = await banc.service.creer(TypeSauvegarde.manuelle);
      final SauvegardeLocale c = await banc.service.creer(TypeSauvegarde.manuelle);

      expect(a.nom, 'crochet-creations-manuelle-2026-10-31-134912.zip');
      expect(b.nom, 'crochet-creations-manuelle-2026-10-31-134912-2-incomplete.zip');
      expect(c.nom, 'crochet-creations-manuelle-2026-10-31-134912-3-incomplete.zip');
      final List<SauvegardeLocale> liste = await banc.service.lister();
      expect(liste, hasLength(3));
      expect(liste.where((SauvegardeLocale s) => !s.complete), hasLength(2));
    });

    test('une ancienne archive à laquelle il manque une photo est reconnue incomplète', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List valide = await banc.octetsArchive();
      final Uint8List ancienne = _retoucher(
        _modifierDonnees(valide, (Map<String, dynamic> d) {
          final Map<String, dynamic> m = d['manifeste'] as Map<String, dynamic>;
          m['format'] = 1;
          m.remove('complete');
          m.remove('fichiersAbsents');
        }),
        <String, List<int>?>{'fichiers.json': null, 'fichiers/photos_produits/$photoSecondaire': null},
      );

      final ManifesteSauvegarde manifeste = await banc.examiner(ancienne);
      expect(manifeste.format, 1);
      expect(manifeste.complete, isFalse);
      expect(manifeste.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
    });
  });

  group('archives du format 1 (avant la liste des empreintes)', () {
    test('se restaurent toujours, sans contrôle des empreintes', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List valide = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);
      final Uint8List ancienne = _retoucher(
        _modifierDonnees(valide, (Map<String, dynamic> d) {
          final Map<String, dynamic> m = d['manifeste'] as Map<String, dynamic>;
          m['format'] = 1;
          m.remove('complete');
          m.remove('fichiersAbsents');
        }),
        <String, List<int>?>{'fichiers.json': null},
      );

      final ManifesteSauvegarde manifeste = await banc.examiner(ancienne);
      expect(manifeste.format, 1);
      expect(manifeste.empreintesVerifiables, isFalse);
      expect(manifeste.complete, isTrue);
      expect(manifeste.nombreFichiers, 4);

      await banc.db.insererClient(nom: 'Martin');
      await banc.db.delete(banc.db.depenses).go();
      final ResultatRestauration resultat = await banc.restaurer(ancienne);
      expect(resultat.fichiers, 4);
      expect(await instantane(banc.db), avant);
      expect(await banc.contenuDe(banc.photos), <String, String>{photoPrincipale: 'photo 1', photoSecondaire: 'photo 2'});
    });
  });

  group('progression', () {
    List<EtapeSauvegarde> suite(List<ProgressionSauvegarde> vues) {
      final List<EtapeSauvegarde> etapes = <EtapeSauvegarde>[];
      for (final ProgressionSauvegarde p in vues) {
        if (etapes.isEmpty || etapes.last != p.etape) etapes.add(p.etape);
      }
      return etapes;
    }

    test('la création annonce ses quatre étapes dans l’ordre, chacune menée à son terme', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      final List<ProgressionSauvegarde> vues = <ProgressionSauvegarde>[];
      await banc.service.creer(TypeSauvegarde.manuelle, surProgression: vues.add);

      expect(suite(vues), <EtapeSauvegarde>[
        EtapeSauvegarde.lectureDonnees,
        EtapeSauvegarde.empreintes,
        EtapeSauvegarde.ecritureFichiers,
        EtapeSauvegarde.verification,
      ]);
      for (final ProgressionSauvegarde p in vues) {
        expect(p.fait, inInclusiveRange(0, p.total));
        expect(p.numeroEtape, inInclusiveRange(1, p.nombreEtapes));
        expect(p.nombreEtapes, 4);
        expect(p.fraction, inInclusiveRange(0.0, 1.0));
      }
      for (final EtapeSauvegarde etape in EtapeSauvegarde.values.take(4)) {
        final ProgressionSauvegarde derniere = vues.lastWhere((ProgressionSauvegarde p) => p.etape == etape);
        expect(derniere.fait, derniere.total, reason: '$etape doit finir');
      }
      expect(vues.lastWhere((ProgressionSauvegarde p) => p.etape == EtapeSauvegarde.ecritureFichiers).total, 4);
    });

    test('la restauration annonce ses trois étapes dans l’ordre', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List archive = await banc.octetsArchive();

      final List<ProgressionSauvegarde> vues = <ProgressionSauvegarde>[];
      await banc.restaurer(archive, surProgression: vues.add);

      expect(suite(vues), <EtapeSauvegarde>[
        EtapeSauvegarde.controleFichiers,
        EtapeSauvegarde.copieDeSecurite,
        EtapeSauvegarde.remplacement,
      ]);
      final ProgressionSauvegarde controle = vues.lastWhere(
        (ProgressionSauvegarde p) => p.etape == EtapeSauvegarde.controleFichiers,
      );
      expect((controle.fait, controle.total), (4, 4));
      expect(vues.every((ProgressionSauvegarde p) => p.nombreEtapes == 3), isTrue);
      expect(vues.last.etape, EtapeSauvegarde.remplacement);
      expect(vues.last.fait, vues.last.total);
    });

    test('sans fichier à compter, la fraction est inconnue (barre sans position)', () {
      expect(const ProgressionSauvegarde(EtapeSauvegarde.empreintes, 0, 0).fraction, isNull);
      expect(const ProgressionSauvegarde(EtapeSauvegarde.empreintes, 1, 4).fraction, 0.25);
    });
  });

  group('place libre et fichiers provisoires', () {
    test('pas assez de place : la sauvegarde est refusée avant d’écrire, avec un message clair', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      banc.espace.octets = 5 * 1024 * 1024;

      await expectLater(
        banc.service.creer(TypeSauvegarde.manuelle),
        throwsA(_erreurAvecMessage('il en reste 5 Mo')),
      );
      await expectLater(
        banc.service.creer(TypeSauvegarde.manuelle),
        throwsA(_erreurAvecMessage('pas assez de place')),
      );
      expect(await banc.service.lister(), isEmpty);
      expect(await banc.service.dossierSauvegardes.list().toList(), isEmpty, reason: 'pas même un fichier provisoire');
    });

    test('assez de place, ou place inconnue : la sauvegarde se fait', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      banc.espace.octets = 1 << 40;
      await banc.service.creer(TypeSauvegarde.manuelle);
      banc.espace.octets = null;
      banc.maintenant = banc.maintenant.add(const Duration(minutes: 1));
      await banc.service.creer(TypeSauvegarde.manuelle);
      expect(await banc.service.lister(), hasLength(2));
    });

    test('restaurer avec trop peu de place : refusé, rien n’est modifié, pas de copie de sécurité', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      banc.espace.octets = 1024;
      await expectLater(banc.restaurer(archive), throwsA(_erreurAvecMessage('pas assez de place')));
      expect(await instantane(banc.db), avant);
      expect(await banc.contenuDe(banc.photos), hasLength(2));
      expect(await banc.service.lister(), isEmpty);
      await banc.verifierPropre();
    });

    test('un fichier provisoire laissé par une sauvegarde interrompue est effacé', () async {
      await banc.service.dossierSauvegardes.create(recursive: true);
      final File reste = File('${banc.service.dossierSauvegardes.path}/crochet-creations-auto-2026-10-30-080000.zip.tmp');
      await reste.writeAsString('à moitié écrit');

      await banc.service.creer(TypeSauvegarde.manuelle);
      expect(await reste.exists(), isFalse);
      expect(await banc.service.lister(), hasLength(1));
    });

    test('deux sauvegardes lancées en même temps se font l’une après l’autre', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      final List<SauvegardeLocale> faites = await Future.wait(<Future<SauvegardeLocale>>[
        banc.service.creer(TypeSauvegarde.manuelle),
        banc.service.creer(TypeSauvegarde.manuelle),
      ]);
      expect(faites.map((SauvegardeLocale s) => s.nom).toSet(), hasLength(2));
      for (final SauvegardeLocale s in faites) {
        expect((await banc.service.examiner(s.fichier)).nombreFichiers, 4);
      }
      expect(await banc.service.dossierSauvegardes.list().length, 2, reason: 'aucun fichier provisoire oublié');
    });
  });

  group('lister et supprimer', () {
    test('du plus récent au plus ancien ; les fichiers étrangers ou provisoires sont ignorés', () async {
      banc.maintenant = DateTime(2026, 10, 29, 8);
      await banc.service.creer(TypeSauvegarde.auto);
      banc.maintenant = DateTime(2026, 10, 31, 9, 30);
      await banc.service.creer(TypeSauvegarde.manuelle);
      banc.maintenant = DateTime(2026, 10, 30, 18);
      await banc.service.creer(TypeSauvegarde.auto);

      final Directory dossier = banc.service.dossierSauvegardes;
      await File('${dossier.path}/notes.txt').writeAsString('pas une sauvegarde');
      await File('${dossier.path}/crochet-creations-auto-2026-11-01-080000.zip.tmp').writeAsString('provisoire');

      final List<SauvegardeLocale> liste = await banc.service.lister();
      expect(liste.map((SauvegardeLocale s) => s.date).toList(), <DateTime>[
        DateTime(2026, 10, 31, 9, 30),
        DateTime(2026, 10, 30, 18),
        DateTime(2026, 10, 29, 8),
      ]);
      expect(liste.map((SauvegardeLocale s) => s.type).toList(), <TypeSauvegarde>[
        TypeSauvegarde.manuelle,
        TypeSauvegarde.auto,
        TypeSauvegarde.auto,
      ]);
    });

    test('sans dossier de sauvegardes : une liste vide', () async {
      expect(await banc.service.lister(), isEmpty);
    });

    test('supprimer efface le fichier, et ne se plaint pas s’il a déjà disparu', () async {
      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      await banc.service.supprimer(s);
      expect(await s.fichier.exists(), isFalse);
      expect(await banc.service.lister(), isEmpty);
      await banc.service.supprimer(s); // une deuxième fois : sans erreur
    });
  });

  group('sauvegarde automatique', () {
    test('une première sauvegarde est faite quand il n’y en a aucune', () async {
      final SauvegardeLocale? s = await banc.service.sauvegarderAutomatiquementSiBesoin();
      expect(s, isNotNull);
      expect(s!.type, TypeSauvegarde.auto);
      expect(await banc.service.derniereSauvegarde(), banc.maintenant);
    });

    test('pas de nouvelle sauvegarde avant un jour, une nouvelle au bout d’un jour', () async {
      await banc.service.sauvegarderAutomatiquementSiBesoin();

      banc.maintenant = banc.maintenant.add(const Duration(hours: 23, minutes: 59));
      expect(await banc.service.sauvegarderAutomatiquementSiBesoin(), isNull);
      expect(await banc.service.lister(), hasLength(1));

      banc.maintenant = DateTime(2026, 10, 31, 13, 49, 12).add(const Duration(days: 1));
      expect(await banc.service.sauvegarderAutomatiquementSiBesoin(), isNotNull);
      expect(await banc.service.lister(), hasLength(2));
    });

    test('une sauvegarde manuelle récente dispense de la sauvegarde automatique', () async {
      await banc.service.creer(TypeSauvegarde.manuelle);
      banc.maintenant = banc.maintenant.add(const Duration(hours: 3));
      expect(await banc.service.sauvegarderAutomatiquementSiBesoin(), isNull);
    });

    test('une copie de sécurité d’avant restauration ne compte pas comme dernière sauvegarde', () async {
      await banc.service.creer(TypeSauvegarde.avantRestauration);
      expect(await banc.service.derniereSauvegarde(), isNull);
      expect(await banc.service.sauvegarderAutomatiquementSiBesoin(), isNotNull);
    });

    test('les 7 dernières sont conservées, les manuelles ne sont jamais supprimées', () async {
      banc.maintenant = DateTime(2026, 10, 20, 9);
      await banc.service.creer(TypeSauvegarde.manuelle);
      // Une ouverture par jour pendant 10 jours (le 20 octobre, la sauvegarde manuelle toute fraîche suffit).
      for (int jour = 0; jour < 10; jour++) {
        banc.maintenant = DateTime(2026, 10, 20 + jour, 9);
        await banc.service.sauvegarderAutomatiquementSiBesoin();
      }
      final List<SauvegardeLocale> liste = await banc.service.lister();
      final List<SauvegardeLocale> automatiques = liste.where((SauvegardeLocale s) => s.type == TypeSauvegarde.auto).toList();
      expect(automatiques, hasLength(ServiceSauvegarde.sauvegardesAutomatiquesConservees));
      expect(automatiques.first.date, DateTime(2026, 10, 29, 9)); // la plus récente
      expect(automatiques.last.date, DateTime(2026, 10, 23, 9)); // les trois plus anciennes ont disparu
      expect(liste.where((SauvegardeLocale s) => s.type == TypeSauvegarde.manuelle), hasLength(1));
    });

    test('les 3 dernières copies de sécurité sont conservées', () async {
      for (int i = 0; i < 5; i++) {
        banc.maintenant = DateTime(2026, 10, 31, 10, i);
        await banc.service.creer(TypeSauvegarde.avantRestauration);
      }
      final List<SauvegardeLocale> liste = await banc.service.lister();
      expect(liste.map((SauvegardeLocale s) => s.date.minute).toList(), <int>[4, 3, 2]);
    });
  });

  group('restaurer', () {
    test('la plus ancienne copie de sécurité se restaure, même si la nouvelle copie la supprime', () async {
      final List<SauvegardeLocale> copies = <SauvegardeLocale>[];
      for (final int minute in <int>[1, 2, 3]) {
        banc.maintenant = DateTime(2026, 10, 31, 13, minute);
        copies.add(await banc.service.creer(TypeSauvegarde.avantRestauration));
      }
      banc.maintenant = DateTime(2026, 10, 31, 14);

      // La restauration fait une 4e copie : au-delà de 3, la plus ancienne (celle qu'on restaure) est supprimée.
      await banc.service.restaurer(copies.first.fichier);

      expect(await copies.first.fichier.exists(), isFalse);
      final List<SauvegardeLocale> restantes = await banc.service.lister();
      expect(restantes, hasLength(3));
      expect(restantes.first.date, DateTime(2026, 10, 31, 14));
    });

    test('sur un autre téléphone : les données, les photos et les PDF reviennent exactement', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      final ResultatRestauration resultat = await autre.restaurer(archive);

      expect(await instantane(autre.db), avant);
      expect(resultat.fichiers, 4);
      expect(resultat.lignes, avant.values.fold<int>(0, (int somme, List<Map<String, Object?>> l) => somme + l.length));
      expect(await autre.contenuDe(autre.photos), <String, String>{
        photoPrincipale: 'photo 1',
        photoSecondaire: 'photo 2',
      });
      expect(await autre.contenuDe(autre.factures), <String, String>{pdfFacture: '%PDF facture'});
      expect(await autre.contenuDe(autre.devis), <String, String>{pdfDevis: '%PDF devis'});
      await autre.verifierPropre();
    });

    test('sur le même téléphone : ce qui a changé depuis est remplacé, les fichiers ajoutés disparaissent', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      // Depuis la sauvegarde : un client ajouté, une dépense supprimée, une photo ajoutée, un PDF perdu.
      await banc.db.insererClient(nom: 'Martin');
      await banc.db.delete(banc.db.depenses).go();
      await banc.ajouterFichier(banc.photos, 'photo_3.jpg', 'photo 3');
      await File('${banc.factures.path}/$pdfFacture').delete();
      expect(await instantane(banc.db), isNot(avant));

      await banc.restaurer(archive);

      expect(await instantane(banc.db), avant);
      expect(await banc.contenuDe(banc.photos), <String, String>{
        photoPrincipale: 'photo 1',
        photoSecondaire: 'photo 2',
      });
      expect(await banc.contenuDe(banc.factures), <String, String>{pdfFacture: '%PDF facture'});
      await banc.verifierPropre();
    });

    test('une copie de sécurité est faite avant, et la restaurer ramène l’état d’avant la restauration', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List ancienne = await banc.octetsArchive();

      await banc.db.insererClient(nom: 'Martin');
      await banc.ajouterFichier(banc.photos, 'photo_3.jpg', 'photo 3');
      final Map<String, List<Map<String, Object?>>> etatActuel = await instantane(banc.db);

      await banc.restaurer(ancienne);
      final List<SauvegardeLocale> liste = await banc.service.lister();
      expect(liste, hasLength(1));
      expect(liste.single.type, TypeSauvegarde.avantRestauration);
      expect(await instantane(banc.db), isNot(etatActuel));

      await banc.service.restaurer(liste.single.fichier);
      expect(await instantane(banc.db), etatActuel);
      expect(await banc.contenuDe(banc.photos), containsPair('photo_3.jpg', 'photo 3'));
    });

    test('une sauvegarde faite avec le schéma 1 (sans « client_nom », catégories, lieux ni bloc-notes) est restaurée telle quelle', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List actuelle = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      // On « vieillit » l'archive : version 1 dans le manifeste et plus de colonne « client_nom ».
      final Uint8List ancienne = _modifierDonnees(actuelle, (Map<String, dynamic> d) {
        (d['manifeste'] as Map<String, dynamic>)['versionSchema'] = 1;
        final Map<String, dynamic> tables = d['tables'] as Map<String, dynamic>;
        tables.remove('categories_produit');
        tables.remove('lieux_vente');
        tables.remove('categories_note');
        tables.remove('notes');
        for (final String table in <String>['ventes', 'devis']) {
          for (final dynamic ligne in tables[table] as List<dynamic>) {
            (ligne as Map<String, dynamic>).remove('client_nom');
          }
        }
        for (final dynamic ligne in tables['ventes'] as List<dynamic>) {
          (ligne as Map<String, dynamic>).remove('lieu_id');
        }
      });

      await banc.db.delete(banc.db.paiements).go();
      await banc.db.delete(banc.db.factures).go();
      await banc.restaurer(ancienne);

      // Tout revient à l'identique ; les catégories, absentes de l'archive, sont recréées (les cinq de départ).
      // Les lieux de départ sont recréés, et la vente, qui n'avait pas de lieu dans l'archive, est « Non renseigné ».
      final Map<String, List<Map<String, Object?>>> apres = await instantane(banc.db);
      expect(apres.remove('categories_produit'), hasLength(5));
      avant.remove('categories_produit');
      expect(apres.remove('lieux_vente'), hasLength(4));
      avant.remove('lieux_vente');
      // Pas de bloc-notes dans l'archive : les deux catégories de notes de départ sont créées, sans note.
      expect(apres.remove('categories_note'), hasLength(2));
      avant.remove('categories_note');
      expect(apres.remove('notes'), isEmpty);
      avant.remove('notes');
      for (final Map<String, Object?> vente in avant['ventes']!) {
        vente['lieu_id'] = null;
      }
      expect(apres, avant);
      expect((await banc.db.select(banc.db.ventes).get()).every((Vente v) => v.clientNom == null), isTrue);
      expect((await banc.db.select(banc.db.ventes).get()).every((Vente v) => v.lieuId == null), isTrue);
      expect(
        (await LieuVenteRepository(banc.db).lister()).map((LieuVente l) => l.nom),
        <String>['Marché', 'Salon', 'Boutique', 'Vente en ligne'],
      );
      final List<CategorieProduit> categories = await CategorieRepository(banc.db).lister();
      expect(categories.map((CategorieProduit c) => c.cle), <String>[
        CleCategorie.crochet,
        CleCategorie.doudou,
        CleCategorie.bouclesOreilles,
        CleCategorie.accessoire,
        CleCategorie.surMesure,
      ]);
      await banc.verifierPropre();
    });

    test('les catégories créées, renommées ou supprimées font partie de la sauvegarde', () async {
      await remplirBase(banc.db);
      final CategorieRepository categories = CategorieRepository(banc.db);
      final CategorieProduit peluches = await categories.creer('Peluches');
      await categories.renommer(
        (await categories.parCle(CleCategorie.crochet))!.id,
        'Mes créations',
      );
      await categories.supprimer((await categories.parCle(CleCategorie.surMesure))!.id);
      await (banc.db.update(banc.db.produits)).write(ProduitsCompanion(categorie: Value(peluches.cle)));
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      await autre.restaurer(archive);

      expect(await instantane(autre.db), avant);
      final List<CategorieProduit> restaurees = await CategorieRepository(autre.db).lister();
      expect(restaurees.map((CategorieProduit c) => c.nom), <String>[
        'Mes créations',
        'Doudou',
        'Boucles d’oreilles',
        'Accessoire',
        'Peluches',
      ]);
      expect((await autre.db.select(autre.db.produits).get()).every((Produit p) => p.categorie == peluches.cle), isTrue);
    });

    test('les lieux créés, renommés ou supprimés, et le lieu de chaque vente, font partie de la sauvegarde', () async {
      await remplirBase(banc.db);
      final LieuVenteRepository lieux = LieuVenteRepository(banc.db);
      final LieuVente fete = await lieux.creer('Fête du village');
      final LieuVente marche = (await lieux.lister()).firstWhere((LieuVente l) => l.nom == 'Marché');
      await lieux.renommer(marche.id, 'Marché du samedi');
      final LieuVente salon = (await lieux.lister()).firstWhere((LieuVente l) => l.nom == 'Salon');
      await lieux.supprimer(salon.id);
      await (banc.db.update(banc.db.ventes)).write(VentesCompanion(lieuId: Value(fete.id)));
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      await autre.restaurer(archive);

      expect(await instantane(autre.db), avant);
      final LieuVenteRepository restaures = LieuVenteRepository(autre.db);
      expect((await restaures.lister()).map((LieuVente l) => l.nom), <String>[
        'Marché du samedi',
        'Boutique',
        'Vente en ligne',
        'Fête du village',
      ]);
      final List<Vente> ventes = await autre.db.select(autre.db.ventes).get();
      expect(ventes, isNotEmpty);
      expect(ventes.every((Vente v) => v.lieuId == fete.id), isTrue);
      expect(await restaures.nombreVentes(fete.id), ventes.length);
    });

    test('les catégories de notes et les notes (avec leur catégorie) font partie de la sauvegarde', () async {
      await remplirBase(banc.db);
      final CategorieNoteRepository categories = CategorieNoteRepository(banc.db);
      final NoteRepository notes = NoteRepository(banc.db);
      final CategorieNote modeles = await categories.creer('Modèles à essayer');
      final CategorieNote futures = (await categories.lister()).firstWhere(
        (CategorieNote c) => c.nom == 'Futures commandes',
      );
      await categories.renommer(futures.id, 'Commandes à venir');
      final CategorieNote documents = (await categories.lister()).firstWhere(
        (CategorieNote c) => c.nom == 'Documents entreprise',
      );
      await categories.supprimer(documents.id); // aucune note dedans : simple suppression
      await notes.creer(titre: 'Poncho', contenu: 'Laine bleue\n\n2 pelotes', categorieId: modeles.id);
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      await autre.restaurer(archive);

      expect(await instantane(autre.db), avant);
      final CategorieNoteRepository restaurees = CategorieNoteRepository(autre.db);
      expect((await restaurees.lister()).map((CategorieNote c) => c.nom), <String>[
        'Commandes à venir',
        'Modèles à essayer',
      ]);
      final List<Note> notesRestaurees = await NoteRepository(autre.db).lister();
      expect(notesRestaurees.map((Note n) => n.titre).toSet(), <String>{'Doudou pour Léa', 'Idée de bonnet', 'Poncho'});
      final Note poncho = notesRestaurees.firstWhere((Note n) => n.titre == 'Poncho');
      expect(poncho.contenu, 'Laine bleue\n\n2 pelotes');
      expect(poncho.categorieId, modeles.id);
      expect(await restaurees.nombreNotes(futures.id), 1);
    });

    test('une sauvegarde faite avant le bloc-notes (schéma 4) est restaurée : catégories de départ recréées, pas de note', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List actuelle = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final Uint8List ancienne = _modifierDonnees(actuelle, (Map<String, dynamic> d) {
        (d['manifeste'] as Map<String, dynamic>)['versionSchema'] = 4;
        final Map<String, dynamic> tables = d['tables'] as Map<String, dynamic>;
        tables.remove('categories_note');
        tables.remove('notes');
      });

      await banc.db.delete(banc.db.notes).go();
      await banc.db.delete(banc.db.categoriesNote).go();
      await banc.db.delete(banc.db.paiements).go();
      await banc.db.delete(banc.db.factures).go();
      await banc.restaurer(ancienne);

      final Map<String, List<Map<String, Object?>>> apres = await instantane(banc.db);
      expect(apres.remove('categories_note'), hasLength(2));
      expect(apres.remove('notes'), isEmpty);
      avant.remove('categories_note');
      avant.remove('notes');
      expect(apres, avant);
      expect(
        (await CategorieNoteRepository(banc.db).lister()).map((CategorieNote c) => c.nom),
        <String>['Futures commandes', 'Documents entreprise'],
      );
    });

    test('une sauvegarde faite après la suppression d’un client garde le nom copié', () async {
      await remplirBase(banc.db);
      await banc.db.delete(banc.db.inscriptionsCours).go();
      final Client client = (await banc.db.select(banc.db.clients).get()).single;
      await ClientRepository(banc.db).supprimer(client.id);
      final Uint8List archive = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      await autre.restaurer(archive);

      expect(await instantane(autre.db), avant);
      final Vente vente = (await autre.db.select(autre.db.ventes).get()).firstWhere((Vente v) => v.clientNom != null);
      expect(vente.clientId, isNull);
      expect(vente.clientNom, 'Marie Dupont');
    });

    test('une sauvegarde de base vide vide tout (la ligne des réglages est toujours là)', () async {
      final Uint8List vide = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> etatVide = await instantane(banc.db);
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      await banc.restaurer(vide);

      expect(await instantane(banc.db), etatVide);
      expect((await instantane(banc.db))['parametres_entreprise'], hasLength(1));
      expect(await banc.contenuDe(banc.photos), isEmpty);
      expect(await banc.contenuDe(banc.factures), isEmpty);
    });

    test('les écrans qui lisent la base en direct sont prévenus', () async {
      await remplirBase(banc.db);
      final Uint8List archive = await banc.octetsArchive();

      final List<int> nombres = <int>[];
      final subscription = banc.db.select(banc.db.clients).watch().listen((List<Client> l) => nombres.add(l.length));
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      await banc.db.insererClient(nom: 'Martin');
      await pumpEventQueue();
      expect(nombres.last, 2);

      await banc.restaurer(archive);
      await pumpEventQueue();
      expect(nombres.last, 1);
    });
  });

  group('une sauvegarde refusée ne change rien', () {
    late Uint8List valide;
    late Map<String, List<Map<String, Object?>>> avant;

    setUp(() async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      valide = await banc.octetsArchive();
      avant = await instantane(banc.db);
    });

    // [aussiALExamen] : faux quand le défaut ne se voit qu'en relisant le contenu des fichiers (à la restauration).
    Future<void> refuser(Uint8List archive, String message, {bool aussiALExamen = true}) async {
      if (aussiALExamen) await expectLater(banc.examiner(archive), throwsA(_erreurAvecMessage(message)));
      await expectLater(banc.restaurer(archive), throwsA(_erreurAvecMessage(message)));
      expect(await instantane(banc.db), avant);
      expect(await banc.contenuDe(banc.photos), hasLength(2));
      expect(await banc.service.lister(), isEmpty, reason: 'pas de copie de sécurité pour un fichier refusé');
      await banc.verifierPropre();
    }

    test('un fichier qui n’est pas un .zip', () async {
      await refuser(Uint8List.fromList(<int>[1, 2, 3, 4, 5]), 'pas une sauvegarde');
    });

    test('un .zip sans donnees.json', () async {
      await refuser(_zip(<String, List<int>>{'autre.txt': utf8.encode('bonjour')}), 'pas une sauvegarde');
    });

    test('un donnees.json qui n’est pas du JSON', () async {
      await refuser(_zip(<String, List<int>>{'donnees.json': utf8.encode('{pas du json')}), 'abîmée');
    });

    test('la sauvegarde d’une autre application', () async {
      await refuser(
        _modifierDonnees(valide, (Map<String, dynamic> d) => (d['manifeste'] as Map<String, dynamic>)['application'] = 'autre-appli'),
        'pas une sauvegarde',
      );
    });

    test('une sauvegarde faite avec une version plus récente de l’application', () async {
      await refuser(
        _modifierDonnees(valide, (Map<String, dynamic> d) => (d['manifeste'] as Map<String, dynamic>)['versionSchema'] = 99),
        'plus récente',
      );
      await refuser(
        _modifierDonnees(valide, (Map<String, dynamic> d) => (d['manifeste'] as Map<String, dynamic>)['format'] = 99),
        'plus récente',
      );
    });

    test('un fichier rangé hors des dossiers prévus (chemin qui remonte, dossier inconnu)', () async {
      for (final String nom in <String>[
        'fichiers/photos_produits/../evil.txt',
        'fichiers/inconnu/photo.jpg',
        'fichiers/photos_produits/..',
        'fichiers/evil.txt',
      ]) {
        final Archive source = ZipDecoder().decodeBytes(valide);
        final Archive copie = Archive();
        for (final ArchiveFile f in source) {
          copie.add(ArchiveFile.bytes(f.name, f.content));
        }
        copie.add(ArchiveFile.bytes(nom, utf8.encode('x')));
        await refuser(Uint8List.fromList(ZipEncoder().encode(copie)), 'incompatible');
      }
    });
  });

  group('une archive abîmée est refusée avant de toucher à quoi que ce soit', () {
    late Uint8List valide;
    late Map<String, List<Map<String, Object?>>> avant;

    setUp(() async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      valide = await banc.octetsArchive();
      avant = await instantane(banc.db);
    });

    Future<void> refuser(Uint8List archive, String message, {bool aussiALExamen = true}) async {
      if (aussiALExamen) await expectLater(banc.examiner(archive), throwsA(_erreurAvecMessage(message)));
      await expectLater(banc.restaurer(archive), throwsA(_erreurAvecMessage(message)));
      expect(await instantane(banc.db), avant);
      expect(await banc.contenuDe(banc.photos), <String, String>{photoPrincipale: 'photo 1', photoSecondaire: 'photo 2'});
      expect(await banc.contenuDe(banc.factures), <String, String>{pdfFacture: '%PDF facture'});
      expect(await banc.service.lister(), isEmpty, reason: 'pas de copie de sécurité pour une archive refusée');
      await banc.verifierPropre();
    }

    test('un fichier dont le contenu ne correspond plus à son empreinte (même taille)', () async {
      await refuser(
        _retoucher(valide, <String, List<int>?>{'fichiers/photos_produits/$photoPrincipale': utf8.encode('photo X')}),
        'abîmée',
        aussiALExamen: false, // seule la relecture du contenu le révèle
      );
    });

    test('un fichier d’une autre taille que celle annoncée', () async {
      await refuser(
        _retoucher(valide, <String, List<int>?>{'fichiers/photos_produits/$photoPrincipale': utf8.encode('photo 1 plus longue')}),
        'incompatible',
      );
    });

    test('un fichier annoncé mais absent de l’archive', () async {
      await refuser(_retoucher(valide, <String, List<int>?>{'fichiers/devis/$pdfDevis': null}), 'incompatible');
    });

    test('un fichier présent mais jamais annoncé', () async {
      await refuser(
        _retoucher(valide, <String, List<int>?>{'fichiers/photos_produits/intrus.jpg': utf8.encode('intrus')}),
        'incompatible',
      );
    });

    test('la liste des fichiers manque, n’est pas du JSON ou est mal formée', () async {
      final String vide = _empreinteDe('');
      final List<List<int>?> listes = <List<int>?>[
        null,
        utf8.encode('{pas du json'),
        utf8.encode('{"fichiers": "oups"}'),
        utf8.encode('{"fichiers": [{"chemin": "photos_produits/$photoPrincipale", "octets": 7, "sha256": "pas-une-empreinte"}]}'),
        utf8.encode('{"fichiers": [{"chemin": "../evil.txt", "octets": 7, "sha256": "$vide"}]}'),
        utf8.encode('{"fichiers": [{"chemin": "photos_produits/$photoPrincipale", "octets": -1, "sha256": "$vide"}]}'),
        utf8.encode(
          '{"fichiers": ['
          '{"chemin": "photos_produits/$photoPrincipale", "octets": 7, "sha256": "$vide"},'
          '{"chemin": "photos_produits/$photoPrincipale", "octets": 7, "sha256": "$vide"}]}',
        ),
      ];
      for (final List<int>? liste in listes) {
        await refuser(_retoucher(valide, <String, List<int>?>{'fichiers.json': liste}), 'incompatible');
      }
    });
  });

  group('une restauration qui échoue en route est annulée', () {
    late Uint8List valide;
    late Map<String, List<Map<String, Object?>>> avant;

    setUp(() async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      valide = await banc.octetsArchive();
      avant = await instantane(banc.db);
    });

    Future<void> echouer(void Function(Map<String, dynamic> tables) abimer) async {
      final Uint8List abimee = _modifierDonnees(valide, (Map<String, dynamic> d) => abimer(d['tables'] as Map<String, dynamic>));
      await expectLater(banc.restaurer(abimee), throwsA(_erreurAvecMessage('rien n’a été modifié')));
      expect(await instantane(banc.db), avant, reason: 'la transaction doit être annulée');
      expect(await banc.contenuDe(banc.photos), <String, String>{photoPrincipale: 'photo 1', photoSecondaire: 'photo 2'});
      await banc.verifierPropre();
    }

    test('une colonne inconnue', () async {
      await echouer((Map<String, dynamic> tables) {
        ((tables['produits'] as List<dynamic>).first as Map<String, dynamic>)['colonne_inventee'] = 1;
      });
    });

    test('une valeur refusée par une contrainte de la base (prix négatif)', () async {
      await echouer((Map<String, dynamic> tables) {
        ((tables['produits'] as List<dynamic>).first as Map<String, dynamic>)['prix_vente_centimes'] = -5;
      });
    });

    test('une liaison cassée (des ventes sans leur client)', () async {
      await echouer((Map<String, dynamic> tables) {
        tables['clients'] = <dynamic>[];
      });
    });

    test('une table qui n’est pas une liste', () async {
      await echouer((Map<String, dynamic> tables) {
        tables['produits'] = 'oups';
      });
    });
  });

  group('pièces jointes des notes', () {
    const String contenuPiece = '%PDF patron du poncho';

    /// Une note avec une pièce jointe (le fichier est rangé dans le dossier des pièces jointes de [b]).
    Future<void> noteAvecPiece(_Banc b, {String nomFichier = 'piece_1.pdf'}) async {
      await b.ajouterFichier(b.piecesJointes, nomFichier, contenuPiece);
      await NoteRepository(b.db).creer(
        titre: 'Patron du poncho',
        piecesJointes: <PieceRangee>[
          PieceRangee(
            nomFichier: nomFichier,
            nomAffiche: 'Patron poncho.pdf',
            type: TypePieceJointe.document,
            octets: utf8.encode(contenuPiece).length,
          ),
        ],
      );
    }

    test('sont citées par les données : leur fichier est irremplaçable, comme une photo', () async {
      await noteAvecPiece(banc);
      final Set<String> citees = FormatSauvegarde.fichiersIrremplacablesCites(await instantane(banc.db));
      expect(citees, <String>{'notes_pieces_jointes/piece_1.pdf'});
    });

    test('l’archive les contient avec leur empreinte, et une restauration sur un autre téléphone les remet à l’identique', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      await noteAvecPiece(banc);

      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(s.complete, isTrue);
      final Archive archive = ZipDecoder().decodeBytes(await s.fichier.readAsBytes());
      expect(utf8.decode(archive.find('fichiers/notes_pieces_jointes/piece_1.pdf')!.content), contenuPiece);
      final Map<String, dynamic> liste =
          jsonDecode(utf8.decode(archive.find('fichiers.json')!.content)) as Map<String, dynamic>;
      final Map<String, dynamic> entree = (liste['fichiers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((Map<String, dynamic> f) => f['chemin'] == 'notes_pieces_jointes/piece_1.pdf');
      expect(entree['sha256'], _empreinteDe(contenuPiece));
      expect(entree['octets'], utf8.encode(contenuPiece).length);

      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);
      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      final ResultatRestauration resultat = await autre.restaurer(await s.fichier.readAsBytes());

      expect(resultat.fichiersAbsents, isEmpty);
      expect(await instantane(autre.db), avant);
      expect(await autre.contenuDe(autre.piecesJointes), <String, String>{'piece_1.pdf': contenuPiece});
      final List<PieceJointeNote> pieces = await autre.db.select(autre.db.piecesJointesNote).get();
      expect(pieces.single.nomAffiche, 'Patron poncho.pdf');
      expect(pieces.single.typeFichier, TypePieceJointe.document);
    });

    test('une pièce jointe dont le fichier manque : la sauvegarde est incomplète, et le dit', () async {
      await noteAvecPiece(banc);
      await File('${banc.piecesJointes.path}/piece_1.pdf').delete();

      final SauvegardeLocale s = await banc.service.creer(TypeSauvegarde.manuelle);
      expect(s.complete, isFalse);
      expect(s.fichiersAbsents, <String>['notes_pieces_jointes/piece_1.pdf']);
      expect(s.nom, endsWith('-incomplete.zip'));
    });

    test('un fichier provisoire (.tmp) du dossier des pièces jointes ne part pas dans l’archive', () async {
      await noteAvecPiece(banc);
      await banc.ajouterFichier(banc.piecesJointes, 'piece_2.mp4.tmp', 'copie interrompue');

      final Archive archive = ZipDecoder().decodeBytes(await banc.octetsArchive());
      expect(archive.files.map((ArchiveFile f) => f.name), contains('fichiers/notes_pieces_jointes/piece_1.pdf'));
      expect(archive.files.map((ArchiveFile f) => f.name), isNot(contains('fichiers/notes_pieces_jointes/piece_2.mp4.tmp')));
    });

    test('une sauvegarde faite avant les pièces jointes (schéma 5) est restaurée : aucune pièce jointe', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List actuelle = await banc.octetsArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final Uint8List ancienne = _modifierDonnees(actuelle, (Map<String, dynamic> d) {
        (d['manifeste'] as Map<String, dynamic>)['versionSchema'] = 5;
        (d['tables'] as Map<String, dynamic>).remove('pieces_jointes_note');
      });
      await noteAvecPiece(banc);
      await banc.restaurer(ancienne);

      final Map<String, List<Map<String, Object?>>> apres = await instantane(banc.db);
      expect(apres.remove('pieces_jointes_note'), isEmpty);
      avant.remove('pieces_jointes_note');
      expect(apres, avant);
    });
  });

  group('export JSON', () {
    test('toutes les données dans un seul fichier, sans les photos ni les PDF', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      final File fichier = await banc.service.ecrireJson();
      expect(fichier.uri.pathSegments.last, 'crochet-creations-donnees-2026-10-31.json');
      expect(fichier.parent.path, banc.service.dossierExports.path);

      final Map<String, dynamic> document = jsonDecode(await fichier.readAsString()) as Map<String, dynamic>;
      final Map<String, dynamic> manifeste = document['manifeste'] as Map<String, dynamic>;
      expect(manifeste['application'], 'crochet-creations');
      expect(manifeste['nombreFichiers'], 4);
      expect((manifeste['lignes'] as Map<String, dynamic>)['produits'], 1);
      expect((document['tables'] as Map<String, dynamic>).keys.toList(), FormatSauvegarde.tables);

      final List<dynamic> clients = (document['tables'] as Map<String, dynamic>)['clients'] as List<dynamic>;
      expect((clients.single as Map<String, dynamic>)['notes'], 'Préfère les couleurs "pastel"');
    });

    test('un fichier du même jour est remplacé', () async {
      await banc.service.ecrireJson();
      await remplirBase(banc.db);
      final File fichier = await banc.service.ecrireJson();
      final Map<String, dynamic> document = jsonDecode(await fichier.readAsString()) as Map<String, dynamic>;
      expect(((document['tables'] as Map<String, dynamic>)['produits'] as List<dynamic>), hasLength(1));
      expect(await banc.service.dossierExports.list().length, 1);
    });
  });
}
