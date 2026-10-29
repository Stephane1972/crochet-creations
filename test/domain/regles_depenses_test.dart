import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/regles_depenses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime maintenant = DateTime(2026, 10, 29, 15, 30);

  String refus(void Function() action) {
    try {
      action();
    } on DonneeInvalide catch (e) {
      return e.message;
    }
    return '';
  }

  group('jours et mois', () {
    test('jourDe retire l’heure', () {
      expect(jourDe(DateTime(2026, 10, 29, 23, 59)), DateTime(2026, 10, 29));
    });

    test('un mois va du premier jour au premier jour du mois suivant (exclu)', () {
      expect(debutDuMois(2026, 10), DateTime(2026, 10, 1));
      expect(debutDuMoisSuivant(2026, 10), DateTime(2026, 11, 1));
      expect(debutDuMoisSuivant(2026, 12), DateTime(2027, 1, 1));
    });

    test('estDansLeMois compare l’année et le mois', () {
      expect(estDansLeMois(DateTime(2026, 10, 31, 23), 2026, 10), isTrue);
      expect(estDansLeMois(DateTime(2026, 11, 1), 2026, 10), isFalse);
      expect(estDansLeMois(DateTime(2025, 10, 15), 2026, 10), isFalse);
    });

    test('une date est « dans le futur » dès le lendemain, pas le jour même', () {
      expect(dateDansLeFutur(DateTime(2026, 10, 29, 23, 59), maintenant), isFalse);
      expect(dateDansLeFutur(DateTime(2026, 10, 30), maintenant), isTrue);
      expect(dateDansLeFutur(DateTime(2026, 10, 1), maintenant), isFalse);
    });
  });

  test('totalCentimes additionne les montants', () {
    expect(totalCentimes(<int>[]), 0);
    expect(totalCentimes(<int>[1250, 399, 5000]), 6649);
  });

  group('verifierDepense', () {
    void verifier({
      int montant = 1250,
      DateTime? date,
      String? fournisseur,
      String? description,
    }) => verifierDepense(
      montantCentimes: montant,
      date: date ?? DateTime(2026, 10, 28),
      maintenant: maintenant,
      fournisseur: fournisseur,
      description: description,
    );

    test('une dépense correcte est acceptée (aujourd’hui et dans le passé)', () {
      expect(() => verifier(), returnsNormally);
      expect(() => verifier(date: DateTime(2026, 10, 29)), returnsNormally);
      expect(() => verifier(date: DateTime(2024, 1, 5)), returnsNormally);
    });

    test('le montant doit être supérieur à zéro', () {
      expect(refus(() => verifier(montant: 0)), 'Le montant de la dépense doit être supérieur à 0 €.');
      expect(refus(() => verifier(montant: -100)), 'Le montant de la dépense doit être supérieur à 0 €.');
    });

    test('la date ne peut pas être dans le futur', () {
      expect(
        refus(() => verifier(date: DateTime(2026, 10, 30))),
        'La date d’une dépense ne peut pas être dans le futur.',
      );
    });

    test('fournisseur et description ont une longueur maximale', () {
      expect(refus(() => verifier(fournisseur: 'a' * 201)), contains('fournisseur est trop long'));
      expect(() => verifier(fournisseur: 'a' * 200), returnsNormally);
      expect(refus(() => verifier(description: 'a' * 2001)), contains('description est trop longue'));
      expect(() => verifier(description: 'a' * 2000), returnsNormally);
    });
  });
}
