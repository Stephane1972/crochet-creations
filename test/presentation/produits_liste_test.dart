import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/home/home_screen.dart';
import 'package:crochet_creations/presentation/produits/produits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Cherche dans l'onglet Produits uniquement (les autres onglets restent construits mais masqués).
Finder dansProduits(Finder cible) =>
    find.descendant(of: find.byType(ProduitsScreen), matching: cible);

Finder champRecherche() => dansProduits(find.byType(TextField));

/// Appuie sur une puce de filtre. La rangée de puces défile : celles qui sortent de l'écran ne sont
/// plus construites, on revient donc au début puis on avance jusqu'à la puce voulue.
Future<void> appuyerPuce(WidgetTester tester, Finder puce) async {
  // La zone de saisie contient aussi un défilement horizontal : on cible celui de la rangée de puces.
  final Finder defilement = find.descendant(
    of: dansProduits(
      find.byWidgetPredicate((Widget w) => w is ListView && w.scrollDirection == Axis.horizontal),
    ),
    matching: find.byType(Scrollable),
  );
  await tester.drag(defilement, const Offset(5000, 0)); // retour au début de la rangée
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(puce, 150, scrollable: defilement);
  await tester.pumpAndSettle(); // le défilement final doit être terminé avant d'appuyer
  await tester.tap(puce);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Quatre produits aux situations de stock différentes.
Future<void> garnirCatalogue(WidgetTester tester, EnvironnementTest env) async {
  await env.creerProduit(tester, matieres: 'Coton bio'); // PRD-0001 : 5 en stock
  await env.creerProduit(
    tester,
    nom: 'Écharpe en laine',
    categorie: CategorieProduit.crochet,
    prix: 3200,
    stock: 0,
  ); // épuisé
  await env.creerProduit(
    tester,
    nom: 'Boucles soleil',
    categorie: CategorieProduit.bouclesOreilles,
    prix: 1200,
    stock: 1,
  ); // stock faible
  await env.creerProduit(
    tester,
    nom: 'Pull sur mesure',
    categorie: CategorieProduit.surMesure,
    prix: 8000,
    stock: 0,
    statut: StatutProduit.surCommande,
  );
}

Future<void> ouvrirProduits(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env);
  await tester.tap(ongletNav('Produits'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

void main() {
  testWidgets('catalogue vide : message d’accueil', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProduits(tester, env);

    expect(find.text('Aucun produit pour le moment'), findsOneWidget);
    expect(dansProduits(find.text('Ajouter')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('la liste affiche nom, référence, prix, stock et alertes', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    await ouvrirProduits(tester, env);

    for (final String nom in <String>[
      'Doudou lapin',
      'Écharpe en laine',
      'Boucles soleil',
      'Pull sur mesure',
    ]) {
      expect(dansProduits(find.text(nom)), findsOneWidget, reason: nom);
    }
    expect(dansProduits(find.text('PRD-0001 · Doudou')), findsOneWidget);
    expect(dansProduits(find.text(formatEuros(2500))), findsOneWidget);
    expect(dansProduits(find.text('5 en stock')), findsOneWidget);
    expect(dansProduits(find.text('1 en stock')), findsOneWidget);

    // Alertes : un produit épuisé, un à stock faible ; « sur commande » n'a jamais d'alerte.
    expect(dansProduits(find.text('Épuisé')), findsOneWidget);
    expect(dansProduits(find.text('Stock faible')), findsOneWidget);
    expect(dansProduits(find.text('Sur commande')), findsOneWidget);
    expect(dansProduits(find.text('Fabriqué à la demande')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('la recherche ignore les accents et les majuscules', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    await ouvrirProduits(tester, env);

    await tester.enterText(champRecherche(), 'ECHARPE');
    await tester.pumpAndSettle();
    expect(dansProduits(find.text('Écharpe en laine')), findsOneWidget);
    expect(dansProduits(find.text('Doudou lapin')), findsNothing);

    // On cherche aussi dans les matières et dans la référence.
    await tester.enterText(champRecherche(), 'coton');
    await tester.pumpAndSettle();
    expect(dansProduits(find.text('Doudou lapin')), findsOneWidget);
    expect(dansProduits(find.text('Écharpe en laine')), findsNothing);

    await tester.enterText(champRecherche(), 'prd-0003');
    await tester.pumpAndSettle();
    expect(dansProduits(find.text('Boucles soleil')), findsOneWidget);

    // Rien de trouvé : message et bouton pour retirer les filtres.
    await tester.enterText(champRecherche(), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun produit trouvé'), findsOneWidget);
    await tester.tap(find.text('Retirer les filtres'));
    await tester.pumpAndSettle();
    expect(dansProduits(find.text('Doudou lapin')), findsOneWidget);
    expect(dansProduits(find.text('Écharpe en laine')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('filtre par catégorie', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    await ouvrirProduits(tester, env);

    await appuyerPuce(tester, dansProduits(find.widgetWithText(ChoiceChip, 'Doudou')));
    expect(dansProduits(find.text('Doudou lapin')), findsOneWidget);
    expect(dansProduits(find.text('Écharpe en laine')), findsNothing);

    await appuyerPuce(tester, dansProduits(find.widgetWithText(ChoiceChip, 'Tous')));
    expect(dansProduits(find.text('Écharpe en laine')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('filtre « À réapprovisionner »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    await ouvrirProduits(tester, env);

    // Épuisé + stock faible = 2 produits à réapprovisionner.
    final Finder puce = dansProduits(find.widgetWithText(FilterChip, 'À réapprovisionner (2)'));
    expect(puce, findsOneWidget);
    await appuyerPuce(tester, puce);

    expect(dansProduits(find.text('Écharpe en laine')), findsOneWidget);
    expect(dansProduits(find.text('Boucles soleil')), findsOneWidget);
    expect(dansProduits(find.text('Doudou lapin')), findsNothing);
    expect(dansProduits(find.text('Pull sur mesure')), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('les produits archivés sont masqués sauf si on le demande', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    final int id = (await env.travailler(tester, () => env.produits.lister())).first.id;
    await env.travailler(tester, () => env.produits.archiver(id));
    await ouvrirProduits(tester, env);

    final String nomArchive = (await env.travailler(tester, () => env.produits.obtenir(id)))!.nom;
    expect(dansProduits(find.text(nomArchive)), findsNothing);

    await appuyerPuce(tester, dansProduits(find.widgetWithText(FilterChip, 'Archivés')));
    expect(dansProduits(find.text(nomArchive)), findsOneWidget);
    expect(dansProduits(find.text('Archivé')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('un appui sur un produit ouvre sa fiche', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    await ouvrirProduits(tester, env);

    await tester.tap(dansProduits(find.text('Boucles soleil')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.text('Historique des ventes'), findsOneWidget);
    expect(find.text('Boucles soleil'), findsWidgets);

    await env.fermer(tester);
  });

  testWidgets('le bouton « Ajouter » ouvre le formulaire de nouveau produit', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProduits(tester, env);

    await tester.tap(dansProduits(find.text('Ajouter')));
    await tester.pumpAndSettle();

    expect(find.text('Nouveau produit'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('la tuile « Stock faible » de l’accueil compte les alertes et ouvre la liste filtrée', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirCatalogue(tester, env);
    await ouvrirAccueil(tester, env);

    final Finder tuile = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.widgetWithText(Card, 'Stock faible'),
    );
    expect(find.descendant(of: tuile, matching: find.text('2')), findsOneWidget);

    await tester.tap(tuile);
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(dansProduits(find.text('Écharpe en laine')).hitTestable(), findsOneWidget);
    expect(dansProduits(find.text('Boucles soleil')).hitTestable(), findsOneWidget);
    expect(dansProduits(find.text('Doudou lapin')), findsNothing);

    await env.fermer(tester);
  });
}
