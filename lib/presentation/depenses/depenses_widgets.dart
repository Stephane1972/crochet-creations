import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/enums.dart';

/// Icône de chaque catégorie de dépense.
IconData iconeCategorieDepense(CategorieDepense categorie) {
  return switch (categorie) {
    CategorieDepense.laineFil => Icons.texture,
    CategorieDepense.fournitures => Icons.content_cut,
    CategorieDepense.emballage => Icons.inventory_2_outlined,
    CategorieDepense.standMarche => Icons.storefront_outlined,
    CategorieDepense.transport => Icons.local_shipping_outlined,
    CategorieDepense.publicite => Icons.campaign_outlined,
    CategorieDepense.materiel => Icons.build_outlined,
    CategorieDepense.autre => Icons.more_horiz,
  };
}

/// Photo d'un ticket, ou une icône de reçu si le fichier a disparu.
class ImageTicket extends ConsumerWidget {
  const ImageTicket({super.key, required this.chemin, this.largeur, this.hauteur, this.rayon = 12});

  final String chemin;
  final double? largeur;
  final double? hauteur;
  final double rayon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget substitut = Container(
      width: largeur,
      height: hauteur,
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Icon(Icons.receipt_long_outlined, size: 40, color: scheme.onSecondaryContainer),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(rayon),
      child: Image.file(
        ref.watch(stockagePhotosProvider).fichier(chemin),
        width: largeur,
        height: hauteur,
        // Un ticket est long et étroit : on le montre en entier plutôt que de le recadrer.
        fit: BoxFit.contain,
        cacheWidth: 1000,
        errorBuilder: (BuildContext context, Object erreur, StackTrace? pile) => substitut,
      ),
    );
  }
}
