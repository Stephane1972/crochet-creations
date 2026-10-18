import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/produits/produits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Ouvre la fiche du produit [nom] depuis l'onglet Produits.
Future<void> ouvrirFiche(WidgetTester tester, EnvironnementTest env, String nom) async {
  await ouvrirAccueil(tester, env);
  await tester.tap(ongletNav('Produits'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(
    find.descendant(of: find.byType(ProduitsScreen), matching: find.text(nom)),
  );
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

Finder stockTotal() => find.byKey(const ValueKey<String>('stock-total'));

String texteDe(WidgetTester tester, Finder cible) => tester.widget<Text>(cible).data ?? '';

/// Vrai si le bouton portant ce libellé peut être actionné (les boutons « avec icône » sont des
/// sous-classes privées : on les retrouve par leur type de base).
bool boutonActif(WidgetTester tester, String libelle) {
  final Finder bouton = find.ancestor(
    of: find.text(libelle),
    matching: find.bySubtype<ButtonStyleButton>(),
  );
  return tester.widget<ButtonStyleButton>(bouton.first).onPressed != null;
}

Future<void> ouvrirMenuProduit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus d’actions'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('la fiche affiche les informations du produit', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.travailler(
      tester,
      () => env.produits.creer(
        const DonneesProduit(
          nom: 'Doudou lapin',
          categorie: CategorieProduit.doudou,
          prixVenteCentimes: 2500,
          coutMatiereCentimes: 600,
          tempsFabricationMinutes: 150,
          matieres: 'Coton bio',
          couleur: 'Beige',
          dimensions: '25 cm',
          description: 'Un doudou tout doux',
          quantiteStock: 5,
          seuilAlerteStock: 2,
          personnalisable: true,
        ),
      ),
    );
    await ouvrirFiche(tester, env, 'Doudou lapin');

    expect(find.text('PRD-0001 · Doudou'), findsOneWidget);
    expect(find.text(formatEuros(2500)), findsOneWidget);
    for (final String texte in <String>[
      'Coton bio',
      'Beige',
      '25 cm',
      'Un doudou tout doux',
      '2 h 30',
      formatEuros(600),
      'Oui',
    ]) {
      expect(find.text(texte), findsOneWidget, reason: texte);
    }
    expect(texteDe(tester, stockTotal()), '5 en stock');
    expect(find.text('Alerte quand il en reste 2 ou moins.'), findsOneWidget);
    expect(find.text('Aucune vente pour ce produit pour l’instant.'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('l’historique liste les ventes du produit', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await env.ajouterVente(tester, produitId: p.id, quantite: 2, date: DateTime(2026, 3, 5));
    await ouvrirFiche(tester, env, 'Doudou lapin');

    expect(find.text('2 vendus en 1 vente'), findsOneWidget);
    expect(find.text(formatEuros(5000)), findsOneWidget);
    expect(
      find.text('${formatDateCourte(DateTime(2026, 3, 5))} · 2 × ${formatEuros(2500)}'),
      findsOneWidget,
    );

    await env.fermer(tester);
  });

  testWidgets('un produit épuisé affiche l’alerte et ne peut pas être vendu', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, stock: 0);
    await ouvrirFiche(tester, env, 'Doudou lapin');

    expect(find.text('Épuisé'), findsOneWidget);
    expect(find.text('Aucun en stock'), findsWidgets);
    expect(boutonActif(tester, 'Vendre'), isFalse);
    expect(boutonActif(tester, 'Ajouter au panier'), isFalse);
    expect(find.textContaining('Il n’en reste plus en stock'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('« Vendre » ouvre l’onglet Vente', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirFiche(tester, env, 'Doudou lapin');

    expect(boutonActif(tester, 'Vendre'), isTrue);
    expect(boutonActif(tester, 'Ajouter au panier'), isTrue);
    await tester.tap(find.text('Vendre'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Prévu à l’étape 5 sur 12').hitTestable(), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('ajuster le stock : nouvelle quantité enregistrée', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await ouvrirFiche(tester, env, 'Doudou lapin');

    await appuyer(tester, find.text('Ajuster le stock'));
    final Finder champ = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));

    // Champ vidé : message d'erreur, rien n'est enregistré.
    await tester.enterText(champ, '');
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pump();
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);

    await tester.enterText(champ, '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(texteDe(tester, stockTotal()), '12 en stock');
    expect(find.text('Stock mis à jour : 12.'), findsOneWidget);
    expect((await env.travailler(tester, () => env.produits.obtenir(p.id)))!.quantiteStock, 12);

    await env.fermer(tester);
  });

  testWidgets('archiver demande confirmation, puis le produit peut être restauré', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await ouvrirFiche(tester, env, 'Doudou lapin');

    // On annule : rien ne change.
    await ouvrirMenuProduit(tester);
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    expect(find.text('Archiver ce produit ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect((await env.travailler(tester, () => env.produits.obtenir(p.id)))!.archiveLe, isNull);

    // On confirme.
    await ouvrirMenuProduit(tester);
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archiver'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.text('Produit archivé : il n’apparaît plus dans le catalogue.'), findsOneWidget);
    expect((await env.travailler(tester, () => env.produits.obtenir(p.id)))!.archiveLe, isNotNull);
    expect(boutonActif(tester, 'Vendre'), isFalse);

    // Restauration depuis le bandeau.
    await tester.tap(find.widgetWithText(TextButton, 'Restaurer'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(find.text('Produit archivé : il n’apparaît plus dans le catalogue.'), findsNothing);
    expect((await env.travailler(tester, () => env.produits.obtenir(p.id)))!.archiveLe, isNull);

    await env.fermer(tester);
  });

  testWidgets('variantes : ajout, stock par variante, nom déjà pris refusé', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirFiche(tester, env, 'Doudou lapin');

    Future<void> ajouterVariante(String nom, String stock) async {
      await appuyer(tester, find.text('Ajouter'));
      await saisir(tester, 'Nom de la variante *', nom);
      final Finder champStock = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(TextFormField, 'Stock'),
      );
      await tester.enterText(champStock, stock);
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      await laisserFinir(tester);
    }

    await ajouterVariante('Rose', '3');
    expect(find.text('Rose'), findsOneWidget);
    expect(find.text('Variante ajoutée.'), findsOneWidget);
    // Le stock du produit (5) est remplacé par celui de ses variantes (3).
    expect(texteDe(tester, stockTotal()), '3 en stock');
    // Plus de bouton d'ajustement global : le stock se règle par variante.
    expect(find.text('Ajuster le stock'), findsNothing);

    await ajouterVariante('rose', '1');
    expect(find.textContaining('existe déjà'), findsOneWidget);
    expect(texteDe(tester, stockTotal()), '3 en stock');

    await env.fermer(tester);
  });

  testWidgets('ajuster le stock d’une variante', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await env.travailler(
      tester,
      () => env.produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Bleu', quantiteStock: 4)),
    );
    await ouvrirFiche(tester, env, 'Doudou lapin');

    await appuyer(tester, find.byTooltip('Actions sur la variante Bleu'));
    await tester.tap(find.text('Ajuster le stock'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)),
      '9',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(texteDe(tester, stockTotal()), '9 en stock');

    await env.fermer(tester);
  });

  testWidgets('archiver une variante, puis la restaurer', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await env.travailler(
      tester,
      () => env.produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Bleu', quantiteStock: 4)),
    );
    await ouvrirFiche(tester, env, 'Doudou lapin');

    await appuyer(tester, find.byTooltip('Actions sur la variante Bleu'));
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    expect(find.text('Archiver cette variante ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archiver'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.text('Variantes archivées (1)'), findsOneWidget);
    expect(texteDe(tester, stockTotal()), '5 en stock'); // retour au stock du produit

    await appuyer(tester, find.text('Variantes archivées (1)'));
    await appuyer(tester, find.widgetWithText(TextButton, 'Restaurer'));
    expect(find.text('Variantes archivées (1)'), findsNothing);
    expect(texteDe(tester, stockTotal()), '4 en stock');

    await env.fermer(tester);
  });

  testWidgets('dupliquer ouvre la copie en modification', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirFiche(tester, env, 'Doudou lapin');

    await ouvrirMenuProduit(tester);
    await tester.tap(find.text('Dupliquer'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.text('Modifier le produit'), findsOneWidget);
    expect(find.text('Référence : PRD-0002'), findsOneWidget);
    expect(find.text('Doudou lapin (copie)'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('le bouton « Modifier » ouvre le formulaire pré-rempli', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, matieres: 'Coton bio');
    await ouvrirFiche(tester, env, 'Doudou lapin');

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.text('Modifier le produit'), findsOneWidget);
    expect(find.text('Référence : PRD-0001'), findsOneWidget);
    expect(find.text('Doudou lapin'), findsOneWidget); // champ « Nom »
    expect(find.text('Coton bio'), findsOneWidget);
    expect(find.text('25'), findsOneWidget); // prix : 25 €

    await env.fermer(tester);
  });
}
