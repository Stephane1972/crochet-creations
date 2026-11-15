import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:crochet_creations/domain/id_client_google.dart';
import 'package:crochet_creations/presentation/drive/drive_providers.dart';
import 'package:crochet_creations/presentation/drive/drive_restauration_screen.dart';
import 'package:crochet_creations/presentation/drive/drive_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  await attendreDisparition(tester, find.text('Lecture du réglage…'));
}

String _dateHeure(DateTime date) => '${formatDateLongue(date)} à ${formatHeure(date)}';

Finder dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

/// Les noms des produits de la base, triés. À appeler quand plus aucun écran ne lit la base en direct.
Future<List<String>> nomsProduits(WidgetTester tester, EnvironnementTest env) {
  return env.travailler(tester, () async {
    final List<Produit> produits = await env.db.select(env.db.produits).get();
    return produits.map((Produit p) => p.nom).toList()..sort();
  });
}

/// Fait la sauvegarde sur Drive à l'heure [quand], sans passer par l'écran (aucun écran ne doit lire la base en direct).
Future<void> sauvegarderSurDrive(WidgetTester tester, EnvironnementTest env, DateTime quand) async {
  env.maintenant = quand;
  await env.travailler(tester, () => env.serviceSauvegardeDrive.sauvegarder());
}

/// Les fichiers qui restent sous [dossier] (aucun s'il n'existe pas).
Future<List<String>> fichiersSous(WidgetTester tester, EnvironnementTest env, Directory dossier) {
  return env.travailler(tester, () async {
    if (!await dossier.exists()) return <String>[];
    return <String>[
      await for (final FileSystemEntity e in dossier.list(recursive: true))
        if (e is File) e.path,
    ];
  });
}

/// Ouvre l'application puis l'écran « Restaurer depuis Drive », liste chargée (ou en erreur).
Future<void> ouvrirRestauration(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.driveRestauration);
  await attendreDisparition(tester, cle('drive-restauration-chargement'));
}

/// Un bouton ou un interrupteur est-il inactif ?
bool inactif(WidgetTester tester, String nom) {
  final Widget w = tester.widget<Widget>(cle(nom));
  if (w is ButtonStyleButton) return w.onPressed == null;
  if (w is SwitchListTile) return w.onChanged == null;
  if (w is ListTile) return !w.enabled;
  throw StateError('Ni bouton, ni interrupteur : $nom');
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

  group('ID client Web', () {
    const String id = '123456789012-abcdefghijklmnopqrstuvwxyz012345$suffixeIdClientGoogle';
    const String autreId = '987654321098-zyxwvutsrqponmlkjihgfedcba543210$suffixeIdClientGoogle';

    Future<void> saisirEtEnregistrer(WidgetTester tester, String saisie) async {
      await tester.enterText(cle('drive-client-web-champ'), saisie);
      await tester.pump();
      await toucher(tester, cle('drive-client-web-enregistrer'));
    }

    testWidgets('pas encore configuré : coller l’ID suffit, sans nouvelle version de l’application', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.configure = false;
      await ouvrirEcran(tester, env);

      expect(cle('drive-client-web-champ'), findsOneWidget);
      expect(texte(tester, 'drive-client-web-etat'), startsWith('Aucun ID client Web n’est enregistré'));
      expect(cle('drive-client-web-oublier'), findsNothing);
      expect(cle('drive-connecter'), findsNothing);

      // Ce qu'on colle peut venir avec des espaces et un retour à la ligne.
      await saisirEtEnregistrer(tester, '  $id \n');

      expect(env.compteGoogle.idEnregistre, id);
      expect(cle('drive-client-web-erreur'), findsNothing);
      expect(texte(tester, 'drive-client-web-ok'), 'ID enregistré. Vous pouvez vous connecter à Google.');
      expect(texte(tester, 'drive-client-web-etat'), 'ID enregistré sur ce téléphone :');
      expect(texte(tester, 'drive-client-web-id'), id);
      expect(cle('drive-non-configure'), findsNothing);
      expect(cle('drive-connecter'), findsOneWidget);
      expect(cle('drive-client-web-oublier'), findsOneWidget);

      // La connexion devient possible ; une fois connecté, la carte de l'ID disparaît.
      await toucher(tester, cle('drive-connecter'));
      expect(texte(tester, 'drive-compte'), 'stef@exemple.fr');
      expect(cle('drive-client-web-champ'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('ce qui n’est pas un ID client est refusé, avec la raison, et rien n’est enregistré', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.configure = false;
      await ouvrirEcran(tester, env);

      await saisirEtEnregistrer(tester, 'bonjour');
      expect(
        texte(tester, 'drive-client-web-erreur'),
        'Ce n’est pas un ID client Google : il doit se terminer par .apps.googleusercontent.com.',
      );

      await saisirEtEnregistrer(tester, '');
      expect(texte(tester, 'drive-client-web-erreur'), startsWith('Collez l’ID client Web'));

      expect(env.compteGoogle.idEnregistre, isNull);
      expect(cle('drive-client-web-ok'), findsNothing);
      expect(cle('drive-non-configure'), findsOneWidget);
      expect(cle('drive-connecter'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('le « code secret » est refusé : il ne doit jamais être collé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.configure = false;
      await ouvrirEcran(tester, env);

      await saisirEtEnregistrer(tester, '${debutCodeSecretGoogle}AbCdEfGhIjKlMnOpQrStUvWxYz12');

      expect(texte(tester, 'drive-client-web-erreur'), startsWith('Ceci est un « code secret »'));
      expect(env.compteGoogle.idEnregistre, isNull);

      await env.fermer(tester);
    });

    testWidgets('un enregistrement impossible sur le téléphone est dit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.configure = false;
      env.compteGoogle.erreurDEnregistrement = const ErreurDrive('Impossible d’enregistrer l’ID sur le téléphone.');
      await ouvrirEcran(tester, env);

      await saisirEtEnregistrer(tester, id);

      expect(texte(tester, 'drive-client-web-erreur'), 'Impossible d’enregistrer l’ID sur le téléphone.');
      expect(cle('drive-client-web-ok'), findsNothing);
      expect(cle('drive-non-configure'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('un ID déjà enregistré s’affiche dans le champ et peut être corrigé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.idEnregistre = id;
      await ouvrirEcran(tester, env);

      expect(tester.widget<TextField>(cle('drive-client-web-champ')).controller!.text, id);
      expect(texte(tester, 'drive-client-web-etat'), 'ID enregistré sur ce téléphone :');
      expect(texte(tester, 'drive-client-web-id'), id);
      expect(cle('drive-connecter'), findsOneWidget);

      await saisirEtEnregistrer(tester, autreId);

      expect(env.compteGoogle.idEnregistre, autreId);
      expect(texte(tester, 'drive-client-web-id'), autreId);

      await env.fermer(tester);
    });

    testWidgets('« Oublier l’ID enregistré » : la connexion n’est plus configurée', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.configure = false;
      await ouvrirEcran(tester, env);
      await saisirEtEnregistrer(tester, id);
      expect(cle('drive-connecter'), findsOneWidget);

      await toucher(tester, cle('drive-client-web-oublier'));

      expect(env.compteGoogle.idEnregistre, isNull);
      expect(cle('drive-non-configure'), findsOneWidget);
      expect(cle('drive-connecter'), findsNothing);
      expect(cle('drive-client-web-oublier'), findsNothing);
      expect(tester.widget<TextField>(cle('drive-client-web-champ')).controller!.text, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('un ID fourni avec l’application est annoncé comme tel, sans bouton pour l’oublier', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirEcran(tester, env); // configuré d'origine, rien d'enregistré

      expect(texte(tester, 'drive-client-web-etat'), 'ID fourni avec l’application :');
      expect(tester.widget<TextField>(cle('drive-client-web-champ')).controller!.text, isEmpty);
      expect(cle('drive-client-web-oublier'), findsNothing);
      expect(cle('drive-connecter'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('un nouvel ID qui demande de relancer l’application le dit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.redemarrageNecessaire = true;
      await ouvrirEcran(tester, env);

      expect(texte(tester, 'drive-client-web-redemarrage'), startsWith('Fermez complètement l’application'));

      await saisirEtEnregistrer(tester, id);

      expect(texte(tester, 'drive-client-web-ok'), contains('fermez complètement l’application'));
      expect(cle('drive-client-web-redemarrage'), findsNothing);

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

  group('sauvegarder sur Drive', () {
    testWidgets('pas connecté : la carte n’est pas proposée', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirEcran(tester, env);

      expect(cle('drive-sauvegarder'), findsNothing);
      expect(cle('drive-restaurer'), findsNothing);
      expect(cle('drive-auto-interrupteur'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('au départ : rien de sauvegardé, envoi automatique désactivé, les deux boutons', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      expect(texte(tester, 'drive-aucune-sauvegarde'), 'Aucune sauvegarde sur Drive pour l’instant.');
      expect(tester.widget<SwitchListTile>(cle('drive-auto-interrupteur')).value, isFalse);
      expect(cle('drive-sauvegarder'), findsOneWidget);
      expect(cle('drive-restaurer'), findsOneWidget);
      expect(cle('drive-non-envoyes'), findsNothing);
      expect(inactif(tester, 'drive-sauvegarder'), isFalse);

      await env.fermer(tester);
    });

    testWidgets('« Sauvegarder maintenant » : les fichiers partent, puis les données, et la sauvegarde est vérifiée', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-sauvegarder'));
      await attendre(tester, cle('drive-sauvegarde-fin'));
      await attendre(tester, cle('drive-derniere-sauvegarde'));

      expect(texte(tester, 'drive-sauvegarde-fin'), 'Sauvegarde envoyée sur Drive et vérifiée.');
      expect(texte(tester, 'drive-derniere-sauvegarde'), 'Dernière sauvegarde : ${_dateHeure(_maintenant)}');
      expect(texte(tester, 'drive-derniere-sauvegarde-detail'), endsWith('5 fichiers listés'));
      expect(cle('drive-aucune-sauvegarde'), findsNothing);
      expect(cle('drive-non-envoyes'), findsNothing);
      expect(cle('drive-sauvegarde-erreur'), findsNothing);
      // Les boutons sont de nouveau proposés.
      expect(cle('drive-sauvegarder'), findsOneWidget);
      expect(cle('drive-restaurer'), findsOneWidget);

      // Sur Drive : les fichiers dans leurs dossiers, et une petite sauvegarde, datée, dans « Sauvegardes ».
      expect(env.clientDrive.nomsDans('Photos des produits'), <String>['photo_1.jpg', 'photo_2.jpg']);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), <String>[nomSauvegardeDrive(_maintenant)]);
      // Le bilan des fichiers (carte « Dernier envoi ») est à jour.
      await attendreTexte(tester, 'drive-bilan-resume', '5 fichiers envoyés (41 o) · 0 déjà sur Drive');

      await env.fermer(tester);
    });

    testWidgets('sans changement : « rien de neuf », aucune nouvelle sauvegarde, et la vérification est datée', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-sauvegarder'));
      await attendre(tester, cle('drive-derniere-sauvegarde'));
      expect(env.clientDrive.envoyes, hasLength(6)); // cinq fichiers, une sauvegarde

      final DateTime plusTard = _maintenant.add(const Duration(hours: 3));
      env.maintenant = plusTard;
      await toucher(tester, cle('drive-sauvegarder'));
      await attendreTexte(tester, 'drive-sauvegarde-fin', 'Rien de neuf : la dernière sauvegarde sur Drive est à jour.');
      await attendre(tester, cle('drive-derniere-verification'));

      expect(texte(tester, 'drive-derniere-verification'), 'Vérifiée le ${_dateHeure(plusTard)} : rien de neuf depuis.');
      expect(texte(tester, 'drive-derniere-sauvegarde'), 'Dernière sauvegarde : ${_dateHeure(_maintenant)}');
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), hasLength(1));
      expect(env.clientDrive.envoyes, hasLength(6)); // rien de plus n'est parti

      await env.fermer(tester);
    });

    testWidgets('l’envoi automatique s’active et se désactive, et le réglage est gardé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);
      bool actif() => tester.widget<SwitchListTile>(cle('drive-auto-interrupteur')).value;

      await toucher(tester, cle('drive-auto-interrupteur'));
      await attendreJusqua(tester, actif, essais: 300);
      expect(actif(), isTrue);
      expect((await env.travailler(tester, () => env.serviceSauvegardeDrive.lireEtat())).envoiAutomatique, isTrue);

      await toucher(tester, cle('drive-auto-interrupteur'));
      await attendreJusqua(tester, () => !actif(), essais: 300);
      expect(actif(), isFalse);
      expect((await env.travailler(tester, () => env.serviceSauvegardeDrive.lireEtat())).envoiAutomatique, isFalse);

      // Activer ne lance rien : la sauvegarde se fait à l'ouverture suivante.
      expect(env.clientDrive.envoyes, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('Google injoignable : l’erreur est dite, et on peut réessayer', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-sauvegarder'));
      await attendre(tester, cle('drive-sauvegarde-erreur'));

      expect(texte(tester, 'drive-sauvegarde-erreur'), 'Pas de connexion à Internet.');
      expect(cle('drive-sauvegarder'), findsOneWidget);
      expect(env.clientDrive.fichiers, isEmpty);

      env.clientDrive.panne = null;
      await toucher(tester, cle('drive-sauvegarder'));
      await attendre(tester, cle('drive-sauvegarde-fin'));
      expect(cle('drive-sauvegarde-erreur'), findsNothing);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), <String>[nomSauvegardeDrive(_maintenant)]);

      await env.fermer(tester);
    });

    testWidgets('un fichier refusé : la sauvegarde est faite sans lui, la carte le dit, et le prochain essai le renvoie', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.echecEnvoi = (String nom) => nom == 'photo_2.jpg' ? const ErreurDrive('Fichier refusé par Drive.') : null;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-sauvegarder'));
      await attendre(tester, cle('drive-sauvegarde-fin'));
      await attendre(tester, cle('drive-non-envoyes'));

      expect(texte(tester, 'drive-sauvegarde-fin'), 'Sauvegarde envoyée sur Drive et vérifiée.');
      expect(
        texte(tester, 'drive-non-envoyes'),
        '1 fichier n’a pas pu partir sur Drive et n’est pas listé dans la dernière sauvegarde (photo_2.jpg). '
        'Relancez la sauvegarde pour réessayer.',
      );
      expect(texte(tester, 'drive-derniere-sauvegarde-detail'), endsWith('4 fichiers listés'));
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), <String>[nomSauvegardeDrive(_maintenant)]);

      // Le fichier est accepté cette fois : il part, et une nouvelle sauvegarde, qui le liste, est ajoutée (l'ancienne reste).
      env.clientDrive.echecEnvoi = null;
      final DateTime plusTard = _maintenant.add(const Duration(hours: 1));
      env.maintenant = plusTard;
      await toucher(tester, cle('drive-sauvegarder'));
      await attendreDisparition(tester, cle('drive-non-envoyes'));
      await attendreTexte(tester, 'drive-derniere-sauvegarde', 'Dernière sauvegarde : ${_dateHeure(plusTard)}');

      expect(texte(tester, 'drive-derniere-sauvegarde-detail'), endsWith('5 fichiers listés'));
      expect(env.clientDrive.nomsDans('Photos des produits'), <String>['photo_1.jpg', 'photo_2.jpg']);
      expect(
        env.clientDrive.nomsDans(nomDossierSauvegardesDrive),
        <String>[nomSauvegardeDrive(_maintenant), nomSauvegardeDrive(plusTard)],
      );

      await env.fermer(tester);
    });

    testWidgets('« Arrêter » : l’envoi s’arrête, les données ne sont pas sauvegardées, et rien d’autre ne peut partir', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      final Completer<void> feuVert = Completer<void>();
      env.clientDrive.pauseEnvoi = (_) => feuVert.future;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-sauvegarder'));
      await attendre(tester, cle('drive-sauvegarde-fichier-en-cours'));

      expect(cle('drive-sauvegarde-progression'), findsOneWidget);
      expect(texte(tester, 'drive-sauvegarde-etape'), startsWith('Étape 1 sur 3 : envoi des fichiers (0 sur 5 fichiers'));
      expect(cle('drive-sauvegarder'), findsNothing); // pas deux sauvegardes à la fois
      expect(cle('drive-sauvegarde-automatique'), findsNothing);
      // Pas d'autre envoi en même temps, ni de changement de réglage.
      expect(inactif(tester, 'drive-envoyer'), isTrue);
      expect(inactif(tester, 'drive-verifier'), isTrue);
      expect(inactif(tester, 'drive-auto-interrupteur'), isTrue);

      await toucher(tester, cle('drive-sauvegarde-arreter'));
      expect(cle('drive-sauvegarde-arret-demande'), findsOneWidget);
      expect(cle('drive-sauvegarde-arreter'), findsNothing);

      feuVert.complete();
      await attendre(tester, cle('drive-sauvegarde-fin'));

      expect(
        texte(tester, 'drive-sauvegarde-fin'),
        'Envoi arrêté avant la fin : les données n’ont pas été sauvegardées sur Drive.',
      );
      expect(cle('drive-sauvegarde-arret'), findsNothing); // arrêt voulu : pas une panne
      expect(env.clientDrive.envoyes, hasLength(1));
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), isEmpty);
      await attendreTexte(tester, 'drive-aucune-sauvegarde', 'Aucune sauvegarde sur Drive pour l’instant.');
      expect(cle('drive-sauvegarder'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('pendant un envoi des fichiers : sauvegarder et restaurer sont bloqués', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      final Completer<void> feuVert = Completer<void>();
      env.clientDrive.pauseEnvoi = (_) => feuVert.future;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-envoyer'));
      await attendre(tester, cle('drive-fichier-en-cours'));
      expect(inactif(tester, 'drive-sauvegarder'), isTrue);
      expect(inactif(tester, 'drive-restaurer'), isTrue);

      feuVert.complete();
      await attendre(tester, cle('drive-fin-envoi'));
      expect(inactif(tester, 'drive-sauvegarder'), isFalse);
      expect(inactif(tester, 'drive-restaurer'), isFalse);

      await env.fermer(tester);
    });

    testWidgets('l’autorisation expire en cours de route : on s’arrête, il faut se reconnecter, rien n’est sauvegardé', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.echecEnvoi = (_) =>
          const ErreurDrive('L’autorisation Google Drive a expiré. Reconnectez-vous.', autorisationAExpire: true);
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-sauvegarder'));
      // La connexion est perdue : l'écran repasse à « Non connecté ».
      await attendre(tester, cle('drive-connecter'));

      expect(cle('drive-sauvegarder'), findsNothing);
      expect(env.clientDrive.fichiers, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('envoi automatique à l’ouverture : la carte le dit pendant qu’il tourne, puis donne le résultat', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      env.compteGoogle.dejaConnecte = _camille;
      await env.travailler(tester, () => env.serviceSauvegardeDrive.reglerEnvoiAutomatique(actif: true));
      final Completer<void> feuVert = Completer<void>();
      env.clientDrive.pauseEnvoi = (_) => feuVert.future;
      await ouvrirEcran(tester, env);
      expect(tester.widget<SwitchListTile>(cle('drive-auto-interrupteur')).value, isTrue);

      // Ce que fait l'application à son ouverture.
      final ProviderContainer conteneur = ProviderScope.containerOf(tester.element(find.byType(DriveScreen)));
      unawaited(conteneur.read(sauvegardeDriveProvider.notifier).lancerSiBesoin());
      await attendre(tester, cle('drive-sauvegarde-automatique'));
      expect(texte(tester, 'drive-sauvegarde-automatique'), 'Sauvegarde automatique en cours.');

      feuVert.complete();
      await attendre(tester, cle('drive-sauvegarde-fin'));
      expect(texte(tester, 'drive-sauvegarde-fin'), 'Sauvegarde envoyée sur Drive et vérifiée.');
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), <String>[nomSauvegardeDrive(_maintenant)]);

      await env.fermer(tester);
    });

    testWidgets('envoi automatique en échec : la carte dit que c’est l’envoi automatique', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await env.travailler(tester, () => env.serviceSauvegardeDrive.reglerEnvoiAutomatique(actif: true));
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await ouvrirEcran(tester, env);

      final ProviderContainer conteneur = ProviderScope.containerOf(tester.element(find.byType(DriveScreen)));
      unawaited(conteneur.read(sauvegardeDriveProvider.notifier).lancerSiBesoin());
      await attendre(tester, cle('drive-sauvegarde-erreur'));

      expect(texte(tester, 'drive-sauvegarde-erreur'), 'La sauvegarde automatique a échoué : Pas de connexion à Internet.');
      expect(cle('drive-sauvegarder'), findsOneWidget);

      await env.fermer(tester);
    });
  });

  group('restaurer depuis Drive', () {
    testWidgets('on y arrive depuis l’écran Google Drive ; sans sauvegarde sur Drive, la liste le dit', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirEcran(tester, env);

      await toucher(tester, cle('drive-restaurer'));
      expect(find.byType(DriveRestaurationScreen), findsOneWidget);
      await attendre(tester, cle('drive-restauration-aucune'));

      expect(cle('drive-sauvegarde-0'), findsNothing);
      expect(find.textContaining('Pour changer de téléphone'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('Google injoignable : l’erreur est dite, et « Réessayer » relit la liste', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await ouvrirRestauration(tester, env);
      await attendre(tester, cle('drive-restauration-liste-erreur'));

      expect(texte(tester, 'drive-restauration-liste-erreur'), 'Pas de connexion à Internet.');

      env.clientDrive.panne = null;
      await toucher(tester, cle('drive-restauration-reessayer'));
      await attendre(tester, cle('drive-restauration-aucune'));
      expect(cle('drive-restauration-liste-erreur'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('autorisation expirée : il faut se reconnecter', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.clientDrive.panne = const ErreurDrive('L’autorisation Google Drive a expiré. Reconnectez-vous.', autorisationAExpire: true);
      await ouvrirRestauration(tester, env);
      await attendre(tester, cle('drive-restauration-liste-erreur'));

      expect(texte(tester, 'drive-restauration-liste-erreur'), 'L’autorisation Google Drive a expiré. Reconnectez-vous.');
      expect(find.textContaining('Reconnectez-vous à Google (écran Google Drive)'), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('la liste montre la plus récente d’abord', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      await sauvegarderSurDrive(tester, env, _maintenant);
      await env.creerProduit(tester, nom: 'Bonnet');
      final DateTime plusTard = _maintenant.add(const Duration(days: 2));
      await sauvegarderSurDrive(tester, env, plusTard);
      await ouvrirRestauration(tester, env);

      Finder dans(String tuile, Finder cible) => find.descendant(of: cle(tuile), matching: cible);
      expect(dans('drive-sauvegarde-0', find.text(_dateHeure(plusTard))), findsOneWidget);
      expect(dans('drive-sauvegarde-0', find.textContaining('La plus récente')), findsOneWidget);
      expect(dans('drive-sauvegarde-1', find.text(_dateHeure(_maintenant))), findsOneWidget);
      expect(dans('drive-sauvegarde-1', find.textContaining('La plus récente')), findsNothing);
      expect(cle('drive-sauvegarde-2'), findsNothing);

      await env.fermer(tester);
    });

    testWidgets('restaurer : confirmation, fichiers retéléchargés depuis Drive, données remplacées, retour à l’accueil', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await sauvegarderSurDrive(tester, env, _maintenant);
      // Depuis la sauvegarde : un produit de plus, et une photo perdue.
      await env.creerProduit(tester, nom: 'Bonnet');
      await env.travailler(tester, () => File('${env.dossierPhotos.path}/photo_1.jpg').delete());
      env.maintenant = _maintenant.add(const Duration(days: 1));
      await ouvrirRestauration(tester, env);

      await toucher(tester, cle('drive-sauvegarde-0'));
      await attendre(tester, find.text('Restaurer cette sauvegarde ?'));
      expect(dansDialogue(find.textContaining('Sauvegarde du ${_dateHeure(_maintenant)}')), findsOneWidget);
      expect(dansDialogue(find.textContaining('5 fichiers')), findsOneWidget);
      expect(dansDialogue(find.textContaining('(41 o)')), findsOneWidget);
      expect(dansDialogue(find.textContaining('copie de sécurité')), findsOneWidget);
      // À ce stade, seule la petite sauvegarde est descendue de Drive.
      expect(env.clientDrive.telecharges, <String>[nomSauvegardeDrive(_maintenant)]);

      await toucher(tester, dansDialogue(find.text('Restaurer')));
      await attendre(tester, find.text('Restauration terminée'));
      expect(dansDialogue(find.textContaining('remis en place')), findsOneWidget);

      await toucher(tester, dansDialogue(find.text('Retour à l’accueil')));
      expect(find.byType(DriveRestaurationScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // plus aucun écran ne lit la base en direct
      expect(await nomsProduits(tester, env), <String>['Doudou lapin']);
      expect(env.clientDrive.telecharges, containsAll(<String>['photo_1.jpg', 'photo_2.jpg', 'FACT-2026-0001.pdf']));
      expect(
        await env.travailler(tester, () => File('${env.dossierPhotos.path}/photo_1.jpg').readAsString()),
        'photo un',
      );
      final List<SauvegardeLocale> locales = await env.travailler(tester, () => env.sauvegarde.lister());
      expect(locales.map((SauvegardeLocale s) => s.type), contains(TypeSauvegarde.avantRestauration));
      expect(
        await fichiersSous(tester, env, Directory('${env.dossier.path}/drive/travail/restauration')),
        isEmpty,
      );

      await env.fermer(tester);
    });

    testWidgets('renoncer : rien ne change, et le téléchargement préparé est effacé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      await sauvegarderSurDrive(tester, env, _maintenant);
      await env.creerProduit(tester, nom: 'Bonnet');
      await ouvrirRestauration(tester, env);

      await toucher(tester, cle('drive-sauvegarde-0'));
      await attendre(tester, find.text('Restaurer cette sauvegarde ?'));
      await toucher(tester, dansDialogue(find.text('Annuler')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DriveRestaurationScreen), findsOneWidget);
      expect(cle('drive-restauration-erreur'), findsNothing);
      expect(env.clientDrive.telecharges, <String>[nomSauvegardeDrive(_maintenant)]); // aucun fichier n'est descendu
      final Directory restauration = Directory('${env.dossier.path}/drive/travail/restauration');
      await attendreJusqua(tester, () => !restauration.existsSync(), essais: 100);
      expect(await fichiersSous(tester, env, restauration), isEmpty);

      await tester.pumpWidget(const SizedBox());
      expect(await nomsProduits(tester, env), <String>['Bonnet', 'Doudou lapin']);
      final List<SauvegardeLocale> locales = await env.travailler(tester, () => env.sauvegarde.lister());
      expect(locales.where((SauvegardeLocale s) => s.type == TypeSauvegarde.avantRestauration), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('pas de réseau pendant le téléchargement : message, rien n’est touché, et on peut recommencer', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      await sauvegarderSurDrive(tester, env, _maintenant);
      await env.creerProduit(tester, nom: 'Bonnet');
      env.clientDrive.echecTelechargement = (String nom) =>
          nom == 'photo_2.jpg' ? const ErreurDrive('Pas de connexion à Internet.') : null;
      await ouvrirRestauration(tester, env);

      await toucher(tester, cle('drive-sauvegarde-0'));
      await attendre(tester, find.text('Restaurer cette sauvegarde ?'));
      await toucher(tester, dansDialogue(find.text('Restaurer')));
      await attendre(tester, cle('drive-restauration-erreur'));

      expect(texte(tester, 'drive-restauration-erreur'), 'Pas de connexion à Internet.');
      expect(find.text('Restauration terminée'), findsNothing);
      expect(cle('drive-sauvegarde-0'), findsOneWidget); // on peut réessayer
      expect(inactif(tester, 'drive-sauvegarde-0'), isFalse);
      final List<SauvegardeLocale> locales = await env.travailler(tester, () => env.sauvegarde.lister());
      expect(locales.where((SauvegardeLocale s) => s.type == TypeSauvegarde.avantRestauration), isEmpty);

      // La connexion est revenue : on recommence.
      env.clientDrive.echecTelechargement = null;
      await toucher(tester, cle('drive-sauvegarde-0'));
      await attendre(tester, find.text('Restaurer cette sauvegarde ?'));
      await toucher(tester, dansDialogue(find.text('Restaurer')));
      await attendre(tester, find.text('Restauration terminée'));
      expect(cle('drive-restauration-erreur'), findsNothing);
      await toucher(tester, dansDialogue(find.text('Retour à l’accueil')));

      await tester.pumpWidget(const SizedBox());
      expect(await nomsProduits(tester, env), <String>['Doudou lapin']);

      await env.fermer(tester);
    });

    testWidgets('pendant la restauration : la progression est montrée, et l’écran ne se quitte pas', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await remplirTelephone(tester, env);
      await env.creerProduit(tester);
      await sauvegarderSurDrive(tester, env, _maintenant);
      final Completer<void> feuVert = Completer<void>();
      env.clientDrive.pauseTelechargement = (String nom) => nom == 'photo_1.jpg' ? feuVert.future : Future<void>.value();
      await ouvrirRestauration(tester, env);

      await toucher(tester, cle('drive-sauvegarde-0'));
      await attendre(tester, find.text('Restaurer cette sauvegarde ?'));
      await toucher(tester, dansDialogue(find.text('Restaurer')));
      await attendre(tester, cle('drive-restauration-fichier'));

      expect(cle('drive-restauration-progression'), findsOneWidget);
      expect(
        texte(tester, 'drive-restauration-etape'),
        startsWith('Étape 1 sur 3 : téléchargement des fichiers depuis Drive ('),
      );
      expect(inactif(tester, 'drive-sauvegarde-0'), isTrue);

      // Le bouton « retour » est sans effet pendant la restauration.
      await toucher(tester, find.byType(BackButton));
      expect(find.byType(DriveRestaurationScreen), findsOneWidget);

      feuVert.complete();
      await attendre(tester, find.text('Restauration terminée'));
      await toucher(tester, dansDialogue(find.text('Retour à l’accueil')));
      expect(find.byType(DriveRestaurationScreen), findsNothing);

      await env.fermer(tester);
    });
  });
}
