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

  group('parseMontantEuros', () {
    test('virgule ou point comme séparateur', () {
      expect(parseMontantEuros('12,50'), 1250);
      expect(parseMontantEuros('12.50'), 1250);
    });

    test('une seule décimale vaut des dizaines de centimes', () {
      expect(parseMontantEuros('12,5'), 1250);
      expect(parseMontantEuros('0,05'), 5);
    });

    test('montant entier, avec espaces et symbole €', () {
      expect(parseMontantEuros('12'), 1200);
      expect(parseMontantEuros(' 1 200 € '), 120000);
      expect(parseMontantEuros('1\u00A0200,00'), 120000);
      expect(parseMontantEuros('0'), 0);
    });

    test('saisies invalides', () {
      expect(parseMontantEuros(''), isNull);
      expect(parseMontantEuros('abc'), isNull);
      expect(parseMontantEuros('-5'), isNull);
      expect(parseMontantEuros('12,345'), isNull);
      expect(parseMontantEuros('12,'), isNull);
      expect(parseMontantEuros('1,2,3'), isNull);
      expect(parseMontantEuros('99999999'), isNull);
    });
  });

  group('formatMontantSaisie', () {
    test('sans centimes quand le montant est rond', () {
      expect(formatMontantSaisie(1200), '12');
      expect(formatMontantSaisie(0), '0');
    });

    test('avec deux décimales sinon', () {
      expect(formatMontantSaisie(1250), '12,50');
      expect(formatMontantSaisie(5), '0,05');
    });

    test('est l’inverse de parseMontantEuros', () {
      for (final int centimes in <int>[0, 5, 99, 100, 1250, 999999]) {
        expect(parseMontantEuros(formatMontantSaisie(centimes)), centimes);
      }
    });
  });
}
