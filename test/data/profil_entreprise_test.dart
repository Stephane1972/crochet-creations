import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/regles_entreprise.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late ParametresRepository parametres;

  setUp(() {
    db = creerBaseEnMemoire();
    parametres = ParametresRepository(db);
  });
  tearDown(() => db.close());

  const DonneesEntreprise complet = DonneesEntreprise(
    nomCommercial: 'Crochet & Créations',
    nomResponsable: 'Camille Martin',
    adresse: '12 rue des Lilas',
    codePostal: '31000',
    ville: 'Toulouse',
    telephone: '06 12 34 56 78',
    email: 'contact@exemple.fr',
    siren: '123 456 789',
    conditionsPaiement: 'Paiement sous 15 jours.',
    iban: 'fr1420041010050500013m02606',
    messageRemerciement: 'Merci et à bientôt !',
  );

  group('enregistrerProfil', () {
    test('enregistre tous les champs, SIREN sans espaces et IBAN mis en forme', () async {
      await parametres.enregistrerProfil(complet);

      final Entreprise e = await parametres.lire();
      expect(e.nomCommercial, 'Crochet & Créations');
      expect(e.nomResponsable, 'Camille Martin');
      expect(e.adresse, '12 rue des Lilas');
      expect(e.codePostal, '31000');
      expect(e.ville, 'Toulouse');
      expect(e.telephone, '06 12 34 56 78');
      expect(e.email, 'contact@exemple.fr');
      expect(e.siren, '123456789');
      expect(e.conditionsPaiement, 'Paiement sous 15 jours.');
      expect(e.iban, 'FR14 2004 1010 0505 0001 3M02 606');
      expect(e.messageRemerciement, 'Merci et à bientôt !');
    });

    test('un profil vide est accepté (il sera exigé au moment de facturer)', () async {
      await parametres.enregistrerProfil(const DonneesEntreprise());

      final Entreprise e = await parametres.lire();
      expect(e.nomCommercial, '');
      expect(e.adresse, isNull);
      expect(e.siren, isNull);
      expect(e.iban, isNull);
    });

    test('des conditions vides redonnent les conditions par défaut, un remerciement vide le supprime', () async {
      await parametres.enregistrerProfil(
        const DonneesEntreprise(conditionsPaiement: '   ', messageRemerciement: ' '),
      );

      final Entreprise e = await parametres.lire();
      expect(e.conditionsPaiement, conditionsPaiementParDefaut);
      expect(e.messageRemerciement, '');
    });

    test('les valeurs facultatives effacées reviennent à vide', () async {
      await parametres.enregistrerProfil(complet);
      await parametres.enregistrerProfil(const DonneesEntreprise(nomCommercial: 'Atelier'));

      final Entreprise e = await parametres.lire();
      expect(e.nomCommercial, 'Atelier');
      expect(e.telephone, isNull);
      expect(e.iban, isNull);
      expect(e.siren, isNull);
    });

    test('ne touche pas au mode jour / nuit', () async {
      await parametres.memoriser(ThemeMode.dark);
      await parametres.enregistrerProfil(complet);

      expect((await parametres.lire()).modeTheme, ModeTheme.nuit);
      expect(await parametres.lireModeTheme(), ThemeMode.dark);
    });

    test('refuse un SIREN, un IBAN, un e-mail, un téléphone ou un code postal incorrects', () async {
      const Map<String, DonneesEntreprise> refus = <String, DonneesEntreprise>{
        'SIREN': DonneesEntreprise(siren: '1234'),
        'IBAN': DonneesEntreprise(iban: 'FR14 2004 1010 0505 0001 3M02 607'),
        'e-mail': DonneesEntreprise(email: 'pas-un-email'),
        'téléphone': DonneesEntreprise(telephone: '12'),
        'code postal': DonneesEntreprise(codePostal: '!!'),
      };
      for (final MapEntry<String, DonneesEntreprise> cas in refus.entries) {
        await expectLater(
          parametres.enregistrerProfil(cas.value),
          throwsA(isA<DonneeInvalide>()),
          reason: cas.key,
        );
      }
    });

    test('refuse un texte trop long et ne change rien', () async {
      await parametres.enregistrerProfil(complet);

      await expectLater(
        parametres.enregistrerProfil(DonneesEntreprise(nomCommercial: 'A' * 101)),
        throwsA(
          isA<DonneeInvalide>().having(
            (DonneeInvalide e) => e.message,
            'message',
            'Le nom de l’entreprise ne peut pas dépasser 100 caractères.',
          ),
        ),
      );
      await expectLater(
        parametres.enregistrerProfil(DonneesEntreprise(conditionsPaiement: 'C' * 301)),
        throwsA(isA<DonneeInvalide>()),
      );
      expect((await parametres.lire()).nomCommercial, 'Crochet & Créations');
    });

    test('DonneesEntreprise.depuis reprend les valeurs enregistrées', () async {
      await parametres.enregistrerProfil(complet);

      final DonneesEntreprise relu = DonneesEntreprise.depuis(await parametres.lire());
      expect(relu.nomCommercial, 'Crochet & Créations');
      expect(relu.siren, '123456789');
      expect(relu.iban, 'FR14 2004 1010 0505 0001 3M02 606');
      expect(
        informationsManquantes(
          nomCommercial: relu.nomCommercial,
          adresse: relu.adresse,
          codePostal: relu.codePostal,
          ville: relu.ville,
          siren: relu.siren,
        ),
        isEmpty,
      );
    });
  });

  test('ProfilIncomplet : le message énumère ce qui manque', () {
    expect(
      ProfilIncomplet(<String>['l’adresse']).message,
      'Pour établir une facture, renseignez d’abord l’adresse dans « Mon entreprise ».',
    );
    expect(
      ProfilIncomplet(<String>['le nom de l’entreprise', 'l’adresse', 'le numéro SIREN']).message,
      'Pour établir une facture, renseignez d’abord le nom de l’entreprise, l’adresse et le numéro SIREN dans « Mon entreprise ».',
    );
  });
}
