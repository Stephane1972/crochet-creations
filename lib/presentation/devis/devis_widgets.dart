import 'package:flutter/material.dart';

import '../../core/widgets/etiquette.dart';
import '../../domain/enums.dart';

/// Pastille du statut d'un devis (Brouillon, Envoyé, Accepté, Refusé, Expiré).
class EtiquetteStatutDevis extends StatelessWidget {
  const EtiquetteStatutDevis(this.statut, {super.key});

  final StatutDevis statut;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    final (Color fond, Color texte, IconData icone) = switch (statut) {
      StatutDevis.brouillon => (c.surfaceContainerHighest, c.onSurfaceVariant, Icons.edit_outlined),
      StatutDevis.envoye => (c.secondaryContainer, c.onSecondaryContainer, Icons.send_outlined),
      StatutDevis.accepte => (c.primaryContainer, c.onPrimaryContainer, Icons.check),
      StatutDevis.refuse => (c.errorContainer, c.onErrorContainer, Icons.close),
      StatutDevis.expire => (c.tertiaryContainer, c.onTertiaryContainer, Icons.schedule),
    };
    return Etiquette(statut.libelle, fond: fond, couleurTexte: texte, icone: icone);
  }
}
