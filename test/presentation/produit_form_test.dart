import 'dart:io';

import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/produits/produits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Écran haut : le formulaire est long et n'est construit qu'à mesure qu'on défile.
const Size _grandEcran = Size(800, 4000);

Future<void> ouvrirFormulaireNouveau(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Produits'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(find.descendant(of: find.byType(ProduitsScreen), matching: find.text('Ajouter')));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

Future<void> choisirCategorie(WidgetTester tester, String libelle) async {
  await appuyer(tester, find.byType(DropdownButtonFormField<CategorieProduit>));
  await tester.tap(find.text(libelle).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un formulaire vide est refusé, champ par champ', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireNouveau(tester, env);

    await appuyer(tester, find.text('Ajouter le produit'));

    expect(find.text('Le nom du produit est obligatoire.'), findsOneWidget);
    expect(find.text('Choisissez une catégorie.'), findsOneWidget);
    expect(find.text('Le prix de vente est obligatoire.'), findsOneWidget);
    expect(find.text('Corrigez les champs signalés en rouge.'), findsOneWidget);
    expect(await env.travailler(tester, () => env.produits.lister()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('les montants et nombres invalides sont signalés', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireNouveau(tester, env);

    await saisir(tester, 'Nom du produit *', 'Bonnet');
    await choisirCategorie(tester, 'Accessoire');
    await saisir(tester, 'Prix de vente (€) *', '12,345');
    await saisir(tester, 'Coût des matières (€)', 'abc');
    await saisir(tester, 'Minutes', '75');
    await appuyer(tester, find.text('Ajouter le produit'));

    expect(find.text('Montant invalide (exemple : 12,50).'), findsNWidgets(2));
    expect(find.text('Valeur trop grande (maximum 59).'), findsOneWidget);
    expect(await env.travailler(tester, () => env.produits.lister()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('création : le produit est enregistré et sa fiche s’ouvre', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireNouveau(tester, env);

    await saisir(tester, 'Nom du produit *', '  Bonnet lama  ');
    await choisirCategorie(tester, 'Accessoire');
    await saisir(tester, 'Matières', 'Coton');
    await saisir(tester, 'Heures', '2');
    await saisir(tester, 'Minutes', '30');
    await saisir(tester, 'Coût des matières (€)', '3,2');
    await saisir(tester, 'Prix de vente (€) *', '12,50');
    await saisir(tester, 'Quantité en stock', '4');
    await saisir(tester, 'Seuil d’alerte', '1');
    await appuyer(tester, find.text('Ajouter le produit'));

    // La fiche du nouveau produit est affichée.
    expect(find.text('Produit ajouté.'), findsOneWidget);
    expect(find.text('PRD-0001 · Accessoire'), findsOneWidget);
    expect(find.text(formatEuros(1250)), findsOneWidget);
    expect(find.text('2 h 30'), findsOneWidget);
    expect(find.text(formatEuros(320)), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('stock-total')), findsOneWidget);

    final List<Produit> produits = await env.travailler(tester, () => env.produits.lister());
    expect(produits, hasLength(1));
    final Produit p = produits.single;
    expect(p.nom, 'Bonnet lama');
    expect(p.categorie, CategorieProduit.accessoire);
    expect(p.prixVenteCentimes, 1250);
    expect(p.coutMatiereCentimes, 320);
    expect(p.tempsFabricationMinutes, 150);
    expect(p.quantiteStock, 4);
    expect(p.seuilAlerteStock, 1);
    expect(p.statut, StatutProduit.disponible);
    expect(p.personnalisable, isFalse);

    await env.fermer(tester);
  });

  testWidgets('statut, personnalisable et produit sur commande', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireNouveau(tester, env);

    await saisir(tester, 'Nom du produit *', 'Pull');
    await choisirCategorie(tester, 'Sur mesure');
    await saisir(tester, 'Prix de vente (€) *', '80');
    await appuyer(tester, find.byType(DropdownButtonFormField<StatutProduit>));
    await tester.tap(find.text('Sur commande').last);
    await tester.pumpAndSettle();
    expect(find.text('Le stock d’un produit sur commande n’est pas suivi.'), findsOneWidget);
    await appuyer(tester, find.byType(SwitchListTile));
    await appuyer(tester, find.text('Ajouter le produit'));

    final Produit p = (await env.travailler(tester, () => env.produits.lister())).single;
    expect(p.statut, StatutProduit.surCommande);
    expect(p.personnalisable, isTrue);
    expect(p.prixVenteCentimes, 8000);

    await env.fermer(tester);
  });

  testWidgets('modification : les valeurs sont reprises et enregistrées', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester, matieres: 'Coton bio');
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await tester.tap(ongletNav('Produits'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(find.descendant(of: find.byType(ProduitsScreen), matching: find.text('Doudou lapin')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    await saisir(tester, 'Nom du produit *', 'Doudou renard');
    await saisir(tester, 'Prix de vente (€) *', '27,90');
    await appuyer(tester, find.text('Enregistrer les modifications'));

    // Retour à la fiche, mise à jour.
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
    expect(find.text('Doudou renard'), findsWidgets);
    expect(find.text(formatEuros(2790)), findsOneWidget);

    final Produit apres = (await env.travailler(tester, () => env.produits.obtenir(p.id)))!;
    expect(apres.nom, 'Doudou renard');
    expect(apres.prixVenteCentimes, 2790);
    expect(apres.reference, 'PRD-0001');
    expect(apres.matieres, 'Coton bio');
    expect(apres.quantiteStock, 5);

    await env.fermer(tester);
  });

  testWidgets('quitter un formulaire modifié demande confirmation', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireNouveau(tester, env);

    await saisir(tester, 'Nom du produit *', 'Brouillon');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);

    // On continue la saisie : le formulaire reste ouvert.
    await tester.tap(find.text('Continuer la saisie'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau produit'), findsOneWidget);

    // On abandonne : retour à la liste, rien n'est enregistré.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau produit'), findsNothing);
    expect(await env.travailler(tester, () => env.produits.lister()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('quitter un formulaire intact ne demande rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireNouveau(tester, env);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Abandonner les modifications ?'), findsNothing);
    expect(find.text('Nouveau produit'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('un produit avec variantes : le stock du produit n’est plus modifiable ici', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await env.travailler(
      tester,
      () => env.produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose', quantiteStock: 3)),
    );
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await tester.tap(ongletNav('Produits'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(find.descendant(of: find.byType(ProduitsScreen), matching: find.text('Doudou lapin')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.widgetWithText(TextFormField, 'Quantité en stock'), findsNothing);
    expect(find.textContaining('Ce produit a des variantes'), findsOneWidget);

    await saisir(tester, 'Prix de vente (€) *', '30');
    await appuyer(tester, find.text('Enregistrer les modifications'));

    // Le stock enregistré dans le produit n'a pas été touché.
    final Produit apres = (await env.travailler(tester, () => env.produits.obtenir(p.id)))!;
    expect(apres.quantiteStock, 5);
    expect(apres.prixVenteCentimes, 3000);

    await env.fermer(tester);
  });

  testWidgets('photo principale : copiée dans l’application, enregistrée avec un chemin relatif', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.selecteur.chemin = await env.photoGalerie(tester, 'IMG_0001.jpg');
    await ouvrirFormulaireNouveau(tester, env);

    await saisir(tester, 'Nom du produit *', 'Bonnet photo');
    await choisirCategorie(tester, 'Accessoire');
    await saisir(tester, 'Prix de vente (€) *', '10');
    await appuyer(tester, find.text('Ajouter la photo principale'));
    await appuyer(tester, find.text('Choisir dans la galerie'));
    await laisserFinir(tester);
    expect(env.selecteur.appels, 1);

    await appuyer(tester, find.text('Ajouter le produit'));
    await laisserFinir(tester);

    final Produit p = (await env.travailler(tester, () => env.produits.lister())).single;
    expect(p.photoPrincipaleChemin, isNotNull);
    expect(p.photoPrincipaleChemin, isNot(contains('/'))); // nom de fichier, pas chemin complet
    final bool existe = await env.travailler(
      tester,
      () => File('${env.dossierPhotos.path}/${p.photoPrincipaleChemin}').exists(),
    );
    expect(existe, isTrue);

    await env.fermer(tester);
  });

  testWidgets('abandonner le formulaire supprime les photos copiées pour rien', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.selecteur.chemin = await env.photoGalerie(tester, 'IMG_0002.jpg');
    await ouvrirFormulaireNouveau(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    await appuyer(tester, find.text('Choisir dans la galerie'));
    await laisserFinir(tester);
    final int avant = await env.travailler(
      tester,
      () async => env.dossierPhotos.existsSync() ? env.dossierPhotos.listSync().length : 0,
    );
    expect(avant, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    final int apres = await env.travailler(tester, () async => env.dossierPhotos.listSync().length);
    expect(apres, 0);

    await env.fermer(tester);
  });

  testWidgets('si l’utilisatrice annule le choix de photo, rien ne change', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.selecteur.chemin = null;
    await ouvrirFormulaireNouveau(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    await appuyer(tester, find.text('Prendre une photo'));
    await laisserFinir(tester);

    expect(env.selecteur.appels, 1);
    expect(find.text('Ajouter la photo principale'), findsOneWidget);
    // Rien n'a changé : on peut quitter sans confirmation.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsNothing);

    await env.fermer(tester);
  });
}
