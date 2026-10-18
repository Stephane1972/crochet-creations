import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/produit_vues.dart';

/// Tous les produits (archivés compris) avec leurs variantes, mis à jour automatiquement.
/// Les filtres s'appliquent ensuite côté écran (voir `filtrerProduits`).
final produitsResumesProvider = StreamProvider.autoDispose<List<ProduitResume>>(
  (ref) => ref.watch(produitRepositoryProvider).observerResumes(inclureArchives: true),
);

/// Nombre de produits (non archivés) dont le stock est faible ou épuisé ; `null` tant que
/// la liste n'est pas chargée.
final nombreAReapprovisionnerProvider = Provider.autoDispose<int?>((ref) {
  final List<ProduitResume>? produits = ref.watch(produitsResumesProvider).valueOrNull;
  if (produits == null) return null;
  return produits.where((ProduitResume r) => r.produit.archiveLe == null && r.aReapprovisionner).length;
});

/// Fiche d'un produit (`null` s'il n'existe pas ou plus).
final produitDetailProvider = StreamProvider.autoDispose.family<ProduitDetail?, int>(
  (ref, int id) => ref.watch(produitRepositoryProvider).observerDetail(id),
);

/// Ventes validées contenant ce produit.
final historiqueProduitProvider = StreamProvider.autoDispose
    .family<List<LigneHistoriqueVente>, int>(
      (ref, int id) => ref.watch(produitRepositoryProvider).observerHistorique(id),
    );
