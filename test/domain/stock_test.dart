import 'package:crochet_creations/domain/calculs/stock.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('etatStock', () {
    test('épuisé quand il ne reste rien', () {
      expect(etatStock(quantite: 0, seuilAlerte: 3), EtatStock.epuise);
      expect(etatStock(quantite: -1, seuilAlerte: 3), EtatStock.epuise);
    });

    test('faible quand la quantité est inférieure ou égale au seuil', () {
      expect(etatStock(quantite: 1, seuilAlerte: 3), EtatStock.faible);
      expect(etatStock(quantite: 3, seuilAlerte: 3), EtatStock.faible);
    });

    test('suffisant au-dessus du seuil', () {
      expect(etatStock(quantite: 4, seuilAlerte: 3), EtatStock.suffisant);
    });

    test('sans seuil, seule la rupture déclenche une alerte', () {
      expect(etatStock(quantite: 1, seuilAlerte: 0), EtatStock.suffisant);
      expect(etatStock(quantite: 0, seuilAlerte: 0), EtatStock.epuise);
    });
  });

  test('seul un produit « sur commande » échappe au suivi du stock', () {
    expect(suitLeStock(StatutProduit.surCommande), isFalse);
    expect(suitLeStock(StatutProduit.disponible), isTrue);
    expect(suitLeStock(StatutProduit.epuise), isTrue);
    expect(suitLeStock(StatutProduit.masque), isTrue);
  });
}
