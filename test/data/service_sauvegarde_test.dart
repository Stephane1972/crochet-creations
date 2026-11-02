import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/data/sauvegarde/service_sauvegarde.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_donnees.dart';

/// Un « téléphone » de test : une base en mémoire, des dossiers temporaires et une horloge qu'on règle.
class _Banc {
  _Banc._(this.db, this.racine);

  static Future<_Banc> creer() async => _Banc._(creerBaseEnMemoire(), await Directory.systemTemp.createTemp('sauvegarde_'));

  final AppDatabase db;
  final Directory racine;
  DateTime maintenant = DateTime(2026, 10, 31, 13, 49, 12);

  Directory get photos => Directory('${racine.path}/photos_produits');
  Directory get factures => Directory('${racine.path}/factures');
  Directory get devis => Directory('${racine.path}/devis');

  late final ServiceSauvegarde service = ServiceSauvegarde(
    base: db,
    dossierSauvegardes: Directory('${racine.path}/sauvegardes'),
    dossierExports: Directory('${racine.path}/exports'),
    dossierPhotos: photos,
    dossierFactures: factures,
    dossierDevis: devis,
    horloge: () => maintenant,
  );

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

  group('créer une sauvegarde', () {
    test('l’archive contient les données, les photos et les PDF', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      final Uint8List octets = await banc.service.fabriquerArchive();
      final Archive archive = ZipDecoder().decodeBytes(octets);
      expect(archive.map((ArchiveFile f) => f.name).toSet(), <String>{
        'donnees.json',
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
      final Uint8List octets = await banc.service.fabriquerArchive();

      final ManifesteSauvegarde manifeste = banc.service.examiner(octets);
      expect(manifeste.creeLe, banc.maintenant);
      expect(manifeste.nombreFichiers, 4);
      expect(manifeste.lignesDe('produits'), 1);
      expect(manifeste.lignesDe('ventes'), 2);
      expect(manifeste.lignesDe('depenses'), 1);
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
      final Archive archive = ZipDecoder().decodeBytes(await banc.service.fabriquerArchive());
      expect(archive.find('fichiers/photos_produits/photo_3.jpg.tmp'), isNull);
      expect(archive.find('fichiers/photos_produits/$photoPrincipale'), isNotNull);
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
    test('sur un autre téléphone : les données, les photos et les PDF reviennent exactement', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List archive = await banc.service.fabriquerArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      final ResultatRestauration resultat = await autre.service.restaurer(archive);

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
      final Uint8List archive = await banc.service.fabriquerArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      // Depuis la sauvegarde : un client ajouté, une dépense supprimée, une photo ajoutée, un PDF perdu.
      await banc.db.insererClient(nom: 'Martin');
      await banc.db.delete(banc.db.depenses).go();
      await banc.ajouterFichier(banc.photos, 'photo_3.jpg', 'photo 3');
      await File('${banc.factures.path}/$pdfFacture').delete();
      expect(await instantane(banc.db), isNot(avant));

      await banc.service.restaurer(archive);

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
      final Uint8List ancienne = await banc.service.fabriquerArchive();

      await banc.db.insererClient(nom: 'Martin');
      await banc.ajouterFichier(banc.photos, 'photo_3.jpg', 'photo 3');
      final Map<String, List<Map<String, Object?>>> etatActuel = await instantane(banc.db);

      await banc.service.restaurer(ancienne);
      final List<SauvegardeLocale> liste = await banc.service.lister();
      expect(liste, hasLength(1));
      expect(liste.single.type, TypeSauvegarde.avantRestauration);
      expect(await instantane(banc.db), isNot(etatActuel));

      await banc.service.restaurer(await liste.single.fichier.readAsBytes());
      expect(await instantane(banc.db), etatActuel);
      expect(await banc.contenuDe(banc.photos), containsPair('photo_3.jpg', 'photo 3'));
    });

    test('une sauvegarde faite avec le schéma 1 (sans « client_nom ») est restaurée telle quelle', () async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      final Uint8List actuelle = await banc.service.fabriquerArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      // On « vieillit » l'archive : version 1 dans le manifeste et plus de colonne « client_nom ».
      final Uint8List ancienne = _modifierDonnees(actuelle, (Map<String, dynamic> d) {
        (d['manifeste'] as Map<String, dynamic>)['versionSchema'] = 1;
        final Map<String, dynamic> tables = d['tables'] as Map<String, dynamic>;
        for (final String table in <String>['ventes', 'devis']) {
          for (final dynamic ligne in tables[table] as List<dynamic>) {
            (ligne as Map<String, dynamic>).remove('client_nom');
          }
        }
      });

      await banc.db.delete(banc.db.paiements).go();
      await banc.db.delete(banc.db.factures).go();
      await banc.service.restaurer(ancienne);

      expect(await instantane(banc.db), avant);
      expect((await banc.db.select(banc.db.ventes).get()).every((Vente v) => v.clientNom == null), isTrue);
      await banc.verifierPropre();
    });

    test('une sauvegarde faite après la suppression d’un client garde le nom copié', () async {
      await remplirBase(banc.db);
      await banc.db.delete(banc.db.inscriptionsCours).go();
      final Client client = (await banc.db.select(banc.db.clients).get()).single;
      await ClientRepository(banc.db).supprimer(client.id);
      final Uint8List archive = await banc.service.fabriquerArchive();
      final Map<String, List<Map<String, Object?>>> avant = await instantane(banc.db);

      final _Banc autre = await _Banc.creer();
      addTearDown(autre.fermer);
      await autre.service.restaurer(archive);

      expect(await instantane(autre.db), avant);
      final Vente vente = (await autre.db.select(autre.db.ventes).get()).firstWhere((Vente v) => v.clientNom != null);
      expect(vente.clientId, isNull);
      expect(vente.clientNom, 'Marie Dupont');
    });

    test('une sauvegarde de base vide vide tout (la ligne des réglages est toujours là)', () async {
      final Uint8List vide = await banc.service.fabriquerArchive();
      final Map<String, List<Map<String, Object?>>> etatVide = await instantane(banc.db);
      await remplirBase(banc.db);
      await banc.ecrireFichiers();

      await banc.service.restaurer(vide);

      expect(await instantane(banc.db), etatVide);
      expect((await instantane(banc.db))['parametres_entreprise'], hasLength(1));
      expect(await banc.contenuDe(banc.photos), isEmpty);
      expect(await banc.contenuDe(banc.factures), isEmpty);
    });

    test('les écrans qui lisent la base en direct sont prévenus', () async {
      await remplirBase(banc.db);
      final Uint8List archive = await banc.service.fabriquerArchive();

      final List<int> nombres = <int>[];
      final subscription = banc.db.select(banc.db.clients).watch().listen((List<Client> l) => nombres.add(l.length));
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      await banc.db.insererClient(nom: 'Martin');
      await pumpEventQueue();
      expect(nombres.last, 2);

      await banc.service.restaurer(archive);
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
      valide = await banc.service.fabriquerArchive();
      avant = await instantane(banc.db);
    });

    Future<void> refuser(Uint8List archive, String message) async {
      expect(() => banc.service.examiner(archive), throwsA(_erreurAvecMessage(message)));
      await expectLater(banc.service.restaurer(archive), throwsA(_erreurAvecMessage(message)));
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

  group('une restauration qui échoue en route est annulée', () {
    late Uint8List valide;
    late Map<String, List<Map<String, Object?>>> avant;

    setUp(() async {
      await remplirBase(banc.db);
      await banc.ecrireFichiers();
      valide = await banc.service.fabriquerArchive();
      avant = await instantane(banc.db);
    });

    Future<void> echouer(void Function(Map<String, dynamic> tables) abimer) async {
      final Uint8List abimee = _modifierDonnees(valide, (Map<String, dynamic> d) => abimer(d['tables'] as Map<String, dynamic>));
      await expectLater(banc.service.restaurer(abimee), throwsA(_erreurAvecMessage('rien n’a été modifié')));
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
