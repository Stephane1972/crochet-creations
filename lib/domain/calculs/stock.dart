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
