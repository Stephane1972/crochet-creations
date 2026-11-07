import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/presentation/lieux/lieux_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:crochet_creations/presentation/ventes/panier_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_confirmation_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(1000, 3000);

Finder dansEcran(Finder cible) => find.descendant(of: find.byType(LieuxScreen), matching: cible);
Finder dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);
Finder dansFeuille(Finder cible) => find.descendant(of: find.byType(BottomSheet), matching: cible);
Finder dansVente(Finder cible) => find.descendant(of: find.byType(VenteScreen), matching: cible);
Finder dansPanier(Finder cible) => find.descendant(of: find.byType(PanierScreen), matching: cible);
Finder dansConfirmation(Finder cible) =>
    find.descendant(of: find.byType(VenteConfirmationScreen), matching: cible);

/// Onglet Plus → Réglages → Lieux de vente.
Future<void> ouvrirLieux(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Plus'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Réglages')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);

  await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Lieux de vente')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
  expect(find.byType(LieuxScreen), findsOneWidget);
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

/// Attend qu'un élément apparaisse (le temps que la base réponde), puis laisse finir les animations.
Future<void> attendreElement(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

Future<LieuVente> lieuNomme(WidgetTester tester, EnvironnementTest env, String nom) async {
  final List<LieuVente> tous = await env.travailler(tester, () => env.lieux.lister());
  return tous.firstWhere((LieuVente l) => l.nom == nom);
}

Future<List<Vente>> ventesEnBase(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.db.select(env.db.ventes).get());

Finder boutonDeplacer() => dansDialogue(find.widgetWithText(FilledButton, 'Déplacer et supprimer'));

/// Onglet Vente → un produit au panier → le panier.
Future<void> ouvrirPanierAvecUnProduit(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: const Size(800, 2400));
  await tester.tap(ongletNav('Vente'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);

  await tester.tap(dansVente(find.byTooltip('Ajouter « Doudou lapin » au panier')));
  await tester.pumpAndSettle();
  await laisserFinir(tester);

  await tester.tap(dansVente(find.text('Voir le panier')));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await attendreElement(tester, dansPanier(find.text('Lieu de vente')));
}

/// « Valider la vente » du panier, puis confirmation dans la fenêtre.
Future<void> validerLaVente(WidgetTester tester) async {
  await tester.tap(find.textContaining('Valider la vente ·'));
  await tester.pumpAndSettle();
  expect(find.text('Valider cette vente ?'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Valider la vente'));
  await tester.pump();
  await attendreJusqua(tester, () => find.byType(VenteConfirmationScreen).evaluate().isNotEmpty);
  await attendreElement(tester, dansConfirmation(find.text('Total')));
}

/// Ouvre la feuille « Lieu de vente » d'une carte (panier ou détail d'une vente).
Future<void> ouvrirFeuilleLieu(WidgetTester tester, Finder carte) async {
  await tester.tap(carte);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  expect(find.byType(BottomSheet), findsOneWidget);
}

/// Choisit un lieu dans la feuille ouverte.
Future<void> choisirDansFeuille(WidgetTester tester, String nom) async {
  await tester.tap(dansFeuille(find.text(nom)));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.pumpAndSettle();
}

/// La coche de la feuille : le nom du lieu actuellement choisi.
Finder cocheSur(String nom) =>
    find.descendant(of: dansFeuille(find.widgetWithText(ListTile, nom)), matching: find.byIcon(Icons.check));

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route, {Object? arguments}) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route, arguments: arguments));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre la vente [venteId] (confirmation) et attend son contenu.
Future<void> ouvrirLaVente(WidgetTester tester, EnvironnementTest env, int venteId) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.venteConfirmation, arguments: venteId);
  await attendreElement(tester, dansConfirmation(find.text('Total')));
}

void main() {
  testWidgets('Réglages mène aux quatre lieux de départ, avec leur nombre de ventes', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit lapin = await env.creerProduit(tester);
    final LieuVente marche = await lieuNomme(tester, env, 'Marché');
    final LieuVente salon = await lieuNomme(tester, env, 'Salon');
    await env.validerVente(tester, produit: lapin, lieuId: marche.id);
    await env.validerVente(tester, produit: lapin, lieuId: marche.id);
    await env.validerVente(tester, produit: lapin, lieuId: salon.id);
    await ouvrirLieux(tester, env);

    for (final String nom in <String>['Marché', 'Salon', 'Boutique', 'Vente en ligne']) {
      expect(dansEcran(find.text(nom)), findsOneWidget, reason: nom);
    }
    expect(dansEcran(find.text('2 ventes')), findsOneWidget);
    expect(dansEcran(find.text('1 vente')), findsOneWidget);
    expect(dansEcran(find.text('Aucune vente')), findsNWidgets(2));

    await env.fermer(tester);
  });

  group('ajouter', () {
    testWidgets('un nouveau lieu apparaît à la fin de la liste', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.text('Nouveau lieu'));
      expect(find.byType(AlertDialog), findsOneWidget);
      await saisirNom(tester, '  Marché   de Noël ');
      await toucher(tester, dansDialogue(find.text('Créer')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(dansEcran(find.text('Marché de Noël')), findsOneWidget);
      expect(find.text('Lieu « Marché de Noël » créé.'), findsOneWidget);
      final List<LieuVente> tous = await env.travailler(tester, () => env.lieux.lister());
      expect(tous, hasLength(5));
      expect(tous.last.nom, 'Marché de Noël');

      await env.fermer(tester);
    });

    testWidgets('un nom vide, réservé ou déjà pris est expliqué dans la boîte, qui reste ouverte', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.text('Nouveau lieu'));
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(find.text('Donnez un nom au lieu de vente.'), findsOneWidget);

      await saisirNom(tester, 'non renseigne');
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(
        find.text('« Non renseigné » désigne une vente sans lieu : choisissez un autre nom.'),
        findsOneWidget,
      );

      // Ni les majuscules ni les accents ne font un autre lieu.
      await saisirNom(tester, 'MARCHE');
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(find.text('Un lieu « Marché » existe déjà.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await toucher(tester, dansDialogue(find.text('Annuler')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(await env.travailler(tester, () => env.lieux.lister()), hasLength(4));

      await env.fermer(tester);
    });
  });

  group('renommer', () {
    testWidgets('le nouveau nom s’affiche, les ventes restent dans le lieu', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente marche = await lieuNomme(tester, env, 'Marché');
      final Vente vente = await env.validerVente(tester, produit: lapin, lieuId: marche.id);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Renommer Marché'));
      expect(tester.widget<TextField>(dansDialogue(find.byType(TextField))).controller!.text, 'Marché');
      await saisirNom(tester, 'Marché du samedi');
      await toucher(tester, dansDialogue(find.text('Enregistrer')));

      expect(dansEcran(find.text('Marché du samedi')), findsOneWidget);
      expect(dansEcran(find.text('Marché')), findsNothing);
      expect(dansEcran(find.text('1 vente')), findsOneWidget);
      expect(find.text('Lieu renommé « Marché du samedi ».'), findsOneWidget);
      final Vente apres = (await ventesEnBase(tester, env)).single;
      expect(apres.id, vente.id);
      expect(apres.lieuId, marche.id);
      expect((await lieuNomme(tester, env, 'Marché du samedi')).id, marche.id);

      await env.fermer(tester);
    });

    testWidgets('le nom d’un autre lieu est refusé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Renommer Salon'));
      await saisirNom(tester, 'boutique');
      await toucher(tester, dansDialogue(find.text('Enregistrer')));

      expect(find.text('Un lieu « Boutique » existe déjà.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect((await lieuNomme(tester, env, 'Salon')).nom, 'Salon');

      await env.fermer(tester);
    });
  });

  group('supprimer', () {
    testWidgets('un lieu sans vente : une confirmation, puis il disparaît', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Boutique'));
      expect(find.text('Supprimer ce lieu ?'), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Supprimer')));

      expect(dansEcran(find.text('Boutique')), findsNothing);
      expect(find.text('Lieu « Boutique » supprimé.'), findsOneWidget);
      expect(await env.travailler(tester, () => env.lieux.lister()), hasLength(3));

      await env.fermer(tester);
    });

    testWidgets('annuler la confirmation ne supprime rien', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Boutique'));
      await toucher(tester, dansDialogue(find.text('Annuler')));

      expect(dansEcran(find.text('Boutique')), findsOneWidget);
      expect(await env.travailler(tester, () => env.lieux.lister()), hasLength(4));

      await env.fermer(tester);
    });

    testWidgets('avec des ventes : on choisit où les déplacer, et elles y vont (aucune n’est supprimée)', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente marche = await lieuNomme(tester, env, 'Marché');
      final LieuVente salon = await lieuNomme(tester, env, 'Salon');
      await env.validerVente(tester, produit: lapin, lieuId: marche.id);
      await env.validerVente(tester, produit: lapin, lieuId: marche.id);
      await env.validerVente(tester, produit: lapin, lieuId: salon.id);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Marché'));
      expect(dansDialogue(find.textContaining('contient 2 ventes')), findsOneWidget);

      // Rien n'est présélectionné : le bouton attend un choix.
      expect(tester.widget<FilledButton>(boutonDeplacer()).onPressed, isNull);
      // Le lieu qu'on supprime ne fait pas partie des destinations ; « Non renseigné » en fait partie.
      expect(dansDialogue(find.text('Marché')), findsNothing);
      expect(dansDialogue(find.text('Non renseigné')), findsOneWidget);
      expect(dansDialogue(find.text('Les ventes n’auront plus de lieu')), findsOneWidget);

      await tester.tap(dansDialogue(find.text('Salon')));
      await tester.pump();
      expect(tester.widget<FilledButton>(boutonDeplacer()).onPressed, isNotNull);
      await toucher(tester, boutonDeplacer());

      expect(dansEcran(find.text('Marché')), findsNothing);
      expect(find.text('Lieu « Marché » supprimé. 2 ventes déplacées vers « Salon ».'), findsOneWidget);
      expect(dansEcran(find.text('3 ventes')), findsOneWidget);
      final List<Vente> ventes = await ventesEnBase(tester, env);
      expect(ventes, hasLength(3));
      expect(ventes.every((Vente v) => v.lieuId == salon.id), isTrue);

      await env.fermer(tester);
    });

    testWidgets('on peut déplacer les ventes vers « Non renseigné »', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente salon = await lieuNomme(tester, env, 'Salon');
      await env.validerVente(tester, produit: lapin, lieuId: salon.id);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Salon'));
      expect(dansDialogue(find.textContaining('contient 1 vente')), findsOneWidget);
      await tester.tap(dansDialogue(find.text('Non renseigné')));
      await tester.pump();
      await toucher(tester, boutonDeplacer());

      expect(dansEcran(find.text('Salon')), findsNothing);
      expect(find.text('Lieu « Salon » supprimé. 1 vente déplacée vers « Non renseigné ».'), findsOneWidget);
      final List<Vente> ventes = await ventesEnBase(tester, env);
      expect(ventes, hasLength(1));
      expect(ventes.single.lieuId, isNull);

      await env.fermer(tester);
    });

    testWidgets('une vente annulée compte : le lieu ne se supprime pas sans choisir où la mettre', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente boutique = await lieuNomme(tester, env, 'Boutique');
      final Vente vente = await env.validerVente(tester, produit: lapin, lieuId: boutique.id);
      await env.travailler(tester, () => env.ventes.annuler(vente.id));
      await ouvrirLieux(tester, env);

      expect(dansEcran(find.text('1 vente')), findsOneWidget);
      await toucher(tester, find.byTooltip('Supprimer Boutique'));
      expect(dansDialogue(find.textContaining('contient 1 vente')), findsOneWidget);
      expect(tester.widget<FilledButton>(boutonDeplacer()).onPressed, isNull);

      await toucher(tester, dansDialogue(find.text('Annuler')));
      expect(dansEcran(find.text('Boutique')), findsOneWidget);
      expect(await ventesEnBase(tester, env), hasLength(1));

      await env.fermer(tester);
    });

    testWidgets('annuler le choix de la destination ne change rien', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente marche = await lieuNomme(tester, env, 'Marché');
      await env.validerVente(tester, produit: lapin, lieuId: marche.id);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Marché'));
      await toucher(tester, dansDialogue(find.text('Annuler')));

      expect(dansEcran(find.text('Marché')), findsOneWidget);
      expect((await ventesEnBase(tester, env)).single.lieuId, marche.id);

      await env.fermer(tester);
    });

    testWidgets('le dernier lieu qu’on supprime : ses ventes passent en « Non renseigné »', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      for (final String nom in <String>['Marché', 'Salon', 'Boutique']) {
        final LieuVente l = await lieuNomme(tester, env, nom);
        await env.travailler(tester, () => env.lieux.supprimer(l.id));
      }
      final LieuVente enLigne = await lieuNomme(tester, env, 'Vente en ligne');
      await env.validerVente(tester, produit: lapin, lieuId: enLigne.id);
      await ouvrirLieux(tester, env);

      await toucher(tester, find.byTooltip('Supprimer Vente en ligne'));
      // Aucun autre lieu : seul « Non renseigné » est proposé.
      await tester.tap(dansDialogue(find.text('Non renseigné')));
      await tester.pump();
      await toucher(tester, boutonDeplacer());

      expect(dansEcran(find.textContaining('Aucun lieu de vente')), findsOneWidget);
      expect((await ventesEnBase(tester, env)).single.lieuId, isNull);

      await env.fermer(tester);
    });
  });

  testWidgets('sans aucun lieu, l’écran invite à en créer un', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    for (final LieuVente l in await env.travailler(tester, () => env.lieux.lister())) {
      await env.travailler(tester, () => env.lieux.supprimer(l.id));
    }
    await ouvrirLieux(tester, env);

    expect(dansEcran(find.textContaining('Aucun lieu de vente')), findsOneWidget);

    await env.fermer(tester);
  });

  group('panier', () {
    testWidgets('sans choix, le lieu est « Non renseigné » ; on choisit un lieu, et la vente le garde', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.creerProduit(tester);
      final LieuVente salon = await lieuNomme(tester, env, 'Salon');
      await ouvrirPanierAvecUnProduit(tester, env);

      expect(dansPanier(find.text('Non renseigné')), findsOneWidget);

      await ouvrirFeuilleLieu(tester, dansPanier(find.text('Lieu de vente')));
      for (final String nom in <String>['Non renseigné', 'Marché', 'Salon', 'Boutique', 'Vente en ligne']) {
        expect(dansFeuille(find.text(nom)), findsOneWidget, reason: nom);
      }
      expect(dansFeuille(find.text('Nouveau lieu de vente')), findsOneWidget);
      expect(cocheSur('Non renseigné'), findsOneWidget);

      await choisirDansFeuille(tester, 'Salon');
      expect(find.byType(BottomSheet), findsNothing);
      expect(dansPanier(find.text('Salon')), findsOneWidget);
      expect(dansPanier(find.text('Non renseigné')), findsNothing);

      // Le lieu choisi est coché quand on rouvre la feuille.
      await ouvrirFeuilleLieu(tester, dansPanier(find.text('Lieu de vente')));
      expect(cocheSur('Salon'), findsOneWidget);
      expect(cocheSur('Non renseigné'), findsNothing);
      await tester.tapAt(const Offset(10, 10)); // referme la feuille sans rien choisir
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(dansPanier(find.text('Salon')), findsOneWidget);

      await validerLaVente(tester);

      expect(dansConfirmation(find.text('Salon')), findsOneWidget);
      final List<Vente> ventes = await ventesEnBase(tester, env);
      expect(ventes, hasLength(1));
      expect(ventes.single.lieuId, salon.id);

      await env.fermer(tester);
    });

    testWidgets('une vente sans lieu choisi est enregistrée « Non renseigné »', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.creerProduit(tester);
      await ouvrirPanierAvecUnProduit(tester, env);

      await validerLaVente(tester);

      expect(dansConfirmation(find.text('Non renseigné')), findsOneWidget);
      expect((await ventesEnBase(tester, env)).single.lieuId, isNull);

      await env.fermer(tester);
    });

    testWidgets('on peut créer un lieu depuis la feuille : il est choisi aussitôt', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.creerProduit(tester);
      await ouvrirPanierAvecUnProduit(tester, env);

      await ouvrirFeuilleLieu(tester, dansPanier(find.text('Lieu de vente')));
      await toucher(tester, dansFeuille(find.text('Nouveau lieu de vente')));
      expect(find.byType(AlertDialog), findsOneWidget);

      // Un nom refusé laisse la boîte ouverte.
      await saisirNom(tester, 'salon');
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(find.text('Un lieu « Salon » existe déjà.'), findsOneWidget);

      await saisirNom(tester, 'Marché de Noël');
      await tester.tap(dansDialogue(find.text('Créer')));
      await tester.pump();
      await attendreJusqua(tester, () => find.byType(BottomSheet).evaluate().isEmpty);
      await tester.pumpAndSettle();
      await laisserFinir(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(dansPanier(find.text('Marché de Noël')), findsOneWidget);
      final LieuVente cree = await lieuNomme(tester, env, 'Marché de Noël');

      await validerLaVente(tester);

      expect((await ventesEnBase(tester, env)).single.lieuId, cree.id);
      expect(dansConfirmation(find.text('Marché de Noël')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('un lieu supprimé pendant que le panier est ouvert ne bloque pas la vente', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.creerProduit(tester);
      final LieuVente salon = await lieuNomme(tester, env, 'Salon');
      await ouvrirPanierAvecUnProduit(tester, env);

      await ouvrirFeuilleLieu(tester, dansPanier(find.text('Lieu de vente')));
      await choisirDansFeuille(tester, 'Salon');
      expect(dansPanier(find.text('Salon')), findsOneWidget);

      // Le lieu disparaît (supprimé depuis les Réglages, par exemple) : la vente passe en « Non renseigné ».
      await env.ecrireEcranOuvert<int>(tester, () => env.lieux.supprimer(salon.id));
      await laisserFinir(tester);
      await attendreElement(tester, dansPanier(find.text('Non renseigné')));
      expect(dansPanier(find.text('Salon')), findsNothing);

      await validerLaVente(tester);

      expect(dansConfirmation(find.text('Non renseigné')), findsOneWidget);
      final List<Vente> ventes = await ventesEnBase(tester, env);
      expect(ventes, hasLength(1));
      expect(ventes.single.lieuId, isNull);

      await env.fermer(tester);
    });
  });

  group('détail d’une vente', () {
    testWidgets('une ancienne vente est « Non renseigné » ; on précise son lieu, puis on le retire', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final Vente vente = await env.validerVente(tester, produit: lapin);
      final LieuVente boutique = await lieuNomme(tester, env, 'Boutique');
      await ouvrirLaVente(tester, env, vente.id);

      expect(dansConfirmation(find.text('Lieu de vente')), findsOneWidget);
      expect(dansConfirmation(find.text('Non renseigné')), findsOneWidget);

      await ouvrirFeuilleLieu(tester, dansConfirmation(find.text('Lieu de vente')));
      expect(cocheSur('Non renseigné'), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Boutique')));
      await tester.pump();
      await attendreElement(tester, find.text('Lieu enregistré.'));

      expect(dansConfirmation(find.text('Boutique')), findsOneWidget);
      expect((await ventesEnBase(tester, env)).single.lieuId, boutique.id);

      await ouvrirFeuilleLieu(tester, dansConfirmation(find.text('Lieu de vente')));
      expect(cocheSur('Boutique'), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Non renseigné')));
      await tester.pump();
      await attendreElement(tester, find.text('Lieu retiré : « Non renseigné ».'));

      expect(dansConfirmation(find.text('Non renseigné')), findsOneWidget);
      expect((await ventesEnBase(tester, env)).single.lieuId, isNull);

      await env.fermer(tester);
    });

    testWidgets('le lieu d’une vente annulée se corrige aussi, sans toucher aux montants ni au stock', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente marche = await lieuNomme(tester, env, 'Marché');
      final LieuVente salon = await lieuNomme(tester, env, 'Salon');
      final Vente vente = await env.validerVente(tester, produit: lapin, lieuId: marche.id);
      await env.travailler(tester, () => env.ventes.annuler(vente.id));
      final Vente avant = (await ventesEnBase(tester, env)).single;
      final int stockAvant = (await env.travailler(tester, () => env.produits.obtenir(lapin.id)))!.quantiteStock;
      await ouvrirLaVente(tester, env, vente.id);

      expect(dansConfirmation(find.text('Vente annulée')), findsOneWidget);
      expect(dansConfirmation(find.text('Marché')), findsOneWidget);

      await ouvrirFeuilleLieu(tester, dansConfirmation(find.text('Lieu de vente')));
      await tester.tap(dansFeuille(find.text('Salon')));
      await tester.pump();
      await attendreElement(tester, find.text('Lieu enregistré.'));

      expect(dansConfirmation(find.text('Salon')), findsOneWidget);
      final Vente apres = (await ventesEnBase(tester, env)).single;
      expect(apres.lieuId, salon.id);
      expect(apres.totalCentimes, avant.totalCentimes);
      expect(apres.statutPaiement, avant.statutPaiement);
      expect(apres.statut, avant.statut);
      final int stockApres = (await env.travailler(tester, () => env.produits.obtenir(lapin.id)))!.quantiteStock;
      expect(stockApres, stockAvant);

      await env.fermer(tester);
    });

    testWidgets('un lieu renommé s’affiche avec son nouveau nom sur la vente', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final Produit lapin = await env.creerProduit(tester);
      final LieuVente marche = await lieuNomme(tester, env, 'Marché');
      final Vente vente = await env.validerVente(tester, produit: lapin, lieuId: marche.id);
      await ouvrirLaVente(tester, env, vente.id);
      expect(dansConfirmation(find.text('Marché')), findsOneWidget);

      await env.ecrireEcranOuvert<LieuVente>(tester, () => env.lieux.renommer(marche.id, 'Marché du samedi'));
      await laisserFinir(tester);
      await attendreElement(tester, dansConfirmation(find.text('Marché du samedi')));

      expect(dansConfirmation(find.text('Marché')), findsNothing);

      await env.fermer(tester);
    });
  });
}
