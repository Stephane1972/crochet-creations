import 'package:crochet_creations/domain/regles_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verifierEmail', () {
    test('un champ vide est accepté (l’e-mail est facultatif)', () {
      expect(verifierEmail(null), isNull);
      expect(verifierEmail(''), isNull);
      expect(verifierEmail('   '), isNull);
    });

    test('les adresses correctes sont acceptées', () {
      expect(verifierEmail('camille@exemple.fr'), isNull);
      expect(verifierEmail(' prenom.nom+crochet@sous.domaine.co '), isNull);
    });

    test('les adresses incorrectes sont refusées avec un message en français', () {
      const String message = 'L’adresse e-mail n’est pas valide.';
      for (final String adresse in <String>[
        'camille',
        'camille@',
        '@exemple.fr',
        'camille@exemple',
        'cam ille@exemple.fr',
        'camille@@exemple.fr',
        'camille@exemple.',
      ]) {
        expect(verifierEmail(adresse), message, reason: adresse);
      }
    });
  });

  group('verifierTelephone', () {
    test('un champ vide est accepté', () {
      expect(verifierTelephone(null), isNull);
      expect(verifierTelephone('  '), isNull);
    });

    test('les écritures usuelles sont acceptées', () {
      for (final String numero in <String>[
        '06 12 34 56 78',
        '0612345678',
        '+33 6 12 34 56 78',
        '(05) 61.23.45.67',
        '06-12-34-56-78',
        '123456', // 6 chiffres : le minimum
        '123456789012345', // 15 chiffres : le maximum
      ]) {
        expect(verifierTelephone(numero), isNull, reason: numero);
      }
    });

    test('les lettres, les numéros trop courts ou trop longs sont refusés', () {
      const String message = 'Le numéro de téléphone n’est pas valide.';
      for (final String numero in <String>[
        'abc',
        '12345', // 5 chiffres
        '1234567890123456', // 16 chiffres
        '06 12 34 56 7a',
        '06 12 34 56 78 #',
      ]) {
        expect(verifierTelephone(numero), message, reason: numero);
      }
    });
  });

  group('verifierCodePostal', () {
    test('un champ vide est accepté', () {
      expect(verifierCodePostal(null), isNull);
      expect(verifierCodePostal(''), isNull);
    });

    test('les codes postaux français et étrangers courants sont acceptés', () {
      for (final String code in <String>['31000', ' 31000 ', '1000', 'B-1000', 'SW1A 1AA', '75 001']) {
        expect(verifierCodePostal(code), isNull, reason: code);
      }
    });

    test('trop court, trop long ou avec des signes inattendus : refusé', () {
      const String message = 'Le code postal n’est pas valide.';
      for (final String code in <String>['12', '12345678901', '31 000!', '3100-', '-3100']) {
        expect(verifierCodePostal(code), message, reason: code);
      }
    });
  });

  group('verifierSiret', () {
    test('un champ vide est accepté', () {
      expect(verifierSiret(null), isNull);
      expect(verifierSiret(' '), isNull);
    });

    test('un SIREN (9 chiffres) ou un SIRET (14 chiffres) est accepté, avec ou sans espaces', () {
      for (final String numero in <String>[
        '123456789',
        '123 456 789',
        '123.456.789',
        '12345678901234',
        '123 456 789 00012',
      ]) {
        expect(verifierSiret(numero), isNull, reason: numero);
      }
    });

    test('un autre nombre de chiffres, ou des lettres : refusé', () {
      const String message = 'Le SIREN (9 chiffres) ou le SIRET (14 chiffres) n’est pas valide.';
      for (final String numero in <String>[
        '12345678', // 8
        '1234567890', // 10
        '123456789012345', // 15
        'ABC123456789',
        '123 456 78X',
      ]) {
        expect(verifierSiret(numero), message, reason: numero);
      }
    });
  });
}
