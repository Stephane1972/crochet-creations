import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/calculs/stock.dart';
import '../../domain/enums.dart';

export '../../core/widgets/etiquette.dart';

/// Icône associée à chaque catégorie (affichée quand un produit n'a pas de photo).
IconData iconeCategorie(CategorieProduit categorie) {
  return switch (categorie) {
    CategorieProduit.crochet => Icons.dry_cleaning_outlined,
    CategorieProduit.doudou => Icons.toys_outlined,
    CategorieProduit.bouclesOreilles => Icons.diamond_outlined,
    CategorieProduit.accessoire => Icons.watch_outlined,
    CategorieProduit.surMesure => Icons.design_services_outlined,
  };
}

/// Photo d'un produit, ou une icône de sa catégorie s'il n'en a pas (ou si le fichier a disparu).
class ImageProduit extends ConsumerWidget {
  const ImageProduit({
    super.key,
    required this.chemin,
    required this.categorie,
    this.largeur,
    this.hauteur,
    this.rayon = 12,
    this.fit = BoxFit.cover,
    this.tailleIcone,
  });

  final String? chemin;
  final CategorieProduit categorie;
  final double? largeur;
  final double? hauteur;
  final double rayon;
  final BoxFit fit;

  /// Taille de l'icône de substitution. Par défaut : 45 % du côté connu (largeur ou hauteur finie).
  final double? tailleIcone;

  /// Côté de référence pour l'icône : `double.infinity` (image qui remplit toute la place)
  /// ne peut pas servir de taille d'icône.
  double get _tailleIconeParDefaut {
    final double? cote = <double?>[largeur, hauteur].firstWhere(
      (double? c) => c != null && c.isFinite,
      orElse: () => null,
    );
    return (cote ?? 64) * 0.45;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Widget substitut = Container(
      width: largeur,
      height: hauteur,
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Icon(
        iconeCategorie(categorie),
        size: tailleIcone ?? _tailleIconeParDefaut,
        color: scheme.onSecondaryContainer,
      ),
    );

    final String? cheminPhoto = chemin;
    final Widget contenu = cheminPhoto == null
        ? substitut
        : Image.file(
            ref.watch(stockagePhotosProvider).fichier(cheminPhoto),
            width: largeur,
            height: hauteur,
            fit: fit,
            cacheWidth: 800,
            errorBuilder: (BuildContext context, Object erreur, StackTrace? pile) => substitut,
          );

    return ClipRRect(borderRadius: BorderRadius.circular(rayon), child: contenu);
  }
}

/// Étiquettes d'état d'un produit : épuisé / stock faible, sur commande, masqué, archivé.
List<Widget> etiquettesProduit(BuildContext context, ProduitResume resume) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final EtatStock? alerte = resume.alerte;

  return <Widget>[
    if (alerte == EtatStock.epuise)
      Etiquette(
        'Épuisé',
        fond: scheme.errorContainer,
        couleurTexte: scheme.onErrorContainer,
        icone: Icons.error_outline,
      ),
    if (alerte == EtatStock.faible)
      Etiquette(
        'Stock faible',
        fond: scheme.tertiaryContainer,
        couleurTexte: scheme.onTertiaryContainer,
        icone: Icons.warning_amber_rounded,
      ),
    if (resume.produit.statut == StatutProduit.surCommande)
      Etiquette(
        'Sur commande',
        fond: scheme.secondaryContainer,
        couleurTexte: scheme.onSecondaryContainer,
      ),
    if (resume.produit.statut == StatutProduit.masque)
      Etiquette(
        'Masqué',
        fond: scheme.surfaceContainerHighest,
        couleurTexte: scheme.onSurfaceVariant,
        icone: Icons.visibility_off_outlined,
      ),
    if (resume.produit.archiveLe != null)
      Etiquette(
        'Archivé',
        fond: scheme.surfaceContainerHighest,
        couleurTexte: scheme.onSurfaceVariant,
        icone: Icons.archive_outlined,
      ),
  ];
}

/// « 5 en stock », « Épuisé »... (rien pour un produit sur commande).
String texteStock(ProduitResume resume) {
  if (!suitLeStock(resume.produit.statut)) return 'Fabriqué à la demande';
  final int total = resume.stockTotal;
  if (total <= 0) return 'Aucun en stock';
  return total == 1 ? '1 en stock' : '$total en stock';
}

/// Prix d'un produit. Avec des variantes, c'est leur prix qui compte (celui du produit si elles
/// n'en ont pas) : « dès X € » quand ils diffèrent.
String textePrix(ProduitResume resume) {
  final int prixProduit = resume.produit.prixVenteCentimes;
  if (!resume.aDesVariantes) return formatEuros(prixProduit);
  final List<int> prix = <int>[
    for (final VarianteProduit v in resume.variantes) v.prixCentimes ?? prixProduit,
  ]..sort();
  return prix.first == prix.last ? formatEuros(prix.first) : 'dès ${formatEuros(prix.first)}';
}
