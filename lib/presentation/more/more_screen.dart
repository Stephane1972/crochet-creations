import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../common/menu_tile.dart';
import '../common/placeholder_screen.dart';

/// Onglet « Plus » : accès aux écrans qui n'ont pas leur propre onglet.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const List<_Entree> _entrees = <_Entree>[
    _Entree(AppRoutes.factures, EcransAVenir.factures),
    _Entree(AppRoutes.devis, EcransAVenir.devis),
    _Entree(AppRoutes.cours, EcransAVenir.cours),
    _Entree(AppRoutes.depenses, EcransAVenir.depenses),
    _Entree(AppRoutes.statistiques, EcransAVenir.statistiques),
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> lignes = <Widget>[];
    for (int i = 0; i < _entrees.length; i++) {
      if (i > 0) lignes.add(const Divider(indent: 56));
      final _Entree entree = _entrees[i];
      lignes.add(
        MenuTile(
          icone: entree.info.icone,
          titre: entree.info.titre,
          description: entree.info.description,
          route: entree.route,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Plus'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          Card(child: Column(children: lignes)),
          const SizedBox(height: 16),
          const Card(
            child: MenuTile(
              icone: Icons.settings_outlined,
              titre: 'Réglages',
              description: 'Apparence, entreprise, sauvegarde.',
              route: AppRoutes.reglages,
            ),
          ),
        ],
      ),
    );
  }
}

class _Entree {
  const _Entree(this.route, this.info);

  final String route;
  final PlaceholderInfo info;
}
