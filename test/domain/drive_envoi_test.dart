import 'package:crochet_creations/data/drive/service_drive.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FichierLocal local(String nom, int octets, {String? empreinte}) =>
      FichierLocal(nom: nom, octets: octets, empreinte: empreinte);
  FichierDistant distant(String id, String nom, {int? octets, String? empreinte}) =>
      FichierDistant(id: id, nom: nom, octets: octets, empreinte: empreinte);

  group('dossiers envoyés', () {
    test('ce sont les quatre dossiers de fichiers de la sauvegarde, avec les mêmes noms', () {
      expect(<String>[for (final DossierDrive d in DossierDrive.values) d.nomLocal], <String>[
        FormatSauvegarde.dossierPhotos,
        FormatSauvegarde.dossierFactures,
        FormatSauvegarde.dossierDevis,
        FormatSauvegarde.dossierPiecesJointes,
      ]);
    });

    test('les noms sur Drive sont distincts ; seuls les PDF comparent le contenu', () {
      expect(<String>{for (final DossierDrive d in DossierDrive.values) d.nomDrive}, hasLength(4));
      expect(<bool>[for (final DossierDrive d in DossierDrive.values) d.compareContenu], <bool>[false, true, true, false]);
    });

    test('le droit demandé à Google est limité aux fichiers créés par l’application', () {
      expect(porteeDrive, 'https://www.googleapis.com/auth/drive.file');
    });
  });

  group('planifierEnvoi', () {
    test('un dossier Drive vide : tout est à créer, dans l’ordre des noms', () {
      final PlanDossier plan = planifierEnvoi(
        dossier: DossierDrive.photos,
        locaux: <FichierLocal>[local('b.jpg', 20), local('a.jpg', 10)],
        distants: const <FichierDistant>[],
      );
      expect(plan.nombreLocaux, 2);
      expect(plan.dejaSurDrive, 0);
      expect(plan.aEnvoyer.map((EnvoiPrevu e) => e.fichier.nom), <String>['a.jpg', 'b.jpg']);
      expect(plan.aEnvoyer.every((EnvoiPrevu e) => e.action == ActionEnvoi.creer && e.idDistant == null), isTrue);
      expect(plan.octetsAEnvoyer, 30);
    });

    test('photos et pièces jointes : même nom et même taille = déjà sur Drive (pas d’empreinte à lire)', () {
      for (final DossierDrive dossier in <DossierDrive>[DossierDrive.photos, DossierDrive.notes]) {
        final PlanDossier plan = planifierEnvoi(
          dossier: dossier,
          locaux: <FichierLocal>[local('a.jpg', 10), local('b.jpg', 20)],
          distants: <FichierDistant>[distant('1', 'a.jpg', octets: 10)],
        );
        expect(plan.dejaSurDrive, 1, reason: dossier.name);
        expect(plan.aEnvoyer.map((EnvoiPrevu e) => e.fichier.nom), <String>['b.jpg']);
      }
    });

    test('même nom mais autre taille : à mettre à jour, sur le fichier Drive existant', () {
      final PlanDossier plan = planifierEnvoi(
        dossier: DossierDrive.photos,
        locaux: <FichierLocal>[local('a.jpg', 12)],
        distants: <FichierDistant>[distant('id-a', 'a.jpg', octets: 10)],
      );
      expect(plan.dejaSurDrive, 0);
      expect(plan.aEnvoyer.single.action, ActionEnvoi.mettreAJour);
      expect(plan.aEnvoyer.single.idDistant, 'id-a');
    });

    test('un fichier de Drive de taille inconnue n’est pas pris pour identique', () {
      final PlanDossier plan = planifierEnvoi(
        dossier: DossierDrive.photos,
        locaux: <FichierLocal>[local('a.jpg', 10)],
        distants: <FichierDistant>[distant('id-a', 'a.jpg')],
      );
      expect(plan.aEnvoyer.single.action, ActionEnvoi.mettreAJour);
    });

    test('PDF : même nom et même taille mais autre empreinte = régénéré, à mettre à jour', () {
      for (final DossierDrive dossier in <DossierDrive>[DossierDrive.factures, DossierDrive.devis]) {
        final PlanDossier plan = planifierEnvoi(
          dossier: dossier,
          locaux: <FichierLocal>[
            local('FACT-2026-0001.pdf', 100, empreinte: 'aaa'),
            local('FACT-2026-0002.pdf', 100, empreinte: 'bbb'),
          ],
          distants: <FichierDistant>[
            distant('1', 'FACT-2026-0001.pdf', octets: 100, empreinte: 'aaa'),
            distant('2', 'FACT-2026-0002.pdf', octets: 100, empreinte: 'zzz'),
          ],
        );
        expect(plan.dejaSurDrive, 1, reason: dossier.name);
        expect(plan.aEnvoyer.single.fichier.nom, 'FACT-2026-0002.pdf');
        expect(plan.aEnvoyer.single.action, ActionEnvoi.mettreAJour);
        expect(plan.aEnvoyer.single.idDistant, '2');
      }
    });

    test('PDF : un fichier Drive sans empreinte (mis là à la main) est remplacé plutôt que cru identique', () {
      final PlanDossier plan = planifierEnvoi(
        dossier: DossierDrive.factures,
        locaux: <FichierLocal>[local('F.pdf', 100, empreinte: 'aaa')],
        distants: <FichierDistant>[distant('1', 'F.pdf', octets: 100)],
      );
      expect(plan.aEnvoyer.single.action, ActionEnvoi.mettreAJour);
    });

    test('plusieurs fichiers Drive de même nom : le fichier identique est préféré, sinon le premier est mis à jour', () {
      final PlanDossier identique = planifierEnvoi(
        dossier: DossierDrive.photos,
        locaux: <FichierLocal>[local('a.jpg', 10)],
        distants: <FichierDistant>[distant('1', 'a.jpg', octets: 5), distant('2', 'a.jpg', octets: 10)],
      );
      expect(identique.dejaSurDrive, 1);
      expect(identique.aEnvoyer, isEmpty);

      final PlanDossier aucun = planifierEnvoi(
        dossier: DossierDrive.photos,
        locaux: <FichierLocal>[local('a.jpg', 10)],
        distants: <FichierDistant>[distant('1', 'a.jpg', octets: 5), distant('2', 'a.jpg', octets: 6)],
      );
      expect(aucun.aEnvoyer.single.idDistant, '1');
    });

    test('un fichier de Drive absent du téléphone est ignoré : jamais de suppression', () {
      final PlanDossier plan = planifierEnvoi(
        dossier: DossierDrive.photos,
        locaux: <FichierLocal>[local('a.jpg', 10)],
        distants: <FichierDistant>[distant('1', 'a.jpg', octets: 10), distant('2', 'ancienne.jpg', octets: 99)],
      );
      expect(plan.dejaSurDrive, 1);
      expect(plan.aEnvoyer, isEmpty);
      expect(plan.nombreLocaux, 1);
    });

    test('rien sur le téléphone : rien à faire', () {
      final PlanDossier plan = planifierEnvoi(
        dossier: DossierDrive.devis,
        locaux: const <FichierLocal>[],
        distants: <FichierDistant>[distant('1', 'x.pdf', octets: 1)],
      );
      expect(plan.nombreLocaux, 0);
      expect(plan.aEnvoyer, isEmpty);
      expect(plan.octetsAEnvoyer, 0);
    });
  });

  group('bilan d’un envoi', () {
    final DateTime date = DateTime(2026, 11, 13, 11, 29, 5);

    test('complet : aucune erreur et allé jusqu’au bout', () {
      expect(RapportEnvoi(date: date, envoyes: 3).complet, isTrue);
      expect(RapportEnvoi(date: date, interrompu: true).complet, isFalse);
      expect(
        RapportEnvoi(
          date: date,
          erreurs: const <ErreurEnvoi>[ErreurEnvoi(dossier: DossierDrive.photos, nom: 'a.jpg', message: 'x')],
        ).complet,
        isFalse,
      );
    });

    test('s’enregistre et se relit à l’identique', () {
      final RapportEnvoi rapport = RapportEnvoi(
        date: date,
        envoyes: 7,
        dejaSurDrive: 12,
        octetsEnvoyes: 123456,
        interrompu: true,
        erreurs: const <ErreurEnvoi>[
          ErreurEnvoi(dossier: DossierDrive.notes, nom: 'video.mp4', message: 'Pas de connexion à Internet.'),
          ErreurEnvoi(dossier: DossierDrive.factures, nom: 'F.pdf', message: 'Google demande de ralentir.'),
        ],
      );
      final RapportEnvoi? relu = RapportEnvoi.depuisJson(rapport.versJson());
      expect(relu, isNotNull);
      expect(relu!.date, date);
      expect(relu.envoyes, 7);
      expect(relu.dejaSurDrive, 12);
      expect(relu.octetsEnvoyes, 123456);
      expect(relu.interrompu, isTrue);
      expect(relu.erreurs.map((ErreurEnvoi e) => (e.dossier, e.nom, e.message)), <(DossierDrive, String, String)>[
        (DossierDrive.notes, 'video.mp4', 'Pas de connexion à Internet.'),
        (DossierDrive.factures, 'F.pdf', 'Google demande de ralentir.'),
      ]);
    });

    test('un bilan illisible ou incomplet donne « aucun bilan », jamais une erreur', () {
      expect(RapportEnvoi.depuisJson(null), isNull);
      expect(RapportEnvoi.depuisJson('texte'), isNull);
      expect(RapportEnvoi.depuisJson(<String, Object?>{}), isNull);
      final Map<String, Object?> bon = RapportEnvoi(date: date).versJson();
      expect(RapportEnvoi.depuisJson(<String, Object?>{...bon, 'date': 'pas une date'}), isNull);
      expect(RapportEnvoi.depuisJson(<String, Object?>{...bon, 'envoyes': 'sept'}), isNull);
      expect(RapportEnvoi.depuisJson(<String, Object?>{...bon, 'erreurs': 'aucune'}), isNull);
    });

    test('une erreur enregistrée sur un dossier inconnu est ignorée, les autres restent', () {
      final Map<String, Object?> json = RapportEnvoi(date: date).versJson();
      json['erreurs'] = <Object?>[
        <String, Object?>{'dossier': 'inconnu', 'nom': 'a', 'message': 'm'},
        <String, Object?>{'dossier': 'devis', 'nom': 'D.pdf', 'message': 'm'},
        'pas une erreur',
      ];
      final RapportEnvoi? relu = RapportEnvoi.depuisJson(json);
      expect(relu!.erreurs.map((ErreurEnvoi e) => e.nom), <String>['D.pdf']);
    });
  });

  group('progression', () {
    test('la fraction suit les octets, sinon les fichiers, et reste entre 0 et 1', () {
      expect(const ProgressionEnvoi.preparation().fraction, 0);
      expect(const ProgressionEnvoi(octetsFaits: 25, octetsTotal: 100, fichiersFaits: 1, fichiersTotal: 2).fraction, 0.25);
      expect(const ProgressionEnvoi(fichiersFaits: 1, fichiersTotal: 4).fraction, 0.25);
      expect(const ProgressionEnvoi(octetsFaits: 500, octetsTotal: 100).fraction, 1);
    });
  });
}
