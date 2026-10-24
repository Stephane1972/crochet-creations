import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clients/clients_screen.dart';
import '../home/home_screen.dart';
import '../more/more_screen.dart';
import '../produits/produits_screen.dart';
import '../ventes/vente_screen.dart';
import 'nav_provider.dart';

/// Structure principale : 5 onglets en bas (Accueil, Produits, Vente, Clients, Plus).
///
/// Les écrans secondaires (factures, devis, cours...) s'ouvrent par-dessus,
/// depuis l'onglet « Plus » ou les raccourcis de l'accueil.
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const List<NavigationDestination> _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Accueil',
    ),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: 'Produits',
    ),
    NavigationDestination(
      icon: Icon(Icons.point_of_sale_outlined),
      selectedIcon: Icon(Icons.point_of_sale),
      label: 'Vente',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outline),
      selectedIcon: Icon(Icons.people),
      label: 'Clients',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu),
      selectedIcon: Icon(Icons.menu_open),
      label: 'Plus',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int index = ref.watch(navIndexProvider);

    // Le bouton « retour » d'Android ramène d'abord à l'accueil avant de quitter l'application.
    return PopScope(
      canPop: index == OngletsNav.accueil,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          ref.read(navIndexProvider.notifier).aller(OngletsNav.accueil);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: const <Widget>[
            HomeScreen(),
            ProduitsScreen(),
            VenteScreen(),
            ClientsScreen(),
            MoreScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (int i) => ref.read(navIndexProvider.notifier).aller(i),
          destinations: _destinations,
        ),
      ),
    );
  }
}
