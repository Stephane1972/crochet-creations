import 'package:crochet_creations/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatEuros', () {
    test('zéro', () {
      expect(formatEuros(0), '0,00 €');
    });

    test('centimes sur deux chiffres', () {
      expect(formatEuros(5), '0,05 €');
      expect(formatEuros(250), '2,50 €');
    });

    test('séparateur de milliers insécable', () {
      expect(formatEuros(123456), '1 234,56 €');
      expect(formatEuros(100000000), '1 000 000,00 €');
    });

    test('montant négatif', () {
      expect(formatEuros(-250), '−2,50 €');
    });

    test('sans centimes (seuils de TVA)', () {
      expect(formatEuros(8500000, avecCentimes: false), '85 000 €');
      expect(formatEuros(3750000, avecCentimes: false), '37 500 €');
    });
  });
}
