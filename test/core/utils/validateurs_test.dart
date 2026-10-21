import 'package:crochet_creations/core/utils/validateurs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validerObligatoire', () {
    test('refuse vide et espaces', () {
      expect(validerObligatoire(null, 'Obligatoire.'), 'Obligatoire.');
      expect(validerObligatoire('   ', 'Obligatoire.'), 'Obligatoire.');
    });

    test('accepte un texte', () {
      expect(validerObligatoire(' Doudou ', 'Obligatoire.'), isNull);
    });
  });

  group('validerLongueurMax', () {
    test('limite la longueur', () {
      expect(validerLongueurMax('abc', 3, 'Le nom'), isNull);
      expect(validerLongueurMax('abcd', 3, 'Le nom'), 'Le nom est trop long (3 caractères maximum).');
      expect(validerLongueurMax(null, 3, 'Le nom'), isNull);
    });
  });

  group('montants', () {
    test('obligatoire', () {
      expect(validerMontantObligatoire('', 'Prix obligatoire.'), 'Prix obligatoire.');
      expect(validerMontantObligatoire('abc', 'Prix obligatoire.'), isNotNull);
      expect(validerMontantObligatoire('12,50', 'Prix obligatoire.'), isNull);
      expect(validerMontantObligatoire('0', 'Prix obligatoire.'), isNull);
    });

    test('facultatif', () {
      expect(validerMontantFacultatif(null), isNull);
      expect(validerMontantFacultatif('  '), isNull);
      expect(validerMontantFacultatif('4.2'), isNull);
      expect(validerMontantFacultatif('4,235'), isNotNull);
      expect(validerMontantFacultatif('-3'), isNotNull);
    });
  });

  group('validerEntier', () {
    test('vide accepté sauf si obligatoire', () {
      expect(validerEntier(''), isNull);
      expect(validerEntier('', obligatoire: true), isNotNull);
    });

    test('entiers positifs ou nuls seulement', () {
      expect(validerEntier('0'), isNull);
      expect(validerEntier('12'), isNull);
      expect(validerEntier('-1'), isNotNull);
      expect(validerEntier('1,5'), isNotNull);
      expect(validerEntier('abc'), isNotNull);
    });

    test('maximum', () {
      expect(validerEntier('59', max: 59), isNull);
      expect(validerEntier('60', max: 59), 'Valeur trop grande (maximum 59).');
    });
  });

  test('lireEntier', () {
    expect(lireEntier(' 7 '), 7);
    expect(lireEntier(''), isNull);
    expect(lireEntier(null), isNull);
    expect(lireEntier('x'), isNull);
  });
}
