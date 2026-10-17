import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/theme/theme_mode_provider.dart';
import 'data/database/app_database.dart';
import 'data/providers.dart';
import 'data/repositories/parametres_repository.dart';
import 'presentation/startup/erreur_demarrage_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Ouverture de la base avant le premier écran : création ou mise à jour du schéma,
    // puis lecture du mode jour / nuit mémorisé (pas de clignotement au démarrage).
    final AppDatabase base = AppDatabase();
    final ParametresRepository parametres = ParametresRepository(base);
    final ThemeMode modeInitial = await parametres.lireModeTheme();

    runApp(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(base),
          modeThemeInitialProvider.overrideWithValue(modeInitial),
          modeThemeStoreProvider.overrideWithValue(parametres),
        ],
        child: const CrochetApp(),
      ),
    );
  } catch (erreur, pile) {
    debugPrint('Ouverture de la base impossible : $erreur\n$pile');
    runApp(ErreurDemarrageApp(erreur: erreur));
  }
}
