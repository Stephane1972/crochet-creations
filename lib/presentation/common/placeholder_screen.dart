import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';

/// Description d'un écran qui sera développé dans une étape ultérieure.
class PlaceholderInfo {
  const PlaceholderInfo({
    required this.titre,
    required this.icone,
    required this.etape,
    required this.description,
  });

  final String titre;
  final IconData icone;

  /// Numéro de l'étape (sur 12) où l'écran sera réellement construit.
  final int etape;
  final String description;
}

/// Écrans prévus mais pas encore développés (voir ROADMAP.md).
abstract final class EcransAVenir {
  static const PlaceholderInfo sauvegarde = PlaceholderInfo(
    titre: 'Sauvegarde et export',
    icone: Icons.backup_outlined,
    etape: 11,
    description: 'Sauvegarde, export CSV/JSON et restauration.',
  );

  /// Écran « Bientôt disponible » à afficher pour chaque route non développée.
  static const Map<String, PlaceholderInfo> parRoute = <String, PlaceholderInfo>{
    AppRoutes.sauvegarde: sauvegarde,
  };
}

/// Écran provisoire « Bientôt disponible ».
///
/// `integre: true` quand il est affiché dans un onglet de la barre de navigation
/// (pas de bouton retour).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.info, this.integre = false});

  final PlaceholderInfo info;
  final bool integre;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(info.titre),
        automaticallyImplyLeading: !integre,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(info.icone, size: 44, color: scheme.onSecondaryContainer),
                ),
                const SizedBox(height: 24),
                Text(
                  'Bientôt disponible',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  info.description,
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Chip(label: Text('Prévu à l’étape ${info.etape} sur 12')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
