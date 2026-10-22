import 'package:flutter/material.dart';

import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/client_vues.dart';
import '../../domain/enums.dart';

/// Pastille ronde avec les initiales du client.
class PastilleClient extends StatelessWidget {
  const PastilleClient({super.key, required this.client, this.taille = 48});

  final Client client;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Text(
        initialesClient(client),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: scheme.onPrimaryContainer,
          fontSize: taille * 0.36,
        ),
      ),
    );
  }
}

/// Étiquettes d'un client : « Professionnel », « Archivé ».
List<Widget> etiquettesClient(BuildContext context, Client client) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return <Widget>[
    if (client.typeClient == TypeClient.professionnel)
      Etiquette(
        'Professionnel',
        fond: scheme.secondaryContainer,
        couleurTexte: scheme.onSecondaryContainer,
        icone: Icons.storefront_outlined,
      ),
    if (client.archiveLe != null)
      Etiquette(
        'Archivé',
        fond: scheme.surfaceContainerHighest,
        couleurTexte: scheme.onSurfaceVariant,
        icone: Icons.archive_outlined,
      ),
  ];
}

/// « 06 12 34 56 78 · Toulouse » : les coordonnées utiles d'un coup d'œil dans la liste.
String resumeCoordonnees(Client client) {
  final String ville = <String?>[
    client.codePostal,
    client.ville,
  ].whereType<String>().where((String s) => s.trim().isNotEmpty).join(' ');
  return <String>[
    if (client.telephone != null) client.telephone!,
    if (ville.isNotEmpty) ville,
  ].join(' · ');
}
