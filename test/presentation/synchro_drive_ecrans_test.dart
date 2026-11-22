import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:crochet_creations/core/plateforme.dart';
import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/service_drive.dart';
import 'package:crochet_creations/data/drive/service_sauvegarde_drive.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:crochet_creations/domain/drive_synchro.dart';
import 'package:crochet_creations/presentation/drive/drive_providers.dart';
import 'package:crochet_creations/presentation/drive/reprise_drive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/aide_base.dart';
import 'aide_widget.dart';

// Reprise d'un appareil à l'autre, côté écrans : la proposition à l'ouverture, l'envoi en passant en arrière-plan (Android) et
// à la fermeture de la fenêtre (Windows). Les règles de comparaison, elles, sont testées dans `drive_synchro_test.dart` et
// `synchro_drive_test.dart`.

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(2000, 4000);

// Lundi 16 et mardi 17 novembre 2026.
final DateTime _lundi = DateTime(2026, 11, 16, 18, 0);
final DateTime _mardi = DateTime(2026, 11, 17, 9, 30);

const ProfilGoogle _camille = ProfilGoogle(email: 'camille@exemple.fr', nom: 'Camille');

Finder _cle(String nom) => find.byKey(Key(nom));

Finder _dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

String _dateHeure(DateTime date) => '${formatDateLongue(date)} à ${formatHeure(date)}';

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> _attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty, essais: 600);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pump(const Duration(milliseconds: 100));
}

/// Fait avancer le temps jusqu'à ce que [cible] ait disparu.
Future<void> _attendreDisparition(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isEmpty, essais: 600);
  expect(cible, findsNothing, reason: 'Élément qui aurait dû disparaître : $cible');
}

/// Appuie sur un élément, laisse finir les animations et les lectures de la base, sans « pumpAndSettle ».
Future<void> _toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pump();
  await tester.tap(cible);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await laisserFinir(tester);
}

/// Ouvre l'écran « Google Drive » par-dessus l'accueil, compte et bilan chargés.
Future<void> _ouvrirEcranDrive(WidgetTester tester) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(AppRoutes.drive));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
  await _attendreDisparition(tester, _cle('drive-chargement'));
  await _attendreDisparition(tester, find.text('Lecture du bilan…'));
  await _attendreDisparition(tester, find.text('Lecture du réglage…'));
}

Future<List<String>> _nomsProduits(WidgetTester tester, EnvironnementTest env) {
  return env.travailler(tester, () async {
    final List<Produit> produits = await env.db.select(env.db.produits).get();
    return produits.map((Produit p) => p.nom).toList()..sort();
  });
}

int _nombreDeSauvegardes(EnvironnementTest env) => env.clientDrive.nomsDans(nomDossierSauvegardesDrive).length;

/// Un téléphone connecté à Google, qui a un produit et a **envoyé ses données lundi soir** : c'est sa dernière version
/// synchronisée. L'envoi automatique est [automatique].
Future<EnvironnementTest> _telephoneSynchronise(
  WidgetTester tester, {
  bool automatique = true,
  Plateforme plateforme = const Plateforme.android(),
}) async {
  final EnvironnementTest env = await EnvironnementTest.creer(tester);
  env.plateforme = plateforme;
  env.compteGoogle.dejaConnecte = _camille;
  await env.creerProduit(tester, nom: 'Doudou lapin');
  env.maintenant = _lundi;
  await env.travailler(tester, () => env.serviceSauvegardeDrive.sauvegarder());
  if (automatique) {
    await env.travailler(tester, () => env.serviceSauvegardeDrive.reglerEnvoiAutomatique(actif: true));
  }
  return env;
}

/// L'autre appareil : ses propres données, qu'il envoie sur le **même** Drive que [telephone].
class _AutreAppareil {
  _AutreAppareil(this.env, this.service);

  final EnvironnementTest env;
  final ServiceSauvegardeDrive service;

  static Future<_AutreAppareil> creer(WidgetTester tester, EnvironnementTest telephone) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    DateTime horloge() => env.maintenant ?? DateTime.now();
    final ServiceDrive envoi = ServiceDrive(
      client: telephone.clientDrive,
      dossiers: <DossierDrive, Directory>{
        DossierDrive.photos: env.dossierPhotos,
        DossierDrive.factures: env.dossierFactures,
        DossierDrive.devis: env.dossierDevis,
        DossierDrive.notes: env.dossierPiecesJointes,
      },
      fichierBilan: File('${env.dossier.path}/drive/dernier_envoi.json'),
      horloge: horloge,
    );
    return _AutreAppareil(
      env,
      ServiceSauvegardeDrive(
        client: telephone.clientDrive,
        envoi: envoi,
        sauvegarde: env.sauvegarde,
        dossierTravail: Directory('${env.dossier.path}/drive/travail'),
        fichierEtat: File('${env.dossier.path}/drive/sauvegardes_drive.json'),
        horloge: horloge,
      ),
    );
  }

  /// Saisit un produit sur cet appareil, puis envoie ses données sur Drive à l'heure [quand].
  Future<void> envoyerAvecProduit(WidgetTester tester, String nomProduit, DateTime quand) async {
    await env.creerProduit(tester, nom: nomProduit);
    env.maintenant = quand;
    await env.travailler(tester, () => service.sauvegarder());
  }

  Future<void> fermer(WidgetTester tester) => env.fermer(tester);
}

/// Ouvre l'application à l'heure [quand] ; si [declencher], fait ensuite ce que fait l'application toute seule à son ouverture
/// (`main.dart`). Rend le conteneur de l'application.
Future<ProviderContainer> _ouvrir(
  WidgetTester tester,
  EnvironnementTest env,
  DateTime quand, {
  bool declencher = true,
}) async {
  env.maintenant = quand;
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  final ProviderContainer conteneur = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
  if (declencher) {
    await env.ecrireEcranOuvert(tester, () => conteneur.read(sauvegardeDriveProvider.notifier).lancerSiBesoin());
    await tester.pump();
  }
  return conteneur;
}

/// Le système change l'état de l'application (au premier plan, en arrière-plan...).
void _etatDeLApplication(WidgetTester tester, AppLifecycleState etat) {
  // ignore: invalid_use_of_protected_member
  tester.binding.handleAppLifecycleStateChanged(etat);
}

/// L'application passe en arrière-plan, puis revient.
void _arrierePlanPuisRetour(WidgetTester tester) {
  _etatDeLApplication(tester, AppLifecycleState.paused);
  _etatDeLApplication(tester, AppLifecycleState.resumed);
}

/// Comme `testWidgets`, mais un test qui reste bloqué échoue au bout de 90 s (avec son nom) au lieu de bloquer toute la suite.
void _ecran(String description, WidgetTesterCallback test) =>
    testWidgets(description, test, timeout: const Timeout(Duration(seconds: 90)));

void main() {
  group('proposition de reprise à l’ouverture', () {
    _ecran('rien n’a changé ici, Drive a une version plus récente : on propose de la reprendre, puis on la reprend', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);
      final _AutreAppareil autre = await _AutreAppareil.creer(tester, env);
      await autre.envoyerAvecProduit(tester, 'Bonnet', _mardi);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      await _ouvrir(tester, env, _mardi.add(const Duration(minutes: 30)));
      await _attendre(tester, _cle('reprise-dialogue'));

      expect(find.text('Reprendre la version de Drive ?'), findsOneWidget);
      expect(_dansDialogue(find.textContaining(_dateHeure(_mardi))), findsOneWidget);
      expect(_cle('reprise-garder'), findsNothing);
      expect(_cle('reprise-plus-tard'), findsOneWidget);
      // La proposition n'a rien envoyé ni remplacé.
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await _toucher(tester, _cle('reprise-reprendre'));
      // L'écran de restauration a déjà choisi la sauvegarde : il télécharge, dit ce qu'elle contient et demande confirmation.
      await _attendre(tester, find.text('Restaurer cette sauvegarde ?'));
      expect(_dansDialogue(find.textContaining('Sauvegarde du ${_dateHeure(_mardi)}')), findsOneWidget);
      expect(_dansDialogue(find.textContaining('copie de sécurité')), findsOneWidget);

      await _toucher(tester, _dansDialogue(find.text('Restaurer')));
      await _attendre(tester, find.text('Restauration terminée'));
      await _toucher(tester, _dansDialogue(find.text('Retour à l’accueil')));

      await tester.pumpWidget(const SizedBox()); // plus aucun écran ne lit la base en direct
      expect(await _nomsProduits(tester, env), <String>['Bonnet']);
      final EtatSauvegardesDrive etat = await env.travailler(tester, () => env.serviceSauvegardeDrive.lireEtat());
      expect(etat.reference!.nom, nomSauvegardeDrive(_mardi));
      // Rien n'a été supprimé, ni ajouté, sur Drive.
      expect(_nombreDeSauvegardes(env), 2);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await env.fermer(tester);
      await autre.fermer(tester);
    });

    _ecran('les deux ont changé : on choisit ; « garder cet appareil » ne supprime rien et ne remplace rien', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);
      await env.creerProduit(tester, nom: 'Écharpe'); // saisi ici depuis lundi soir
      final _AutreAppareil autre = await _AutreAppareil.creer(tester, env);
      await autre.envoyerAvecProduit(tester, 'Bonnet', _mardi);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      final ProviderContainer conteneur = await _ouvrir(tester, env, _mardi.add(const Duration(minutes: 30)));
      await _attendre(tester, _cle('reprise-dialogue'));

      expect(find.text('Deux versions différentes'), findsOneWidget);
      expect(_dansDialogue(find.textContaining('rien n’est envoyé automatiquement')), findsOneWidget);
      expect(_cle('reprise-garder'), findsOneWidget);
      expect(_cle('reprise-reprendre'), findsOneWidget);

      await _toucher(tester, _cle('reprise-garder'));
      await attendreJusqua(tester, () => conteneur.read(repriseDriveProvider) == null);
      expect(_cle('reprise-dialogue'), findsNothing);

      // Drive est intact, rien n'est parti, rien n'a été repris.
      expect(_nombreDeSauvegardes(env), 2);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));
      final ConstatSynchro apres = await env.ecrireEcranOuvert(tester, () => env.serviceSauvegardeDrive.constater());
      expect(apres.situation, SituationSynchro.aEnvoyer); // les données d'ici partiront au prochain envoi
      expect(apres.demandeUneDecision, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(await _nomsProduits(tester, env), <String>['Doudou lapin', 'Écharpe']);

      await env.fermer(tester);
      await autre.fermer(tester);
    });

    _ecran('« Plus tard » ne change rien : la proposition reste sur l’écran Google Drive, d’où on peut décider', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);
      final _AutreAppareil autre = await _AutreAppareil.creer(tester, env);
      await autre.envoyerAvecProduit(tester, 'Bonnet', _mardi);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      final ProviderContainer conteneur = await _ouvrir(tester, env, _mardi.add(const Duration(minutes: 30)));
      await _attendre(tester, _cle('reprise-dialogue'));
      await _toucher(tester, _cle('reprise-plus-tard'));

      expect(_cle('reprise-dialogue'), findsNothing);
      expect(conteneur.read(repriseDriveProvider), isNotNull);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await _ouvrirEcranDrive(tester);
      expect(_cle('drive-reprise-texte'), findsOneWidget);
      expect(find.text('Une version plus récente est sur Drive'), findsOneWidget);

      await _toucher(tester, _cle('drive-reprise-decider'));
      await _attendre(tester, _cle('reprise-dialogue'));
      expect(find.text('Reprendre la version de Drive ?'), findsOneWidget);

      await env.fermer(tester);
      await autre.fermer(tester);
    });

    _ecran('tant que la décision n’est pas prise, rien ne part tout seul (ouverture, arrière-plan, fermeture)', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);
      await env.creerProduit(tester, nom: 'Écharpe'); // du neuf ici : sans la décision en attente, cela partirait
      final _AutreAppareil autre = await _AutreAppareil.creer(tester, env);
      await autre.envoyerAvecProduit(tester, 'Bonnet', _mardi);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      final ProviderContainer conteneur = await _ouvrir(tester, env, _mardi.add(const Duration(minutes: 30)));
      await _attendre(tester, _cle('reprise-dialogue'));
      await _toucher(tester, _cle('reprise-plus-tard'));

      // Les jours passent : à l'ouverture suivante, en arrière-plan, à la fermeture, aucun envoi.
      env.maintenant = _mardi.add(const Duration(days: 3));
      final SauvegardeDriveNotifier notifier = conteneur.read(sauvegardeDriveProvider.notifier);
      await env.ecrireEcranOuvert(tester, () async {
        await notifier.lancerSiBesoin();
        await notifier.envoyerEnArrierePlan();
        await notifier.envoyerEnQuittant();
      });

      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));
      expect(_nombreDeSauvegardes(env), 2);
      expect(conteneur.read(sauvegardeDriveProvider).phase, PhaseSauvegardeDrive.repos);

      await env.fermer(tester);
      await autre.fermer(tester);
    });

    _ecran('rien de plus récent sur Drive : ni fenêtre ni carte', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);

      final ProviderContainer conteneur = await _ouvrir(tester, env, _lundi.add(const Duration(minutes: 30)));
      await laisserFinir(tester);

      expect(_cle('reprise-dialogue'), findsNothing);
      expect(conteneur.read(repriseDriveProvider), isNull);

      await _ouvrirEcranDrive(tester);
      expect(_cle('drive-reprise-texte'), findsNothing);
      expect(_cle('drive-reprise-decider'), findsNothing);

      await env.fermer(tester);
    });

    _ecran('envoi automatique désactivé : rien n’est comparé, rien n’est proposé', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, automatique: false);
      final _AutreAppareil autre = await _AutreAppareil.creer(tester, env);
      await autre.envoyerAvecProduit(tester, 'Bonnet', _mardi);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      final ProviderContainer conteneur = await _ouvrir(tester, env, _mardi.add(const Duration(minutes: 30)));
      await laisserFinir(tester);

      expect(_cle('reprise-dialogue'), findsNothing);
      expect(conteneur.read(repriseDriveProvider), isNull);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await env.fermer(tester);
      await autre.fermer(tester);
    });
  });

  group('envoi de ce qui a changé', () {
    _ecran('à l’ouverture : du neuf ici (un envoi manqué) part le jour même ; sans rien de neuf, rien ne part', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);
      await env.creerProduit(tester, nom: 'Écharpe');
      final int envoyesAvant = env.clientDrive.envoyes.length;

      // Le jour n'est pas passé (une heure après l'envoi de lundi) : seul le « du neuf » déclenche l'envoi.
      final DateTime plusTard = _lundi.add(const Duration(hours: 1));
      final ProviderContainer conteneur = await _ouvrir(tester, env, plusTard);

      expect(conteneur.read(sauvegardeDriveProvider).resultat!.issue, IssueSauvegardeDrive.faite);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), contains(nomSauvegardeDrive(plusTard)));
      expect(_nombreDeSauvegardes(env), 2);
      expect(env.clientDrive.envoyes.length, greaterThan(envoyesAvant));

      // Rien de plus de neuf : l'ouverture suivante, le même jour, n'envoie rien.
      final int envoyesApres = env.clientDrive.envoyes.length;
      env.maintenant = plusTard.add(const Duration(hours: 1));
      await env.ecrireEcranOuvert(tester, () => conteneur.read(sauvegardeDriveProvider.notifier).lancerSiBesoin());
      expect(env.clientDrive.envoyes, hasLength(envoyesApres));
      expect(_cle('reprise-dialogue'), findsNothing);

      await env.fermer(tester);
    });

    _ecran('Android : en passant en arrière-plan, ce qui a changé part, au plus toutes les 10 minutes', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester);
      await env.creerProduit(tester, nom: 'Écharpe');
      final DateTime t0 = _lundi.add(const Duration(hours: 1));
      final ProviderContainer conteneur = await _ouvrir(tester, env, t0, declencher: false);
      addTearDown(() => _etatDeLApplication(tester, AppLifecycleState.resumed));

      // 1. Premier passage en arrière-plan : l'envoi part.
      _arrierePlanPuisRetour(tester);
      await attendreJusqua(tester, () => _nombreDeSauvegardes(env) == 2, essais: 600);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), contains(nomSauvegardeDrive(t0)));
      await attendreJusqua(tester, () => !conteneur.read(sauvegardeDriveProvider).occupe, essais: 600);

      // 2. Du neuf, mais 5 minutes plus tard : trop tôt, rien ne part.
      await env.ecrireEcranOuvert(tester, () => env.db.insererClient(nom: 'Camille'));
      env.maintenant = t0.add(const Duration(minutes: 5));
      final int envoyesAvant = env.clientDrive.envoyes.length;
      _arrierePlanPuisRetour(tester);
      await laisserFinir(tester);
      await laisserFinir(tester);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));
      expect(_nombreDeSauvegardes(env), 2);

      // 3. 11 minutes après le premier : l'envoi repart.
      env.maintenant = t0.add(const Duration(minutes: 11));
      _arrierePlanPuisRetour(tester);
      await attendreJusqua(tester, () => _nombreDeSauvegardes(env) == 3, essais: 600);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), contains(nomSauvegardeDrive(t0.add(const Duration(minutes: 11)))));
      await attendreJusqua(tester, () => !conteneur.read(sauvegardeDriveProvider).occupe, essais: 600);

      await env.fermer(tester);
    });

    _ecran('Android : sans envoi automatique, le passage en arrière-plan n’envoie rien', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, automatique: false);
      await env.creerProduit(tester, nom: 'Écharpe');
      await _ouvrir(tester, env, _lundi.add(const Duration(hours: 1)), declencher: false);
      addTearDown(() => _etatDeLApplication(tester, AppLifecycleState.resumed));
      final int envoyesAvant = env.clientDrive.envoyes.length;

      _arrierePlanPuisRetour(tester);
      await laisserFinir(tester);
      await laisserFinir(tester);

      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await env.fermer(tester);
    });

    _ecran('Windows : passer en arrière-plan n’envoie rien (c’est la fermeture de la fenêtre qui envoie)', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, plateforme: const Plateforme.windows());
      await env.creerProduit(tester, nom: 'Écharpe');
      await _ouvrir(tester, env, _lundi.add(const Duration(hours: 1)), declencher: false);
      addTearDown(() => _etatDeLApplication(tester, AppLifecycleState.resumed));
      final int envoyesAvant = env.clientDrive.envoyes.length;

      _arrierePlanPuisRetour(tester);
      await laisserFinir(tester);
      await laisserFinir(tester);

      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await env.fermer(tester);
    });
  });

  group('Windows : fermeture de la fenêtre', () {
    SynchroDriveObservateurState observateur(WidgetTester tester) =>
        tester.state<SynchroDriveObservateurState>(find.byType(SynchroDriveObservateur));

    _ecran('ce qui a changé part avant la fermeture, qui est toujours permise', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, plateforme: const Plateforme.windows());
      await env.creerProduit(tester, nom: 'Écharpe');
      final DateTime t0 = _lundi.add(const Duration(hours: 1));
      await _ouvrir(tester, env, t0, declencher: false);

      AppExitResponse? reponse;
      unawaited(observateur(tester).demandeDeSortie().then((AppExitResponse r) => reponse = r));
      await attendreJusqua(tester, () => reponse != null, essais: 600);

      expect(reponse, AppExitResponse.exit);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), contains(nomSauvegardeDrive(t0)));
      expect(_nombreDeSauvegardes(env), 2);
      expect(_cle('fermeture-dialogue'), findsNothing);

      await env.fermer(tester);
    });

    _ecran('rien de neuf : la fenêtre se ferme tout de suite, sans message ni envoi', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, plateforme: const Plateforme.windows());
      await _ouvrir(tester, env, _lundi.add(const Duration(hours: 1)), declencher: false);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      AppExitResponse? reponse;
      unawaited(observateur(tester).demandeDeSortie().then((AppExitResponse r) => reponse = r));
      await attendreJusqua(tester, () => reponse != null, essais: 600);

      expect(reponse, AppExitResponse.exit);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));
      expect(_cle('fermeture-dialogue'), findsNothing);

      await env.fermer(tester);
    });

    _ecran('envoi automatique désactivé : on ferme sans rien envoyer', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephoneSynchronise(
        tester,
        automatique: false,
        plateforme: const Plateforme.windows(),
      );
      await env.creerProduit(tester, nom: 'Écharpe');
      await _ouvrir(tester, env, _lundi.add(const Duration(hours: 1)), declencher: false);
      final int envoyesAvant = env.clientDrive.envoyes.length;

      AppExitResponse? reponse;
      unawaited(observateur(tester).demandeDeSortie().then((AppExitResponse r) => reponse = r));
      await attendreJusqua(tester, () => reponse != null, essais: 600);

      expect(reponse, AppExitResponse.exit);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));

      await env.fermer(tester);
    });

    _ecran('un envoi qui traîne : un message le dit, et « Fermer sans attendre » ferme tout de suite', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, plateforme: const Plateforme.windows());
      await env.creerProduit(tester, nom: 'Écharpe');
      final DateTime t0 = _lundi.add(const Duration(hours: 1));
      await _ouvrir(tester, env, t0, declencher: false);

      // Drive est lent : l'envoi est retenu jusqu'à ce qu'on le libère.
      final Completer<void> retenu = Completer<void>();
      env.clientDrive.pauseEnvoi = (String nom) => retenu.future;

      AppExitResponse? reponse;
      unawaited(observateur(tester).demandeDeSortie().then((AppExitResponse r) => reponse = r));
      await _attendre(tester, _cle('fermeture-dialogue'));

      expect(find.text('Envoi vers Drive avant de fermer'), findsOneWidget);
      expect(_cle('fermeture-etape'), findsOneWidget);
      expect(reponse, isNull);

      await _toucher(tester, _cle('fermeture-sans-attendre'));
      await attendreJusqua(tester, () => reponse != null, essais: 600);
      expect(reponse, AppExitResponse.exit);
      expect(_cle('fermeture-dialogue'), findsNothing);
      // L'envoi n'avait pas abouti : il est retenté à la prochaine ouverture (le « du neuf » est toujours là).
      expect(_nombreDeSauvegardes(env), 1);

      // (Le test laisse l'envoi finir proprement.)
      retenu.complete();
      await attendreJusqua(tester, () => _nombreDeSauvegardes(env) == 2, essais: 600);

      await env.fermer(tester);
    });

    _ecran('une version plus récente attend une décision : rien n’est envoyé à la fermeture', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await _telephoneSynchronise(tester, plateforme: const Plateforme.windows());
      await env.creerProduit(tester, nom: 'Écharpe');
      final _AutreAppareil autre = await _AutreAppareil.creer(tester, env);
      await autre.envoyerAvecProduit(tester, 'Bonnet', _mardi);
      final int envoyesAvant = env.clientDrive.envoyes.length;
      await _ouvrir(tester, env, _mardi.add(const Duration(minutes: 30)), declencher: false);

      AppExitResponse? reponse;
      unawaited(observateur(tester).demandeDeSortie().then((AppExitResponse r) => reponse = r));
      await attendreJusqua(tester, () => reponse != null, essais: 600);

      expect(reponse, AppExitResponse.exit);
      expect(env.clientDrive.envoyes, hasLength(envoyesAvant));
      expect(_nombreDeSauvegardes(env), 2);
      expect(_cle('fermeture-dialogue'), findsNothing);

      await env.fermer(tester);
      await autre.fermer(tester);
    });
  });
}
