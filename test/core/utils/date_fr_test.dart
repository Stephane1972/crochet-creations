import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDateLongue', () {
    test('jour de semaine, quantième et mois en français', () {
      expect(formatDateLongue(DateTime(2026, 10, 17)), 'samedi 17 octobre');
      expect(formatDateLongue(DateTime(2026, 2, 3)), 'mardi 3 février');
    });

    test('premier du mois : « 1er »', () {
      expect(formatDateLongue(DateTime(2026, 11, 1)), 'dimanche 1er novembre');
    });
  });

  group('salutation', () {
    test('« Bonjour » en journée', () {
      expect(salutation(DateTime(2026, 10, 17, 9)), 'Bonjour');
      expect(salutation(DateTime(2026, 10, 17, 17, 59)), 'Bonjour');
    });

    test('« Bonsoir » à partir de 18 h et la nuit', () {
      expect(salutation(DateTime(2026, 10, 17, 18)), 'Bonsoir');
      expect(salutation(DateTime(2026, 10, 17, 2)), 'Bonsoir');
    });
  });
}
