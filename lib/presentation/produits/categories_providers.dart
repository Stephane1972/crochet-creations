import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'produits_providers.dart';

/// Les catégories de produits, dans l'ordre d'affichage, mises à jour automatiquement.
final categoriesProduitProvider = StreamProvider.autoDispose<List<CategorieProduit>>(
  (ref) => ref.watch(categorieRepositoryProvider).observer(),
);

/// Nom de chaque catégorie, par clé (vide tant que la liste n'est pas chargée).
final nomsCategoriesProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final List<CategorieProduit> liste =
      ref.watch(categoriesProduitProvider).valueOrNull ?? const <CategorieProduit>[];
  return <String, String>{for (final CategorieProduit c in liste) c.cle: c.nom};
});

/// Nombre de produits de chaque catégorie, archivés compris, par clé (les catégories vides n'y figurent pas).
final nombreProduitsParCategorieProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final Map<String, int> comptes = <String, int>{};
  for (final r in ref.watch(produitsResumesProvider).valueOrNull ?? const []) {
    final String cle = r.produit.categorie;
    comptes[cle] = (comptes[cle] ?? 0) + 1;
  }
  return comptes;
});

/// Le nom à afficher pour la catégorie [cle] : son nom actuel, ou rien tant que les catégories se chargent, ou
/// « Sans catégorie » si elle a disparu (cela ne devrait pas arriver : supprimer une catégorie déplace ses produits).
String nomCategorie(Map<String, String> noms, String cle) => noms[cle] ?? (noms.isEmpty ? '' : 'Sans catégorie');
