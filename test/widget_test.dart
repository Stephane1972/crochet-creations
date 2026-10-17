import 'package:crochet_creations/app.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:crochet_creations/presentation/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Démarre l'application, attend la fin du splash et arrive sur l'accueil.
Future<void> ouvrirAccueil(WidgetTester tester) async {
  // Écran haut, comme un téléphone : évite de faire défiler dans les tests.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: CrochetApp()));
  expect(find.text('Crochet & Créations'), findsOneWidget); // splash

  await tester.pump(SplashScreen.duree + const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Finder ongletNav(String libelle) {
  return find.descendant(of: find.byType(NavigationBar), matching: find.text(libelle));
}

void main() {
  testWidgets('le splash mène à l’accueil avec ses 5 onglets', (WidgetTester tester) async {
    await ouvrirAccueil(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String libelle in <String>['Accueil', 'Produits', 'Vente', 'Clients', 'Plus']) {
      expect(ongletNav(libelle), findsOneWidget, reason: 'onglet $libelle');
    }
    expect(find.text('Actions rapides'), findsOneWidget);
    expect(find.text('Franchise de TVA'), findsOneWidget);
  });

  testWidgets('« Nouvelle vente » ouvre l’onglet Vente', (WidgetTester tester) async {
    await ouvrirAccueil(tester);

    // « Nouvelle vente » existe aussi comme titre de l'onglet Vente (masqué) :
    // on cible donc la tuile de l'accueil, la seule sur laquelle on peut appuyer.
    await tester.tap(find.text('Nouvelle vente').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Prévu à l’étape 5 sur 12').hitTestable(), findsOneWidget);
  });

  testWidgets('« Nouveau devis » ouvre un écran « Bientôt disponible »', (WidgetTester tester) async {
    await ouvrirAccueil(tester);

    await tester.tap(find.text('Nouveau devis'));
    await tester.pumpAndSettle();

    expect(find.text('Bientôt disponible'), findsOneWidget);
    expect(find.text('Prévu à l’étape 7 sur 12'), findsOneWidget);
  });

  testWidgets('le choix « Nuit » des réglages bascule le thème', (WidgetTester tester) async {
    await ouvrirAccueil(tester);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();

    final BuildContext contexte = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(contexte).brightness, Brightness.light);

    await tester.tap(find.text('Nuit'));
    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.dark);

    await tester.tap(find.text('Jour'));
    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.light);
  });
}
