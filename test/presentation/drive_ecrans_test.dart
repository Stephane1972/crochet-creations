import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/presentation/drive/drive_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(2000, 4000);

// Vendredi 13 novembre 2026, 12 h 30.
final DateTime _maintenant = DateTime(2026, 11, 13, 12, 30);

const ProfilGoogle _camille = ProfilGoogle(email: 'camille@exemple.fr', nom: 'Camille');

Finder cle(String nom) => find.byKey(Key(nom));

/// Le texte affiché par le widget `Text` portant cette clé.
String texte(WidgetTester tester, String nom) => tester.widget<Text>(cle(nom)).data!;

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty, essais: 600);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pump(const Duration(milliseconds: 100));
}

/// Fait avancer le temps jusqu'à ce que [cible] ait disparu.
Future<void> attendreDisparition(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isEmpty, essais: 600);
  expect(cible, findsNothing, reason: 'Élément qui aurait dû disparaître : $cible');
}

/// Fait avancer le temps jusqu'à ce que le texte de la clé [nom] soit [attendu].
Future<void> attendreTexte(WidgetTester tester, String nom, String attendu) async {
  await attendreJusqua(
    tester,
    () => cle(nom).evaluate().isNotEmpty && tester.widget<Text>(cle(nom)).data == attendu,
    essais: 600,
  );
  expect(cle(nom), findsOneWidget, reason: 'Élément attendu : $nom');
  expect(texte(tester, nom), attendu);
}

/// Appuie sur un élément, laisse finir les animations et les lectures de la base, sans « pumpAndSettle » (une vérification
/// affiche une barre de progression qui ne se calme jamais).
Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pump();
  await tester.tap(cible);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await laisserFinir(tester);
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre l'application (à l'heure fixe) puis l'écran « Google Drive », compte et dernier bilan chargés.
Future<void> ouvrirEcran(WidgetTester tester, EnvironnementTest env) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.drive);
  await attendreDisparition(tester, cle('drive-chargement'));
  await attendreDisparition(tester, find.text('Lecture du bilan…'));
}

/// Cinq fichiers sur le téléphone : deux photos, une facture, un devis, une pièce jointe (41 octets en tout).
Future<void> remplirTelephone(WidgetTester tester, EnvironnementTest env) {
  return env.travailler(tester, () async {
    Future<void> ecrire(Directory dossier, String nom, String contenu) async {
      await dossier.create(recursive: true);
      await File('${dossier.path}/$nom').writeAsString(contenu);
    }

    await ecrire(env.dossierPhotos, 'photo_1.jpg', 'photo un');
    await ecrire(env.dossierPhotos, 'photo_2.jpg', 'photo deux');
    await ecrire(env.dossierFactures, 'FACT-2026-0001.pdf', 'facture un');
    await ecrire(env.dossierDevis, 'DEVIS-2026-0001.pdf', 'devis un');
    await ecrire(env.dossierPiecesJointes, 'piece_1.mp4', 'video');
  });
}

void main() {
  testWidgets('l’écran est atteint depuis « Plus », « Réglages », puis « Google Drive »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Réglages')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);

    await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Google Drive')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);

    expect(find.byType(DriveScreen), findsOneWidget);
    expect(find.text('Bientôt disponible'), findsNothing);

    await env.fermer(tester);
  });

  group('connexion', () {
    testWidgets('pas encore configuré : l’écran l’explique, sans bouton de connexion', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.configure = false;
      await ouvrirEcran(tester, env);

      expect(cle('drive-non-configure'), findsOneWidget);
      expect(find.textContaining('README'), findsOneWidget);
      expect(cle('drive-connecter'), findsNothing);
      expect(cle('drive-envoyer'), findsNothing);
      // Le dernier bilan reste visible.
      expect(texte(tester, 'drive-aucun-bilan'), 'Aucun envoi pour l’instant.');

      await env.fermer(tester);
    });

    testWidgets('personne n’est connecté : bouton « Se connecter à Google », pas d’envoi possible', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirEcran(tester, env);

      expect(cle('drive-non-connecte'), findsOneWidget);
      expect(cle('drive-connecter'), findsOneWidget);
      expect(cle('drive-envoyer'), findsNothing);
      expect(cle('drive-verifier'), findsNothing);
      expect(env.compteGoogle.connexions, 0);

      await env.fermer(tester);
    });

    testWidgets('se connecter : le compte s’affiche et l’envoi devient possible', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-connecter'));

      expect(env.compteGoogle.connexions, 1);
      expect(texte(tester, 'drive-compte'), 'stef@exemple.fr');
      expect(cle('drive-connecter'), findsNothing);
      expect(cle('drive-envoyer'), findsOneWidget);
      expect(cle('drive-verifier'), findsOneWidget);
      expect(cle('drive-deconnecter'), findsOneWidget);
      expect(cle('drive-erreur-connexion'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('déjà connecté au lancement : rien à demander', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      expect(texte(tester, 'drive-compte'), 'camille@exemple.fr');
      expect(env.compteGoogle.connexions, 0);
      expect(cle('drive-envoyer'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('fermer la fenêtre de connexion n’est pas une panne : aucun message', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.erreurDeConnexion = const ErreurDrive('Connexion annulée.', annulee: true);
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-connecter'));

      expect(env.compteGoogle.connexions, 1);
      expect(cle('drive-erreur-connexion'), findsNothing);
      expect(cle('drive-connecter'), findsOneWidget);
      expect(cle('drive-envoyer'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('une vraie panne de connexion est dite, puis disparaît quand on réussit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.erreurDeConnexion = const ErreurDrive('La configuration Google de l’application est incorrecte.');
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-connecter'));
      expect(texte(tester, 'drive-erreur-connexion'), 'La configuration Google de l’application est incorrecte.');
      expect(cle('drive-envoyer'), findsNothing);

      env.compteGoogle.erreurDeConnexion = null;
      await toucher(tester, cle('drive-connecter'));
      expect(cle('drive-erreur-connexion'), findsNothing);
      expect(texte(tester, 'drive-compte'), 'stef@exemple.fr');

      await env.fermer(tester);
    });

    testWidgets('se déconnecter : plus de compte, plus d’envoi, et les fichiers déjà sur Drive restent', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-fin-envoi'));
      final int surDrive = env.clientDrive.fichiers.length;
      expect(surDrive, 5);

      await toucher(tester, cle('drive-deconnecter'));

      expect(env.compteGoogle.deconnexions, 1);
      expect(cle('drive-non-connecte'), findsOneWidget);
      expect(cle('drive-envoyer'), findsNothing);
      expect(cle('drive-fin-envoi'), findsNothing);
      expect(env.clientDrive.fichiers.length, surDrive); // rien n'est supprimé sur Drive

      await env.fermer(tester);
    });
  });

  group('vérifier', () {
    testWidgets('dit ce qui reste à envoyer, sans rien créer ni envoyer sur Drive', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-verifier'));
      await attendre(tester, cle('drive-verification-resume'));

      expect(texte(tester, 'drive-verification-resume'), '5 fichiers à envoyer (41 o).');
      expect(
        texte(tester, 'drive-plan-photos'),
        'Photos des produits : 2 fichiers sur le téléphone · 0 déjà sur Drive · 2 à envoyer',
      );
      expect(
        texte(tester, 'drive-plan-factures'),
        'Factures : 1 fichier sur le téléphone · 0 déjà sur Drive · 1 à envoyer',
      );
      expect(texte(tester, 'drive-plan-devis'), 'Devis : 1 fichier sur le téléphone · 0 déjà sur Drive · 1 à envoyer');
      expect(
        texte(tester, 'drive-plan-notes'),
        'Notes - pièces jointes : 1 fichier sur le téléphone · 0 déjà sur Drive · 1 à envoyer',
      );
      // Vérifier ne crée rien.
      expect(env.clientDrive.dossiersCrees, 0);
      expect(env.clientDrive.fichiers, isEmpty);
      // Les deux boutons sont de nouveau proposés.
      expect(cle('drive-envoyer'), findsOneWidget);
      expect(cle('drive-verifier'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('Google injoignable : l’erreur est dite, et on peut réessayer', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-verifier'));
      await attendre(tester, cle('drive-erreur'));

      expect(texte(tester, 'drive-erreur'), 'Pas de connexion à Internet.');
      expect(cle('drive-envoyer'), findsOneWidget);

      env.clientDrive.panne = null;
      await toucher(tester, cle('drive-verifier'));
      await attendre(tester, cle('drive-verification-resume'));
      expect(cle('drive-erreur'), findsNothing);
      expect(texte(tester, 'drive-verification-resume'), 'Tout est déjà sur Drive.'); // rien sur le téléphone

      await env.fermer(tester);
    });
  });

  group('envoyer', () {
    testWidgets('tout part sur Drive, et le bilan est montré puis gardé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);
      expect(texte(tester, 'drive-aucun-bilan'), 'Aucun envoi pour l’instant.');

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-fin-envoi'));
      await attendre(tester, cle('drive-bilan-resume'));

      expect(texte(tester, 'drive-fin-envoi'), 'Envoi terminé : tout est sur Drive.');
      expect(texte(tester, 'drive-bilan-date'), '${formatDateLongue(_maintenant)} à ${formatHeure(_maintenant)}');
      expect(texte(tester, 'drive-bilan-resume'), '5 fichiers envoyés (41 o) · 0 déjà sur Drive');
      expect(texte(tester, 'drive-bilan-etat'), 'Tout est sur Drive.');
      expect(cle('drive-bilan-erreur-0'), findsNothing);

      // Sur le faux Drive : les quatre sous-dossiers, et chaque fichier à sa place.
      expect(env.clientDrive.nomsDans('Photos des produits'), <String>['photo_1.jpg', 'photo_2.jpg']);
      expect(env.clientDrive.nomsDans('Factures'), <String>['FACT-2026-0001.pdf']);
      expect(env.clientDrive.nomsDans('Devis'), <String>['DEVIS-2026-0001.pdf']);
      expect(env.clientDrive.nomsDans('Notes - pièces jointes'), <String>['piece_1.mp4']);

      // Le bilan est gardé sur le téléphone.
      final bool gardeBilan = await env.travailler(tester, () async => (await env.serviceDrive.dernierBilan())?.complet ?? false);
      expect(gardeBilan, isTrue);

      await env.fermer(tester);
    });

    testWidgets('un second envoi ne renvoie rien : Drive est la mémoire', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-fin-envoi'));
      await attendreTexte(tester, 'drive-bilan-resume', '5 fichiers envoyés (41 o) · 0 déjà sur Drive');
      expect(env.clientDrive.envoyes, hasLength(5));

      // La vérification le sait…
      await toucher(tester, cle('drive-verifier'));
      await attendre(tester, cle('drive-verification-resume'));
      expect(texte(tester, 'drive-verification-resume'), 'Tout est déjà sur Drive.');
      expect(
        texte(tester, 'drive-plan-photos'),
        'Photos des produits : 2 fichiers sur le téléphone · 2 déjà sur Drive · 0 à envoyer',
      );

      // … et l'envoi n'envoie rien de plus.
      await toucher(tester, cle('drive-envoyer'));
      await attendreTexte(tester, 'drive-bilan-resume', '0 fichier envoyé (0 o) · 5 déjà sur Drive');
      expect(texte(tester, 'drive-fin-envoi'), 'Envoi terminé : tout est sur Drive.');
      expect(env.clientDrive.envoyes, hasLength(5));

      await env.fermer(tester);
    });

    testWidgets('le dernier bilan est montré dès l’ouverture, même sans connexion', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.maintenant = _maintenant;
      await env.travailler(tester, () => env.serviceDrive.envoyer());

      await ouvrirEcran(tester, env);

      expect(cle('drive-connecter'), findsOneWidget);
      expect(texte(tester, 'drive-bilan-resume'), '5 fichiers envoyés (41 o) · 0 déjà sur Drive');
      expect(texte(tester, 'drive-bilan-etat'), 'Tout est sur Drive.');
      expect(cle('drive-aucun-bilan'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('un fichier refusé n’empêche pas les autres, et le bilan le dit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.echecEnvoi = (String nom) => nom == 'photo_2.jpg' ? const ErreurDrive('Fichier refusé par Drive.') : null;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-fin-envoi'));
      await attendre(tester, cle('drive-bilan-resume'));

      expect(
        texte(tester, 'drive-fin-envoi'),
        'Envoi terminé, mais certains fichiers n’ont pas pu partir (voir le bilan plus bas).',
      );
      expect(texte(tester, 'drive-bilan-resume'), '4 fichiers envoyés (31 o) · 0 déjà sur Drive');
      expect(texte(tester, 'drive-bilan-etat'), startsWith('Envoi incomplet : certains fichiers n’ont pas pu partir.'));
      expect(texte(tester, 'drive-bilan-erreur-0'), 'Photos des produits · photo_2.jpg : Fichier refusé par Drive.');
      expect(cle('drive-bilan-erreur-1'), findsNothing);
      expect(env.clientDrive.nomsDans('Photos des produits'), <String>['photo_1.jpg']);

      // En relançant, seul ce qui manque repart.
      env.clientDrive.echecEnvoi = null;
      await toucher(tester, cle('drive-envoyer'));
      await attendreTexte(tester, 'drive-bilan-resume', '1 fichier envoyé (10 o) · 4 déjà sur Drive');
      expect(texte(tester, 'drive-bilan-etat'), 'Tout est sur Drive.');
      expect(env.clientDrive.nomsDans('Photos des produits'), <String>['photo_1.jpg', 'photo_2.jpg']);

      await env.fermer(tester);
    });

    testWidgets('l’autorisation expire en cours d’envoi : on s’arrête, et il faut se reconnecter', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.echecEnvoi = (_) => const ErreurDrive('L’autorisation Google Drive a expiré. Reconnectez-vous.', autorisationAExpire: true);
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      // La connexion est perdue : l'écran repasse à « Non connecté ».
      await attendre(tester, cle('drive-connecter'));
      await attendre(tester, cle('drive-bilan-etat'));

      expect(cle('drive-envoyer'), findsNothing);
      expect(texte(tester, 'drive-bilan-etat'), startsWith('Envoi incomplet : il s’est arrêté avant la fin.'));
      expect(texte(tester, 'drive-bilan-erreur-0'), contains('L’autorisation Google Drive a expiré'));
      expect(env.clientDrive.envoyes, isEmpty); // rien n'a été insisté après le refus
      expect(env.clientDrive.fichiers, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('Google injoignable avant de commencer : rien ne part, le bilan d’avant est gardé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-erreur'));

      expect(texte(tester, 'drive-erreur'), 'Pas de connexion à Internet.');
      expect(texte(tester, 'drive-aucun-bilan'), 'Aucun envoi pour l’instant.');
      expect(env.clientDrive.envoyes, isEmpty);
      expect(cle('drive-envoyer'), findsOneWidget); // on peut réessayer

      await env.fermer(tester);
    });

    testWidgets('« Arrêter » : l’envoi s’arrête à la fin du fichier en cours', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      // Le premier envoi est « gardé » en cours, le temps de regarder l'écran.
      final Completer<void> feuVert = Completer<void>();
      env.clientDrive.pauseEnvoi = (_) => feuVert.future;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-fichier-en-cours'));

      expect(texte(tester, 'drive-progression-texte'), startsWith('0 sur 5 fichiers · 0 o sur 41 o'));
      expect(cle('drive-progression'), findsOneWidget);
      expect(cle('drive-arreter'), findsOneWidget);
      expect(cle('drive-envoyer'), findsNothing); // pas deux envois à la fois

      await toucher(tester, cle('drive-arreter'));
      expect(cle('drive-arret-demande'), findsOneWidget);
      expect(cle('drive-arreter'), findsNothing);

      // Le fichier en cours finit, puis l'envoi s'arrête.
      feuVert.complete();
      await attendre(tester, cle('drive-fin-envoi'));
      await attendre(tester, cle('drive-bilan-etat'));

      expect(texte(tester, 'drive-fin-envoi'), 'Envoi arrêté avant la fin.');
      expect(env.clientDrive.envoyes, hasLength(1));
      expect(texte(tester, 'drive-bilan-etat'), startsWith('Envoi incomplet : il s’est arrêté avant la fin.'));
      expect(cle('drive-bilan-erreur-0'), findsNothing);
      expect(cle('drive-envoyer'), findsOneWidget);

      await env.fermer(tester);
    });
  });
}
