import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Écran affiché à la place de l'application quand la base de données ne peut pas s'ouvrir
/// (fichier abîmé, mise à jour impossible...). Mieux qu'un écran blanc : il explique quoi faire.
class ErreurDemarrageApp extends StatelessWidget {
  const ErreurDemarrageApp({super.key, required this.erreur});

  final Object erreur;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.nomApplication,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _Contenu(erreur: erreur),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.erreur});

  final Object erreur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const SizedBox(height: 32),
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 20),
            Text(
              'Impossible d’ouvrir vos données',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Ce message n’efface rien. Fermez complètement l’application, '
              'puis rouvrez-la. Si ce message revient, notez le détail ci-dessous '
              'et transmettez-le à la personne qui a installé l’application.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  erreur.toString(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
