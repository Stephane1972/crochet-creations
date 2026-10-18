import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onglets de la barre de navigation du bas.
abstract final class OngletsNav {
  static const int accueil = 0;
  static const int produits = 1;
  static const int vente = 2;
  static const int clients = 3;
  static const int plus = 4;
}

/// Onglet actuellement affiché. Permet aux écrans (ex. les raccourcis de l'accueil)
/// de changer d'onglet sans connaître la barre de navigation.
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => OngletsNav.accueil;

  void aller(int index) => state = index;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(NavIndexNotifier.new);
