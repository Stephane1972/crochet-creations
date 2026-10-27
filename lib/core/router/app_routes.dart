/// Noms des routes de l'application.
///
/// Les écrans qui ne sont pas encore développés pointent vers un écran
/// « Bientôt disponible » (voir presentation/common/placeholder_screen.dart).
abstract final class AppRoutes {
  static const String splash = '/';
  static const String accueil = '/accueil';

  // Produits (étape 3). La fiche et la modification reçoivent l'identifiant du produit
  // (un entier) dans `arguments`.
  static const String produitNouveau = '/produits/nouveau';
  static const String produitFiche = '/produits/fiche';
  static const String produitModifier = '/produits/modifier';

  // Clients (étape 4). La fiche et la modification reçoivent l'identifiant du client
  // (un entier) dans `arguments`.
  static const String clientNouveau = '/clients/nouveau';
  static const String clientFiche = '/clients/fiche';
  static const String clientModifier = '/clients/modifier';

  // Ventes (étape 5). La nouvelle vente est l'onglet « Vente » ; le panier s'ouvre par-dessus.
  // La confirmation (et la consultation d'une vente) reçoit l'identifiant de la vente dans `arguments`.
  static const String panier = '/ventes/panier';
  static const String venteConfirmation = '/ventes/confirmation';

  // Documents (étapes 6 et 7). L'aperçu d'une facture reçoit l'identifiant de la facture dans `arguments`.
  static const String factures = '/factures';
  static const String factureDetail = '/factures/detail';

  // Devis (étape 7). L'aperçu, la modification et la conversion reçoivent l'identifiant du devis (un entier)
  // dans `arguments`.
  static const String devis = '/devis';
  static const String devisNouveau = '/devis/nouveau';
  static const String devisDetail = '/devis/detail';
  static const String devisModifier = '/devis/modifier';
  static const String devisConversion = '/devis/conversion';

  // Cours (étape 8)
  static const String cours = '/cours';

  // Dépenses (étape 9)
  static const String depenses = '/depenses';

  // Statistiques (étape 10)
  static const String statistiques = '/statistiques';

  // Réglages
  static const String reglages = '/reglages';
  static const String monEntreprise = '/reglages/entreprise';
  static const String sauvegarde = '/reglages/sauvegarde';
}
