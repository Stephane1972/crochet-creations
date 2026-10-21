import '../../domain/calculs/stock.dart';
import '../../domain/enums.dart';
import '../database/app_database.dart';

/// Articles à compter pour le stock d'un produit : lui-même s'il n'a pas de variantes,
/// sinon chacune de ses variantes (qui héritent du seuil du produit si elles n'en ont pas).
List<StockArticle> articlesDeStock(Produit produit, List<VarianteProduit> variantesActives) {
  if (variantesActives.isEmpty) {
    return <StockArticle>[
      StockArticle(quantite: produit.quantiteStock, seuilAlerte: produit.seuilAlerteStock),
    ];
  }
  return <StockArticle>[
    for (final VarianteProduit v in variantesActives)
      StockArticle(
        quantite: v.quantiteStock,
        seuilAlerte: v.seuilAlerteStock ?? produit.seuilAlerteStock,
      ),
  ];
}

/// Un produit et ses variantes actives : ce qu'il faut pour afficher une ligne du catalogue.
class ProduitResume {
  const ProduitResume({required this.produit, this.variantes = const <VarianteProduit>[]});

  final Produit produit;

  /// Variantes non archivées.
  final List<VarianteProduit> variantes;

  bool get aDesVariantes => variantes.isNotEmpty;

  /// Stock total : somme des variantes, ou stock du produit s'il n'en a pas.
  int get stockTotal => aDesVariantes
      ? variantes.fold(0, (int somme, VarianteProduit v) => somme + v.quantiteStock)
      : produit.quantiteStock;

  EtatStock get etatStock => etatStockGlobal(articlesDeStock(produit, variantes));

  /// Alerte à afficher (stock faible ou épuisé), `null` si rien à signaler.
  EtatStock? get alerte => alerteStock(statut: produit.statut, etat: etatStock);

  /// Produit à réapprovisionner : en alerte, hors produits sur commande.
  bool get aReapprovisionner => alerte != null;

  /// Peut-on le vendre maintenant ? Non s'il est archivé, marqué « épuisé »,
  /// ou s'il n'en reste plus en stock (sauf produit sur commande, fabriqué à la demande).
  bool get vendable {
    if (produit.archiveLe != null || produit.statut == StatutProduit.epuise) return false;
    return !suitLeStock(produit.statut) || stockTotal > 0;
  }
}

/// Tout ce qu'affiche la fiche d'un produit.
class ProduitDetail {
  const ProduitDetail({
    required this.produit,
    this.variantes = const <VarianteProduit>[],
    this.photosSecondaires = const <PhotoProduit>[],
  });

  final Produit produit;

  /// Toutes les variantes, archivées comprises.
  final List<VarianteProduit> variantes;
  final List<PhotoProduit> photosSecondaires;

  List<VarianteProduit> get variantesActives =>
      variantes.where((VarianteProduit v) => v.archiveLe == null).toList();

  List<VarianteProduit> get variantesArchivees =>
      variantes.where((VarianteProduit v) => v.archiveLe != null).toList();

  ProduitResume get resume => ProduitResume(produit: produit, variantes: variantesActives);

  /// Photo principale d'abord, puis les photos secondaires dans l'ordre.
  List<String> get cheminsPhotos => <String>[
    if (produit.photoPrincipaleChemin != null) produit.photoPrincipaleChemin!,
    for (final PhotoProduit p in photosSecondaires) p.chemin,
  ];
}

/// Une ligne de l'historique des ventes d'un produit.
class LigneHistoriqueVente {
  const LigneHistoriqueVente({
    required this.venteId,
    required this.dateVente,
    required this.designation,
    required this.quantite,
    required this.prixUnitaireCentimes,
    required this.totalLigneCentimes,
    this.clientNom,
  });

  final int venteId;
  final DateTime dateVente;
  final String designation;
  final int quantite;
  final int prixUnitaireCentimes;
  final int totalLigneCentimes;

  /// `null` pour un client de passage.
  final String? clientNom;
}

/// Nom d'un client pour l'affichage : « Prénom Nom », sinon la raison sociale.
String nomClientAffiche({String? prenom, String? nom, String? raisonSociale}) {
  final String personne = <String?>[
    prenom,
    nom,
  ].whereType<String>().map((String s) => s.trim()).where((String s) => s.isNotEmpty).join(' ');
  if (personne.isNotEmpty) return personne;
  return raisonSociale?.trim() ?? '';
}
