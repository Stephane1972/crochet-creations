import 'package:crochet_creations/domain/regles_entreprise.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verifierSiren', () {
    test('un champ vide est accepté (le SIREN est vérifié au moment de facturer)', () {
      expect(verifierSiren(null), isNull);
      expect(verifierSiren(''), isNull);
      expect(verifierSiren('   '), isNull);
    });

    test('9 chiffres, avec ou sans espaces', () {
      expect(verifierSiren('123456789'), isNull);
      expect(verifierSiren(' 123 456 789 '), isNull);
    });

    test('un SIRET (14 chiffres) est refusé avec une explication', () {
      expect(verifierSiren('12345678900012'), contains('SIRET'));
      expect(verifierSiren('123 456 789 00012'), contains('9 premiers'));
    });

    test('trop court, trop long ou avec des lettres', () {
      expect(verifierSiren('12345678'), 'Le SIREN comporte 9 chiffres.');
      expect(verifierSiren('1234567890'), 'Le SIREN comporte 9 chiffres.');
      expect(verifierSiren('12345678A'), 'Le SIREN ne contient que des chiffres.');
    });

    test('normaliserSiren retire les espaces et les points', () {
      expect(normaliserSiren('123 456.789'), '123456789');
    });
  });

  group('verifierIban', () {
    test('un champ vide est accepté (l’IBAN est facultatif)', () {
      expect(verifierIban(null), isNull);
      expect(verifierIban(''), isNull);
      expect(verifierIban('  '), isNull);
    });

    test('des IBAN valides, avec ou sans espaces, en majuscules ou non', () {
      expect(verifierIban('FR14 2004 1010 0505 0001 3M02 606'), isNull);
      expect(verifierIban('fr1420041010050500013m02606'), isNull);
      expect(verifierIban('FR76 3000 6000 0112 3456 7890 189'), isNull);
      expect(verifierIban('GB82 WEST 1234 5698 7654 32'), isNull);
      expect(verifierIban('DE89 3704 0044 0532 0130 00'), isNull);
    });

    test('une clé de contrôle fausse est refusée', () {
      expect(verifierIban('FR14 2004 1010 0505 0001 3M02 607'), 'IBAN incorrect : vérifiez les chiffres et les lettres.');
      expect(verifierIban('FR15 2004 1010 0505 0001 3M02 606'), isNotNull);
    });

    test('une forme impossible est refusée', () {
      expect(verifierIban('12345678'), isNotNull);
      expect(verifierIban('FR14'), isNotNull);
      expect(verifierIban('FR14 2004 1010 0505 0001 3M02 606 99999999999999999999'), isNotNull);
      expect(verifierIban('FR14-2004-1010'), isNotNull);
    });

    test('formaterIban : majuscules et groupes de 4', () {
      expect(formaterIban('fr1420041010050500013m02606'), 'FR14 2004 1010 0505 0001 3M02 606');
      expect(formaterIban('FR14 2004 1010 0505 0001 3M02 606'), 'FR14 2004 1010 0505 0001 3M02 606');
      expect(formaterIban('GB82 WEST 1234 5698 7654 32'), 'GB82 WEST 1234 5698 7654 32');
      expect(formaterIban('FR14'), 'FR14');
      expect(formaterIban(''), '');
    });
  });

  group('informationsManquantes', () {
    test('un profil complet n’a rien à ajouter', () {
      expect(
        informationsManquantes(
          nomCommercial: 'Crochet & Créations',
          adresse: '12 rue des Lilas',
          codePostal: '31000',
          ville: 'Toulouse',
          siren: '123 456 789',
        ),
        isEmpty,
      );
    });

    test('le nom de la personne suffit si l’entreprise n’a pas de nom commercial', () {
      expect(
        informationsManquantes(
          nomResponsable: 'Camille Martin',
          adresse: '12 rue des Lilas',
          codePostal: '31000',
          ville: 'Toulouse',
          siren: '123456789',
        ),
        isEmpty,
      );
    });

    test('un profil vide manque de tout, dans l’ordre d’une facture', () {
      expect(informationsManquantes(), <String>[
        'le nom de l’entreprise',
        'l’adresse',
        'le code postal et la ville',
        'le numéro SIREN',
      ]);
    });

    test('des espaces seuls comptent pour vide', () {
      expect(
        informationsManquantes(nomCommercial: '  ', adresse: ' ', codePostal: ' ', ville: ' ', siren: ' '),
        hasLength(4),
      );
    });

    test('le code postal ET la ville sont nécessaires', () {
      expect(
        informationsManquantes(
          nomCommercial: 'Atelier',
          adresse: '1 rue',
          codePostal: '31000',
          siren: '123456789',
        ),
        <String>['le code postal et la ville'],
      );
      expect(
        informationsManquantes(
          nomCommercial: 'Atelier',
          adresse: '1 rue',
          ville: 'Toulouse',
          siren: '123456789',
        ),
        <String>['le code postal et la ville'],
      );
    });

    test('un SIREN mal formé est signalé', () {
      expect(
        informationsManquantes(
          nomCommercial: 'Atelier',
          adresse: '1 rue',
          codePostal: '31000',
          ville: 'Toulouse',
          siren: '12345',
        ),
        <String>['un numéro SIREN valide (9 chiffres)'],
      );
    });
  });
}
