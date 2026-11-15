import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder;
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/service_drive.dart';
import 'package:crochet_creations/data/drive/service_sauvegarde_drive.dart';
import 'package:crochet_creations/data/sauvegarde/espace_libre.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/data/sauvegarde/service_sauvegarde.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_donnees.dart';
import 'aide_drive.dart';

class _FauxEspaceLibre implements ControleEspaceLibre {
  int? octets;

  @override
  Future<int?> octetsLibres(Directory dossier) async => octets;
}

const String _nomPiece = 'piece_1.mp4';
const String _nomSauvegarde = 'crochet-creations-sauvegarde-2026-11-14-183005.zip';

/// Un « téléphone » de test : une base en mémoire, les dossiers de fichiers, les trois services, et une horloge qu'on règle.
/// Plusieurs téléphones peuvent partager le même faux Drive : c'est le changement de téléphone.
class _Telephone {
  _Telephone._(this.db, this.racine, this.drive);

  static Future<_Telephone> creer(FauxClientDrive drive) async =>
      _Telephone._(creerBaseEnMemoire(), await Directory.systemTemp.createTemp('sauvegarde_drive_'), drive);

  final AppDatabase db;
  final Directory racine;
  final FauxClientDrive drive;
  DateTime maintenant = DateTime(2026, 11, 14, 18, 30, 5);
  final _FauxEspaceLibre espace = _FauxEspaceLibre();

  Directory dossierLocal(DossierDrive dossier) => Directory('${racine.path}/${dossier.nomLocal}');
  Directory get photos => dossierLocal(DossierDrive.photos);
  Directory get factures => dossierLocal(DossierDrive.factures);
  Directory get devis => dossierLocal(DossierDrive.devis);
  Directory get pieces => dossierLocal(DossierDrive.notes);
  Directory get travail => Directory('${racine.path}/drive/travail');
  File get fichierEtat => File('${racine.path}/drive/sauvegardes_drive.json');

  late final ServiceSauvegarde sauvegarde = ServiceSauvegarde(
    base: db,
    dossierSauvegardes: Directory('${racine.path}/sauvegardes'),
    dossierExports: Directory('${racine.path}/exports'),
    dossierPhotos: photos,
    dossierFactures: factures,
    dossierDevis: devis,
    dossierPiecesJointes: pieces,
    horloge: () => maintenant,
    espaceLibre: espace,
  );

  late final ServiceDrive envoi = ServiceDrive(
    client: drive,
    dossiers: <DossierDrive, Directory>{for (final DossierDrive d in DossierDrive.values) d: dossierLocal(d)},
    fichierBilan: File('${racine.path}/drive/dernier_envoi.json'),
    horloge: () => maintenant,
  );

  late final ServiceSauvegardeDrive service = nouveauService();

  ServiceSauvegardeDrive nouveauService() => ServiceSauvegardeDrive(
    client: drive,
    envoi: envoi,
    sauvegarde: sauvegarde,
    dossierTravail: travail,
    fichierEtat: fichierEtat,
    horloge: () => maintenant,
  );

  Future<void> _ecrire(Directory dossier, String nom, String contenu) async {
    await dossier.create(recursive: true);
    await File('${dossier.path}/$nom').writeAsString(contenu);
  }

  /// Les quatre fichiers cités par [remplirBase], et une pièce jointe de note.
  Future<void> ecrireFichiers() async {
    await _ecrire(photos, photoPrincipale, 'photo 1');
    await _ecrire(photos, photoSecondaire, 'photo 2');
    await _ecrire(factures, pdfFacture, '%PDF facture');
    await _ecrire(devis, pdfDevis, '%PDF devis');
    await _ecrire(pieces, _nomPiece, 'vidéo');
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

  /// Aucun dossier de travail de la restauration (`.restauration`, `.ancien`), ni téléchargement provisoire, ne doit rester.
  Future<void> verifierPropre() async {
    final List<String> noms = <String>[
      await for (final FileSystemEntity e in racine.list()) e.uri.pathSegments.where((String s) => s.isNotEmpty).last,
    ];
    expect(noms.where((String n) => n.endsWith('.restauration') || n.endsWith('.ancien')), isEmpty);
    expect(await _fichiersSous(travail), isEmpty, reason: 'le dossier de travail doit être vidé');
  }

  Future<List<String>> _fichiersSous(Directory dossier) async {
    if (!await dossier.exists()) return <String>[];
    return <String>[
      await for (final FileSystemEntity e in dossier.list(recursive: true))
        if (e is File) e.path,
    ];
  }

  Future<void> fermer() async {
    await db.close();
    if (await racine.exists()) await racine.delete(recursive: true);
  }
}

String _sha(String texte) => sha256.convert(utf8.encode(texte)).toString();

/// Les entrées d'une archive de sauvegarde Drive du faux Drive.
Archive _archiveDrive(FauxClientDrive drive, String nom) =>
    ZipDecoder().decodeBytes(Uint8List.fromList(drive.fichierNomme(nom)!.contenu));

Map<String, dynamic> _json(Archive archive, String nom) =>
    jsonDecode(utf8.decode(archive.find(nom)!.content)) as Map<String, dynamic>;

void main() {
  late FauxClientDrive drive;
  late _Telephone tel;

  setUp(() async {
    drive = FauxClientDrive();
    tel = await _Telephone.creer(drive);
    addTearDown(tel.fermer);
  });

  Future<_Telephone> autreTelephone() async {
    final _Telephone autre = await _Telephone.creer(drive);
    addTearDown(autre.fermer);
    return autre;
  }

  group('sauvegarder', () {
    test('la première sauvegarde envoie les fichiers puis les données, sans recopier les fichiers dans la sauvegarde', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();

      final List<ProgressionSauvegardeDrive> etapes = <ProgressionSauvegardeDrive>[];
      final ResultatSauvegardeDrive resultat = await tel.service.sauvegarder(progression: etapes.add);

      expect(resultat.issue, IssueSauvegardeDrive.faite);
      expect(resultat.envoi.envoyes, 5);
      expect(resultat.fichiersNonEnvoyes, isEmpty);
      expect(drive.nomsDans('Photos des produits'), <String>[photoPrincipale, photoSecondaire]);
      expect(drive.nomsDans('Factures'), <String>[pdfFacture]);
      expect(drive.nomsDans('Devis'), <String>[pdfDevis]);
      expect(drive.nomsDans('Notes - pièces jointes'), <String>[_nomPiece]);
      expect(drive.nomsDans(nomDossierSauvegardesDrive), <String>[_nomSauvegarde]);

      expect(resultat.sauvegarde!.nom, _nomSauvegarde);
      expect(resultat.sauvegarde!.date, tel.maintenant);
      expect(resultat.sauvegarde!.fichiers, 5);
      expect(resultat.sauvegarde!.octets, drive.fichierNomme(_nomSauvegarde)!.contenu.length);

      // Les étapes se suivent : fichiers, données, envoi de la sauvegarde.
      expect(etapes.map((ProgressionSauvegardeDrive p) => p.etape).toSet(), <EtapeSauvegardeDrive>{
        EtapeSauvegardeDrive.fichiers,
        EtapeSauvegardeDrive.donnees,
        EtapeSauvegardeDrive.envoi,
      });
      expect(etapes.last.etape, EtapeSauvegardeDrive.envoi);
    });

    test('la sauvegarde contient les données et la liste des fichiers avec leur empreinte, mais aucun fichier', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();

      final Archive archive = _archiveDrive(drive, _nomSauvegarde);
      expect(archive.where((ArchiveFile e) => e.isFile).map((ArchiveFile e) => e.name).toSet(), <String>{
        'donnees.json',
        'fichiers.json',
      });

      final Map<String, dynamic> donnees = _json(archive, 'donnees.json');
      final Map<String, dynamic> manifeste = donnees['manifeste'] as Map<String, dynamic>;
      expect(manifeste['donneesSeules'], isTrue);
      expect(manifeste['nombreFichiers'], 5);
      expect(manifeste['complete'], isTrue);
      final Map<String, dynamic> tables = donnees['tables'] as Map<String, dynamic>;
      expect(tables.keys.toSet(), FormatSauvegarde.tables.toSet());
      expect(tables['clients'], isNotEmpty);

      final Map<String, dynamic> liste = _json(archive, 'fichiers.json');
      final Map<String, Map<String, dynamic>> parChemin = <String, Map<String, dynamic>>{
        for (final Object? f in liste['fichiers'] as List<Object?>) (f! as Map<String, dynamic>)['chemin'] as String: f as Map<String, dynamic>,
      };
      expect(parChemin.keys.toSet(), <String>{
        'photos_produits/$photoPrincipale',
        'photos_produits/$photoSecondaire',
        'factures/$pdfFacture',
        'devis/$pdfDevis',
        'notes_pieces_jointes/$_nomPiece',
      });
      expect(parChemin['photos_produits/$photoPrincipale']!['sha256'], _sha('photo 1'));
      expect(parChemin['photos_produits/$photoPrincipale']!['octets'], 'photo 1'.length);
      expect(parChemin['factures/$pdfFacture']!['sha256'], _sha('%PDF facture'));
    });

    test('rien ne reste dans le dossier de travail, ni fichier provisoire', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();
      await tel.verifierPropre();
    });

    test('le bilan est gardé sur le téléphone : dernière sauvegarde, dernier passage, aucun fichier non parti', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();

      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.derniere!.nom, _nomSauvegarde);
      expect(etat.derniere!.fichiers, 5);
      expect(etat.derniereVerification, tel.maintenant);
      expect(etat.fichiersNonEnvoyes, isEmpty);
      expect(etat.envoiAutomatique, isFalse);
      // Le bilan de l'envoi des fichiers (étape 6) est tenu à jour lui aussi.
      expect((await tel.envoi.dernierBilan())!.envoyes, 5);
    });

    test('rien de neuf : aucune nouvelle sauvegarde n’est ajoutée, mais le passage est noté', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();
      final int envoisAvant = drive.envoyes.length;

      tel.maintenant = DateTime(2026, 11, 14, 18, 45);
      final ResultatSauvegardeDrive deuxieme = await tel.service.sauvegarder();

      expect(deuxieme.issue, IssueSauvegardeDrive.dejaAJour);
      expect(deuxieme.sauvegarde!.nom, _nomSauvegarde);
      expect(deuxieme.sauvegarde!.fichiers, 5);
      expect(drive.envoyes.length, envoisAvant, reason: 'ni fichier ni sauvegarde renvoyés');
      expect(drive.nomsDans(nomDossierSauvegardesDrive), <String>[_nomSauvegarde]);

      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.derniereVerification, DateTime(2026, 11, 14, 18, 45));
      expect(etat.derniere!.nom, _nomSauvegarde);
    });

    test('les données ont changé : une nouvelle sauvegarde s’ajoute, et l’ancienne est gardée', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();

      await tel.db.insererClient(nom: 'Martin');
      tel.maintenant = DateTime(2026, 11, 14, 19, 0, 0);
      final ResultatSauvegardeDrive deuxieme = await tel.service.sauvegarder();

      expect(deuxieme.issue, IssueSauvegardeDrive.faite);
      expect(drive.nomsDans(nomDossierSauvegardesDrive), <String>[
        _nomSauvegarde,
        'crochet-creations-sauvegarde-2026-11-14-190000.zip',
      ]);
      final List<SauvegardeDrive> liste = await tel.service.listerSauvegardes();
      expect(liste.map((SauvegardeDrive s) => s.nom), <String>[
        'crochet-creations-sauvegarde-2026-11-14-190000.zip',
        _nomSauvegarde,
      ]);
    });

    test('un fichier ajouté suffit à justifier une nouvelle sauvegarde (les données, elles, n’ont pas changé)', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();

      await tel.ajouterFichier(tel.photos, 'photo_3.jpg', 'photo 3');
      tel.maintenant = DateTime(2026, 11, 14, 19, 0, 0);
      final ResultatSauvegardeDrive deuxieme = await tel.service.sauvegarder();

      expect(deuxieme.issue, IssueSauvegardeDrive.faite);
      expect(deuxieme.sauvegarde!.fichiers, 6);
      expect(drive.nomsDans('Photos des produits'), contains('photo_3.jpg'));
    });

    test('un fichier qui n’a pas pu partir n’est pas listé, et la sauvegarde le dit ; une fois parti, il est listé', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      drive.echecEnvoi = (String nom) => nom == photoSecondaire ? const ErreurDrive('Connexion coupée.') : null;

      final ResultatSauvegardeDrive resultat = await tel.service.sauvegarder();

      expect(resultat.issue, IssueSauvegardeDrive.faite);
      expect(resultat.fichiersNonEnvoyes, <String>['photos_produits/$photoSecondaire']);
      expect(resultat.envoi.erreurs, hasLength(1));
      final Archive archive = _archiveDrive(drive, _nomSauvegarde);
      final Map<String, dynamic> manifeste = _json(archive, 'donnees.json')['manifeste'] as Map<String, dynamic>;
      expect(manifeste['complete'], isFalse);
      expect(manifeste['fichiersAbsents'], <String>['photos_produits/$photoSecondaire']);
      final List<Object?> listes = _json(archive, 'fichiers.json')['fichiers'] as List<Object?>;
      expect(listes, hasLength(4));
      expect(
        listes.map((Object? f) => (f! as Map<String, dynamic>)['chemin']),
        isNot(contains('photos_produits/$photoSecondaire')),
      );
      expect((await tel.service.lireEtat()).fichiersNonEnvoyes, <String>['photos_produits/$photoSecondaire']);

      // La connexion revient : le fichier part, et la nouvelle sauvegarde le liste.
      drive.echecEnvoi = null;
      tel.maintenant = DateTime(2026, 11, 14, 19, 0, 0);
      final ResultatSauvegardeDrive suite = await tel.service.sauvegarder();
      expect(suite.issue, IssueSauvegardeDrive.faite);
      expect(suite.fichiersNonEnvoyes, isEmpty);
      expect(suite.sauvegarde!.fichiers, 5);
      expect((await tel.service.lireEtat()).fichiersNonEnvoyes, isEmpty);
    });

    test('si l’envoi des fichiers est arrêté, les données ne sont pas sauvegardées', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      final AnnulationEnvoi annulation = AnnulationEnvoi();
      drive.avantEnvoi = (String nom) => annulation.demander();

      final ResultatSauvegardeDrive resultat = await tel.service.sauvegarder(annulation: annulation);

      expect(resultat.issue, IssueSauvegardeDrive.interrompue);
      expect(resultat.sauvegarde, isNull);
      expect(resultat.envoi.interrompu, isTrue);
      expect(drive.nomsDans(nomDossierSauvegardesDrive), isEmpty);
      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.derniere, isNull);
      expect(etat.derniereVerification, isNull);
    });

    test('la connexion à Google perdue en route interrompt aussi la sauvegarde des données', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      drive.echecEnvoi = (String nom) => const ErreurDrive('L’autorisation Google Drive a expiré. Reconnectez-vous.', autorisationAExpire: true);

      final ResultatSauvegardeDrive resultat = await tel.service.sauvegarder();

      expect(resultat.issue, IssueSauvegardeDrive.interrompue);
      expect(resultat.arret!.autorisationAExpire, isTrue);
      expect(drive.nomsDans(nomDossierSauvegardesDrive), isEmpty);
    });

    test('Google injoignable avant de commencer : erreur lisible, rien n’est noté', () async {
      await remplirBase(tel.db);
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');

      await expectLater(
        tel.service.sauvegarder(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', 'Pas de connexion à Internet.')),
      );
      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.derniere, isNull);
      expect(etat.derniereVerification, isNull);
    });

    test('une sauvegarde qu’on ne retrouve pas sur Drive n’est pas comptée', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      drive.oublierEnvoi = (String nom) => dateDeNomSauvegardeDrive(nom) != null;

      await expectLater(
        tel.service.sauvegarder(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('pas été retrouvée'))),
      );
      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.derniere, isNull);
      expect(etat.derniereVerification, isNull);
      await tel.verifierPropre();
    });

    test('une seule opération à la fois', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      final Completer<void> feu = Completer<void>();
      drive.pauseEnvoi = (String nom) => feu.future;

      final Future<ResultatSauvegardeDrive> premiere = tel.service.sauvegarder();
      await expectLater(
        tel.service.sauvegarder(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('déjà en cours'))),
      );
      feu.complete();
      expect((await premiere).issue, IssueSauvegardeDrive.faite);
      // Et une fois finie, une autre peut démarrer.
      expect((await tel.service.sauvegarder()).issue, IssueSauvegardeDrive.dejaAJour);
    });

    test('une base vide se sauvegarde aussi (sans fichier)', () async {
      final ResultatSauvegardeDrive resultat = await tel.service.sauvegarder();
      expect(resultat.issue, IssueSauvegardeDrive.faite);
      expect(resultat.sauvegarde!.fichiers, 0);
      expect(_json(_archiveDrive(drive, _nomSauvegarde), 'fichiers.json')['fichiers'], isEmpty);
    });
  });

  group('envoi automatique', () {
    test('désactivé au départ : rien ne se passe', () async {
      await remplirBase(tel.db);
      expect(await tel.service.automatiqueEstDu(), isFalse);
      expect(await tel.service.sauvegarderSiBesoin(), isNull);
      expect(drive.envoyes, isEmpty);
    });

    test('activé : une sauvegarde au premier passage, puis une par jour au plus', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.reglerEnvoiAutomatique(actif: true);
      expect((await tel.service.lireEtat()).envoiAutomatique, isTrue);
      expect(await tel.service.automatiqueEstDu(), isTrue);

      final ResultatSauvegardeDrive? premier = await tel.service.sauvegarderSiBesoin();
      expect(premier!.issue, IssueSauvegardeDrive.faite);

      // Le même jour : rien.
      tel.maintenant = tel.maintenant.add(const Duration(hours: 23));
      expect(await tel.service.sauvegarderSiBesoin(), isNull);

      // Le lendemain : un passage ; rien de neuf, donc pas de nouvelle sauvegarde.
      tel.maintenant = DateTime(2026, 11, 15, 18, 30, 5);
      final ResultatSauvegardeDrive? lendemain = await tel.service.sauvegarderSiBesoin();
      expect(lendemain!.issue, IssueSauvegardeDrive.dejaAJour);
      expect(drive.nomsDans(nomDossierSauvegardesDrive), hasLength(1));

      // Un jour après ce dernier passage (le 15 à 18 h 30), des données ont changé : une nouvelle sauvegarde.
      await tel.db.insererClient(nom: 'Martin');
      tel.maintenant = DateTime(2026, 11, 16, 19);
      final ResultatSauvegardeDrive? suivant = await tel.service.sauvegarderSiBesoin();
      expect(suivant!.issue, IssueSauvegardeDrive.faite);
      expect(drive.nomsDans(nomDossierSauvegardesDrive), hasLength(2));
    });

    test('désactiver l’envoi automatique l’arrête', () async {
      await tel.service.reglerEnvoiAutomatique(actif: true);
      await tel.service.reglerEnvoiAutomatique(actif: false);
      tel.maintenant = DateTime(2026, 11, 20);
      expect(await tel.service.sauvegarderSiBesoin(), isNull);
    });

    test('un échec (pas de réseau) n’est pas noté comme un passage : il est retenté à la prochaine ouverture', () async {
      await tel.service.reglerEnvoiAutomatique(actif: true);
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');

      await expectLater(tel.service.sauvegarderSiBesoin(), throwsA(isA<ErreurDrive>()));
      expect(await tel.service.automatiqueEstDu(), isTrue);

      drive.panne = null;
      expect((await tel.service.sauvegarderSiBesoin())!.issue, IssueSauvegardeDrive.faite);
    });
  });

  group('état gardé sur le téléphone', () {
    test('le réglage et le bilan survivent à un redémarrage', () async {
      await remplirBase(tel.db);
      await tel.service.reglerEnvoiAutomatique(actif: true);
      await tel.service.sauvegarder();

      final EtatSauvegardesDrive relu = await tel.nouveauService().lireEtat();
      expect(relu.envoiAutomatique, isTrue);
      expect(relu.derniere!.nom, _nomSauvegarde);
    });

    test('régler l’envoi automatique ne perd pas le dernier bilan', () async {
      await remplirBase(tel.db);
      await tel.service.sauvegarder();
      await tel.service.reglerEnvoiAutomatique(actif: true);

      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.envoiAutomatique, isTrue);
      expect(etat.derniere!.nom, _nomSauvegarde);
    });

    test('un fichier illisible redonne l’état de départ, sans erreur', () async {
      await tel.fichierEtat.parent.create(recursive: true);
      await tel.fichierEtat.writeAsString('pas du json {');
      final EtatSauvegardesDrive etat = await tel.service.lireEtat();
      expect(etat.envoiAutomatique, isFalse);
      expect(etat.derniere, isNull);
    });

    test('des réglages rapprochés se suivent sans se perdre', () async {
      await Future.wait(<Future<void>>[
        tel.service.reglerEnvoiAutomatique(actif: true),
        tel.service.reglerEnvoiAutomatique(actif: false),
        tel.service.reglerEnvoiAutomatique(actif: true),
      ]);
      expect((await tel.service.lireEtat()).envoiAutomatique, isTrue);
    });
  });

  group('listerSauvegardes', () {
    test('aucune sauvegarde (ni même de dossier) : liste vide, et rien n’est créé sur Drive', () async {
      expect(await tel.service.listerSauvegardes(), isEmpty);
      expect(drive.dossiersCrees, 0);
    });

    test('les fichiers étrangers déposés dans le dossier sont ignorés', () async {
      await tel.service.sauvegarder();
      drive.fichiers['x'] = FichierDriveFaux(
        id: 'x',
        nom: 'mes-notes.txt',
        dossierId: drive.idSousDossier(nomDossierSauvegardesDrive)!,
        contenu: <int>[1, 2],
      );
      final List<SauvegardeDrive> liste = await tel.service.listerSauvegardes();
      expect(liste.map((SauvegardeDrive s) => s.nom), <String>[_nomSauvegarde]);
    });

    test('Google injoignable : erreur lisible', () async {
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await expectLater(tel.service.listerSauvegardes(), throwsA(isA<ErreurDrive>()));
    });
  });

  group('restaurer depuis Drive', () {
    /// Une boutique sauvegardée sur Drive depuis le téléphone [tel].
    Future<void> sauvegarderLaBoutique() async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      await tel.service.sauvegarder();
    }

    test('sur un téléphone neuf : les données, les photos, les PDF et les pièces jointes reviennent exactement', () async {
      await sauvegarderLaBoutique();
      final Map<String, List<Map<String, Object?>>> attendu = await instantane(tel.db);
      final _Telephone neuf = await autreTelephone();

      final List<SauvegardeDrive> liste = await neuf.service.listerSauvegardes();
      expect(liste, hasLength(1));
      final PreparationRestaurationDrive preparation = await neuf.service.preparerRestauration(liste.first);
      expect(preparation.examen.fichiers, hasLength(5));
      expect(preparation.examen.octetsFichiers, 'photo 1'.length + 'photo 2'.length + '%PDF facture'.length + '%PDF devis'.length + utf8.encode('vidéo').length);
      expect(preparation.examen.manifeste.complete, isTrue);

      // Préparer ne modifie rien.
      expect(await neuf.contenuDe(neuf.photos), isEmpty);

      final List<ProgressionRestaurationDrive> etapes = <ProgressionRestaurationDrive>[];
      final ResultatRestauration resultat = await neuf.service.restaurer(preparation, progression: etapes.add);

      expect(await instantane(neuf.db), attendu);
      expect(resultat.fichiers, 5);
      expect(resultat.fichiersAbsents, isEmpty);
      expect(await neuf.contenuDe(neuf.photos), <String, String>{photoPrincipale: 'photo 1', photoSecondaire: 'photo 2'});
      expect(await neuf.contenuDe(neuf.factures), <String, String>{pdfFacture: '%PDF facture'});
      expect(await neuf.contenuDe(neuf.devis), <String, String>{pdfDevis: '%PDF devis'});
      expect(await neuf.contenuDe(neuf.pieces), <String, String>{_nomPiece: 'vidéo'});
      await neuf.verifierPropre();

      // Les trois étapes sont annoncées, dans l'ordre.
      final List<EtapeRestaurationDrive> ordre = <EtapeRestaurationDrive>[];
      for (final ProgressionRestaurationDrive p in etapes) {
        if (ordre.isEmpty || ordre.last != p.etape) ordre.add(p.etape);
      }
      expect(ordre, <EtapeRestaurationDrive>[
        EtapeRestaurationDrive.telechargement,
        EtapeRestaurationDrive.copieDeSecurite,
        EtapeRestaurationDrive.remplacement,
      ]);
      final ProgressionRestaurationDrive finTelechargement =
          etapes.lastWhere((ProgressionRestaurationDrive p) => p.etape == EtapeRestaurationDrive.telechargement);
      expect(finTelechargement.fichiersFaits, 5);
      expect(finTelechargement.fichiersTotal, 5);
      expect(finTelechargement.fraction, 1);

      // Le téléphone neuf a fait une copie de sécurité de ce qu'il avait (rien) avant de remplacer.
      expect((await neuf.sauvegarde.lister()).where((SauvegardeLocale s) => s.type == TypeSauvegarde.avantRestauration), hasLength(1));
    });

    test('sur le même téléphone : ce qui a changé depuis est remplacé, et les fichiers ajoutés depuis disparaissent', () async {
      await sauvegarderLaBoutique();
      final Map<String, List<Map<String, Object?>>> attendu = await instantane(tel.db);

      await tel.db.insererClient(nom: 'Martin');
      await tel.ajouterFichier(tel.photos, 'photo_3.jpg', 'photo 3');
      await File('${tel.factures.path}/$pdfFacture').delete();
      expect(await instantane(tel.db), isNot(attendu));

      final PreparationRestaurationDrive preparation = await tel.service.preparerRestauration(
        (await tel.service.listerSauvegardes()).first,
      );
      await tel.service.restaurer(preparation);

      expect(await instantane(tel.db), attendu);
      expect(await tel.contenuDe(tel.photos), <String, String>{photoPrincipale: 'photo 1', photoSecondaire: 'photo 2'});
      expect(await tel.contenuDe(tel.factures), <String, String>{pdfFacture: '%PDF facture'});
      await tel.verifierPropre();
    });

    test('un fichier absent de Drive : la photo est signalée, le reste revient', () async {
      await sauvegarderLaBoutique();
      drive.fichiers.removeWhere((String id, FichierDriveFaux f) => f.nom == photoSecondaire);
      final _Telephone neuf = await autreTelephone();

      final PreparationRestaurationDrive preparation = await neuf.service.preparerRestauration(
        (await neuf.service.listerSauvegardes()).first,
      );
      final ResultatRestauration resultat = await neuf.service.restaurer(preparation);

      expect(resultat.fichiers, 4);
      expect(resultat.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
      expect(await neuf.contenuDe(neuf.photos), <String, String>{photoPrincipale: 'photo 1'});
      expect(await instantane(neuf.db), await instantane(tel.db));
      await neuf.verifierPropre();
    });

    test('un PDF absent de Drive n’est pas signalé : il se refait à la demande', () async {
      await sauvegarderLaBoutique();
      drive.fichiers.removeWhere((String id, FichierDriveFaux f) => f.nom == pdfFacture);
      final _Telephone neuf = await autreTelephone();

      final ResultatRestauration resultat = await neuf.service.restaurer(
        await neuf.service.preparerRestauration((await neuf.service.listerSauvegardes()).first),
      );

      expect(resultat.fichiers, 4);
      expect(resultat.fichiersAbsents, isEmpty);
      expect(await neuf.contenuDe(neuf.factures), isEmpty);
    });

    test('un fichier abîmé sur Drive (même taille, autre contenu) n’est pas remis en place', () async {
      await sauvegarderLaBoutique();
      drive.fichierNomme(photoPrincipale)!.contenu = utf8.encode('photo X');
      final _Telephone neuf = await autreTelephone();

      final ResultatRestauration resultat = await neuf.service.restaurer(
        await neuf.service.preparerRestauration((await neuf.service.listerSauvegardes()).first),
      );

      expect(resultat.fichiers, 4);
      expect(resultat.fichiersAbsents, <String>['photos_produits/$photoPrincipale']);
      expect(await neuf.contenuDe(neuf.photos), <String, String>{photoSecondaire: 'photo 2'});
      await neuf.verifierPropre();
    });

    test('un PDF refait depuis (autre taille sur Drive) n’est pas confondu avec celui de la sauvegarde', () async {
      await sauvegarderLaBoutique();
      drive.fichierNomme(pdfFacture)!.contenu = utf8.encode('%PDF facture refaite');
      final _Telephone neuf = await autreTelephone();

      final ResultatRestauration resultat = await neuf.service.restaurer(
        await neuf.service.preparerRestauration((await neuf.service.listerSauvegardes()).first),
      );

      expect(resultat.fichiers, 4);
      expect(await neuf.contenuDe(neuf.factures), isEmpty);
    });

    test('une sauvegarde faite alors qu’une photo n’était pas partie le dit avant la restauration et après', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      drive.echecEnvoi = (String nom) => nom == photoSecondaire ? const ErreurDrive('Connexion coupée.') : null;
      await tel.service.sauvegarder();
      drive.echecEnvoi = null;
      final _Telephone neuf = await autreTelephone();

      final PreparationRestaurationDrive preparation = await neuf.service.preparerRestauration(
        (await neuf.service.listerSauvegardes()).first,
      );
      expect(preparation.examen.manifeste.complete, isFalse);
      expect(preparation.examen.manifeste.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
      expect(preparation.examen.fichiers, hasLength(4));

      final ResultatRestauration resultat = await neuf.service.restaurer(preparation);
      expect(resultat.fichiersAbsents, <String>['photos_produits/$photoSecondaire']);
    });

    test('pas de réseau pendant le téléchargement : tout est abandonné, rien n’a été modifié', () async {
      await sauvegarderLaBoutique();
      final _Telephone autre = await autreTelephone();
      await autre.db.insererClient(nom: 'Locale');
      await autre.ajouterFichier(autre.photos, 'locale.jpg', 'ma photo');
      final Map<String, List<Map<String, Object?>>> avant = await instantane(autre.db);

      final PreparationRestaurationDrive preparation = await autre.service.preparerRestauration(
        (await autre.service.listerSauvegardes()).first,
      );
      drive.echecTelechargement = (String nom) =>
          nom == photoSecondaire ? const ErreurDrive('Pas de connexion à Internet.') : null;

      await expectLater(
        autre.service.restaurer(preparation),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', 'Pas de connexion à Internet.')),
      );

      expect(await instantane(autre.db), avant);
      expect(await autre.contenuDe(autre.photos), <String, String>{'locale.jpg': 'ma photo'});
      expect(await autre.contenuDe(autre.factures), isEmpty);
      await autre.verifierPropre();
      expect((await autre.sauvegarde.lister()).where((SauvegardeLocale s) => s.type == TypeSauvegarde.avantRestauration), isEmpty);

      // La connexion revient : on recommence depuis le début.
      drive.echecTelechargement = null;
      final ResultatRestauration resultat = await autre.service.restaurer(
        await autre.service.preparerRestauration((await autre.service.listerSauvegardes()).first),
      );
      expect(resultat.fichiers, 5);
      expect(await autre.contenuDe(autre.photos), <String, String>{photoPrincipale: 'photo 1', photoSecondaire: 'photo 2'});
    });

    test('une sauvegarde de Drive illisible est refusée avec un message, et rien ne reste', () async {
      drive.dossiers['racine'] = DossierDriveFaux(nom: nomDossierRacineDrive, parentId: 'root');
      drive.dossiers['sauvegardes'] = DossierDriveFaux(nom: nomDossierSauvegardesDrive, parentId: 'racine');
      drive.fichiers['abime'] = FichierDriveFaux(
        id: 'abime',
        nom: _nomSauvegarde,
        dossierId: 'sauvegardes',
        contenu: utf8.encode('ceci n’est pas une archive'),
      );
      final SauvegardeDrive choisie = (await tel.service.listerSauvegardes()).single;

      await expectLater(tel.service.preparerRestauration(choisie), throwsA(isA<DonneeInvalide>()));
      await tel.verifierPropre();
      // Rien n'a été supprimé sur Drive.
      expect(drive.fichiers.containsKey('abime'), isTrue);
    });

    test('les dossiers des photos et documents introuvables sur Drive : erreur claire, rien n’est modifié', () async {
      await sauvegarderLaBoutique();
      drive.dossiers.removeWhere((String id, DossierDriveFaux d) => DossierDrive.values.any((DossierDrive x) => x.nomDrive == d.nom));
      final _Telephone neuf = await autreTelephone();

      final PreparationRestaurationDrive preparation = await neuf.service.preparerRestauration(
        (await neuf.service.listerSauvegardes()).first,
      );
      await expectLater(
        neuf.service.restaurer(preparation),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('introuvables'))),
      );
      expect(await instantane(neuf.db), isNot(await instantane(tel.db)));
      await neuf.verifierPropre();
    });

    test('pas assez de place sur le téléphone : la restauration est refusée avant de télécharger les fichiers', () async {
      await sauvegarderLaBoutique();
      final _Telephone neuf = await autreTelephone();
      final PreparationRestaurationDrive preparation = await neuf.service.preparerRestauration(
        (await neuf.service.listerSauvegardes()).first,
      );
      neuf.espace.octets = 5;
      drive.telecharges.clear();

      await expectLater(neuf.service.restaurer(preparation), throwsA(isA<DonneeInvalide>()));

      expect(drive.telecharges, isEmpty);
      await neuf.verifierPropre();
    });

    test('renoncer efface le téléchargement préparé', () async {
      await sauvegarderLaBoutique();
      final _Telephone neuf = await autreTelephone();
      await neuf.service.preparerRestauration((await neuf.service.listerSauvegardes()).first);
      expect(await neuf._fichiersSous(neuf.travail), isNotEmpty);

      await neuf.service.abandonnerRestauration();

      await neuf.verifierPropre();
    });

    test('une opération à la fois : on ne prépare pas une restauration pendant une sauvegarde', () async {
      await sauvegarderLaBoutique();
      await tel.db.insererClient(nom: 'Martin');
      final Completer<void> feu = Completer<void>();
      drive.pauseEnvoi = (String nom) => feu.future;
      final Future<ResultatSauvegardeDrive> enCours = tel.service.sauvegarder();

      await expectLater(
        tel.service.preparerRestauration((await tel.service.listerSauvegardes()).first),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('déjà en cours'))),
      );
      feu.complete();
      await enCours;
    });

    test('la sauvegarde Drive, choisie par erreur dans la restauration locale, dit où elle se restaure', () async {
      await sauvegarderLaBoutique();
      final File copie = File('${tel.racine.path}/recue.zip');
      await copie.writeAsBytes(drive.fichierNomme(_nomSauvegarde)!.contenu);

      await expectLater(
        tel.sauvegarde.examiner(copie),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('Google Drive'))),
      );
      await expectLater(
        tel.sauvegarde.restaurer(copie),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('Google Drive'))),
      );
    });
  });

  group('données seules (service de sauvegarde)', () {
    Future<Set<String>> tousLesFichiers() async => <String>{
      'photos_produits/$photoPrincipale',
      'photos_produits/$photoSecondaire',
      'factures/$pdfFacture',
      'devis/$pdfDevis',
      'notes_pieces_jointes/$_nomPiece',
    };

    test('l’empreinte est la même tant que rien ne change, et change avec les données ou la liste des fichiers', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      final Set<String> confirmes = await tousLesFichiers();

      final DonneesSeules a = await tel.sauvegarde.lireDonneesSeules(fichiersConfirmes: confirmes);
      tel.maintenant = DateTime(2027, 1, 1);
      final DonneesSeules b = await tel.sauvegarde.lireDonneesSeules(fichiersConfirmes: confirmes);
      expect(a.empreinte, b.empreinte, reason: 'la date n’entre pas dans l’empreinte');
      expect(a.empreinte, hasLength(64));
      expect(a.nombreFichiers, 5);

      final DonneesSeules moins = await tel.sauvegarde.lireDonneesSeules(fichiersConfirmes: <String>{...confirmes}..remove('devis/$pdfDevis'));
      expect(moins.empreinte, isNot(a.empreinte));
      expect(moins.nombreFichiers, 4);

      await tel.ajouterFichier(tel.photos, photoPrincipale, 'photo 1 retouchée');
      final DonneesSeules taille = await tel.sauvegarde.lireDonneesSeules(fichiersConfirmes: confirmes);
      expect(taille.empreinte, isNot(a.empreinte), reason: 'une photo de taille différente est une autre situation');

      await tel.db.insererClient(nom: 'Martin');
      final DonneesSeules donnees = await tel.sauvegarde.lireDonneesSeules(fichiersConfirmes: confirmes);
      expect(donnees.empreinte, isNot(taille.empreinte));
    });

    test('seuls les fichiers confirmés et présents sont listés', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      final DonneesSeules donnees = await tel.sauvegarde.lireDonneesSeules(
        fichiersConfirmes: <String>{
          'photos_produits/$photoPrincipale',
          'photos_produits/fantome.jpg', // confirmé sur Drive mais absent du téléphone
          '../../etc/passwd', // un chemin qui sort du dossier n'est jamais listé
        },
      );
      expect(donnees.nombreFichiers, 1);
      expect(donnees.fichiersAbsents, contains('photos_produits/$photoSecondaire'));
    });

    test('l’archive est écrite sans fichier provisoire, et remplace une ancienne du même nom', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      final DonneesSeules donnees = await tel.sauvegarde.lireDonneesSeules(fichiersConfirmes: await tousLesFichiers());
      final File destination = File('${tel.racine.path}/sortie/archive.zip');
      await destination.parent.create(recursive: true);
      await destination.writeAsString('ancienne');

      final File ecrite = await tel.sauvegarde.ecrireDonneesSeules(donnees, destination);

      expect(ecrite.path, destination.path);
      expect(await File('${destination.path}.tmp').exists(), isFalse);
      final ExamenDonneesSeules examen = await tel.sauvegarde.examinerDonneesSeules(destination);
      expect(examen.fichiers, hasLength(5));
      expect(examen.manifeste.nombreFichiers, 5);
      expect(examen.manifeste.fichiersAbsents, isEmpty);
    });

    test('une archive complète n’est pas une sauvegarde « données seules »', () async {
      await remplirBase(tel.db);
      await tel.ecrireFichiers();
      final File complete = (await tel.sauvegarde.creer(TypeSauvegarde.manuelle)).fichier;
      await expectLater(tel.sauvegarde.examinerDonneesSeules(complete), throwsA(isA<DonneeInvalide>()));
    });
  });
}
