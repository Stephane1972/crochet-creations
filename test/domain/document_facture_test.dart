import 'package:crochet_creations/domain/document_facture.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/regles_entreprise.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('libelleRemiseDocument', () {
    test('un montant s’appelle simplement « Remise »', () {
      expect(libelleRemiseDocument(RemiseType.montant, 500), 'Remise');
      expect(libelleRemiseDocument(RemiseType.aucune, 0), 'Remise');
    });

    test('un pourcentage entier', () {
      expect(libelleRemiseDocument(RemiseType.pourcentage, 1000), 'Remise (10 %)');
      expect(libelleRemiseDocument(RemiseType.pourcentage, 10000), 'Remise (100 %)');
    });

    test('un pourcentage avec décimales, sans zéro inutile', () {
      expect(libelleRemiseDocument(RemiseType.pourcentage, 1250), 'Remise (12,5 %)');
      expect(libelleRemiseDocument(RemiseType.pourcentage, 1275), 'Remise (12,75 %)');
      expect(libelleRemiseDocument(RemiseType.pourcentage, 505), 'Remise (5,05 %)');
    });
  });

  group('formaterSiren', () {
    test('groupe les 9 chiffres par trois', () {
      expect(formaterSiren('123456789'), '123 456 789');
      expect(formaterSiren('123 456 789'), '123 456 789');
      expect(formaterSiren('123.456.789'), '123 456 789');
    });

    test('rend telle quelle une valeur qui n’a pas 9 chiffres', () {
      expect(formaterSiren(' 1234 '), '1234');
      expect(formaterSiren(''), '');
    });
  });
}
