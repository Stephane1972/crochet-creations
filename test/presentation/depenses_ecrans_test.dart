import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/depenses/depense_form_screen.dart';
import 'package:crochet_creations/presentation/depenses/depenses_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Large : toutes les pastilles de catégorie tiennent sur une ligne, sans faire défiler.
const Size _grandEcran = Size(1400, 2400);

Finder dansListe(Finder cible) => find.descendant(of: find.byType(DepensesScreen), matching: cible);
Finder dansFormulaire(Finder cible) => find.descendant(of: find.byType(DepenseFormScreen), matching: cible);

/// Feuille du bas ouverte (choix du produit).
Finder dansFeuille(Finder cible) => find.descendant(of: find.byType(BottomSheet), matching: cible);

/// Message affiché en bas de l'écran (snackbar).
Finder message(String texte) => find.text(texte);

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Appuie sur un élément, laisse finir les animations et les lectures de la base, sans « pumpAndSettle » (un
/// écran qui charge, ou un bouton qui enregistre, affiche un indicateur d'attente qui ne se calme jamais).
Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pump();
  await tester.tap(cible);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await laisserFinir(tester);
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route, {Object? arguments}) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route, arguments: arguments));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre l'application puis la liste des dépenses (sur le mois en cours).
Future<void> ouvrirListe(WidgetTester tester, EnvironnementTest env, {required Finder attendu}) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.depenses);
  await attendre(tester, attendu);
}

/// Ouvre l'application puis une route du formulaire des dépenses.
Future<void> ouvrirFormulaire(WidgetTester tester, EnvironnementTest env, String route, {Object? arguments}) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, route, arguments: arguments);
  await attendre(tester, find.widgetWithText(TextFormField, 'Montant (€) *'));
}

/// Depuis le formulaire ouvert : le menu « Plus d'actions » puis [action].
Future<void> choisirDansLeMenu(WidgetTester tester, String action) async {
  await toucher(tester, find.byTooltip('Plus d’actions'));
  await toucher(tester, find.text(action));
}

String texteDuChamp(WidgetTester tester, String libelle) {
  final TextFormField champ = tester.widget(find.widgetWithText(TextFormField, libelle));
  return champ.controller!.text;
}

Future<List<Depense>> depensesEnBase(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.db.select(env.db.depenses).get());

/// Le mois en cours en toutes lettres (« octobre 2026 »).
String moisCourant() {
  final DateTime maintenant = DateTime.now();
  return formatMois(maintenant.year, maintenant.month);
}

void main() {
  // ---------------------------------------------------------------------------
  // Liste des dépenses (écran 19)
  // ---------------------------------------------------------------------------

  testWidgets('liste des dépenses : vide au départ, ouverte depuis « Plus »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Dépenses')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, dansListe(find.text('Aucune dépense en ${moisCourant()}.')));

    expect(dansListe(find.text(moisCourant())), findsOneWidget);
    expect(dansListe(find.text('Nouvelle dépense')), findsOneWidget);
    expect(dansListe(find.text('Toutes')), findsOneWidget);
    expect(dansListe(find.text('Archivées')), findsOneWidget);
    for (final CategorieDepense c in CategorieDepense.values) {
      expect(dansListe(find.text(c.libelle)), findsOneWidget, reason: c.libelle);
    }

    await env.fermer(tester);
  });

  testWidgets('liste des dépenses : total du mois, filtre par catégorie, mois précédent', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final DateTime maintenant = DateTime.now();
    final DateTime precedent = DateTime(maintenant.year, maintenant.month - 1);
    await env.creerDepense(tester, fournisseur: 'Mercerie du Port', montant: 2490, description: 'Coton, 10 pelotes');
    await env.creerDepense(
      tester,
      fournisseur: 'Sacs et Cie',
      categorie: CategorieDepense.emballage,
      montant: 450,
    );
    await env.creerDepense(tester, fournisseur: 'Laines Anna', montant: 1000);
    await env.creerDepense(
      tester,
      fournisseur: 'Papeterie',
      categorie: CategorieDepense.autre,
      montant: 7000,
      date: DateTime(precedent.year, precedent.month, 15),
    );

    await ouvrirListe(tester, env, attendu: dansListe(find.text('Mercerie du Port')));

    // Le mois en cours : trois dépenses, la dernière enregistrée d'abord (même jour).
    expect(dansListe(find.text('Total du mois')), findsOneWidget);
    expect(dansListe(find.text(formatEuros(3940))), findsOneWidget);
    expect(dansListe(find.text('3 dépenses')), findsOneWidget);
    expect(dansListe(find.text('Papeterie')), findsNothing);
    expect(dansListe(find.text('Coton, 10 pelotes')), findsOneWidget);
    expect(dansListe(find.text(formatEuros(2490))), findsOneWidget);
    final double hautAnna = tester.getTopLeft(dansListe(find.text('Laines Anna'))).dy;
    final double hautSacs = tester.getTopLeft(dansListe(find.text('Sacs et Cie'))).dy;
    final double hautMercerie = tester.getTopLeft(dansListe(find.text('Mercerie du Port'))).dy;
    expect(hautAnna, lessThan(hautSacs));
    expect(hautSacs, lessThan(hautMercerie));

    // Une catégorie : la liste et le total se réduisent.
    await toucher(tester, dansListe(find.text('Laine / fil')));
    await attendre(tester, dansListe(find.text('Total · Laine / fil')));
    expect(dansListe(find.text(formatEuros(3490))), findsOneWidget);
    expect(dansListe(find.text('2 dépenses')), findsOneWidget);
    expect(dansListe(find.text('Sacs et Cie')), findsNothing);

    // Une catégorie sans dépense ce mois-ci.
    await toucher(tester, dansListe(find.text('Publicité')));
    await attendre(tester, dansListe(find.text('Aucune dépense « Publicité » en ${moisCourant()}.')));

    // Retour à toutes les catégories.
    await toucher(tester, dansListe(find.text('Toutes')));
    await attendre(tester, dansListe(find.text('Total du mois')));
    expect(dansListe(find.text('3 dépenses')), findsOneWidget);

    // Le mois précédent : seulement sa dépense. On ne peut pas aller au-delà du mois en cours.
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
    await toucher(tester, find.byTooltip('Mois précédent'));
    await attendre(tester, dansListe(find.text('Papeterie')));
    expect(dansListe(find.text(formatMois(precedent.year, precedent.month))), findsOneWidget);
    expect(dansListe(find.text(formatEuros(7000))), findsNWidgets(2)); // le total et la ligne
    expect(dansListe(find.text('1 dépense')), findsOneWidget);
    expect(dansListe(find.text('Mercerie du Port')), findsNothing);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNotNull);

    await toucher(tester, find.byTooltip('Mois suivant'));
    await attendre(tester, dansListe(find.text('Mercerie du Port')));
    expect(dansListe(find.text(moisCourant())), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('liste des dépenses : le produit concerné et le ticket joint sont indiqués', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit doudou = await env.creerProduit(tester, nom: 'Doudou lapin');
    await env.creerDepense(tester, fournisseur: 'Mercerie du Port', produitId: doudou.id, photo: 'ticket.jpg');
    await env.creerDepense(tester, fournisseur: 'Sacs et Cie', categorie: CategorieDepense.emballage, montant: 450);

    await ouvrirListe(tester, env, attendu: dansListe(find.text('Mercerie du Port')));

    expect(dansListe(find.text('Produit : Doudou lapin')), findsOneWidget);
    expect(dansListe(find.text('Ticket joint')), findsOneWidget); // seulement sur la première

    await env.fermer(tester);
  });

  testWidgets('liste des dépenses : une dépense sans fournisseur porte le nom de sa catégorie', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerDepense(tester, fournisseur: null, categorie: CategorieDepense.standMarche, montant: 3500);

    await ouvrirListe(tester, env, attendu: dansListe(find.text(formatEuros(3500))));

    // Le nom de la catégorie sert de titre : on le lit dans la ligne (et sur la pastille de filtre).
    expect(dansListe(find.text('Stand / marché')), findsNWidgets(2));

    await env.fermer(tester);
  });

  testWidgets('liste des dépenses : les dépenses archivées ont leur filtre', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Depense archivee = await env.creerDepense(tester, fournisseur: 'Ancienne mercerie');
    await env.creerDepense(tester, fournisseur: 'Sacs et Cie', montant: 450);
    await env.travailler(tester, () => env.depenses.archiver(archivee.id));

    await ouvrirListe(tester, env, attendu: dansListe(find.text('Sacs et Cie')));
    expect(dansListe(find.text('Ancienne mercerie')), findsNothing);
    expect(dansListe(find.text('1 dépense')), findsOneWidget);

    await toucher(tester, dansListe(find.text('Archivées')));
    await attendre(tester, dansListe(find.text('Ancienne mercerie')));
    expect(dansListe(find.text('Sacs et Cie')), findsNothing);
    expect(dansListe(find.text('1 dépense archivée ce mois-ci')), findsOneWidget);
    expect(dansListe(find.text('Total du mois')), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('liste des dépenses : un appui ouvre la dépense pour la modifier', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerDepense(tester, fournisseur: 'Mercerie du Port', montant: 2490, description: 'Coton');

    await ouvrirListe(tester, env, attendu: dansListe(find.text('Mercerie du Port')));
    await toucher(tester, dansListe(find.text('Mercerie du Port')));
    await attendre(tester, find.widgetWithText(TextFormField, 'Montant (€) *'));

    expect(dansFormulaire(find.text('Modifier la dépense')), findsOneWidget);
    expect(texteDuChamp(tester, 'Montant (€) *'), '24,90');
    expect(texteDuChamp(tester, 'Fournisseur'), 'Mercerie du Port');
    expect(texteDuChamp(tester, 'Description'), 'Coton');

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Nouvelle dépense
  // ---------------------------------------------------------------------------

  testWidgets('nouvelle dépense : enregistrée avec ses informations, la date du jour par défaut', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle);
    final DateTime maintenant = DateTime.now();
    expect(dansFormulaire(find.text('Nouvelle dépense')), findsOneWidget);
    expect(dansFormulaire(find.text('${formatDateLongue(maintenant)} ${maintenant.year}')), findsOneWidget);

    await saisir(tester, 'Montant (€) *', '24,90');
    await saisir(tester, 'Fournisseur', 'Mercerie du Port');
    await saisir(tester, 'Description', 'Dix pelotes de coton');
    await appuyer(tester, find.byType(DropdownButtonFormField<CategorieDepense>));
    await tester.tap(find.text('Emballage').last);
    await tester.pumpAndSettle();
    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Dépense enregistrée.'));

    expect(find.byType(DepenseFormScreen), findsNothing);
    final Depense d = (await depensesEnBase(tester, env)).single;
    expect(d.montantCentimes, 2490);
    expect(d.categorie, CategorieDepense.emballage);
    expect(d.fournisseur, 'Mercerie du Port');
    expect(d.description, 'Dix pelotes de coton');
    expect(d.dateDepense, DateTime(maintenant.year, maintenant.month, maintenant.day));
    expect(d.photoTicketChemin, isNull);
    expect(d.produitId, isNull);
    expect(d.archiveLe, isNull);

    await env.fermer(tester);
  });

  testWidgets('nouvelle dépense : le montant est obligatoire et supérieur à zéro, rien n’est enregistré sans lui', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle);

    await toucher(tester, find.text('Enregistrer'));
    expect(message('Corrigez les champs signalés en rouge.'), findsWidgets);
    expect(find.text('Indiquez le montant.'), findsOneWidget);

    await saisir(tester, 'Montant (€) *', 'abc');
    expect(find.text('Montant invalide (exemple : 12,50).'), findsOneWidget);

    await saisir(tester, 'Montant (€) *', '0');
    expect(find.text('Le montant doit être supérieur à 0.'), findsOneWidget);
    await toucher(tester, find.text('Enregistrer'));
    expect(find.byType(DepenseFormScreen), findsOneWidget);

    expect(await depensesEnBase(tester, env), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('nouvelle dépense : le produit concerné se choisit dans le catalogue, sans rien modifier', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit doudou = await env.creerProduit(tester, nom: 'Doudou lapin', stock: 5);
    await env.creerProduit(tester, nom: 'Boucles fleurs', categorie: CategorieProduit.bouclesOreilles);
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle);

    expect(dansFormulaire(find.text('Aucun produit')), findsOneWidget);
    await toucher(tester, find.text('Produit concerné'));
    await attendre(tester, dansFeuille(find.text('Doudou lapin')));
    expect(dansFeuille(find.text('Aucun produit')), findsOneWidget);
    expect(dansFeuille(find.text('Boucles fleurs')), findsOneWidget);

    // La recherche réduit la liste.
    final Finder recherche = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(recherche, 'zzz');
    await tester.pump();
    expect(dansFeuille(find.text('Aucun produit trouvé.')), findsOneWidget);
    await tester.enterText(recherche, 'lapin');
    await tester.pump();
    expect(dansFeuille(find.text('Boucles fleurs')), findsNothing);

    await toucher(tester, dansFeuille(find.text('Doudou lapin')));
    expect(find.byType(BottomSheet), findsNothing);
    expect(dansFormulaire(find.text('Doudou lapin')), findsOneWidget);

    await saisir(tester, 'Montant (€) *', '12');
    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Dépense enregistrée.'));

    final Depense d = (await depensesEnBase(tester, env)).single;
    expect(d.produitId, doudou.id);
    expect(d.montantCentimes, 1200);
    final Produit apres = (await env.travailler(tester, () => env.produits.obtenir(doudou.id)))!;
    expect(apres.quantiteStock, 5);
    expect(apres.coutMatiereCentimes, doudou.coutMatiereCentimes);

    await env.fermer(tester);
  });

  testWidgets('nouvelle dépense : « Aucun produit » retire le produit choisi', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester, nom: 'Doudou lapin');
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle);

    await toucher(tester, find.text('Produit concerné'));
    await attendre(tester, dansFeuille(find.text('Doudou lapin')));
    await toucher(tester, dansFeuille(find.text('Doudou lapin')));
    expect(dansFormulaire(find.text('Doudou lapin')), findsOneWidget);

    await toucher(tester, find.text('Produit concerné'));
    await attendre(tester, dansFeuille(find.text('Aucun produit')));
    await toucher(tester, dansFeuille(find.text('Aucun produit')));
    expect(dansFormulaire(find.text('Doudou lapin')), findsNothing);
    expect(dansFormulaire(find.text('Aucun produit')), findsOneWidget);

    await saisir(tester, 'Montant (€) *', '5');
    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Dépense enregistrée.'));
    expect((await depensesEnBase(tester, env)).single.produitId, isNull);

    await env.fermer(tester);
  });

  testWidgets('nouvelle dépense : la photo du ticket est copiée dans l’application et enregistrée', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.selecteur.chemin = await env.photoGalerie(tester, 'IMG_ticket.jpg');
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle);

    await saisir(tester, 'Montant (€) *', '18,50');
    await appuyer(tester, find.text('Ajouter la photo du ticket'));
    await appuyer(tester, find.text('Choisir dans la galerie'));
    await laisserFinir(tester);
    expect(env.selecteur.appels, 1);

    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Dépense enregistrée.'));

    final Depense d = (await depensesEnBase(tester, env)).single;
    expect(d.photoTicketChemin, isNotNull);
    expect(d.photoTicketChemin, isNot(contains('/'))); // nom de fichier, pas chemin complet
    final bool existe = await env.travailler(
      tester,
      () => File('${env.dossierPhotos.path}/${d.photoTicketChemin}').exists(),
    );
    expect(existe, isTrue);

    await env.fermer(tester);
  });

  testWidgets('nouvelle dépense : quitter une saisie demande confirmation, rien n’est enregistré si on abandonne', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle);

    await saisir(tester, 'Fournisseur', 'Mercerie du Port');

    // On choisit de continuer la saisie.
    await retourArriere(tester);
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);
    await tester.tap(find.text('Continuer la saisie'));
    await tester.pumpAndSettle();
    expect(find.byType(DepenseFormScreen), findsOneWidget);
    expect(texteDuChamp(tester, 'Fournisseur'), 'Mercerie du Port');

    // On abandonne.
    await retourArriere(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
    await tester.pumpAndSettle();
    expect(find.byType(DepenseFormScreen), findsNothing);
    expect(await depensesEnBase(tester, env), isEmpty);

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Modifier, archiver, restaurer
  // ---------------------------------------------------------------------------

  testWidgets('modifier une dépense : modifications enregistrées', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Depense depense = await env.creerDepense(tester, fournisseur: 'Mercerie du Port', description: 'Coton');
    await ouvrirFormulaire(tester, env, AppRoutes.depenseModifier, arguments: depense.id);

    await saisir(tester, 'Montant (€) *', '30');
    await saisir(tester, 'Fournisseur', 'Laines Anna');
    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Modifications enregistrées.'));

    expect(find.byType(DepenseFormScreen), findsNothing);
    final Depense apres = (await depensesEnBase(tester, env)).single;
    expect(apres.id, depense.id);
    expect(apres.montantCentimes, 3000);
    expect(apres.fournisseur, 'Laines Anna');
    expect(apres.description, 'Coton');

    await env.fermer(tester);
  });

  testWidgets('modifier une dépense : retirer la photo du ticket supprime le fichier après l’enregistrement', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final File fichier = File('${env.dossierPhotos.path}/ticket_test.jpg');
    await env.travailler(tester, () async {
      await env.dossierPhotos.create(recursive: true);
      await fichier.writeAsString('image');
    });
    final Depense depense = await env.creerDepense(tester, photo: 'ticket_test.jpg');
    await ouvrirFormulaire(tester, env, AppRoutes.depenseModifier, arguments: depense.id);

    await appuyer(tester, find.text('Changer ou retirer la photo'));
    await appuyer(tester, find.text('Retirer la photo'));
    // Tant que ce n'est pas enregistré, le fichier reste : un abandon ne fait rien perdre.
    expect(await env.travailler(tester, () => fichier.exists()), isTrue);

    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Modifications enregistrées.'));

    expect((await depensesEnBase(tester, env)).single.photoTicketChemin, isNull);
    expect(await env.travailler(tester, () => fichier.exists()), isFalse);

    await env.fermer(tester);
  });

  testWidgets('archiver puis restaurer une dépense', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerDepense(tester, fournisseur: 'Mercerie du Port');

    await ouvrirListe(tester, env, attendu: dansListe(find.text('Mercerie du Port')));
    await toucher(tester, dansListe(find.text('Mercerie du Port')));
    await attendre(tester, find.widgetWithText(TextFormField, 'Montant (€) *'));

    // Archiver : une confirmation, puis la dépense quitte la liste.
    await choisirDansLeMenu(tester, 'Archiver la dépense');
    expect(find.text('Archiver cette dépense ?'), findsOneWidget);
    await toucher(tester, find.widgetWithText(FilledButton, 'Archiver'));
    await attendre(tester, message('Dépense archivée.'));
    await attendre(tester, dansListe(find.text('Aucune dépense en ${moisCourant()}.')));
    expect(find.byType(DepenseFormScreen), findsNothing);
    expect((await depensesEnBase(tester, env)).single.archiveLe, isNotNull);

    // Elle se retrouve dans « Archivées », où le formulaire l'indique.
    await toucher(tester, dansListe(find.text('Archivées')));
    await attendre(tester, dansListe(find.text('Mercerie du Port')));
    await toucher(tester, dansListe(find.text('Mercerie du Port')));
    await attendre(tester, dansFormulaire(find.text('Cette dépense est archivée.')));

    // Restaurer : elle revient dans la liste.
    await choisirDansLeMenu(tester, 'Restaurer la dépense');
    await attendre(tester, message('Dépense restaurée.'));
    await attendre(tester, dansListe(find.text('Aucune dépense archivée en ${moisCourant()}.')));
    expect((await depensesEnBase(tester, env)).single.archiveLe, isNull);

    await toucher(tester, dansListe(find.text('Toutes')));
    await attendre(tester, dansListe(find.text('Mercerie du Port')));

    await env.fermer(tester);
  });

  testWidgets('annuler l’archivage d’une dépense ne change rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Depense depense = await env.creerDepense(tester);
    await ouvrirFormulaire(tester, env, AppRoutes.depenseModifier, arguments: depense.id);

    await choisirDansLeMenu(tester, 'Archiver la dépense');
    expect(find.text('Archiver cette dépense ?'), findsOneWidget);
    await toucher(tester, find.text('Annuler'));

    expect(find.byType(DepenseFormScreen), findsOneWidget);
    expect((await depensesEnBase(tester, env)).single.archiveLe, isNull);

    await env.fermer(tester);
  });

  testWidgets('une dépense inconnue : message clair', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.depenseModifier, arguments: 4242);
    await attendre(tester, find.text('Cette dépense n’existe plus.'));
    expect(find.text('Enregistrer'), findsNothing);

    await env.fermer(tester);
  });
}
