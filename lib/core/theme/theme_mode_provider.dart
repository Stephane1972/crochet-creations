import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mode d'affichage choisi : automatique (suit le téléphone), jour ou nuit.
///
/// Pour l'instant le choix n'est pas mémorisé : il revient en « automatique »
/// à chaque lancement. Il sera enregistré dans la base de données à l'étape 2
/// (table `parametres_entreprise`).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void definir(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
