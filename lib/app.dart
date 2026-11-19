import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/plateforme.dart';
import 'core/router/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/widgets/adaptive_system_overlay.dart';
import 'presentation/router/app_router.dart';

/// Racine de l'application : thèmes jour/nuit, français, navigation.
class CrochetApp extends ConsumerWidget {
  const CrochetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode modeTheme = ref.watch(themeModeProvider);
    final Plateforme plateforme = ref.watch(plateformeProvider);

    return MaterialApp(
      title: AppConstants.nomApplication,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: modeTheme,
      // Application entièrement en français (calendriers, boutons système...).
      locale: const Locale('fr', 'FR'),
      supportedLocales: const <Locale>[Locale('fr', 'FR')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? child) {
        final Widget contenu = AdaptiveSystemOverlay(child: child ?? const SizedBox.shrink());
        if (!plateforme.fenetreDeBureau) return contenu;
        // Windows : la même interface que sur téléphone, à la largeur d'un téléphone, centrée dans la fenêtre
        // (le fond de la fenêtre reprend celui des écrans : pas de bande d'une autre couleur).
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Plateforme.largeurMaxContenu),
              child: contenu,
            ),
          ),
        );
      },
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
