import 'package:crochet_creations/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Espion implements ModeThemeStore {
  final List<ThemeMode> enregistres = <ThemeMode>[];

  @override
  Future<void> memoriser(ThemeMode mode) async => enregistres.add(mode);
}

class _EnPanne implements ModeThemeStore {
  @override
  Future<void> memoriser(ThemeMode mode) => Future<void>.error(StateError('disque plein'));
}

void main() {
  test('le mode affiché au démarrage est celui lu dans la base', () {
    final ProviderContainer container = ProviderContainer(
      overrides: [modeThemeInitialProvider.overrideWithValue(ThemeMode.dark)],
    );
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('chaque changement de mode est enregistré', () {
    final _Espion espion = _Espion();
    final ProviderContainer container = ProviderContainer(
      overrides: [modeThemeStoreProvider.overrideWithValue(espion)],
    );
    addTearDown(container.dispose);

    container.read(themeModeProvider.notifier).definir(ThemeMode.dark);
    container.read(themeModeProvider.notifier).definir(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(espion.enregistres, <ThemeMode>[ThemeMode.dark, ThemeMode.light]);
  });

  test('si l’enregistrement échoue, l’affichage change quand même (sans erreur)', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [modeThemeStoreProvider.overrideWithValue(_EnPanne())],
    );
    addTearDown(container.dispose);

    container.read(themeModeProvider.notifier).definir(ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
