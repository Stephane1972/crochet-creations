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

  group('etatStockGlobal', () {
    const StockArticle plein = StockArticle(quantite: 10, seuilAlerte: 2);
    const StockArticle faible = StockArticle(quantite: 2, seuilAlerte: 2);
    const StockArticle vide = StockArticle(quantite: 0, seuilAlerte: 2);

    test('sans aucun article, le produit est considéré épuisé', () {
      expect(etatStockGlobal(const <StockArticle>[]), EtatStock.epuise);
    });

    test('un article seul : son propre état', () {
      expect(etatStockGlobal(const <StockArticle>[plein]), EtatStock.suffisant);
      expect(etatStockGlobal(const <StockArticle>[faible]), EtatStock.faible);
      expect(etatStockGlobal(const <StockArticle>[vide]), EtatStock.epuise);
    });

    test('épuisé seulement si toutes les variantes sont épuisées', () {
      expect(etatStockGlobal(const <StockArticle>[vide, vide]), EtatStock.epuise);
      expect(etatStockGlobal(const <StockArticle>[vide, plein]), EtatStock.faible);
    });

    test('faible dès qu’une variante est faible', () {
      expect(etatStockGlobal(const <StockArticle>[plein, faible]), EtatStock.faible);
    });

    test('suffisant quand toutes les variantes le sont', () {
      expect(etatStockGlobal(const <StockArticle>[plein, plein]), EtatStock.suffisant);
    });
  });

  group('alerteStock', () {
    test('un produit sur commande n’a jamais d’alerte', () {
      expect(alerteStock(statut: StatutProduit.surCommande, etat: EtatStock.epuise), isNull);
    });

    test('le statut « épuisé » prime sur la quantité enregistrée', () {
      expect(alerteStock(statut: StatutProduit.epuise, etat: EtatStock.suffisant), EtatStock.epuise);
    });

    test('sinon l’alerte suit l’état du stock', () {
      expect(alerteStock(statut: StatutProduit.disponible, etat: EtatStock.suffisant), isNull);
      expect(alerteStock(statut: StatutProduit.disponible, etat: EtatStock.faible), EtatStock.faible);
      expect(alerteStock(statut: StatutProduit.disponible, etat: EtatStock.epuise), EtatStock.epuise);
      expect(alerteStock(statut: StatutProduit.masque, etat: EtatStock.faible), EtatStock.faible);
    });
  });
}
