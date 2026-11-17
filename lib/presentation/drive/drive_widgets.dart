import 'package:flutter/material.dart';

/// Une carte à titre, comme celles des écrans Google Drive.
class CarteDrive extends StatelessWidget {
  const CarteDrive({super.key, required this.titre, required this.enfants});

  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...enfants,
          ],
        ),
      ),
    );
  }
}

Text texteDiscretDrive(BuildContext context, String texte, {Key? key}) {
  final ThemeData theme = Theme.of(context);
  return Text(
    texte,
    key: key,
    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  );
}

Text texteErreurDrive(BuildContext context, String texte, {Key? key}) {
  final ThemeData theme = Theme.of(context);
  return Text(texte, key: key, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error));
}
