/// Listes de choix de l'application (catégories, statuts, modes de paiement...).
///
/// ⚠️ Dans la base de données, chaque valeur est enregistrée sous son **nom Dart**
/// (par exemple `bouclesOreilles`). Renommer une valeur ici sans migration rendrait
/// illisibles les données déjà enregistrées. Ajouter une valeur à la fin est sans risque.
/// Les noms de `NatureLigne`, `RemiseType`, `StatutFacture` et `TypeCompteur` sont aussi
/// écrits dans des contraintes SQL (voir `tables.dart`) : ne pas les renommer.
library;

/// Catégorie d'un produit.
enum CategorieProduit {
  crochet('Crochet'),
  doudou('Doudou'),
  bouclesOreilles('Boucles d’oreilles'),
  accessoire('Accessoire'),
  surMesure('Sur mesure');

  const CategorieProduit(this.libelle);
  final String libelle;
}

/// Statut commercial d'un produit.
enum StatutProduit {
  disponible('Disponible'),
  surCommande('Sur commande'),
  epuise('Épuisé'),
  masque('Masqué');

  const StatutProduit(this.libelle);
  final String libelle;
}

/// Particulier ou professionnel.
enum TypeClient {
  particulier('Particulier'),
  professionnel('Professionnel');

  const TypeClient(this.libelle);
  final String libelle;
}

enum Civilite {
  madame('Madame'),
  monsieur('Monsieur'),
  autre('Autre');

  const Civilite(this.libelle);
  final String libelle;
}

/// Nature d'une ligne de vente ou de devis. Elle alimente les deux compteurs
/// de chiffre d'affaires (ventes d'objets / cours et prestations).
enum NatureLigne {
  bien('Objet'),
  service('Prestation');

  const NatureLigne(this.libelle);
  final String libelle;
}

/// Type de remise accordée sur une vente ou un devis.
enum RemiseType {
  aucune('Aucune'),

  /// La valeur est en centièmes de pour cent : 1500 = 15,00 %.
  pourcentage('Pourcentage'),

  /// La valeur est un montant en centimes.
  montant('Montant');

  const RemiseType(this.libelle);
  final String libelle;
}

/// Une vente validée est définitive : une erreur se corrige en l'annulant
/// (le stock est alors remis), jamais en la supprimant.
enum StatutVente {
  validee('Validée'),
  annulee('Annulée');

  const StatutVente(this.libelle);
  final String libelle;
}

enum StatutPaiement {
  impayee('Impayée'),
  partiellementPayee('Partiellement payée'),
  payee('Payée'),
  remboursee('Remboursée');

  const StatutPaiement(this.libelle);
  final String libelle;
}

enum ModePaiement {
  especes('Espèces'),
  carte('Carte'),
  virement('Virement'),
  paypal('PayPal'),
  cheque('Chèque'),
  autre('Autre');

  const ModePaiement(this.libelle);
  final String libelle;
}

/// Une facture émise ne se supprime pas ; elle peut seulement être marquée annulée.
enum StatutFacture {
  emise('Émise'),
  annulee('Annulée');

  const StatutFacture(this.libelle);
  final String libelle;
}

enum StatutDevis {
  brouillon('Brouillon'),
  envoye('Envoyé'),
  accepte('Accepté'),
  refuse('Refusé'),
  expire('Expiré');

  const StatutDevis(this.libelle);
  final String libelle;
}

enum NiveauCours {
  debutant('Débutant'),
  intermediaire('Intermédiaire'),
  avance('Avancé'),
  tousNiveaux('Tous niveaux');

  const NiveauCours(this.libelle);
  final String libelle;
}

enum StatutCours {
  planifie('Prévu'),
  annule('Annulé');

  const StatutCours(this.libelle);
  final String libelle;
}

enum StatutInscription {
  confirmee('Confirmée'),
  listeAttente('Liste d’attente'),
  annulee('Annulée');

  const StatutInscription(this.libelle);
  final String libelle;
}

enum CategorieDepense {
  laineFil('Laine / fil'),
  fournitures('Fournitures'),
  emballage('Emballage'),
  standMarche('Stand / marché'),
  transport('Transport'),
  publicite('Publicité'),
  materiel('Matériel'),
  autre('Autre');

  const CategorieDepense(this.libelle);
  final String libelle;
}

/// Mode d'affichage mémorisé (équivalent du `ThemeMode` de Flutter,
/// mais sans dépendre de Flutter dans la couche `domain`).
enum ModeTheme {
  systeme('Automatique'),
  jour('Jour'),
  nuit('Nuit');

  const ModeTheme(this.libelle);
  final String libelle;
}

/// Suites de numéros gérées par la table `numerotation_documents`.
enum TypeCompteur {
  /// FACT-2026-0001 : une suite par année.
  facture('FACT', parAnnee: true),

  /// DEVIS-2026-0001 : une suite par année.
  devis('DEVIS', parAnnee: true),

  /// PRD-0001 : référence automatique des produits, une seule suite.
  produit('PRD', parAnnee: false);

  const TypeCompteur(this.prefixe, {required this.parAnnee});
  final String prefixe;
  final bool parAnnee;
}
