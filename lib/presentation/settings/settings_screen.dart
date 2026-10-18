import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/widgets/app_logo.dart';
import '../common/menu_tile.dart';

/// Réglages. À l'étape 1 : choix du thème (automatique / jour / nuit) et accès
/// aux écrans « Mon entreprise » et « Sauvegarde » (qui arriveront plus tard).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ThemeMode mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          const _TitreSection('Apparence'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Thème', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '« Auto » suit le réglage jour/nuit de votre téléphone.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<ThemeMode>>[
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('Auto'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Jour'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Nuit'),
                        ),
                      ],
                      selected: <ThemeMode>{mode},
                      onSelectionChanged: (Set<ThemeMode> choix) {
                        ref.read(themeModeProvider.notifier).definir(choix.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _TitreSection('Mon activité'),
          const Card(
            child: Column(
              children: <Widget>[
                MenuTile(
                  icone: Icons.storefront_outlined,
                  titre: 'Mon entreprise',
                  description: 'Nom, adresse, SIREN et mentions des factures.',
                  route: AppRoutes.monEntreprise,
                ),
                Divider(indent: 56),
                MenuTile(
                  icone: Icons.backup_outlined,
                  titre: 'Sauvegarde et export',
                  description: 'Sauvegarder, exporter et restaurer vos données.',
                  route: AppRoutes.sauvegarde,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _TitreSection('À propos'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  const AppLogo(taille: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(AppConstants.nomApplication, style: theme.textTheme.titleSmall),
                        Text(
                          'Version ${AppConstants.version} · étape 3 sur 12 · '
                          'fonctionne sans connexion',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(texte, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
