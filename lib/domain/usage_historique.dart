/// Un type d'élément où un client ou un produit apparaît : « 3 ventes », « 1 facture »...
class ElementUsage {
  const ElementUsage(this.nombre, this.singulier, this.pluriel);

  final int nombre;
  final String singulier;
  final String pluriel;

  /// « 1 facture », « 3 ventes » (le pluriel dès 2).
  String get texte => '$nombre ${nombre > 1 ? pluriel : singulier}';
}

/// Ce qu'un client ou un produit a déjà servi à faire (ventes, factures, devis, inscriptions à des cours).
///
/// Sert à prévenir, avant de supprimer un client ou un produit, de ce qui en dépend : ces ventes, factures et
/// devis sont conservés (ils gardent le nom ou la désignation d'origine) mais ne sont plus liés à la fiche supprimée.
class UsageHistorique {
  UsageHistorique(Iterable<ElementUsage> elements)
    : elements = List<ElementUsage>.unmodifiable(elements.where((ElementUsage e) => e.nombre > 0));

  /// Les éléments trouvés, sans ceux dont le nombre est nul.
  final List<ElementUsage> elements;

  /// Il apparaît quelque part (vente, facture, devis, inscription à un cours).
  bool get estUtilise => elements.isNotEmpty;

  /// « 3 ventes, 1 facture et 2 devis » (vide s'il n'a jamais servi).
  String get enumeration {
    final List<String> textes = <String>[for (final ElementUsage e in elements) e.texte];
    if (textes.length <= 1) return textes.join();
    return '${textes.sublist(0, textes.length - 1).join(', ')} et ${textes.last}';
  }
}
