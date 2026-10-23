import 'package:flutter/material.dart';

/// Une ligne « libellé ........ montant » d'un récapitulatif (sous-total, remise, total...).
class LigneMontant extends StatelessWidget {
  const LigneMontant({
    super.key,
    required this.libelle,
    required this.montant,
    this.fort = false,
    this.couleur,
  });

  final String libelle;
  final String montant;

  /// Mise en valeur (le total).
  final bool fort;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final TextTheme textes = Theme.of(context).textTheme;
    final TextStyle? style = (fort ? textes.titleMedium : textes.bodyMedium)?.copyWith(color: couleur);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Flexible(child: Text(libelle, style: style)),
          const SizedBox(width: 12),
          Text(montant, style: style),
        ],
      ),
    );
  }
}

/// Carte avec un titre : une rubrique d'un écran de vente.
class CarteRubrique extends StatelessWidget {
  const CarteRubrique({super.key, required this.titre, required this.child});

  final String titre;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
