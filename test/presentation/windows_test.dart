import 'dart:async';

import 'package:crochet_creations/core/plateforme.dart';
import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/domain/id_client_google.dart';
import 'package:crochet_creations/presentation/common/choix_photo.dart';
import 'package:crochet_creations/presentation/common/photo_retrouvee.dart';
import 'package:crochet_creations/presentation/notes/pieces_jointes_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/aide_drive.dart';
import 'aide_widget.dart';

// Une grande fenêtre d'ordinateur.
const Size _fenetre = Size(1600, 1000);

Future<void> ouvrirRoute(WidgetTester tester, String route) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Un bouton qui ouvre la feuille « photo » de l'application, sur la plateforme donnée.
class _OuvrirChoixPhoto extends ConsumerWidget {
  const _OuvrirChoixPhoto();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('ouvrir'),
          onPressed: () => demanderChoixPhoto(context, ref, retirable: false),
          child: const Text('Ouvrir'),
        ),
      ),
    );
  }
}

/// Un bouton qui ouvre la feuille « pièce jointe », avec ou sans appareil photo.
class _OuvrirSourcePiece extends StatelessWidget {
  const _OuvrirSourcePiece({required this.appareilPhoto});

  final bool appareilPhoto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('ouvrir'),
          onPressed: () => demanderSourcePieceJointe(context, appareilPhoto: appareilPhoto),
          child: const Text('Ouvrir'),
        ),
      ),
    );
  }
}

Future<void> ouvrirFeuille(WidgetTester tester, Widget page, {List<Override> overrides = const <Override>[]}) async {
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: page)));
  await tester.tap(find.byKey(const Key('ouvrir')));
  await tester.pumpAndSettle();
}

void main() {
  group('Windows : la même application, dans une fenêtre', () {
    testWidgets('Windows : le contenu garde la largeur d’un téléphone, centré dans la fenêtre', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.plateforme = const Plateforme.windows();
      await ouvrirAccueil(tester, env, taille: _fenetre);

      expect(tester.getSize(find.byType(NavigationBar)).width, Plateforme.largeurMaxContenu);
      final double centre = tester.getCenter(find.byType(NavigationBar)).dx;
      expect(centre, closeTo(_fenetre.width / 2, 0.5));
    });

    testWidgets('Android : le contenu prend toute la largeur, comme toujours', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirAccueil(tester, env, taille: _fenetre);

      expect(tester.getSize(find.byType(NavigationBar)).width, _fenetre.width);
    });

    testWidgets('Windows : l’écran Google Drive demande l’ID client et le code secret de l’accès « application de bureau »', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.plateforme = const Plateforme.windows();
      env.compteGoogle = FauxCompteGoogleBureau();
      await ouvrirAccueil(tester, env, taille: _fenetre);
      await ouvrirRoute(tester, AppRoutes.drive);

      expect(find.text('Accès Google « application de bureau »'), findsOneWidget);
      expect(find.byKey(const Key('drive-client-web-champ')), findsOneWidget);
      expect(find.byKey(const Key('drive-code-secret-champ')), findsOneWidget);
      expect(find.text('Code secret : pas encore enregistré.'), findsOneWidget);
      // Sans accès enregistré, pas de bouton de connexion : la carte de connexion dit de configurer d'abord.
      expect(find.byKey(const Key('drive-connecter')), findsNothing);
      expect(find.textContaining('sur ce téléphone'), findsNothing);
    });

    testWidgets('Windows : saisir l’ID puis le code secret rend la connexion possible', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final FauxCompteGoogleBureau compte = FauxCompteGoogleBureau();
      env.plateforme = const Plateforme.windows();
      env.compteGoogle = compte;
      await ouvrirAccueil(tester, env, taille: _fenetre);
      await ouvrirRoute(tester, AppRoutes.drive);

      // L'ID seul ne suffit pas.
      await tester.enterText(find.byKey(const Key('drive-client-web-champ')), '123456789012-abcdefghijkl$suffixeIdClientGoogle');
      await tester.ensureVisible(find.byKey(const Key('drive-client-web-enregistrer')));
      await tester.tap(find.byKey(const Key('drive-client-web-enregistrer')));
      await tester.pump();
      await laisserFinir(tester);
      expect(find.text('ID enregistré. Il manque encore le code secret du client.'), findsOneWidget);
      expect(find.byKey(const Key('drive-connecter')), findsNothing);

      // Le code secret complète l'accès.
      await tester.enterText(find.byKey(const Key('drive-code-secret-champ')), '${debutCodeSecretGoogle}AbCdEfGhIjKlMnOpQrStUvWxYz12');
      await tester.ensureVisible(find.byKey(const Key('drive-client-web-enregistrer')));
      await tester.tap(find.byKey(const Key('drive-client-web-enregistrer')));
      await tester.pump();
      await laisserFinir(tester);

      expect(compte.codeSecret, isNotNull);
      expect(find.text('Accès enregistré. Vous pouvez vous connecter à Google.'), findsOneWidget);
      expect(find.text('Code secret : enregistré sur cet ordinateur.'), findsOneWidget);
      expect(find.byKey(const Key('drive-connecter')), findsOneWidget);
    });

    testWidgets('Windows : un code secret qui est en fait l’ID client est refusé avec une explication', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.plateforme = const Plateforme.windows();
      env.compteGoogle = FauxCompteGoogleBureau();
      await ouvrirAccueil(tester, env, taille: _fenetre);
      await ouvrirRoute(tester, AppRoutes.drive);

      await tester.enterText(find.byKey(const Key('drive-client-web-champ')), '123456789012-abcdefghijkl$suffixeIdClientGoogle');
      await tester.enterText(find.byKey(const Key('drive-code-secret-champ')), '123456789012-abcdefghijkl$suffixeIdClientGoogle');
      await tester.ensureVisible(find.byKey(const Key('drive-client-web-enregistrer')));
      await tester.tap(find.byKey(const Key('drive-client-web-enregistrer')));
      await tester.pump();
      await laisserFinir(tester);

      expect(find.textContaining('ID client, pas le code secret'), findsOneWidget);
    });

    testWidgets('Android : l’écran Google Drive reste celui de l’ID client Web, sans code secret', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirAccueil(tester, env, taille: _fenetre);
      await ouvrirRoute(tester, AppRoutes.drive);

      expect(find.text('ID client Web Google'), findsOneWidget);
      expect(find.byKey(const Key('drive-code-secret-champ')), findsNothing);
      expect(find.text('Accès Google « application de bureau »'), findsNothing);
    });

    // Un environnement et un accueil par test : on n'en ouvre pas deux dans le même `testWidgets`.
    testWidgets('Windows : l’entrée « Google Drive » des Réglages décrit l’envoi sur Drive', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.plateforme = const Plateforme.windows();
      await ouvrirAccueil(tester, env, taille: _fenetre);
      await ouvrirRoute(tester, AppRoutes.reglages);

      expect(find.textContaining('Envoyer photos, factures, devis'), findsOneWidget);
      expect(find.textContaining('Pas encore disponible'), findsNothing);
    });

    testWidgets('Android : l’entrée « Google Drive » des Réglages décrit l’envoi sur Drive, comme toujours', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirAccueil(tester, env, taille: _fenetre);
      await ouvrirRoute(tester, AppRoutes.reglages);

      expect(find.textContaining('Envoyer photos, factures, devis'), findsOneWidget);
      expect(find.textContaining('Pas encore disponible'), findsNothing);
    });
  });

  group('Windows : pas d’appareil photo', () {
    testWidgets('feuille « photo » sous Windows : on choisit un fichier de l’ordinateur', (WidgetTester tester) async {
      await ouvrirFeuille(
        tester,
        const _OuvrirChoixPhoto(),
        overrides: <Override>[
          plateformeProvider.overrideWithValue(const Plateforme.windows()),
          photoRetrouveeInitialeProvider.overrideWithValue(null),
        ],
      );

      expect(find.text('Prendre une photo'), findsNothing);
      expect(find.text('Choisir une photo sur l’ordinateur'), findsOneWidget);
    });

    testWidgets('feuille « photo » sous Android : l’appareil photo et la galerie, comme toujours', (WidgetTester tester) async {
      await ouvrirFeuille(
        tester,
        const _OuvrirChoixPhoto(),
        overrides: <Override>[
          plateformeProvider.overrideWithValue(const Plateforme.android()),
          photoRetrouveeInitialeProvider.overrideWithValue(null),
        ],
      );

      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Choisir dans la galerie'), findsOneWidget);
    });

    testWidgets('feuille « pièce jointe » sans appareil photo : ni photo ni vidéo à prendre, mais des fichiers à choisir', (
      WidgetTester tester,
    ) async {
      await ouvrirFeuille(tester, const _OuvrirSourcePiece(appareilPhoto: false));

      expect(find.text('Prendre une photo'), findsNothing);
      expect(find.text('Filmer une vidéo'), findsNothing);
      expect(find.text('Choisir une photo sur l’ordinateur'), findsOneWidget);
      expect(find.text('Choisir une vidéo sur l’ordinateur'), findsOneWidget);
      expect(find.textContaining('Choisir un document'), findsOneWidget);
    });

    testWidgets('feuille « pièce jointe » avec appareil photo : les cinq choix d’Android', (WidgetTester tester) async {
      await ouvrirFeuille(tester, const _OuvrirSourcePiece(appareilPhoto: true));

      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Filmer une vidéo'), findsOneWidget);
      expect(find.text('Choisir une photo dans la galerie'), findsOneWidget);
      expect(find.text('Choisir une vidéo dans la galerie'), findsOneWidget);
      expect(find.textContaining('Choisir un document'), findsOneWidget);
    });
  });
}
