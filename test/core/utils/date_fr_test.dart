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

  test('formatDateCourte : jour et mois sur deux chiffres', () {
    expect(formatDateCourte(DateTime(2026, 3, 5)), '05/03/2026');
    expect(formatDateCourte(DateTime(2026, 12, 25, 18, 30)), '25/12/2026');
  });

  test('formatHeure : heure sans zéro devant, minutes sur deux chiffres', () {
    expect(formatHeure(DateTime(2026, 10, 17, 14, 30)), '14 h 30');
    expect(formatHeure(DateTime(2026, 10, 17, 9, 5)), '9 h 05');
    expect(formatHeure(DateTime(2026, 10, 17, 0, 0)), '0 h 00');
  });
}
