import 'dart:io';

import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/service_partages_drive.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_partage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_drive.dart';

void main() {
  late FauxClientDrive drive;
  late ServicePartagesDrive service;
  late Directory temp;

  setUp(() {
    drive = FauxClientDrive();
    service = ServicePartagesDrive(client: drive);
    temp = Directory.systemTemp.createTempSync('crochet_partages_');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  /// Pose un fichier dans un sous-dossier du dossier principal (créé au besoin) et retourne son identifiant Drive.
  Future<String> poser(String dossier, String nom, {String contenu = 'x'}) async {
    final String racine = await drive.trouverDossier(nomDossierRacineDrive) ?? await drive.creerDossier(nomDossierRacineDrive);
    final String sous = await drive.trouverDossier(dossier, parentId: racine) ?? await drive.creerDossier(dossier, parentId: racine);
    final File local = File('${temp.path}/$nom')..writeAsStringSync(contenu);
    await drive.envoyer(fichier: local, nom: nom, dossierId: sous);
    return drive.fichiers.values.firstWhere((FichierDriveFaux f) => f.nom == nom && f.dossierId == sous).id;
  }

  group('lister', () {
    test('sans dossier sur Drive : trois rubriques vides, et rien n’est créé', () async {
      final FichiersPartageables liste = await service.lister();
      expect(liste.keys, RubriquePartage.values);
      for (final List<FichierDistant> fichiers in liste.values) {
        expect(fichiers, isEmpty);
      }
      expect(drive.dossiersCrees, 0);
    });

    test('les fichiers de chaque rubrique, les plus récemment nommés d’abord, avec l’indice « partagé »', () async {
      await poser('Factures', 'FACT-2026-0001.pdf');
      final String deuxieme = await poser('Factures', 'FACT-2026-0002.pdf');
      await poser('Devis', 'DEVIS-2026-0001.pdf');
      await service.partagerAvec(deuxieme, 'marie@exemple.fr');

      final FichiersPartageables liste = await service.lister();
      expect(liste[RubriquePartage.factures]!.map((FichierDistant f) => f.nom), <String>['FACT-2026-0002.pdf', 'FACT-2026-0001.pdf']);
      expect(liste[RubriquePartage.factures]!.map((FichierDistant f) => f.partage), <bool>[true, false]);
      expect(liste[RubriquePartage.devis]!.single.nom, 'DEVIS-2026-0001.pdf');
      expect(liste[RubriquePartage.exports], isEmpty);
    });

    test('les sauvegardes, les photos et les pièces jointes ne sont jamais proposées', () async {
      await poser('Sauvegardes', 'sauvegarde-2026-11-16.zip');
      await poser('Photos des produits', 'photo_1.jpg');
      await poser('Notes - pièces jointes', 'piece_1.mp4');
      await poser('Factures', 'FACT-2026-0001.pdf');

      final FichiersPartageables liste = await service.lister();
      final List<String> noms = <String>[
        for (final List<FichierDistant> fichiers in liste.values) ...fichiers.map((FichierDistant f) => f.nom),
      ];
      expect(noms, <String>['FACT-2026-0001.pdf']);
    });

    test('une panne de connexion est dite en clair', () async {
      drive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await expectLater(service.lister(), throwsA(isA<ErreurDrive>()));
    });
  });

  group('acces', () {
    test('un fichier neuf est privé : seul le propriétaire y a accès', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      final AccesFichier acces = await service.acces(id);
      expect(acces.estPrive, isTrue);
      expect(acces.proprietaire?.email, 'stef@exemple.fr');
    });

    test('le lien du fichier est donné par Drive', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      expect(await service.lien(id), 'https://drive.exemple.fr/fichier/$id');
    });
  });

  group('partagerAvec', () {
    test('partage en lecture avec l’adresse, nettoyée, et rend les accès à jour', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      final AccesFichier acces = await service.partagerAvec(id, '  Marie@Exemple.FR ', emailProprietaire: 'stef@exemple.fr');

      expect(drive.partagesDemandes, <String>['FACT-2026-0001.pdf | marie@exemple.fr']);
      expect(acces.personnes.map((AccesDrive a) => a.email), <String?>['marie@exemple.fr']);
      expect(acces.estPrive, isFalse);
    });

    test('adresse mal écrite, vide, la sienne ou déjà partagée : refus clair, sans appel à Google', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      await service.partagerAvec(id, 'marie@exemple.fr');
      drive.partagesDemandes.clear();

      for (final String saisie in <String>['marie', '   ', 'stef@exemple.fr', 'MARIE@exemple.fr']) {
        await expectLater(
          service.partagerAvec(id, saisie, emailProprietaire: 'stef@exemple.fr'),
          throwsA(isA<ErreurDrive>()),
          reason: saisie,
        );
      }
      expect(drive.partagesDemandes, isEmpty);
    });

    test('une adresse que Google refuse : l’erreur de Google est transmise, rien n’est partagé', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      drive.adressesRefusees.add('inconnue@exemple.fr');
      await expectLater(
        service.partagerAvec(id, 'inconnue@exemple.fr'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('n’a pas accepté'))),
      );
      expect((await service.acces(id)).estPrive, isTrue);
    });
  });

  group('activerLien', () {
    test('active le lien public et rend l’adresse du fichier', () async {
      final String id = await poser('Devis', 'DEVIS-2026-0001.pdf');
      final String? lien = await service.activerLien(id);
      expect(lien, 'https://drive.exemple.fr/fichier/$id');
      expect(drive.liensActives, <String>['DEVIS-2026-0001.pdf']);
      expect((await service.acces(id)).lienPublic, isNotNull);
    });

    test('un lien déjà actif n’est pas créé une seconde fois', () async {
      final String id = await poser('Devis', 'DEVIS-2026-0001.pdf');
      await service.activerLien(id);
      await service.activerLien(id);
      expect(drive.liensActives, hasLength(1));
    });
  });

  group('retirer', () {
    test('retire une personne ; le fichier reste sur Drive', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      final AccesFichier avant = await service.partagerAvec(id, 'marie@exemple.fr');
      final int fichiers = drive.fichiers.length;

      final AccesFichier apres = await service.retirer(id, avant.personnes.single);

      expect(apres.estPrive, isTrue);
      expect(drive.accesRetires, <String>['FACT-2026-0001.pdf | marie@exemple.fr']);
      expect(drive.fichiers.length, fichiers);
      expect(drive.fichiers[id], isNotNull);
    });

    test('arrête le lien public', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      await service.activerLien(id);
      final AccesFichier acces = await service.acces(id);
      final AccesFichier apres = await service.retirer(id, acces.lienPublic!);
      expect(apres.lienPublic, isNull);
      expect(apres.estPrive, isTrue);
    });

    test('le propriétaire ne se retire pas', () async {
      final String id = await poser('Factures', 'FACT-2026-0001.pdf');
      final AccesFichier acces = await service.acces(id);
      await expectLater(service.retirer(id, acces.proprietaire!), throwsA(isA<ErreurDrive>()));
      expect(drive.accesRetires, isEmpty);
    });
  });

  group('envoyerExport', () {
    test('crée les dossiers « Exports » au besoin et y envoie l’archive', () async {
      final File archive = File('${temp.path}/crochet-creations-catalogue-2026-11-16.zip')..writeAsStringSync('zip');
      final bool remplace = await service.envoyerExport(archive);

      expect(remplace, isFalse);
      expect(drive.nomsDans(nomDossierExportsDrive), <String>['crochet-creations-catalogue-2026-11-16.zip']);
      final FichiersPartageables liste = await service.lister();
      expect(liste[RubriquePartage.exports]!.single.nom, 'crochet-creations-catalogue-2026-11-16.zip');
    });

    test('le même jour, l’archive remplace la précédente (un seul fichier, ses accès restent)', () async {
      final File archive = File('${temp.path}/catalogue.zip')..writeAsStringSync('premier');
      await service.envoyerExport(archive);
      final String id = (await service.lister())[RubriquePartage.exports]!.single.id;
      await service.partagerAvec(id, 'marie@exemple.fr');

      archive.writeAsStringSync('second');
      final bool remplace = await service.envoyerExport(archive);

      expect(remplace, isTrue);
      expect(drive.nomsDans(nomDossierExportsDrive), <String>['catalogue.zip']);
      expect(drive.fichiers[id]!.versions, 2);
      expect((await service.acces(id)).personnes, hasLength(1));
    });

    test('un autre jour, un nouveau fichier s’ajoute et l’ancien reste', () async {
      await service.envoyerExport(File('${temp.path}/catalogue-1.zip')..writeAsStringSync('a'));
      await service.envoyerExport(File('${temp.path}/catalogue-2.zip')..writeAsStringSync('b'));
      expect(drive.nomsDans(nomDossierExportsDrive), <String>['catalogue-1.zip', 'catalogue-2.zip']);
    });
  });
}
