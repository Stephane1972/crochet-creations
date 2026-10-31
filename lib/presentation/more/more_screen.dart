import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../common/menu_tile.dart';

/// Onglet « Plus » : accès aux écrans qui n'ont pas leur propre onglet.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static final List<_Entree> _entrees = <_Entree>[
    const _Entree(
      AppRoutes.factures,
      'Factures',
      Icons.receipt_long_outlined,
      'Liste, aperçu, impression et partage des factures PDF.',
    ),
    const _Entree(
      AppRoutes.devis,
      'Devis',
      Icons.request_quote_outlined,
      'Création de devis, aperçu PDF et conversion en commande ou en facture.',
    ),
    const _Entree(
      AppRoutes.cours,
      'Cours',
      Icons.school_outlined,
      'Cours de crochet, inscriptions, liste d’attente et paiements.',
    ),
    const _Entree(
      AppRoutes.depenses,
      'Dépenses',
      Icons.payments_outlined,
      'Achats de laine, fournitures, frais de marché, avec photo du ticket.',
    ),
    const _Entree(
      AppRoutes.statistiques,
      'Statistiques',
      Icons.insights_outlined,
      'Chiffre d’affaires, meilleures ventes, marge estimée, alerte de franchise de TVA.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> lignes = <Widget>[];
    for (int i = 0; i < _entrees.length; i++) {
      if (i > 0) lignes.add(const Divider(indent: 56));
      final _Entree entree = _entrees[i];
      lignes.add(
        MenuTile(
          icone: entree.icone,
          titre: entree.titre,
          description: entree.description,
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
  const _Entree(this.route, this.titre, this.icone, this.description);

  final String route;
  final String titre;
  final IconData icone;
  final String description;
}
