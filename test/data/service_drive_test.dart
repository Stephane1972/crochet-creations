import 'dart:convert';
import 'dart:io';

import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/service_drive.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

import 'aide_drive.dart';

void main() {
  late Directory racine;
  late Map<DossierDrive, Directory> dossiers;
  late FauxClientDrive drive;
  late File fichierBilan;
  late ServiceDrive service;
  final DateTime maintenant = DateTime(2026, 11, 13, 12, 30);

  setUp(() {
    racine = Directory.systemTemp.createTempSync('crochet_drive_');
    dossiers = <DossierDrive, Directory>{
      for (final DossierDrive d in DossierDrive.values)
        d: Directory('${racine.path}/${d.nomLocal}')..createSync(recursive: true),
    };
    drive = FauxClientDrive();
    fichierBilan = File('${racine.path}/drive/dernier_envoi.json');
    service = ServiceDrive(client: drive, dossiers: dossiers, fichierBilan: fichierBilan, horloge: () => maintenant);
  });

  tearDown(() {
    racine.deleteSync(recursive: true);
  });

  void ecrire(DossierDrive dossier, String nom, String contenu) =>
      File('${dossiers[dossier]!.path}/$nom').writeAsStringSync(contenu);

  /// Un petit jeu de fichiers dans les quatre dossiers.
  void remplir() {
    ecrire(DossierDrive.photos, 'photo_1.jpg', 'photo un');
    ecrire(DossierDrive.photos, 'photo_2.jpg', 'photo deux');
    ecrire(DossierDrive.factures, 'FACT-2026-0001.pdf', 'facture un');
    ecrire(DossierDrive.devis, 'DEVIS-2026-0001.pdf', 'devis un');
    ecrire(DossierDrive.notes, 'piece_1.mp4', 'video');
  }

  group('vérifier', () {
    test('compte ce qui est à envoyer, sans rien créer ni envoyer sur Drive', () async {
      remplir();
      final VerificationDrive verification = await service.verifier();
      expect(verification.fichiersLocaux, 5);
      expect(verification.dejaSurDrive, 0);
      expect(verification.fichiersAEnvoyer, 5);
      expect(verification.octetsAEnvoyer, 'photo un'.length + 'photo deux'.length + 'facture un'.length + 'devis un'.length + 5);
      expect(verification.toutEstSurDrive, isFalse);
      expect(drive.dossiersCrees, 0);
      expect(drive.dossiers, isEmpty);
      expect(drive.fichiers, isEmpty);
      expect(await service.dernierBilan(), isNull); // vérifier n'écrit pas de bilan
    });

    test('ignore les fichiers provisoires, les fichiers cachés et les sous-dossiers', () async {
      ecrire(DossierDrive.photos, 'photo_1.jpg', 'photo');
      ecrire(DossierDrive.photos, 'copie.jpg.tmp', 'en cours');
      ecrire(DossierDrive.photos, '.cache', 'caché');
      Directory('${dossiers[DossierDrive.photos]!.path}/sous').createSync();
      File('${dossiers[DossierDrive.photos]!.path}/sous/autre.jpg').writeAsStringSync('rangé plus bas');
      final VerificationDrive verification = await service.verifier();
      expect(verification.fichiersLocaux, 1);
      expect(verification.plans.first.aEnvoyer.single.fichier.nom, 'photo_1.jpg');
    });

    test('un dossier du téléphone qui n’existe pas encore compte pour vide', () async {
      dossiers[DossierDrive.notes]!.deleteSync();
      final VerificationDrive verification = await service.verifier();
      expect(verification.fichiersLocaux, 0);
      expect(verification.toutEstSurDrive, isTrue);
    });

    test('après un envoi complet : tout est sur Drive', () async {
      remplir();
      await service.envoyer();
      final VerificationDrive verification = await service.verifier();
      expect(verification.toutEstSurDrive, isTrue);
      expect(verification.dejaSurDrive, 5);
    });

    test('si Google est injoignable : une erreur lisible', () async {
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await expectLater(service.verifier(), throwsA(isA<ErreurDrive>()));
    });
  });

  group('envoyer', () {
    test('crée le dossier principal et ses quatre sous-dossiers, puis range chaque fichier à sa place', () async {
      remplir();
      final ResultatEnvoi resultat = await service.envoyer();

      expect(drive.dossiersCrees, 5);
      expect(drive.nomsDans('Photos des produits'), <String>['photo_1.jpg', 'photo_2.jpg']);
      expect(drive.nomsDans('Factures'), <String>['FACT-2026-0001.pdf']);
      expect(drive.nomsDans('Devis'), <String>['DEVIS-2026-0001.pdf']);
      expect(drive.nomsDans('Notes - pièces jointes'), <String>['piece_1.mp4']);

      final RapportEnvoi rapport = resultat.rapport;
      expect(rapport.envoyes, 5);
      expect(rapport.dejaSurDrive, 0);
      expect(rapport.erreurs, isEmpty);
      expect(rapport.interrompu, isFalse);
      expect(rapport.complet, isTrue);
      expect(rapport.date, maintenant);
      expect(rapport.octetsEnvoyes, 'photo un'.length + 'photo deux'.length + 'facture un'.length + 'devis un'.length + 5);
      expect(resultat.arret, isNull);
    });

    test('envoie le contenu exact des fichiers', () async {
      ecrire(DossierDrive.photos, 'photo_1.jpg', 'octets de la photo');
      await service.envoyer();
      expect(utf8.decode(drive.fichierNomme('photo_1.jpg')!.contenu), 'octets de la photo');
    });

    test('note l’empreinte SHA-256 des PDF, pas celle des photos', () async {
      ecrire(DossierDrive.factures, 'F.pdf', 'contenu du pdf');
      ecrire(DossierDrive.photos, 'p.jpg', 'photo');
      await service.envoyer();
      expect(drive.fichierNomme('F.pdf')!.empreinte, sha256.convert(utf8.encode('contenu du pdf')).toString());
      expect(drive.fichierNomme('p.jpg')!.empreinte, isNull);
    });

    test('un second envoi ne renvoie rien et réutilise les dossiers', () async {
      remplir();
      await service.envoyer();
      final int dejaEnvoyes = drive.envoyes.length;
      final RapportEnvoi second = (await service.envoyer()).rapport;
      expect(drive.envoyes.length, dejaEnvoyes);
      expect(drive.dossiersCrees, 5);
      expect(second.envoyes, 0);
      expect(second.dejaSurDrive, 5);
      expect(second.complet, isTrue);
    });

    test('un nouveau fichier part seul ; les anciens restent où ils sont', () async {
      remplir();
      await service.envoyer();
      ecrire(DossierDrive.photos, 'photo_3.jpg', 'nouvelle photo');
      final RapportEnvoi rapport = (await service.envoyer()).rapport;
      expect(rapport.envoyes, 1);
      expect(rapport.dejaSurDrive, 5);
      expect(drive.envoyes.last, 'photo_3.jpg');
    });

    test('un PDF régénéré (même nom, même taille, autre contenu) remplace l’ancien ; une photo reste telle quelle', () async {
      ecrire(DossierDrive.factures, 'F.pdf', 'version A');
      ecrire(DossierDrive.photos, 'p.jpg', 'photo A');
      await service.envoyer();

      ecrire(DossierDrive.factures, 'F.pdf', 'version B'); // même taille
      ecrire(DossierDrive.photos, 'p.jpg', 'photo B'); // même taille : une photo ne change jamais après son ajout
      final RapportEnvoi rapport = (await service.envoyer()).rapport;

      expect(rapport.envoyes, 1);
      final FichierDriveFaux pdf = drive.fichierNomme('F.pdf')!;
      expect(utf8.decode(pdf.contenu), 'version B');
      expect(pdf.versions, 2);
      expect(drive.fichiers.values.where((FichierDriveFaux f) => f.nom == 'F.pdf'), hasLength(1)); // pas de doublon
      expect(utf8.decode(drive.fichierNomme('p.jpg')!.contenu), 'photo A');
    });

    test('ne supprime jamais rien sur Drive : un fichier absent du téléphone reste sur Drive', () async {
      remplir();
      await service.envoyer();
      File('${dossiers[DossierDrive.photos]!.path}/photo_1.jpg').deleteSync();
      await service.envoyer();
      expect(drive.nomsDans('Photos des produits'), <String>['photo_1.jpg', 'photo_2.jpg']);
    });

    test('un fichier en échec n’empêche pas les autres ; il est nommé dans le bilan', () async {
      remplir();
      drive.echecEnvoi = (String nom) => nom == 'photo_2.jpg' ? const ErreurDrive('Pas de connexion à Internet.') : null;
      final ResultatEnvoi resultat = await service.envoyer();
      final RapportEnvoi rapport = resultat.rapport;
      expect(rapport.envoyes, 4);
      expect(rapport.erreurs, hasLength(1));
      expect(rapport.erreurs.single.dossier, DossierDrive.photos);
      expect(rapport.erreurs.single.nom, 'photo_2.jpg');
      expect(rapport.erreurs.single.message, 'Pas de connexion à Internet.');
      expect(rapport.interrompu, isFalse);
      expect(rapport.complet, isFalse);
      expect(resultat.arret, isNull);

      // Une fois le problème réglé, un nouvel envoi n'envoie que ce qui manque.
      drive.echecEnvoi = null;
      final RapportEnvoi reprise = (await service.envoyer()).rapport;
      expect(reprise.envoyes, 1);
      expect(reprise.dejaSurDrive, 4);
      expect(reprise.complet, isTrue);
    });

    test('une erreur inattendue d’un fichier est dite elle aussi, sans arrêter les autres', () async {
      remplir();
      drive.echecEnvoi = (String nom) => nom == 'piece_1.mp4' ? throw const FileSystemException('lecture impossible') : null;
      final RapportEnvoi rapport = (await service.envoyer()).rapport;
      expect(rapport.envoyes, 4);
      expect(rapport.erreurs.single.nom, 'piece_1.mp4');
      expect(rapport.erreurs.single.message, startsWith('Envoi impossible'));
    });

    test('trois échecs d’affilée arrêtent l’envoi : inutile d’insister', () async {
      for (int i = 1; i <= 6; i++) {
        ecrire(DossierDrive.photos, 'photo_$i.jpg', 'photo $i');
      }
      drive.echecEnvoi = (String nom) => const ErreurDrive('Google Drive est momentanément indisponible.');
      final ResultatEnvoi resultat = await service.envoyer();
      expect(resultat.rapport.erreurs, hasLength(ServiceDrive.echecsAvantArret));
      expect(resultat.rapport.envoyes, 0);
      expect(resultat.rapport.interrompu, isTrue);
      expect(resultat.arret, isNotNull);
    });

    test('un succès remet le compteur d’échecs à zéro', () async {
      for (final String lettre in <String>['a', 'b', 'c', 'd', 'e']) {
        ecrire(DossierDrive.photos, '$lettre.jpg', 'photo $lettre');
      }
      // a, b : échecs ; c : succès ; d, e : échecs → jamais trois d'affilée.
      drive.echecEnvoi = (String nom) => nom == 'c.jpg' ? null : const ErreurDrive('Trop lent.');
      final RapportEnvoi rapport = (await service.envoyer()).rapport;
      expect(rapport.envoyes, 1);
      expect(rapport.erreurs, hasLength(4));
      expect(rapport.interrompu, isFalse);
    });

    test('une autorisation expirée arrête tout de suite, en le disant', () async {
      for (final String lettre in <String>['a', 'b', 'c']) {
        ecrire(DossierDrive.photos, '$lettre.jpg', 'photo $lettre');
      }
      drive.echecEnvoi = (String nom) =>
          nom == 'b.jpg' ? const ErreurDrive('L’autorisation Google Drive a expiré.', autorisationAExpire: true) : null;
      final ResultatEnvoi resultat = await service.envoyer();
      expect(resultat.rapport.envoyes, 1); // a.jpg est parti
      expect(resultat.rapport.erreurs.single.nom, 'b.jpg');
      expect(resultat.rapport.interrompu, isTrue);
      expect(resultat.arret!.autorisationAExpire, isTrue);
      expect(drive.nomsDans('Photos des produits'), <String>['a.jpg']);
    });

    test('l’arrêt demandé a lieu à la fin du fichier en cours : jamais un fichier à moitié envoyé', () async {
      for (final String lettre in <String>['a', 'b', 'c']) {
        ecrire(DossierDrive.photos, '$lettre.jpg', 'photo $lettre');
      }
      final AnnulationEnvoi annulation = AnnulationEnvoi();
      drive.avantEnvoi = (String nom) {
        if (nom == 'b.jpg') annulation.demander();
      };
      final ResultatEnvoi resultat = await service.envoyer(annulation: annulation);
      expect(drive.nomsDans('Photos des produits'), <String>['a.jpg', 'b.jpg']); // b était commencé : il est allé au bout
      expect(resultat.rapport.envoyes, 2);
      expect(resultat.rapport.interrompu, isTrue);
      expect(resultat.rapport.erreurs, isEmpty);
      expect(resultat.rapport.complet, isFalse);
      expect(resultat.arret, isNull);

      // Reprise : seul c.jpg manque.
      final RapportEnvoi reprise = (await service.envoyer()).rapport;
      expect(reprise.envoyes, 1);
      expect(reprise.dejaSurDrive, 2);
    });

    test('si la préparation échoue (Google injoignable) : une erreur, rien ne part et l’ancien bilan reste', () async {
      remplir();
      await service.envoyer();
      final RapportEnvoi? avant = await service.dernierBilan();

      ecrire(DossierDrive.photos, 'photo_9.jpg', 'neuve');
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await expectLater(service.envoyer(), throwsA(isA<ErreurDrive>()));

      final RapportEnvoi? apres = await service.dernierBilan();
      expect(apres!.date, avant!.date);
      expect(apres.envoyes, 5);
    });

    test('la progression avance jusqu’au bout, fichier par fichier', () async {
      remplir();
      final List<ProgressionEnvoi> suite = <ProgressionEnvoi>[];
      await service.envoyer(progression: suite.add);
      expect(suite.first.fichiersTotal, 0); // préparation
      expect(suite.first.fichierEnCours, isNull);
      expect(suite.any((ProgressionEnvoi p) => p.fichierEnCours == 'FACT-2026-0001.pdf'), isTrue);
      expect(suite.map((ProgressionEnvoi p) => p.fichiersFaits), orderedEquals(suite.map((ProgressionEnvoi p) => p.fichiersFaits).toList()..sort()));
      final ProgressionEnvoi derniere = suite.last;
      expect(derniere.fichiersTotal, 5);
      expect(derniere.fichiersFaits, 5);
      expect(derniere.fraction, 1);
      expect(derniere.fichierEnCours, isNull);
    });

    test('un envoi sans rien à envoyer le dit : zéro fichier, tout est déjà sur Drive', () async {
      final ResultatEnvoi resultat = await service.envoyer();
      expect(resultat.rapport.envoyes, 0);
      expect(resultat.rapport.dejaSurDrive, 0);
      expect(resultat.rapport.complet, isTrue);
    });
  });

  group('dernier bilan', () {
    test('aucun avant le premier envoi', () async {
      expect(await service.dernierBilan(), isNull);
    });

    test('est gardé dans un fichier à part, relu à l’identique, sans fichier provisoire', () async {
      remplir();
      drive.echecEnvoi = (String nom) => nom == 'piece_1.mp4' ? const ErreurDrive('Votre Drive est plein.') : null;
      final RapportEnvoi rapport = (await service.envoyer()).rapport;
      expect(fichierBilan.existsSync(), isTrue);
      expect(File('${fichierBilan.path}.tmp').existsSync(), isFalse);

      // Un autre service (l'application relancée) retrouve le même bilan.
      final ServiceDrive relance = ServiceDrive(client: drive, dossiers: dossiers, fichierBilan: fichierBilan);
      final RapportEnvoi? relu = await relance.dernierBilan();
      expect(relu!.date, rapport.date);
      expect(relu.envoyes, 4);
      expect(relu.erreurs.single.nom, 'piece_1.mp4');
      expect(relu.erreurs.single.message, 'Votre Drive est plein.');
    });

    test('le nouvel envoi remplace le bilan précédent', () async {
      ecrire(DossierDrive.photos, 'p.jpg', 'photo');
      await service.envoyer();
      ecrire(DossierDrive.photos, 'q.jpg', 'autre');
      await service.envoyer();
      final RapportEnvoi? bilan = await service.dernierBilan();
      expect(bilan!.envoyes, 1);
      expect(bilan.dejaSurDrive, 1);
    });

    test('un fichier de bilan abîmé donne « aucun bilan », sans erreur', () async {
      fichierBilan.parent.createSync(recursive: true);
      fichierBilan.writeAsStringSync('{ pas du json');
      expect(await service.dernierBilan(), isNull);
      fichierBilan.writeAsStringSync('[1, 2, 3]');
      expect(await service.dernierBilan(), isNull);
    });

    test('ne pas pouvoir écrire le bilan ne casse pas l’envoi', () async {
      remplir();
      // Un fichier là où le service voudrait créer un dossier : l'écriture du bilan échoue.
      File('${racine.path}/drive').writeAsStringSync('je suis un fichier, pas un dossier');
      final ResultatEnvoi resultat = await service.envoyer();
      expect(resultat.rapport.envoyes, 5);
      expect(await service.dernierBilan(), isNull);
    });
  });
}
