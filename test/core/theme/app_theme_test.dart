import 'package:crochet_creations/core/theme/app_colors.dart';
import 'package:crochet_creations/core/theme/app_theme.dart';
import 'package:crochet_creations/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rapport de contraste WCAG entre deux couleurs (de 1 à 21).
double contraste(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double clair = la > lb ? la : lb;
  final double fonce = la > lb ? lb : la;
  return (clair + 0.05) / (fonce + 0.05);
}

void main() {
  group('Thème jour', () {
    final ThemeData theme = AppTheme.light;

    test('utilise Material 3 et les couleurs de la charte', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, AppColors.saugeFonce);
      expect(theme.colorScheme.secondary, AppColors.roseSoutenu);
      expect(theme.colorScheme.secondaryContainer, AppColors.rosePastel);
      expect(theme.scaffoldBackgroundColor, AppColors.fondJour);
      expect(theme.colorScheme.onSurface, AppColors.texteJour);
    });
  });

  group('Thème nuit', () {
    final ThemeData theme = AppTheme.dark;

    test('utilise Material 3 et les couleurs de la charte', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppColors.vertClair);
      expect(theme.colorScheme.secondary, AppColors.roseClair);
      expect(theme.scaffoldBackgroundColor, AppColors.fondNuit);
      expect(theme.colorScheme.surfaceContainerLow, AppColors.carteNuit);
      expect(theme.colorScheme.onSurface, AppColors.texteNuit);
    });
  });

  group('Lisibilité (contraste WCAG AA, 4,5:1 minimum)', () {
    void verifier(String nom, ColorScheme s) {
      final Map<String, List<Color>> paires = <String, List<Color>>{
        'texte sur fond': <Color>[s.onSurface, s.surface],
        'texte sur carte': <Color>[s.onSurface, s.surfaceContainerLow],
        'texte secondaire sur fond': <Color>[s.onSurfaceVariant, s.surface],
        'texte secondaire sur carte': <Color>[s.onSurfaceVariant, s.surfaceContainerLow],
        'texte sur bouton principal': <Color>[s.onPrimary, s.primary],
        'texte sur couleur secondaire': <Color>[s.onSecondary, s.secondary],
        'texte sur conteneur vert': <Color>[s.onPrimaryContainer, s.primaryContainer],
        'texte sur conteneur rose': <Color>[s.onSecondaryContainer, s.secondaryContainer],
        'texte d’erreur': <Color>[s.onError, s.error],
        'texte sur conteneur d’erreur': <Color>[s.onErrorContainer, s.errorContainer],
        'texte sur barre de navigation': <Color>[s.onSurface, s.surfaceContainer],
      };
      paires.forEach((String libelle, List<Color> couleurs) {
        expect(
          contraste(couleurs[0], couleurs[1]),
          greaterThanOrEqualTo(4.5),
          reason: '$nom : $libelle',
        );
      });
    }

    test('mode jour', () => verifier('jour', AppTheme.schemaJour));
    test('mode nuit', () => verifier('nuit', AppTheme.schemaNuit));

    test('vert profond des liens sur fond crème et sur carte blanche', () {
      expect(contraste(AppColors.saugeTexte, AppColors.fondJour), greaterThanOrEqualTo(4.5));
      expect(contraste(AppColors.saugeTexte, Colors.white), greaterThanOrEqualTo(4.5));
    });
  });

  group('Mode d’affichage', () {
    test('démarre en automatique et peut être changé', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      container.read(themeModeProvider.notifier).definir(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      container.read(themeModeProvider.notifier).definir(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });
  });
}
