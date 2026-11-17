import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_partage.dart';
import 'package:crochet_creations/presentation/drive/drive_partage_fichier_screen.dart';
import 'package:crochet_creations/presentation/drive/drive_partages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/aide_donnees.dart';
import '../data/aide_drive.dart';
import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(2000, 4000);

// Vendredi 13 novembre 2026, 12 h 30.
final DateTime _maintenant = DateTime(2026, 11, 13, 12, 30);

const ProfilGoogle _camille = ProfilGoogle(email: 'camille@exemple.fr', nom: 'Camille');

const String _facture = 'FACT-2026-0001.pdf';
const String _devis = 'DEVIS-2026-0001.pdf';
const String _archive = 'crochet-creations-catalogue-2026-11-13.zip';

Finder cle(String nom) => find.byKey(Key(nom));

String texte(WidgetTester tester, String nom) => tester.widget<Text>(cle(nom)).data!;

Finder dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty, essais: 600);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> attendreDisparition(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isEmpty, essais: 600);
  expect(cible, findsNothing, reason: 'Élément qui aurait dû disparaître : $cible');
}

Future<void> attendreTexte(WidgetTester tester, String nom, String attendu) async {
  await attendreJusqua(
    tester,
    () => cle(nom).evaluate().isNotEmpty && tester.widget<Text>(cle(nom)).data == attendu,
    essais: 600,
  );
  expect(cle(nom), findsOneWidget, reason: 'Élément attendu : $nom');
  expect(texte(tester, nom), attendu);
}

Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pump();
  await tester.tap(cible);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await laisserFinir(tester);
}

Future<void> ouvrirRoute(WidgetTester tester, String route) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Pose un fichier sur le faux Drive, dans le sous-dossier [dossier] du dossier principal, et retourne son identifiant.
Future<String> poserSurDrive(WidgetTester tester, EnvironnementTest env, String dossier, String nom) {
  return env.travailler(tester, () async {
    final FauxClientDrive d = env.clientDrive;
    final String racine = await d.trouverDossier(nomDossierRacineDrive) ?? await d.creerDossier(nomDossierRacineDrive);
    final String sous = await d.trouverDossier(dossier, parentId: racine) ?? await d.creerDossier(dossier, parentId: racine);
    final File local = File('${env.dossier.path}/envoi_$nom')..writeAsStringSync('contenu de $nom');
    await d.envoyer(fichier: local, nom: nom, dossierId: sous);
    return d.fichierNomme(nom)!.id;
  });
}

/// Ouvre l'application puis l'écran « Partages », comptes et listes chargés.
Future<void> ouvrirPartages(WidgetTester tester, EnvironnementTest env) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.drivePartages);
  await attendreDisparition(tester, cle('partages-chargement-compte'));
  for (final RubriquePartage r in RubriquePartage.values) {
    await attendreDisparition(tester, cle('partages-chargement-${r.name}'));
  }
}

/// Ouvre l'écran d'un fichier depuis la liste, accès chargés.
Future<void> ouvrirFichier(WidgetTester tester, String nom) async {
  await toucher(tester, cle('partages-fichier-$nom'));
  await attendre(tester, find.byType(DrivePartageFichierScreen));
  await attendreDisparition(tester, cle('partage-chargement'));
}

/// Une tablette qui connaît un compte et un fichier de la rubrique Factures, ouverte sur l'écran de ce fichier.
Future<(EnvironnementTest, String)> ouvrirFacture(WidgetTester tester) async {
  final EnvironnementTest env = await EnvironnementTest.creer(tester);
  env.compteGoogle.dejaConnecte = _camille;
  final String id = await poserSurDrive(tester, env, 'Factures', _facture);
  await ouvrirPartages(tester, env);
  await ouvrirFichier(tester, _facture);
  return (env, id);
}

void main() {
  group('entrée depuis l’écran Google Drive', () {
    testWidgets('connecté : la carte « Partager des fichiers » ouvre l’écran Partages', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      env.maintenant = _maintenant;
      await ouvrirAccueil(tester, env, taille: _grandEcran);
      await ouvrirRoute(tester, AppRoutes.drive);
      await attendreDisparition(tester, cle('drive-chargement'));
      await attendreDisparition(tester, find.text('Lecture du bilan…'));

      await toucher(tester, cle('drive-partages'));
      await attendreDisparition(tester, cle('partages-chargement-compte'));
      await attendreDisparition(tester, cle('partages-chargement-factures'));

      expect(find.byType(DrivePartagesScreen), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('pas connecté : pas de carte de partage', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.maintenant = _maintenant;
      await ouvrirAccueil(tester, env, taille: _grandEcran);
      await ouvrirRoute(tester, AppRoutes.drive);
      await attendreDisparition(tester, cle('drive-chargement'));
      await attendreDisparition(tester, find.text('Lecture du bilan…'));

      expect(cle('drive-partages'), findsNothing);
      await env.fermer(tester);
    });
  });

  group('écran Partages', () {
    testWidgets('pas connecté : l’écran l’explique et ne touche pas à Drive', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirPartages(tester, env);

      expect(cle('partages-non-connecte'), findsOneWidget);
      expect(cle('partages-envoyer-catalogue'), findsNothing);
      expect(env.clientDrive.dossiersCrees, 0);
      await env.fermer(tester);
    });

    testWidgets('trois rubriques : leurs fichiers, partagés ou privés, et jamais les sauvegardes', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      final String idFacture = await poserSurDrive(tester, env, 'Factures', _facture);
      await poserSurDrive(tester, env, 'Devis', _devis);
      await poserSurDrive(tester, env, 'Sauvegardes', 'sauvegarde-secrete.zip');
      env.clientDrive.fichiers[idFacture]!.acces.add(
        const AccesDrive(id: 'perm-1', type: TypeAcces.personne, email: 'marie@exemple.fr'),
      );

      await ouvrirPartages(tester, env);

      expect(texte(tester, 'partages-etat-$_facture'), 'Partagé');
      expect(texte(tester, 'partages-etat-$_devis'), 'Privé');
      expect(cle('partages-vide-exports'), findsOneWidget);
      expect(find.text('sauvegarde-secrete.zip'), findsNothing);
      expect(env.clientDrive.dossiersCrees, 4); // le dossier principal et trois sous-dossiers, posés par le test : la lecture n'en crée aucun
      await env.fermer(tester);
    });

    testWidgets('sans fichier sur Drive : chaque rubrique l’explique', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await ouvrirPartages(tester, env);

      expect(cle('partages-vide-factures'), findsOneWidget);
      expect(cle('partages-vide-devis'), findsOneWidget);
      expect(cle('partages-vide-exports'), findsOneWidget);
      expect(env.clientDrive.dossiersCrees, 0);
      await env.fermer(tester);
    });

    testWidgets('une panne de connexion est dite en clair, et « Réessayer » relit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');
      await ouvrirPartages(tester, env);

      expect(texte(tester, 'partages-erreur-factures'), 'Pas de connexion à Internet.');

      env.clientDrive.panne = null;
      await toucher(tester, cle('partages-reessayer-factures'));
      await attendre(tester, cle('partages-vide-factures'));
      expect(cle('partages-erreur-factures'), findsNothing);
      await env.fermer(tester);
    });
  });

  group('catalogue sur Drive', () {
    Future<EnvironnementTest> envAvecCatalogue(WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await env.travailler(tester, () async {
        await remplirBase(env.db);
        await env.dossierPhotos.create(recursive: true);
        File('${env.dossierPhotos.path}/$photoPrincipale').writeAsStringSync('photo un');
        File('${env.dossierPhotos.path}/$photoSecondaire').writeAsStringSync('photo deux');
      });
      return env;
    }

    testWidgets('« Envoyer le catalogue » prépare l’archive, l’envoie dans « Exports » et la propose au partage', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await envAvecCatalogue(tester);
      await ouvrirPartages(tester, env);

      await toucher(tester, cle('partages-envoyer-catalogue'));
      await attendre(tester, cle('partages-catalogue-resultat'));

      final String resultat = texte(tester, 'partages-catalogue-resultat');
      expect(resultat, contains('Catalogue envoyé sur Drive'));
      expect(resultat, contains('« Exports »'));
      expect(resultat, contains(_archive));
      expect(resultat, contains('1 produit, 2 photos'));
      expect(env.clientDrive.nomsDans('Exports'), <String>[_archive]);
      await attendre(tester, cle('partages-fichier-$_archive'));
      expect(texte(tester, 'partages-etat-$_archive'), 'Privé');
      expect(cle('partages-vide-exports'), findsNothing);
      await env.fermer(tester);
    });

    testWidgets('le renvoyer le même jour met à jour le même fichier', (WidgetTester tester) async {
      final EnvironnementTest env = await envAvecCatalogue(tester);
      await ouvrirPartages(tester, env);

      await toucher(tester, cle('partages-envoyer-catalogue'));
      await attendre(tester, cle('partages-catalogue-resultat'));
      final String premier = texte(tester, 'partages-catalogue-resultat');
      await toucher(tester, cle('partages-envoyer-catalogue'));
      await attendreTexte(
        tester,
        'partages-catalogue-resultat',
        premier.replaceFirst('Catalogue envoyé', 'Catalogue mis à jour'),
      );

      expect(texte(tester, 'partages-catalogue-resultat'), startsWith('Catalogue mis à jour sur Drive'));
      expect(env.clientDrive.nomsDans('Exports'), <String>[_archive]);
      await env.fermer(tester);
    });

    testWidgets('une photo introuvable est signalée dans le résultat', (WidgetTester tester) async {
      final EnvironnementTest env = await envAvecCatalogue(tester);
      await env.travailler(tester, () async => File('${env.dossierPhotos.path}/$photoSecondaire').deleteSync());
      await ouvrirPartages(tester, env);

      await toucher(tester, cle('partages-envoyer-catalogue'));
      await attendre(tester, cle('partages-catalogue-resultat'));

      expect(texte(tester, 'partages-catalogue-resultat'), contains('1 photo introuvable'));
      await env.fermer(tester);
    });

    testWidgets('une panne de connexion : message clair, rien sur Drive', (WidgetTester tester) async {
      final EnvironnementTest env = await envAvecCatalogue(tester);
      await ouvrirPartages(tester, env);
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');

      await toucher(tester, cle('partages-envoyer-catalogue'));
      await attendre(tester, cle('partages-catalogue-erreur'));

      expect(texte(tester, 'partages-catalogue-erreur'), 'Pas de connexion à Internet.');
      expect(cle('partages-catalogue-resultat'), findsNothing);
      expect(env.clientDrive.fichiers, isEmpty);
      await env.fermer(tester);
    });
  });

  group('partage d’un fichier', () {
    testWidgets('un fichier neuf est privé : résumé, propriétaire, lien non public', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);

      expect(texte(tester, 'partage-nom'), _facture);
      expect(texte(tester, 'partage-resume'), 'Privé : vous seul·e y avez accès.');
      expect(cle('partage-proprietaire'), findsOneWidget);
      expect(cle('partage-lien-prive'), findsOneWidget);
      expect(cle('partage-activer-lien'), findsOneWidget);
      expect(cle('partage-arreter-lien'), findsNothing);
      expect(env.clientDrive.partagesDemandes, isEmpty);
      expect(env.clientDrive.liensActives, isEmpty);
      await env.fermer(tester);
    });

    testWidgets('partager avec une personne : adresse nettoyée, lecture seule, résumé à jour', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);

      await tester.enterText(cle('partage-courriel'), '  Marie@Exemple.FR ');
      await toucher(tester, cle('partage-partager'));
      await attendre(tester, cle('partage-info'));

      expect(env.clientDrive.partagesDemandes, <String>['$_facture | marie@exemple.fr']);
      expect(texte(tester, 'partage-info'), contains('marie@exemple.fr'));
      expect(texte(tester, 'partage-info'), contains('sans le modifier'));
      expect(texte(tester, 'partage-resume'), 'Partagé avec 1 personne.');
      expect(cle('partage-personne-0'), findsOneWidget);
      expect(find.text('Peut lire'), findsOneWidget);
      expect(tester.widget<TextField>(cle('partage-courriel')).controller!.text, isEmpty);
      await env.fermer(tester);
    });

    testWidgets('une adresse mal écrite est refusée sous le champ, sans appel à Google', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);

      await tester.enterText(cle('partage-courriel'), 'marie');
      await toucher(tester, cle('partage-partager'));

      expect(find.text('L’adresse e-mail n’est pas valide.'), findsOneWidget);
      expect(env.clientDrive.partagesDemandes, isEmpty);

      await tester.enterText(cle('partage-courriel'), 'marie@exemple.fr');
      await tester.pump();
      expect(find.text('L’adresse e-mail n’est pas valide.'), findsNothing); // l'erreur s'efface dès qu'on corrige
      await env.fermer(tester);
    });

    testWidgets('sa propre adresse, ou une adresse déjà partagée : refus clair', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);

      await tester.enterText(cle('partage-courriel'), 'Camille@exemple.fr');
      await toucher(tester, cle('partage-partager'));
      expect(find.text('C’est votre propre adresse : ce fichier est déjà à vous.'), findsOneWidget);

      await tester.enterText(cle('partage-courriel'), 'marie@exemple.fr');
      await toucher(tester, cle('partage-partager'));
      await attendre(tester, cle('partage-info'));
      await tester.enterText(cle('partage-courriel'), 'MARIE@exemple.fr');
      await toucher(tester, cle('partage-partager'));
      expect(find.text('Ce fichier est déjà partagé avec cette adresse.'), findsOneWidget);

      expect(env.clientDrive.partagesDemandes, hasLength(1));
      await env.fermer(tester);
    });

    testWidgets('une adresse que Google refuse : l’erreur est dite, rien n’est partagé', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);
      env.clientDrive.adressesRefusees.add('inconnue@exemple.fr');

      await tester.enterText(cle('partage-courriel'), 'inconnue@exemple.fr');
      await toucher(tester, cle('partage-partager'));
      await attendre(tester, cle('partage-erreur'));

      expect(texte(tester, 'partage-erreur'), contains('n’a pas accepté'));
      expect(texte(tester, 'partage-resume'), 'Privé : vous seul·e y avez accès.');
      await env.fermer(tester);
    });

    testWidgets('connexion à Google perdue : l’erreur demande de se reconnecter', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);
      env.clientDrive.echecAcces = (String _) => const ErreurDrive(
        'L’autorisation Google Drive a expiré. Reconnectez-vous.',
        autorisationAExpire: true,
      );

      await tester.enterText(cle('partage-courriel'), 'marie@exemple.fr');
      await toucher(tester, cle('partage-partager'));
      await attendre(tester, cle('partage-erreur'));

      expect(texte(tester, 'partage-erreur'), contains('Reconnectez-vous'));
      expect(texte(tester, 'partage-erreur'), contains('Réglages › Google Drive'));
      await env.fermer(tester);
    });

    testWidgets('retirer une personne : confirmation, puis l’accès disparaît et le fichier reste', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      final String id = await poserSurDrive(tester, env, 'Factures', _facture);
      env.clientDrive.fichiers[id]!.acces.add(
        const AccesDrive(id: 'perm-1', type: TypeAcces.personne, email: 'marie@exemple.fr', nom: 'Marie Dupont'),
      );
      await ouvrirPartages(tester, env);
      await ouvrirFichier(tester, _facture);
      expect(texte(tester, 'partage-resume'), 'Partagé avec 1 personne.');

      // Annuler ne retire rien.
      await toucher(tester, cle('partage-retirer-0'));
      expect(dansDialogue(find.text('Retirer l’accès ?')), findsOneWidget);
      expect(dansDialogue(find.textContaining('Le fichier reste sur votre Drive.')), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Annuler')));
      expect(env.clientDrive.accesRetires, isEmpty);
      expect(cle('partage-personne-0'), findsOneWidget);

      // Confirmer retire l'accès, pas le fichier.
      await toucher(tester, cle('partage-retirer-0'));
      await toucher(tester, dansDialogue(find.text('Retirer l’accès')));
      await attendre(tester, cle('partage-info'));

      expect(env.clientDrive.accesRetires, <String>['$_facture | Marie Dupont (marie@exemple.fr)']);
      expect(texte(tester, 'partage-resume'), 'Privé : vous seul·e y avez accès.');
      expect(cle('partage-personne-0'), findsNothing);
      expect(env.clientDrive.fichiers[id], isNotNull);
      await env.fermer(tester);
    });

    testWidgets('lien public : la confirmation explique, annuler ne change rien, confirmer l’active', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);

      await toucher(tester, cle('partage-activer-lien'));
      expect(dansDialogue(find.text('Activer le lien public ?')), findsOneWidget);
      expect(dansDialogue(find.textContaining('Toute personne qui a le lien pourra lire')), findsOneWidget);
      expect(dansDialogue(find.textContaining('nom et l’adresse du client')), findsOneWidget); // une facture
      await toucher(tester, dansDialogue(find.text('Annuler')));
      expect(env.clientDrive.liensActives, isEmpty);
      expect(cle('partage-lien-prive'), findsOneWidget);

      await toucher(tester, cle('partage-activer-lien'));
      await toucher(tester, dansDialogue(find.text('Activer le lien')));
      await attendre(tester, cle('partage-lien-public'));

      expect(env.clientDrive.liensActives, <String>[_facture]);
      expect(texte(tester, 'partage-resume'), 'Lien public activé.');
      expect(cle('partage-lien-prive'), findsNothing);
      expect(cle('partage-arreter-lien'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('lien public : arrêter demande confirmation, retire le lien et garde les personnes', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      final String id = await poserSurDrive(tester, env, 'Factures', _facture);
      env.clientDrive.fichiers[id]!.acces
        ..add(const AccesDrive(id: 'perm-1', type: TypeAcces.personne, email: 'marie@exemple.fr'))
        ..add(const AccesDrive(id: 'perm-2', type: TypeAcces.lienPublic));
      await ouvrirPartages(tester, env);
      await ouvrirFichier(tester, _facture);
      expect(texte(tester, 'partage-resume'), 'Partagé avec 1 personne, lien public activé.');

      await toucher(tester, cle('partage-arreter-lien'));
      expect(dansDialogue(find.text('Arrêter le lien public ?')), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Arrêter le lien')));
      await attendre(tester, cle('partage-lien-prive'));

      expect(texte(tester, 'partage-resume'), 'Partagé avec 1 personne.');
      expect(cle('partage-personne-0'), findsOneWidget);
      expect(env.clientDrive.fichiers[id], isNotNull);
      await env.fermer(tester);
    });

    testWidgets('l’avertissement « client » n’apparaît pas pour un export', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      await poserSurDrive(tester, env, 'Exports', _archive);
      await ouvrirPartages(tester, env);
      await ouvrirFichier(tester, _archive);

      await toucher(tester, cle('partage-activer-lien'));

      expect(dansDialogue(find.text('Activer le lien public ?')), findsOneWidget);
      expect(dansDialogue(find.textContaining('nom et l’adresse du client')), findsNothing);
      await toucher(tester, dansDialogue(find.text('Annuler')));
      await env.fermer(tester);
    });

    testWidgets('copier le lien met l’adresse du fichier dans le presse-papiers', (WidgetTester tester) async {
      final List<String> copies = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall appel) async {
        if (appel.method == 'Clipboard.setData') {
          copies.add((appel.arguments as Map<Object?, Object?>)['text']! as String);
        }
        return null;
      });
      final (EnvironnementTest env, String id) = await ouvrirFacture(tester);

      await toucher(tester, cle('partage-copier-lien'));
      await attendre(tester, cle('partage-info'));

      expect(copies, <String>['https://drive.exemple.fr/fichier/$id']);
      expect(texte(tester, 'partage-info'), 'Lien copié.');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      await env.fermer(tester);
    });

    testWidgets('accès à d’autres personnes créés hors de l’application : montrés, jamais modifiés', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      final String id = await poserSurDrive(tester, env, 'Factures', _facture);
      env.clientDrive.fichiers[id]!.acces
        ..add(const AccesDrive(id: 'perm-1', type: TypeAcces.personne, email: 'paul@exemple.fr', peutModifier: true))
        ..add(const AccesDrive(id: 'perm-2', type: TypeAcces.autre, email: 'equipe@exemple.fr'));
      await ouvrirPartages(tester, env);
      await ouvrirFichier(tester, _facture);

      expect(find.text('Peut aussi modifier (accordé en dehors de l’application)'), findsOneWidget);
      expect(find.text('Accès créé en dehors de l’application : à gérer dans Drive.'), findsOneWidget);
      expect(cle('partage-autre-0'), findsOneWidget);
      expect(cle('partage-retirer-1'), findsNothing); // un accès « autre » ne se retire pas d'ici
      await env.fermer(tester);
    });

    testWidgets('lecture impossible : le message, puis « Réessayer »', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.dejaConnecte = _camille;
      final String id = await poserSurDrive(tester, env, 'Factures', _facture);
      await ouvrirPartages(tester, env);
      env.clientDrive.echecAcces = (String _) => const ErreurDrive('Pas de connexion à Internet.');

      await toucher(tester, cle('partages-fichier-$_facture'));
      await attendre(tester, cle('partage-erreur-chargement'));
      expect(texte(tester, 'partage-erreur-chargement'), 'Pas de connexion à Internet.');
      expect(cle('partage-partager'), findsNothing);

      env.clientDrive.echecAcces = null;
      await toucher(tester, cle('partage-reessayer'));
      await attendre(tester, cle('partage-resume'));
      expect(cle('partage-erreur-chargement'), findsNothing);
      expect(env.clientDrive.fichiers[id], isNotNull);
      await env.fermer(tester);
    });

    testWidgets('au retour, la liste montre le fichier comme partagé', (WidgetTester tester) async {
      final (EnvironnementTest env, String _) = await ouvrirFacture(tester);
      await tester.enterText(cle('partage-courriel'), 'marie@exemple.fr');
      await toucher(tester, cle('partage-partager'));
      await attendre(tester, cle('partage-info'));

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await laisserFinir(tester);

      await attendreTexte(tester, 'partages-etat-$_facture', 'Partagé');
      await env.fermer(tester);
    });
  });
}
