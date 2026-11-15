import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nom d’une sauvegarde Drive', () {
    test('la date est écrite dans le nom, à la seconde', () {
      expect(nomSauvegardeDrive(DateTime(2026, 11, 14, 18, 30, 5)), 'crochet-creations-sauvegarde-2026-11-14-183005.zip');
      expect(nomSauvegardeDrive(DateTime(2026, 1, 2, 3, 4, 5)), 'crochet-creations-sauvegarde-2026-01-02-030405.zip');
    });

    test('on retrouve la date depuis le nom', () {
      final DateTime date = DateTime(2026, 11, 14, 18, 30, 5);
      expect(dateDeNomSauvegardeDrive(nomSauvegardeDrive(date)), date);
    });

    test('un autre nom n’est pas une sauvegarde', () {
      expect(dateDeNomSauvegardeDrive('photo_1.jpg'), isNull);
      expect(dateDeNomSauvegardeDrive('crochet-creations-manuelle-2026-10-31-134912.zip'), isNull);
      expect(dateDeNomSauvegardeDrive('crochet-creations-sauvegarde-2026-11-14-183005.zip.tmp'), isNull);
      expect(dateDeNomSauvegardeDrive('crochet-creations-sauvegarde-2026-11-14.zip'), isNull);
    });

    test('une date impossible est refusée, pas ramenée au mois suivant', () {
      expect(dateDeNomSauvegardeDrive('crochet-creations-sauvegarde-2026-13-45-250000.zip'), isNull);
      expect(dateDeNomSauvegardeDrive('crochet-creations-sauvegarde-2026-02-30-120000.zip'), isNull);
      expect(dateDeNomSauvegardeDrive('crochet-creations-sauvegarde-2026-11-14-246000.zip'), isNull);
    });

    test('le dossier des sauvegardes est distinct des quatre dossiers de fichiers', () {
      expect(<String>[for (final DossierDrive d in DossierDrive.values) d.nomDrive], isNot(contains(nomDossierSauvegardesDrive)));
    });
  });

  group('sauvegardesDrive', () {
    FichierDistant fichier(String id, String nom, {int? octets, String? empreinte}) =>
        FichierDistant(id: id, nom: nom, octets: octets, empreinte: empreinte);

    test('les plus récentes d’abord, les fichiers étrangers sont ignorés', () {
      final List<SauvegardeDrive> liste = sauvegardesDrive(<FichierDistant>[
        fichier('1', 'crochet-creations-sauvegarde-2026-11-10-080000.zip', octets: 100, empreinte: 'aaa'),
        fichier('2', 'notes-a-moi.txt'),
        fichier('3', 'crochet-creations-sauvegarde-2026-11-14-183005.zip', octets: 300),
        fichier('4', 'crochet-creations-sauvegarde-2026-11-12-120000.zip'),
      ]);
      expect(liste.map((SauvegardeDrive s) => s.id), <String>['3', '4', '1']);
      expect(liste.first.date, DateTime(2026, 11, 14, 18, 30, 5));
      expect(liste.last.octets, 100);
      expect(liste.last.empreinte, 'aaa');
    });

    test('aucun fichier : liste vide', () {
      expect(sauvegardesDrive(const <FichierDistant>[]), isEmpty);
    });
  });

  group('état des sauvegardes Drive', () {
    test('au départ, l’envoi automatique est désactivé et rien n’est enregistré', () {
      const EtatSauvegardesDrive etat = EtatSauvegardesDrive();
      expect(etat.envoiAutomatique, isFalse);
      expect(etat.derniere, isNull);
      expect(etat.derniereVerification, isNull);
      expect(etat.fichiersNonEnvoyes, isEmpty);
    });

    test('s’enregistre en JSON et se relit à l’identique', () {
      final EtatSauvegardesDrive etat = EtatSauvegardesDrive(
        envoiAutomatique: true,
        derniereVerification: DateTime(2026, 11, 14, 18, 31),
        derniere: BilanSauvegardeDrive(
          date: DateTime(2026, 11, 14, 18, 30, 5),
          nom: 'crochet-creations-sauvegarde-2026-11-14-183005.zip',
          octets: 4096,
          fichiers: 12,
        ),
        fichiersNonEnvoyes: const <String>['photos_produits/photo_2.jpg'],
      );
      final EtatSauvegardesDrive relu = EtatSauvegardesDrive.depuisJson(etat.versJson());
      expect(relu.envoiAutomatique, isTrue);
      expect(relu.derniereVerification, DateTime(2026, 11, 14, 18, 31));
      expect(relu.derniere!.nom, 'crochet-creations-sauvegarde-2026-11-14-183005.zip');
      expect(relu.derniere!.date, DateTime(2026, 11, 14, 18, 30, 5));
      expect(relu.derniere!.octets, 4096);
      expect(relu.derniere!.fichiers, 12);
      expect(relu.fichiersNonEnvoyes, <String>['photos_produits/photo_2.jpg']);
    });

    test('un contenu illisible redonne les valeurs de départ, sans erreur', () {
      for (final Object? json in <Object?>[null, 'texte', 42, <Object?>[], <String, Object?>{'envoiAutomatique': 'oui'}]) {
        final EtatSauvegardesDrive etat = EtatSauvegardesDrive.depuisJson(json);
        expect(etat.envoiAutomatique, isFalse, reason: '$json');
        expect(etat.derniere, isNull, reason: '$json');
      }
      final EtatSauvegardesDrive partiel = EtatSauvegardesDrive.depuisJson(<String, Object?>{
        'envoiAutomatique': true,
        'derniereVerification': 'pas une date',
        'derniere': <String, Object?>{'nom': 'sans date'},
        'fichiersNonEnvoyes': <Object?>['a', 3, 'b'],
      });
      expect(partiel.envoiAutomatique, isTrue);
      expect(partiel.derniereVerification, isNull);
      expect(partiel.derniere, isNull);
      expect(partiel.fichiersNonEnvoyes, <String>['a', 'b']);
    });

    test('copier ne change que ce qui est donné', () {
      final EtatSauvegardesDrive etat = const EtatSauvegardesDrive().copier(envoiAutomatique: true);
      final EtatSauvegardesDrive suite = etat.copier(derniereVerification: DateTime(2026, 11, 14));
      expect(suite.envoiAutomatique, isTrue);
      expect(suite.derniereVerification, DateTime(2026, 11, 14));
    });
  });

  group('envoiAutomatiqueDu', () {
    final DateTime maintenant = DateTime(2026, 11, 14, 18, 30);

    test('jamais quand l’envoi automatique est désactivé', () {
      expect(envoiAutomatiqueDu(const EtatSauvegardesDrive(), maintenant), isFalse);
      expect(
        envoiAutomatiqueDu(EtatSauvegardesDrive(derniereVerification: maintenant.subtract(const Duration(days: 30))), maintenant),
        isFalse,
      );
    });

    test('oui s’il est activé et qu’il n’est jamais passé', () {
      expect(envoiAutomatiqueDu(const EtatSauvegardesDrive(envoiAutomatique: true), maintenant), isTrue);
    });

    test('pas avant un jour', () {
      EtatSauvegardesDrive passe(Duration il) =>
          EtatSauvegardesDrive(envoiAutomatique: true, derniereVerification: maintenant.subtract(il));
      expect(envoiAutomatiqueDu(passe(const Duration(hours: 23, minutes: 59)), maintenant), isFalse);
      expect(envoiAutomatiqueDu(passe(const Duration(days: 1)), maintenant), isTrue);
      expect(envoiAutomatiqueDu(passe(const Duration(days: 9)), maintenant), isTrue);
    });

    test('une horloge revenue en arrière ne bloque pas l’envoi', () {
      final EtatSauvegardesDrive etat = EtatSauvegardesDrive(
        envoiAutomatique: true,
        derniereVerification: maintenant.add(const Duration(days: 3)),
      );
      expect(envoiAutomatiqueDu(etat, maintenant), isTrue);
    });
  });
}
