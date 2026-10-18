import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'presentation/aide_widget.dart';

void main() {
  testWidgets('le splash mène à l’accueil avec ses 5 onglets', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String libelle in <String>['Accueil', 'Produits', 'Vente', 'Clients', 'Plus']) {
      expect(ongletNav(libelle), findsOneWidget, reason: 'onglet $libelle');
    }
    expect(find.text('Actions rapides'), findsOneWidget);
    expect(find.text('Franchise de TVA'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('« Nouvelle vente » ouvre l’onglet Vente', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

    // « Nouvelle vente » existe aussi comme titre de l'onglet Vente (masqué) :
    // on cible donc la tuile de l'accueil, la seule sur laquelle on peut appuyer.
    await tester.tap(find.text('Nouvelle vente').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Prévu à l’étape 5 sur 12').hitTestable(), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('« Nouveau devis » ouvre un écran « Bientôt disponible »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

    await tester.tap(find.text('Nouveau devis'));
    await tester.pumpAndSettle();

    expect(find.text('Bientôt disponible'), findsOneWidget);
    expect(find.text('Prévu à l’étape 7 sur 12'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('« Ajouter un produit » ouvre le formulaire de nouveau produit', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

    await tester.tap(find.text('Ajouter un produit'));
    await tester.pumpAndSettle();

    expect(find.text('Nouveau produit'), findsOneWidget);
    expect(find.text('Nom du produit *'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('le choix « Nuit » des réglages bascule le thème', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

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

    await env.fermer(tester);
  });
}
