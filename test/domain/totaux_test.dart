import 'package:crochet_creations/domain/calculs/totaux.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<LigneACalculer> panier = <LigneACalculer>[
    LigneACalculer(quantite: 2, prixUnitaireCentimes: 1250), // 25,00 €
    LigneACalculer(quantite: 1, prixUnitaireCentimes: 3000), // 30,00 €
  ];

  group('calculerTotaux', () {
    test('sans remise ni frais de port : le total est la somme des lignes', () {
      final TotauxDocument t = calculerTotaux(lignes: panier);
      expect(t.sousTotalCentimes, 5500);
      expect(t.remiseCentimes, 0);
      expect(t.fraisPortCentimes, 0);
      expect(t.totalCentimes, 5500);
    });

    test('remise de 10 % et frais de port de 4,90 € : 55,00 − 5,50 + 4,90 = 54,40 €', () {
      final TotauxDocument t = calculerTotaux(
        lignes: panier,
        remiseType: RemiseType.pourcentage,
        remiseValeur: 1000, // 10,00 %
        fraisPortCentimes: 490,
      );
      expect(t.remiseCentimes, 550);
      expect(t.totalCentimes, 5440);
    });

    test('remise en montant', () {
      final TotauxDocument t = calculerTotaux(
        lignes: panier,
        remiseType: RemiseType.montant,
        remiseValeur: 500,
      );
      expect(t.remiseCentimes, 500);
      expect(t.totalCentimes, 5000);
    });

    test('la valeur de remise est ignorée quand il n’y a pas de remise', () {
      final TotauxDocument t = calculerTotaux(lignes: panier, remiseValeur: 9999);
      expect(t.remiseCentimes, 0);
    });

    test('le pourcentage est arrondi au centime le plus proche (0,5 vers le haut)', () {
      TotauxDocument avec(int prixCentimes) => calculerTotaux(
        lignes: <LigneACalculer>[LigneACalculer(quantite: 1, prixUnitaireCentimes: prixCentimes)],
        remiseType: RemiseType.pourcentage,
        remiseValeur: 1000,
      );
      expect(avec(1004).remiseCentimes, 100); // 100,4
      expect(avec(1005).remiseCentimes, 101); // 100,5
      expect(avec(1006).remiseCentimes, 101); // 100,6
    });

    test('100 % de remise : il ne reste que les frais de port, qui ne sont pas remisés', () {
      final TotauxDocument t = calculerTotaux(
        lignes: panier,
        remiseType: RemiseType.pourcentage,
        remiseValeur: 10000,
        fraisPortCentimes: 600,
      );
      expect(t.remiseCentimes, 5500);
      expect(t.totalCentimes, 600);
    });

    test('un panier vide vaut 0 €, plus les éventuels frais de port', () {
      expect(calculerTotaux(lignes: const <LigneACalculer>[]).totalCentimes, 0);
      expect(
        calculerTotaux(lignes: const <LigneACalculer>[], fraisPortCentimes: 300).totalCentimes,
        300,
      );
    });

    test('une remise en montant supérieure au sous-total est refusée', () {
      expect(
        () => calculerTotaux(lignes: panier, remiseType: RemiseType.montant, remiseValeur: 5501),
        throwsA(isA<RemiseInvalide>()),
      );
    });

    test('un pourcentage de remise hors de 0–100 % est refusé', () {
      expect(
        () => calculerTotaux(lignes: panier, remiseType: RemiseType.pourcentage, remiseValeur: 10001),
        throwsA(isA<RemiseInvalide>()),
      );
      expect(
        () => calculerTotaux(lignes: panier, remiseType: RemiseType.pourcentage, remiseValeur: -1),
        throwsA(isA<RemiseInvalide>()),
      );
    });

    test('quantité nulle, prix négatif ou frais de port négatifs sont refusés', () {
      expect(
        () => calculerTotaux(
          lignes: const <LigneACalculer>[LigneACalculer(quantite: 0, prixUnitaireCentimes: 100)],
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(
        () => calculerTotaux(
          lignes: const <LigneACalculer>[LigneACalculer(quantite: 1, prixUnitaireCentimes: -1)],
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(
        () => calculerTotaux(lignes: panier, fraisPortCentimes: -1),
        throwsA(isA<DonneeInvalide>()),
      );
    });
  });
}
