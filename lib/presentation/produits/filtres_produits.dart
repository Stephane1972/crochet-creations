import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/recherche.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/enums.dart';

/// Recherche et filtres de la liste des produits.
class FiltresProduits {
  const FiltresProduits({
    this.recherche = '',
    this.categorie,
    this.aReapprovisionner = false,
    this.archives = false,
  });

  final String recherche;

  /// `null` = toutes les catégories.
  final CategorieProduit? categorie;

  /// Seulement les produits dont le stock est faible ou épuisé.
  final bool aReapprovisionner;

  /// Afficher aussi les produits archivés.
  final bool archives;

  /// Vrai si un critère limite la liste (la case « archivés » élargit la liste, elle ne la limite pas).
  bool get limiteLaListe => recherche.trim().isNotEmpty || categorie != null || aReapprovisionner;

  FiltresProduits avecRecherche(String valeur) => FiltresProduits(
    recherche: valeur,
    categorie: categorie,
    aReapprovisionner: aReapprovisionner,
    archives: archives,
  );

  FiltresProduits avecCategorie(CategorieProduit? valeur) => FiltresProduits(
    recherche: recherche,
    categorie: valeur,
    aReapprovisionner: aReapprovisionner,
    archives: archives,
  );

  FiltresProduits avecReapprovisionner({required bool valeur}) => FiltresProduits(
    recherche: recherche,
    categorie: categorie,
    aReapprovisionner: valeur,
    archives: archives,
  );

  FiltresProduits avecArchives({required bool valeur}) => FiltresProduits(
    recherche: recherche,
    categorie: categorie,
    aReapprovisionner: aReapprovisionner,
    archives: valeur,
  );
}

class FiltresProduitsNotifier extends Notifier<FiltresProduits> {
  @override
  FiltresProduits build() => const FiltresProduits();

  void rechercher(String valeur) => state = state.avecRecherche(valeur);

  void choisirCategorie(CategorieProduit? valeur) => state = state.avecCategorie(valeur);

  void basculerReapprovisionner() =>
      state = state.avecReapprovisionner(valeur: !state.aReapprovisionner);

  void basculerArchives() => state = state.avecArchives(valeur: !state.archives);

  void reinitialiser() => state = const FiltresProduits();

  /// Raccourci de l'accueil : seulement les produits à réapprovisionner, sans autre filtre.
  void afficherAReapprovisionner() =>
      state = const FiltresProduits().avecReapprovisionner(valeur: true);
}

final filtresProduitsProvider = NotifierProvider<FiltresProduitsNotifier, FiltresProduits>(
  FiltresProduitsNotifier.new,
);

/// Applique la recherche et les filtres (l'ordre alphabétique de la liste d'origine est conservé).
List<ProduitResume> filtrerProduits(List<ProduitResume> produits, FiltresProduits filtres) {
  return produits.where((ProduitResume r) {
    if (!filtres.archives && r.produit.archiveLe != null) return false;
    if (filtres.categorie != null && r.produit.categorie != filtres.categorie) return false;
    if (filtres.aReapprovisionner && !r.aReapprovisionner) return false;
    return correspondALaRecherche(filtres.recherche, _champsRecherchables(r));
  }).toList();
}

/// Les textes dans lesquels on cherche : nom, référence, catégorie, matières, couleur, description
/// et noms des variantes.
List<String?> _champsRecherchables(ProduitResume r) {
  final Produit p = r.produit;
  return <String?>[
    p.nom,
    p.reference,
    p.categorie.libelle,
    p.matieres,
    p.couleur,
    p.description,
    for (final VarianteProduit v in r.variantes) ...<String?>[v.libelle, v.couleur, v.taille],
  ];
}
