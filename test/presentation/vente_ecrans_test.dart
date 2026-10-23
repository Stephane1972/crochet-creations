import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/clients/client_fiche_screen.dart';
import 'package:crochet_creations/presentation/ventes/panier_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_confirmation_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Les onglets restent tous construits : on cherche dans l'écran voulu seulement.
Finder dansVente(Finder cible) => find.descendant(of: find.byType(VenteScreen), matching: cible);
Finder dansPanier(Finder cible) => find.descendant(of: find.byType(PanierScreen), matching: cible);
Finder dansConfirmation(Finder cible) =>
    find.descendant(of: find.byType(VenteConfirmationScreen), matching: cible);

/// Message affiché en bas de l'écran (snackbar). Il n'est pas forcément dans l'écran qui l'a
/// demandé (les onglets sont imbriqués dans le Scaffold de l'accueil) : on le cherche partout.
Finder message(String texte) => find.text(texte);

/// Feuille du bas ouverte (choix de variante, choix du client).
Finder dansFeuille(Finder cible) => find.descendant(of: find.byType(BottomSheet), matching: cible);

const Size _grandEcran = Size(800, 2400);

/// Ouvre l'onglet Vente.
Future<void> ouvrirVente(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Vente'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Appuie sur « Ajouter au panier » d'un produit de l'onglet Vente.
Future<void> ajouterDepuisOnglet(WidgetTester tester, String nom) async {
  await tester.tap(dansVente(find.byTooltip('Ajouter « $nom » au panier')));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

Future<void> ouvrirPanier(WidgetTester tester) async {
  await tester.tap(dansVente(find.text('Voir le panier')));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Attend qu'un texte apparaisse (le temps que la base réponde), puis laisse finir les animations.
Future<void> attendreTexte(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  await tester.pumpAndSettle();
}

/// « Valider la vente » du panier, puis confirmation dans la fenêtre.
Future<void> validerLaVente(WidgetTester tester) async {
  await tester.tap(find.textContaining('Valider la vente ·'));
  await tester.pumpAndSettle();
  expect(find.text('Valider cette vente ?'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Valider la vente'));
  await tester.pump();
  await attendreJusqua(tester, () => find.byType(VenteConfirmationScreen).evaluate().isNotEmpty);
  await attendreTexte(tester, dansConfirmation(find.text('Total')));
}

Future<Vente> uniqueVente(WidgetTester tester, EnvironnementTest env) async {
  final List<Vente> ventes = await env.travailler(tester, () => env.db.select(env.db.ventes).get());
  expect(ventes, hasLength(1));
  return ventes.single;
}

Future<int> stockDe(WidgetTester tester, EnvironnementTest env, int produitId) async {
  return (await env.travailler(tester, () => env.produits.obtenir(produitId)))!.quantiteStock;
}

void main() {
  testWidgets('onglet Vente : client de passage, produits et panier vide', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirVente(tester, env);

    expect(dansVente(find.text('Client de passage')), findsOneWidget);
    expect(dansVente(find.text('Article ou prestation libre')), findsOneWidget);
    expect(dansVente(find.text('Doudou lapin')), findsOneWidget);
    expect(dansVente(find.text('Panier vide')), findsOneWidget);
    final FilledButton bouton = tester.widget<FilledButton>(
      find.ancestor(of: dansVente(find.text('Voir le panier')), matching: find.bySubtype<FilledButton>()),
    );
    expect(bouton.onPressed, isNull);

    await env.fermer(tester);
  });

  testWidgets('ajouter un produit met à jour la barre du panier', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirVente(tester, env);

    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    expect(message('« Doudou lapin » ajouté au panier.'), findsWidgets);
    expect(dansVente(find.text('1 article')), findsOneWidget);
    expect(dansVente(find.text('Sous-total ${formatEuros(2500)}')), findsOneWidget);
    expect(dansVente(find.text('1 au panier')), findsOneWidget);

    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    expect(dansVente(find.text('2 articles')), findsOneWidget);
    expect(dansVente(find.text('Sous-total ${formatEuros(5000)}')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('un produit épuisé ne peut pas être ajouté', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, stock: 0);
    await ouvrirVente(tester, env);

    final IconButton ajout = tester.widget<IconButton>(
      dansVente(find.widgetWithIcon(IconButton, Icons.add_shopping_cart)),
    );
    expect(ajout.onPressed, isNull);

    await env.fermer(tester);
  });

  testWidgets('le stock limite ce qu’on peut mettre au panier', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, stock: 1);
    await ouvrirVente(tester, env);

    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ajouterDepuisOnglet(tester, 'Doudou lapin');

    expect(
      message('Stock insuffisant pour « Doudou lapin » : 1 disponible(s), 2 demandé(s).'),
      findsWidgets,
    );
    expect(dansVente(find.text('1 article')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('un produit à variantes demande laquelle choisir', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await env.travailler(
      tester,
      () => env.produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose', quantiteStock: 3)),
    );
    await env.travailler(
      tester,
      () => env.produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Bleu', quantiteStock: 0)),
    );
    await ouvrirVente(tester, env);

    await tester.tap(dansVente(find.byTooltip('Ajouter « Doudou lapin » au panier')));
    await tester.pumpAndSettle();
    expect(find.text('Quelle variante de « Doudou lapin » ?'), findsOneWidget);
    expect(dansFeuille(find.text('3 en stock')), findsOneWidget);
    expect(dansFeuille(find.text('Épuisée')), findsOneWidget);

    // Une variante épuisée ne se choisit pas.
    await tester.tap(dansFeuille(find.text('Bleu')));
    await tester.pumpAndSettle();
    expect(find.text('Quelle variante de « Doudou lapin » ?'), findsOneWidget);

    await tester.tap(dansFeuille(find.text('Rose')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(dansVente(find.text('1 article')), findsOneWidget);

    await ouvrirPanier(tester);
    expect(dansPanier(find.text('Doudou lapin – Rose')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('article ou prestation libre : saisie, puis ligne du panier', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirVente(tester, env);

    await tester.tap(dansVente(find.text('Article ou prestation libre')));
    await tester.pumpAndSettle();

    // Une désignation et un prix sont obligatoires.
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Indiquez le nom de l’article.'), findsOneWidget);
    expect(find.text('Indiquez le prix.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Désignation'), 'Doudou sur mesure');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix unitaire (€)'), '45');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(message('Article ajouté au panier.'), findsWidgets);
    expect(dansVente(find.text('1 article')), findsOneWidget);

    await ouvrirPanier(tester);
    expect(dansPanier(find.text('Doudou sur mesure')), findsOneWidget);
    expect(dansPanier(find.text('Valider la vente · ${formatEuros(4500)}')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('choisir un client, puis revenir au client de passage', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerClient(tester, const DonneesClient(prenom: 'Camille', nom: 'Martin'));
    await ouvrirVente(tester, env);

    await tester.tap(dansVente(find.text('Client de passage')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(dansFeuille(find.text('Camille Martin')));
    await tester.pumpAndSettle();
    expect(dansVente(find.text('Camille Martin')), findsOneWidget);
    expect(dansVente(find.text('Client de passage')), findsNothing);

    await tester.tap(dansVente(find.text('Camille Martin')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(dansFeuille(find.text('Client de passage')));
    await tester.pumpAndSettle();
    expect(dansVente(find.text('Client de passage')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('panier : quantités, limite du stock et retrait d’un article', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, stock: 2);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    expect(dansPanier(find.text('Valider la vente · ${formatEuros(2500)}')), findsOneWidget);

    await tester.tap(dansPanier(find.byTooltip('Une de plus')));
    await tester.pumpAndSettle();
    expect(dansPanier(find.text('Valider la vente · ${formatEuros(5000)}')), findsOneWidget);
    expect(dansPanier(find.text('Tout le stock est dans le panier.')), findsOneWidget);
    final IconButton plus = tester.widget<IconButton>(dansPanier(find.widgetWithIcon(IconButton, Icons.add)));
    expect(plus.onPressed, isNull);

    await tester.tap(dansPanier(find.byTooltip('Une de moins')));
    await tester.pumpAndSettle();
    expect(dansPanier(find.text('Valider la vente · ${formatEuros(2500)}')), findsOneWidget);

    await tester.tap(dansPanier(find.byTooltip('Retirer « Doudou lapin » du panier')));
    await tester.pumpAndSettle();
    expect(dansPanier(find.text('Le panier est vide')), findsOneWidget);

    await tester.tap(dansPanier(find.text('Ajouter des articles')));
    await tester.pumpAndSettle();
    expect(find.byType(PanierScreen), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('vente payée comptant : stock décompté, panier vidé, confirmation', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    await validerLaVente(tester);

    expect(dansConfirmation(find.text('Vente enregistrée')), findsOneWidget);
    expect(dansConfirmation(find.text('Payée')), findsOneWidget);
    expect(dansConfirmation(find.textContaining('Client de passage')), findsOneWidget);
    expect(dansConfirmation(find.text('Doudou lapin')), findsOneWidget);
    expect(dansConfirmation(find.text(formatEuros(2500))), findsWidgets);
    expect(dansConfirmation(find.textContaining('Encaisser le solde')), findsNothing);
    expect(await stockDe(tester, env, p.id), 4);
    final Vente vente = await uniqueVente(tester, env);
    expect(vente.statutPaiement, StatutPaiement.payee);
    expect(vente.clientId, isNull);

    // « Nouvelle vente » revient à l'onglet Vente, avec un panier vide.
    await tester.tap(find.text('Nouvelle vente'));
    await tester.pumpAndSettle();
    expect(find.byType(VenteConfirmationScreen), findsNothing);
    expect(dansVente(find.text('Panier vide')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('vente à un client, avec remise en pourcentage et frais de port', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client camille = await env.creerClient(
      tester,
      const DonneesClient(prenom: 'Camille', nom: 'Martin'),
    );
    await env.creerProduit(tester);
    await ouvrirVente(tester, env);

    await tester.tap(dansVente(find.text('Client de passage')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(dansFeuille(find.text('Camille Martin')));
    await tester.pumpAndSettle();
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    await tester.tap(dansPanier(find.text('En %')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Remise (%)'), '10');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Frais de port (€)'), '3');
    await tester.pump();

    expect(dansPanier(find.text('−${formatEuros(250)}')), findsOneWidget);
    expect(dansPanier(find.text('Valider la vente · ${formatEuros(2550)}')), findsOneWidget);

    await validerLaVente(tester);

    expect(dansConfirmation(find.textContaining('Camille Martin')), findsOneWidget);
    final Vente vente = await uniqueVente(tester, env);
    expect(vente.clientId, camille.id);
    expect(vente.remiseType, RemiseType.pourcentage);
    expect(vente.remiseCentimes, 250);
    expect(vente.fraisPortCentimes, 300);
    expect(vente.totalCentimes, 2550);

    await env.fermer(tester);
  });

  testWidgets('payer plus tard : vente impayée, puis encaissement du solde', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    await tester.tap(dansPanier(find.text('Plus tard')));
    await tester.pumpAndSettle();
    await validerLaVente(tester);

    expect(dansConfirmation(find.text('Impayée')), findsOneWidget);
    expect(dansConfirmation(find.text('Reste à payer')), findsOneWidget);
    expect((await uniqueVente(tester, env)).statutPaiement, StatutPaiement.impayee);

    await tester.tap(dansConfirmation(find.textContaining('Encaisser le solde')));
    await tester.pumpAndSettle();
    expect(find.text('Encaisser un paiement'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Encaisser'));
    await tester.pump();
    await attendreTexte(tester, dansConfirmation(find.text('Payée')));

    expect(message('Paiement enregistré.'), findsWidgets);
    expect(dansConfirmation(find.text('Reste à payer')), findsNothing);
    expect(dansConfirmation(find.textContaining('Encaisser le solde')), findsNothing);
    expect((await uniqueVente(tester, env)).statutPaiement, StatutPaiement.payee);

    await env.fermer(tester);
  });

  testWidgets('acompte : vente partiellement payée, solde à encaisser', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    await tester.tap(dansPanier(find.text('Acompte')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Montant de l’acompte (€)'), '10');
    await tester.pump();
    await validerLaVente(tester);

    expect(dansConfirmation(find.text('Partiellement payée')), findsOneWidget);
    expect(dansConfirmation(find.text('Déjà encaissé')), findsOneWidget);
    expect(dansConfirmation(find.text(formatEuros(1500))), findsWidgets); // le solde
    expect(dansConfirmation(find.textContaining('Encaisser le solde')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('un acompte supérieur au total est refusé, le panier est conservé', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    await tester.tap(dansPanier(find.text('Acompte')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Montant de l’acompte (€)'), '30');
    await tester.pump();
    await tester.tap(find.textContaining('Valider la vente ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider la vente'));
    await tester.pump();
    await attendreTexte(tester, message('Le montant encaissé ne peut pas dépasser le total de la vente.'));

    expect(find.byType(PanierScreen), findsOneWidget);
    expect(find.byType(VenteConfirmationScreen), findsNothing);
    expect(dansPanier(find.text('Doudou lapin')), findsOneWidget);
    expect(await stockDe(tester, env, p.id), 5);
    expect(await env.travailler(tester, () => env.db.select(env.db.ventes).get()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('stock épuisé entre-temps : la validation est refusée sans rien enregistrer', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester, stock: 1);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);

    // Une autre vente a pris le dernier exemplaire.
    await env.ecrireEcranOuvert(tester, () => env.produits.ajusterStock(produitId: p.id, delta: -1));

    await tester.tap(find.textContaining('Valider la vente ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider la vente'));
    await tester.pump();
    await attendreTexte(
      tester,
      message('Stock insuffisant pour « Doudou lapin » : 0 disponible(s), 1 demandé(s).'),
    );

    expect(find.byType(PanierScreen), findsOneWidget);
    expect(await env.travailler(tester, () => env.db.select(env.db.ventes).get()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('annuler une vente remet le stock et rembourse', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    await ouvrirVente(tester, env);
    await ajouterDepuisOnglet(tester, 'Doudou lapin');
    await ouvrirPanier(tester);
    await validerLaVente(tester);
    expect(await stockDe(tester, env, p.id), 4);

    // On garde la vente : rien ne change.
    await tester.tap(dansConfirmation(find.text('Annuler la vente')));
    await tester.pumpAndSettle();
    expect(find.text('Annuler cette vente ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Garder la vente'));
    await tester.pumpAndSettle();
    expect(dansConfirmation(find.text('Vente enregistrée')), findsOneWidget);
    expect(await stockDe(tester, env, p.id), 4);

    // On annule.
    await tester.tap(dansConfirmation(find.text('Annuler la vente')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Annuler la vente'));
    await tester.pump();
    await attendreTexte(tester, dansConfirmation(find.text('Vente annulée')));

    expect(dansConfirmation(find.text('Annulée · remboursée')), findsOneWidget);
    expect(dansConfirmation(find.text('Remboursement')), findsOneWidget);
    expect(dansConfirmation(find.text('Annuler la vente')), findsNothing);
    expect(await stockDe(tester, env, p.id), 5);
    expect((await uniqueVente(tester, env)).statut, StatutVente.annulee);

    await env.fermer(tester);
  });

  testWidgets('l’historique d’un client ouvre ses ventes', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client camille = await env.creerClient(
      tester,
      const DonneesClient(prenom: 'Camille', nom: 'Martin'),
    );
    final Produit p = await env.creerProduit(tester);
    await env.validerVente(tester, produit: p, clientId: camille.id);
    await ouvrirAccueil(tester, env, taille: const Size(800, 3200));
    await tester.tap(ongletNav('Clients'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(find.text('Camille Martin').hitTestable());
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(find.byType(ClientFicheScreen), findsOneWidget);

    // La ligne de la vente indique son statut de paiement (« Impayée » : aucun paiement).
    await tester.tap(find.descendant(of: find.byType(ClientFicheScreen), matching: find.text('Impayée')));
    await tester.pumpAndSettle();
    await attendreTexte(tester, dansConfirmation(find.text('Total')));

    expect(find.byType(VenteConfirmationScreen), findsOneWidget);
    expect(dansConfirmation(find.text('Impayée')), findsOneWidget);
    expect(dansConfirmation(find.textContaining('Camille Martin')), findsOneWidget);

    await env.fermer(tester);
  });
}
