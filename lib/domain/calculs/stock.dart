import '../enums.dart';

/// Situation du stock d'un article, pour les alertes.
enum EtatStock {
  /// Stock confortable.
  suffisant,

  /// Stock faible : quantité inférieure ou égale au seuil d'alerte.
  faible,

  /// Plus rien en stock.
  epuise,
}

/// Un produit « sur commande » est fabriqué à la demande : son stock n'est ni
/// décrémenté à la vente, ni vérifié.
bool suitLeStock(StatutProduit statut) => statut != StatutProduit.surCommande;

/// Situation du stock selon la [quantite] restante et le [seuilAlerte].
EtatStock etatStock({required int quantite, required int seuilAlerte}) {
  if (quantite <= 0) return EtatStock.epuise;
  if (quantite <= seuilAlerte) return EtatStock.faible;
  return EtatStock.suffisant;
}

/// Quantité et seuil d'alerte d'un article suivi en stock (un produit, ou l'une de ses variantes).
class StockArticle {
  const StockArticle({required this.quantite, required this.seuilAlerte});

  final int quantite;
  final int seuilAlerte;

  EtatStock get etat => etatStock(quantite: quantite, seuilAlerte: seuilAlerte);
}

/// Situation globale d'un produit à partir de ses articles (lui-même, ou ses variantes).
///
/// - **épuisé** : il ne reste rien du tout (ou aucun article) ;
/// - **faible** : au moins un article est faible ou épuisé alors que d'autres restent disponibles ;
/// - **suffisant** : tous les articles sont confortablement approvisionnés.
EtatStock etatStockGlobal(Iterable<StockArticle> articles) {
  final List<EtatStock> etats = articles.map((StockArticle a) => a.etat).toList();
  if (etats.isEmpty || etats.every((EtatStock e) => e == EtatStock.epuise)) {
    return EtatStock.epuise;
  }
  if (etats.any((EtatStock e) => e != EtatStock.suffisant)) return EtatStock.faible;
  return EtatStock.suffisant;
}

/// Alerte à afficher pour un produit, ou `null` s'il n'y a rien à signaler.
///
/// Un produit « sur commande » n'est pas suivi en stock : jamais d'alerte. Un produit que
/// l'artisane a marqué « épuisé » est signalé comme tel, quel que soit le stock enregistré.
EtatStock? alerteStock({required StatutProduit statut, required EtatStock etat}) {
  if (!suitLeStock(statut)) return null;
  if (statut == StatutProduit.epuise) return EtatStock.epuise;
  return etat == EtatStock.suffisant ? null : etat;
}
