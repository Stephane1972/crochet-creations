import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/presentation/cours/cours_widgets.dart';
import 'package:crochet_creations/presentation/produits/produit_widgets.dart';
import 'package:crochet_creations/presentation/produits/produits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Photo prise juste avant qu'Android ferme l'application : retrouvée au démarrage, puis proposée dans la
/// feuille de choix de photo des formulaires (produit, cours, ticket de dépense).

/// Écran haut : les formulaires sont longs et ne sont construits qu'à mesure qu'on défile.
const Size _grandEcran = Size(800, 4000);

const String _proposition = 'Utiliser la photo retrouvée';

/// Ouvre l'application puis le formulaire « nouveau produit ».
Future<void> ouvrirFormulaireProduit(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Produits'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(find.descendant(of: find.byType(ProduitsScreen), matching: find.text('Ajouter')));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Ouvre l'application puis une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirFormulaire(WidgetTester tester, EnvironnementTest env, String route, Finder attendu) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await attendreJusqua(tester, () => attendu.evaluate().isNotEmpty);
  await laisserFinir(tester);
}

/// Nombre de fichiers présents dans le dossier des photos de l'application.
Future<int> nombreDePhotosCopiees(WidgetTester tester, EnvironnementTest env) {
  return env.travailler(
    tester,
    () async => env.dossierPhotos.existsSync() ? env.dossierPhotos.listSync().length : 0,
  );
}

void main() {
  testWidgets('formulaire produit : la photo retrouvée est proposée, utilisée, puis n’est plus proposée', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.photoRetrouvee = await env.photoGalerie(tester, 'IMG_perdue.jpg');
    await ouvrirFormulaireProduit(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    expect(find.text(_proposition), findsOneWidget);
    expect(find.text('Prendre une photo'), findsOneWidget); // les choix habituels restent là
    expect(find.text('Choisir dans la galerie'), findsOneWidget);

    await appuyer(tester, find.text(_proposition));
    await laisserFinir(tester);

    expect(env.selecteur.appels, 0, reason: 'ni appareil photo ni galerie : la photo est déjà là');
    expect(find.text('Ajouter la photo principale'), findsNothing);
    expect(find.byType(ImageProduit), findsOneWidget);
    expect(await nombreDePhotosCopiees(tester, env), 1, reason: 'copiée dans l’application comme toute photo');

    // Elle est « consommée » : la feuille suivante ne la propose plus.
    await appuyer(tester, find.byType(ImageProduit));
    expect(find.text(_proposition), findsNothing);
    expect(find.text('Retirer la photo'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('une autre photo choisie à la place fait oublier la photo retrouvée', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.photoRetrouvee = await env.photoGalerie(tester, 'IMG_perdue.jpg');
    env.selecteur.chemin = await env.photoGalerie(tester, 'IMG_galerie.jpg');
    await ouvrirFormulaireProduit(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    expect(find.text(_proposition), findsOneWidget);
    await appuyer(tester, find.text('Choisir dans la galerie'));
    await laisserFinir(tester);
    expect(env.selecteur.appels, 1);
    expect(find.byType(ImageProduit), findsOneWidget);

    await appuyer(tester, find.byType(ImageProduit));
    expect(find.text(_proposition), findsNothing);
    expect(find.text('Retirer la photo'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('refermer la feuille sans rien choisir garde la photo retrouvée pour plus tard', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.photoRetrouvee = await env.photoGalerie(tester, 'IMG_perdue.jpg');
    await ouvrirFormulaireProduit(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    expect(find.text(_proposition), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // en dehors de la feuille : elle se referme
    await tester.pumpAndSettle();
    expect(find.text(_proposition), findsNothing);
    expect(env.selecteur.appels, 0);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    expect(find.text(_proposition), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('une photo retrouvée dont le fichier a disparu n’est pas proposée', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.photoRetrouvee = '${env.dossier.path}/inexistante.jpg';
    await ouvrirFormulaireProduit(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    expect(find.text(_proposition), findsNothing);
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir dans la galerie'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('sans photo retrouvée, la feuille est celle d’avant', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirFormulaireProduit(tester, env);

    await appuyer(tester, find.text('Ajouter la photo principale'));
    expect(find.text(_proposition), findsNothing);
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir dans la galerie'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('formulaire cours : la photo retrouvée est proposée et utilisable', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.photoRetrouvee = await env.photoGalerie(tester, 'IMG_perdue.jpg');
    await ouvrirFormulaire(tester, env, AppRoutes.coursNouveau, find.text('Ajouter une photo'));

    await appuyer(tester, find.text('Ajouter une photo'));
    expect(find.text(_proposition), findsOneWidget);
    await appuyer(tester, find.text(_proposition));
    await laisserFinir(tester);

    expect(env.selecteur.appels, 0);
    expect(find.text('Ajouter une photo'), findsNothing);
    expect(find.byType(ImageCours), findsOneWidget);
    expect(await nombreDePhotosCopiees(tester, env), 1);

    await env.fermer(tester);
  });

  testWidgets('formulaire dépense : la photo retrouvée est proposée et utilisable pour le ticket', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.photoRetrouvee = await env.photoGalerie(tester, 'IMG_perdue.jpg');
    await ouvrirFormulaire(tester, env, AppRoutes.depenseNouvelle, find.text('Ajouter la photo du ticket'));

    await appuyer(tester, find.text('Ajouter la photo du ticket'));
    expect(find.text(_proposition), findsOneWidget);
    await appuyer(tester, find.text(_proposition));
    await laisserFinir(tester);

    expect(env.selecteur.appels, 0);
    expect(find.text('Ajouter la photo du ticket'), findsNothing);
    expect(find.text('Changer ou retirer la photo'), findsOneWidget);
    expect(await nombreDePhotosCopiees(tester, env), 1);

    await env.fermer(tester);
  });
}
