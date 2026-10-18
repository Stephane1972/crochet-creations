import 'package:flutter/material.dart';

/// Ligne de menu : icône, titre, courte description, flèche. Ouvre une route.
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icone,
    required this.titre,
    required this.description,
    required this.route,
  });

  final IconData icone;
  final String titre;
  final String description;
  final String route;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icone, color: scheme.primary),
      title: Text(titre, style: theme.textTheme.titleSmall),
      subtitle: Text(
        description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }
}
