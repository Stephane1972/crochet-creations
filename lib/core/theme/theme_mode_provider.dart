import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Endroit où le choix jour / nuit / automatique est mémorisé entre deux lancements.
/// Implémenté par la base de données (`ParametresRepository`).
abstract interface class ModeThemeStore {
  Future<void> memoriser(ThemeMode mode);
}

class _StoreSansMemoire implements ModeThemeStore {
  const _StoreSansMemoire();

  @override
  Future<void> memoriser(ThemeMode mode) async {}
}

/// Mode au démarrage : lu dans la base par `main()` avant l'affichage du premier écran
/// (pas de clignotement). Automatique par défaut, par exemple dans les tests.
final modeThemeInitialProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// Mémorisation du choix. Sans mémoire par défaut ; `main()` la branche sur la base de données.
final modeThemeStoreProvider = Provider<ModeThemeStore>((ref) => const _StoreSansMemoire());

/// Mode d'affichage choisi : automatique (suit le téléphone), jour ou nuit.
/// Chaque changement est enregistré dans la base (table `parametres_entreprise`).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(modeThemeInitialProvider);

  void definir(ThemeMode mode) {
    state = mode;
    // L'affichage change tout de suite ; l'enregistrement se fait en arrière-plan.
    ref.read(modeThemeStoreProvider).memoriser(mode).catchError((Object erreur) {
      debugPrint('Impossible de mémoriser le mode d’affichage : $erreur');
    });
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
