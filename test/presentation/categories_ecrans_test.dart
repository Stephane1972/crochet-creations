import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/produits/categories_screen.dart';
import 'package:crochet_creations/presentation/produits/produits_screen.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(1000, 3000);

Finder dansEcran(Finder cible) => find.descendant(of: find.byType(CategoriesScreen), matching: cible);
Finder dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

/// Onglet Plus → Réglages → Catégories.
Future<void> ouvrirCategories(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Plus'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Réglages')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);

  await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Catégories')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
  expect(find.byType(CategoriesScreen), findsOneWidget);
}

Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.tap(cible);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.pumpAndSettle();
}

Future<void> saisirNom(WidgetTester tester, String texte) async {
  await tester.enterText(dansDialogue(find.byType(TextField)), texte);
  await tester.pump();
}

Future<CategorieProduit> categorie(WidgetTester tester, EnvironnementTest env, String cle) async {
  final CategorieProduit? trouvee = await env.travailler<CategorieProduit?>(
    tester,
    () => env.categories.parCle(cle),
  );
  return trouvee!;
}

void main() {
  testWidgets('l’écran est atteint depuis Réglages et montre les cinq catégories avec leur nombre de produits', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, nom: 'Lapin', categorie: CleCategorie.doudou);
    await env.creerProduit(tester, nom: 'Ours', categorie: CleCategorie.doudou);
    await env.creerProduit(tester, nom: 'Plaid', categorie: CleCategorie.crochet);
    await ouvrirCategories(tester, env);

    for (final String nom in <String>['Crochet', 'Doudou', 'Boucles d’oreilles', 'Accessoire', 'Sur mesure']) {
      expect(dansEcran(find.text(nom)), findsOneWidget, reason: nom);
    }
    expect(dansEcran(find.text('2 produits')), findsOneWidget);
    expect(dansEcran(find.text('1 produit')), findsOneWidget);
    expect(dansEcran(find.text('Aucun produit')), findsNWidgets(3));

    await env.fermer(tester);
  });

  group('ajouter', () {
    testWidgets('une nouvelle catégorie apparaît à la fin de la liste', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.text('Nouvelle catégorie'));
      expect(find.byType(AlertDialog), findsOneWidget);
      await saisirNom(tester, '  Peluches ');
      await toucher(tester, dansDialogue(find.text('Créer')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(dansEcran(find.text('Peluches')), findsOneWidget);
      expect(find.text('Catégorie « Peluches » créée.'), findsOneWidget);
      final List<CategorieProduit> toutes = await env.travailler(tester, () => env.categories.lister());
      expect(toutes.map((CategorieProduit c) => c.nom).last, 'Peluches');

      await env.fermer(tester);
    });

    testWidgets('un nom vide ou déjà pris est expliqué dans la boîte, qui reste ouverte', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.text('Nouvelle catégorie'));
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(find.text('Donnez un nom à la catégorie.'), findsOneWidget);

      await saisirNom(tester, 'doudou');
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(find.text('Une catégorie « Doudou » existe déjà.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await toucher(tester, dansDialogue(find.text('Annuler')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(await env.travailler(tester, () => env.categories.lister()), hasLength(5));

      await env.fermer(tester);
    });
  });

  group('renommer', () {
    testWidgets('le nouveau nom s’affiche, les produits restent dans la catégorie', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit p = await env.creerProduit(tester, nom: 'Lapin', categorie: CleCategorie.doudou);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Renommer Doudou'));
      expect(tester.widget<TextField>(dansDialogue(find.byType(TextField))).controller!.text, 'Doudou');
      await saisirNom(tester, 'Peluches douces');
      await toucher(tester, dansDialogue(find.text('Enregistrer')));

      expect(dansEcran(find.text('Peluches douces')), findsOneWidget);
      expect(dansEcran(find.text('Doudou')), findsNothing);
      expect(find.text('Catégorie renommée « Peluches douces ».'), findsOneWidget);
      final Produit apres = (await env.travailler(tester, () => env.produits.obtenir(p.id)))!;
      expect(apres.categorie, CleCategorie.doudou);
      expect((await categorie(tester, env, CleCategorie.doudou)).nom, 'Peluches douces');

      await env.fermer(tester);
    });

    testWidgets('le nom d’une autre catégorie est refusé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Renommer Doudou'));
      await saisirNom(tester, 'crochet');
      await toucher(tester, dansDialogue(find.text('Enregistrer')));

      expect(find.text('Une catégorie « Crochet » existe déjà.'), findsOneWidget);
      expect((await categorie(tester, env, CleCategorie.doudou)).nom, 'Doudou');

      await env.fermer(tester);
    });
  });

  group('supprimer', () {
    testWidgets('une catégorie vide : une confirmation, puis elle disparaît', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Sur mesure'));
      expect(find.text('Supprimer cette catégorie ?'), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Supprimer')));

      expect(dansEcran(find.text('Sur mesure')), findsNothing);
      expect(find.text('Catégorie « Sur mesure » supprimée.'), findsOneWidget);
      expect(await env.travailler(tester, () => env.categories.parCle(CleCategorie.surMesure)), isNull);

      await env.fermer(tester);
    });

    testWidgets('annuler la confirmation ne supprime rien', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Sur mesure'));
      await toucher(tester, dansDialogue(find.text('Annuler')));

      expect(dansEcran(find.text('Sur mesure')), findsOneWidget);
      expect(await env.travailler(tester, () => env.categories.lister()), hasLength(5));

      await env.fermer(tester);
    });

    testWidgets('avec des produits : on choisit où les déplacer, et ils y vont', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester, nom: 'Lapin', categorie: CleCategorie.doudou);
      final Produit ours = await env.creerProduit(tester, nom: 'Ours', categorie: CleCategorie.doudou);
      await env.travailler(tester, () => env.produits.archiver(ours.id));
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Doudou'));
      expect(dansDialogue(find.textContaining('contient 2 produits')), findsOneWidget);

      // Rien n'est présélectionné : le bouton attend un choix.
      Finder bouton = dansDialogue(find.widgetWithText(FilledButton, 'Déplacer et supprimer'));
      expect(tester.widget<FilledButton>(bouton).onPressed, isNull);
      // La catégorie qu'on supprime ne fait pas partie des destinations.
      expect(dansDialogue(find.text('Doudou')), findsNothing);

      await tester.tap(dansDialogue(find.text('Accessoire')));
      await tester.pump();
      bouton = dansDialogue(find.widgetWithText(FilledButton, 'Déplacer et supprimer'));
      expect(tester.widget<FilledButton>(bouton).onPressed, isNotNull);
      await toucher(tester, bouton);

      expect(dansEcran(find.text('Doudou')), findsNothing);
      expect(
        find.text('Catégorie « Doudou » supprimée. 2 produits déplacés vers « Accessoire ».'),
        findsOneWidget,
      );
      expect(dansEcran(find.text('2 produits')), findsOneWidget);
      expect((await env.travailler(tester, () => env.produits.obtenir(lapin.id)))!.categorie, CleCategorie.accessoire);
      expect((await env.travailler(tester, () => env.produits.obtenir(ours.id)))!.categorie, CleCategorie.accessoire);

      await env.fermer(tester);
    });

    testWidgets('annuler le choix de la destination ne change rien', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester, nom: 'Lapin', categorie: CleCategorie.doudou);
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Doudou'));
      expect(dansDialogue(find.textContaining('contient 1 produit')), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Annuler')));

      expect(dansEcran(find.text('Doudou')), findsOneWidget);
      expect((await env.travailler(tester, () => env.produits.obtenir(lapin.id)))!.categorie, CleCategorie.doudou);

      await env.fermer(tester);
    });

    testWidgets('la seule catégorie qui contient des produits ne peut pas être supprimée', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.creerProduit(tester, nom: 'Lapin', categorie: CleCategorie.doudou);
      for (final String cle in <String>[
        CleCategorie.crochet,
        CleCategorie.bouclesOreilles,
        CleCategorie.accessoire,
        CleCategorie.surMesure,
      ]) {
        final CategorieProduit c = await categorie(tester, env, cle);
        await env.travailler(tester, () => env.categories.supprimer(c.id));
      }
      await ouvrirCategories(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Doudou'));

      expect(find.text('Suppression impossible'), findsOneWidget);
      expect(dansDialogue(find.textContaining('Créez d’abord une autre catégorie')), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Fermer')));
      expect(dansEcran(find.text('Doudou')), findsOneWidget);

      await env.fermer(tester);
    });
  });

  testWidgets('sans aucune catégorie, l’écran invite à en créer une', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    for (final CategorieProduit c in await env.travailler(tester, () => env.categories.lister())) {
      await env.travailler(tester, () => env.categories.supprimer(c.id));
    }
    await ouvrirCategories(tester, env);

    expect(dansEcran(find.textContaining('Aucune catégorie')), findsOneWidget);

    await env.fermer(tester);
  });

  group('liste des produits', () {
    Finder dansProduits(Finder cible) => find.descendant(of: find.byType(ProduitsScreen), matching: cible);

    Future<void> ouvrirProduits(WidgetTester tester, EnvironnementTest env) async {
      await ouvrirAccueil(tester, env);
      await tester.tap(ongletNav('Produits'));
      await tester.pumpAndSettle();
      await laisserFinir(tester);
    }

    testWidgets('une catégorie créée a sa puce et son nom s’affiche sur les produits', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final CategorieProduit peluches = await env.travailler(tester, () => env.categories.creer('Peluches'));
      await env.creerProduit(tester, nom: 'Renard', categorie: peluches.cle);
      await ouvrirProduits(tester, env);

      expect(dansProduits(find.widgetWithText(ChoiceChip, 'Peluches')), findsOneWidget);
      expect(dansProduits(find.text('PRD-0001 · Peluches')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('supprimer la catégorie filtrée enlève le filtre au lieu de laisser une liste vide', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.creerProduit(tester, nom: 'Lapin', categorie: CleCategorie.doudou);
      await env.creerProduit(tester, nom: 'Plaid', categorie: CleCategorie.crochet);
      await ouvrirProduits(tester, env);

      await tester.tap(dansProduits(find.widgetWithText(ChoiceChip, 'Doudou')));
      await tester.pumpAndSettle();
      expect(dansProduits(find.text('Plaid')), findsNothing);

      final CategorieProduit doudou = await categorie(tester, env, CleCategorie.doudou);
      await env.ecrireEcranOuvert(
        tester,
        () => env.categories.supprimer(doudou.id, deplacerVersCle: CleCategorie.crochet),
      );
      await laisserFinir(tester);

      expect(dansProduits(find.widgetWithText(ChoiceChip, 'Doudou')), findsNothing);
      expect(tester.widget<ChoiceChip>(dansProduits(find.widgetWithText(ChoiceChip, 'Tous'))).selected, isTrue);
      expect(dansProduits(find.text('Lapin')), findsOneWidget);
      expect(dansProduits(find.text('Plaid')), findsOneWidget);

      await env.fermer(tester);
    });
  });
}
