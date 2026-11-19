// Test de démarrage de la VRAIE application (celle de lib/main.dart, avec sa vraie base SQLite et ses vrais dossiers).
//
// Lancé par le workflow « Windows » de GitHub Actions, sur un vrai Windows :
//   flutter test integration_test/demarrage_windows_test.dart -d windows
// Il prouve que l'application s'ouvre jusqu'à l'accueil (base de données, dossiers, thème, navigation). Les autres tests
// (dossier test/) tournent sur Linux ; celui-ci est le seul qui touche à Windows lui-même.

import 'dart:async';

import 'package:crochet_creations/core/plateforme.dart';
import 'package:crochet_creations/main.dart' as appli;
import 'package:crochet_creations/presentation/startup/erreur_demarrage_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('démarrage : la vraie application s’ouvre jusqu’à l’accueil', (WidgetTester tester) async {
    expect(Plateforme.courante().nom, 'Windows');

    unawaited(appli.main());

    // Splash, ouverture de la base, puis accueil : on attend la barre de navigation (30 s au plus).
    bool accueil = false;
    for (int i = 0; i < 150 && !accueil; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      accueil = find.byType(NavigationBar).evaluate().isNotEmpty;
    }
    expect(
      accueil,
      isTrue,
      reason: 'L’accueil ne s’est pas affiché (écran d’erreur de démarrage : ${find.byType(ErreurDemarrageApp).evaluate().isNotEmpty}).',
    );

    // Windows : le contenu garde la largeur d'un téléphone.
    expect(tester.getSize(find.byType(NavigationBar)).width, lessThanOrEqualTo(Plateforme.largeurMaxContenu));
    // Pas d'écran d'erreur de démarrage.
    expect(find.byType(ErreurDemarrageApp), findsNothing);
  });
}
