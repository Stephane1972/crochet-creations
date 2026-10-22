import 'package:flutter/material.dart';

/// Petite pastille d'information (« Stock faible », « Archivé »...).
class Etiquette extends StatelessWidget {
  const Etiquette(this.texte, {super.key, required this.fond, required this.couleurTexte, this.icone});

  final String texte;
  final Color fond;
  final Color couleurTexte;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icone != null) ...<Widget>[
            Icon(icone, size: 14, color: couleurTexte),
            const SizedBox(width: 4),
          ],
          Text(
            texte,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: couleurTexte,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
