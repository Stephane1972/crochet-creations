import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/repositories/agenda_repository.dart';
import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/presentation/agenda/agenda_google_screen.dart';
import 'package:crochet_creations/presentation/agenda/agenda_screen.dart';
import 'package:crochet_creations/presentation/drive/drive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// « Aujourd'hui » dans tous ces tests : le lundi 23 novembre 2026, à 10 h.
final DateTime _maintenant = DateTime(2026, 11, 23, 10);

const ProfilGoogle _stef = ProfilGoogle(email: 'stef@exemple.fr', nom: 'Stéphane');

Finder _cle(String nom) => find.byKey(Key(nom));

String _texte(WidgetTester tester, String cle) => tester.widget<Text>(_cle(cle)).data!;

bool _actif(WidgetTester tester) => tester.widget<SwitchListTile>(_cle('agenda-google-actif')).value;

Finder _dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

/// Appuie sur un élément, puis laisse finir les animations et les lectures de la base, sans « pumpAndSettle » (une barre de
/// progression tourne pendant une synchronisation, et ne se calme jamais).
Future<void> _toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pump();
  await tester.tap(cible);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await laisserFinir(tester);
}

/// Attend que la synchronisation en cours soit terminée.
Future<void> _attendreFinDeSynchro(WidgetTester tester) async {
  await attendreJusqua(tester, () => _cle('agenda-google-en-cours').evaluate().isEmpty, essais: 400);
  await laisserFinir(tester);
}

/// Attend qu'un texte (partie de texte) soit affiché.
Future<void> _attendreTexte(WidgetTester tester, String extrait) async {
  await attendreJusqua(tester, () => find.textContaining(extrait).evaluate().isNotEmpty, essais: 400);
  expect(find.textContaining(extrait), findsWidgets, reason: 'Texte attendu : $extrait');
}

/// Ouvre l'application (à l'heure fixe) puis, par-dessus l'accueil, l'écran « Google Agenda ».
///
/// [attendre] : la clé d'un élément à attendre (les réglages se lisent dans la base, un peu après l'ouverture de l'écran).
Future<void> _ouvrirEcran(WidgetTester tester, EnvironnementTest env, {String? attendre}) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: const Size(800, 1800));
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(AppRoutes.agendaGoogle));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await attendreJusqua(
    tester,
    () => find.byType(AgendaGoogleScreen).evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  if (attendre != null) await attendreJusqua(tester, () => _cle(attendre).evaluate().isNotEmpty, essais: 400);
  await laisserFinir(tester);
  expect(find.byType(AgendaGoogleScreen), findsOneWidget);
}

/// Prépare, avant d'ouvrir l'application : la personne est connectée, sans les déclarations (14 jours de plus à compter) ;
/// [evenements] événements « Événement 1 », « Événement 2 »... aux jours 11, 12... décembre ; la synchronisation est
/// [active] ou non ; le droit « Google Agenda » est [droit] ou non.
Future<void> _preparer(
  WidgetTester tester,
  EnvironnementTest env, {
  int evenements = 0,
  bool active = false,
  bool droit = true,
  bool connecte = true,
}) async {
  env.compteGoogle
    ..dejaConnecte = connecte ? _stef : null
    ..agendaAccorde = droit;
  await env.travailler(tester, () async {
    await env.parametres.enregistrerFiltresAgenda(const FiltresAgenda(declaration: false));
    for (int i = 1; i <= evenements; i++) {
      await env.agenda.creer(DonneesEvenement(titre: 'Événement $i', jour: DateTime(2026, 12, 10 + i)));
    }
    if (active) await env.parametres.enregistrerAgendaGoogle(actif: true);
  });
}

void main() {
  group('accès', () {
    testWidgets('le calendrier a un bouton qui ouvre l’écran « Google Agenda »', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env);
      env.maintenant = _maintenant;
      await ouvrirAccueil(tester, env, taille: const Size(800, 1800));
      await _toucher(tester, find.text('Calendrier').hitTestable());
      expect(find.byType(AgendaScreen), findsOneWidget);

      await _toucher(tester, find.byTooltip('Synchroniser avec Google Agenda'));
      await attendreJusqua(tester, () => find.byType(AgendaGoogleScreen).evaluate().isNotEmpty);

      expect(find.byType(AgendaGoogleScreen), findsOneWidget);
      expect(find.text('Envoyer mon calendrier vers Google Agenda'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('l’explication dit où vont les événements, dans quel sens, et que rien n’est supprimé sans demande', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env);
      await _ouvrirEcran(tester, env);

      expect(find.textContaining('son propre agenda « Un p’tit crochet dans les stocks »'), findsOneWidget);
      expect(find.textContaining('Un seul sens'), findsOneWidget);
      expect(find.textContaining('marqué « [Annulé] »'), findsWidgets);
      await env.fermer(tester);
    });

    testWidgets('sur un appareil sans Google Agenda : le dit, sans rien proposer', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.agendaGoogleIndisponible = true;
      await _preparer(tester, env);
      await _ouvrirEcran(tester, env);

      expect(_cle('agenda-google-indisponible'), findsOneWidget);
      expect(_cle('agenda-google-actif'), findsNothing);
      expect(_cle('agenda-google-synchroniser'), findsNothing);
      await env.fermer(tester);
    });

    testWidgets('pas connecté à Google : le dit, et mène à l’écran Google Drive', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, connecte: false);
      await _ouvrirEcran(tester, env);

      expect(_cle('agenda-google-non-connecte'), findsOneWidget);
      expect(_cle('agenda-google-actif'), findsNothing);

      await _toucher(tester, _cle('agenda-google-connexion'));
      await attendreJusqua(tester, () => find.byType(DriveScreen).evaluate().isNotEmpty);

      expect(find.byType(DriveScreen), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('connecté : l’interrupteur est éteint, avec le compte, et rien d’autre n’est proposé', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env);
      await _ouvrirEcran(tester, env);

      expect(_actif(tester), isFalse);
      expect(find.text('Compte Google : stef@exemple.fr'), findsOneWidget);
      expect(_cle('agenda-google-synchroniser'), findsNothing);
      expect(_cle('agenda-google-nettoyer'), findsNothing);
      expect(env.agendaGoogle.journal, isEmpty);
      await env.fermer(tester);
    });
  });

  group('activation', () {
    testWidgets('activer : le droit est demandé, l’agenda est créé et rempli, le bilan est affiché', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, droit: false);
      await _ouvrirEcran(tester, env);

      await _toucher(tester, _cle('agenda-google-actif'));
      await attendreJusqua(tester, () => _cle('agenda-google-bilan').evaluate().isNotEmpty);
      await _attendreFinDeSynchro(tester);

      expect(env.compteGoogle.demandesAgenda, 1);
      expect(_actif(tester), isTrue);
      expect(_texte(tester, 'agenda-google-bilan'), '1 ajouté.');
      expect(find.textContaining('Dernière synchronisation'), findsOneWidget);
      expect(env.agendaGoogle.calendriers.values.single.keys, <String>['ptite1']);
      expect(_cle('agenda-google-synchroniser'), findsOneWidget);
      expect(_cle('agenda-google-ouvrir'), findsOneWidget);
      expect(_cle('agenda-google-nettoyer'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('si la personne ferme la fenêtre d’autorisation : rien n’est activé, et elle est prévenue', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.compteGoogle.reponseDemandeAgenda = false;
      await _preparer(tester, env, evenements: 1, droit: false);
      await _ouvrirEcran(tester, env);

      await _toucher(tester, _cle('agenda-google-actif'));
      await _attendreTexte(tester, 'Autorisation annulée');

      expect(_actif(tester), isFalse);
      expect(env.agendaGoogle.journal, isEmpty);
      expect(_cle('agenda-google-synchroniser'), findsNothing);
      await env.fermer(tester);
    });

    testWidgets('activée mais droit retiré : le dit, et un bouton redonne le droit puis synchronise', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, active: true, droit: false);
      await _ouvrirEcran(tester, env);
      await attendreJusqua(tester, () => _cle('agenda-google-droit-absent').evaluate().isNotEmpty);

      expect(_cle('agenda-google-droit-absent'), findsOneWidget);
      expect(_actif(tester), isTrue);

      await _toucher(tester, _cle('agenda-google-autoriser'));
      await attendreJusqua(tester, () => _cle('agenda-google-droit-absent').evaluate().isEmpty);
      await _attendreFinDeSynchro(tester);

      expect(env.compteGoogle.demandesAgenda, 1);
      expect(_cle('agenda-google-droit-absent'), findsNothing);
      expect(_cle('agenda-google-autoriser'), findsNothing);
      expect(_texte(tester, 'agenda-google-bilan'), '1 ajouté.');
      expect(env.agendaGoogle.calendriers.values.single.keys, <String>['ptite1']);
      await env.fermer(tester);
    });

    testWidgets('désactiver : les boutons disparaissent, et ce qui est dans Google Agenda y reste', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);
      expect(env.agendaGoogle.calendriers.values.single.keys, <String>['ptite1']);

      await _toucher(tester, _cle('agenda-google-actif'));
      await attendreJusqua(tester, () => _cle('agenda-google-synchroniser').evaluate().isEmpty);

      expect(_actif(tester), isFalse);
      expect(_cle('agenda-google-synchroniser'), findsNothing);
      expect(env.agendaGoogle.calendriers.values.single.keys, <String>['ptite1']);
      expect(env.agendaGoogle.appels('supprimer'), 0);
      await env.fermer(tester);
    });
  });

  group('synchronisation', () {
    testWidgets('avant toute synchronisation : « aucune depuis l’ouverture » ; « Synchroniser maintenant » envoie le calendrier', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, active: true);
      await _ouvrirEcran(tester, env);
      await attendreJusqua(tester, () => _cle('agenda-google-bilan').evaluate().isNotEmpty);
      expect(_texte(tester, 'agenda-google-bilan'), 'Aucune synchronisation depuis l’ouverture de l’application.');

      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);

      expect(_texte(tester, 'agenda-google-bilan'), '1 ajouté.');

      // Un nouvel événement : « 1 ajouté, 1 déjà à jour ».
      await env.ecrireEcranOuvert(
        tester,
        () => env.agenda.creer(DonneesEvenement(titre: 'Salon créateurs', jour: DateTime(2026, 12, 20))),
      );
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);

      expect(_texte(tester, 'agenda-google-bilan'), '1 ajouté, 1 déjà à jour.');
      expect(env.agendaGoogle.calendriers.values.single.keys, <String>['ptite1', 'ptite2']);
      await env.fermer(tester);
    });

    testWidgets('une écriture refusée : synchronisation partielle, le motif est montré', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 2, active: true);
      env.agendaGoogle.panne = (String operation, String? id) =>
          operation == 'creer' && id == 'ptite2' ? const ErreurDrive('Google refuse cet événement.') : null;
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');

      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);

      final String bilan = _texte(tester, 'agenda-google-bilan');
      expect(bilan, contains('1 ajouté, 1 en échec.'));
      expect(bilan, contains('Motif : Google refuse cet événement.'));
      await env.fermer(tester);
    });

    testWidgets('une erreur de réseau est expliquée', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, active: true);
      env.agendaGoogle.panne = (String operation, String? id) =>
          operation == 'creerCalendrier' ? const ErreurDrive('Pas de connexion à Internet.') : null;
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');

      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);

      expect(_texte(tester, 'agenda-google-bilan'), 'Pas de connexion à Internet.');
      await env.fermer(tester);
    });

    testWidgets('agenda supprimé dans Google Agenda : « introuvable », et un bouton en crée un nouveau', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);
      expect(_cle('agenda-google-recreer'), findsNothing);

      env.agendaGoogle.supprimerAgendaDansGoogle(env.agendaGoogle.calendriers.keys.single);
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);

      expect(_texte(tester, 'agenda-google-bilan'), contains('introuvable'));
      expect(_cle('agenda-google-recreer'), findsOneWidget);
      expect(env.agendaGoogle.appels('creerCalendrier'), 1);

      await _toucher(tester, _cle('agenda-google-recreer'));
      await _attendreFinDeSynchro(tester);

      expect(_texte(tester, 'agenda-google-bilan'), '1 ajouté.');
      expect(_cle('agenda-google-recreer'), findsNothing);
      expect(env.agendaGoogle.calendriers.keys, <String>['agenda-test-2']);
      expect(env.agendaGoogle.calendriers['agenda-test-2']!.keys, <String>['ptite1']);
      await env.fermer(tester);
    });

    testWidgets('« Ouvrir Google Agenda » ouvre le navigateur sur le compte connecté', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');

      await _toucher(tester, _cle('agenda-google-ouvrir'));

      expect(env.ouvreurAdresse.ouvertes.map((Uri u) => u.toString()), <String>[
        lienOuvrirGoogleAgenda(compte: 'stef@exemple.fr').toString(),
      ]);
      await env.fermer(tester);
    });

    testWidgets('si le navigateur ne s’ouvre pas : un message le dit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.ouvreurAdresse.reussit = false;
      await _preparer(tester, env, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');

      await _toucher(tester, _cle('agenda-google-ouvrir'));

      expect(find.textContaining('Impossible d’ouvrir Google Agenda'), findsOneWidget);
      await env.fermer(tester);
    });
  });

  group('nettoyer l’agenda Google', () {
    testWidgets('liste ce qui serait supprimé, demande confirmation, et ne supprime que les événements « [Annulé] »', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 2, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);
      expect(_texte(tester, 'agenda-google-bilan'), '2 ajoutés.');

      // Un événement disparaît de l'application : il est marqué « [Annulé] » dans Google, pas supprimé.
      await env.ecrireEcranOuvert(tester, () => env.agenda.supprimer(1));
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);
      expect(_texte(tester, 'agenda-google-bilan'), '1 marqué « [Annulé] », 1 déjà à jour.');
      final String agendaGoogle = env.agendaGoogle.calendriers.keys.single;
      expect(env.agendaGoogle.evenement(agendaGoogle, 'ptite1')!.titre, '[Annulé] Événement 1');
      expect(env.agendaGoogle.appels('supprimer'), 0);

      // Annuler la confirmation : rien n'est supprimé.
      await _toucher(tester, _cle('agenda-google-nettoyer'));
      await _attendreTexte(tester, '1 événement marqué « [Annulé] » sera supprimé');
      expect(find.text('Nettoyer l’agenda Google ?'), findsOneWidget);
      await _toucher(tester, _dansDialogue(find.text('Annuler')));
      expect(env.agendaGoogle.appels('supprimer'), 0);
      expect(find.byType(AlertDialog), findsNothing);

      // Confirmer : seul l'événement marqué est supprimé de Google Agenda ; l'application n'est pas touchée.
      await _toucher(tester, _cle('agenda-google-nettoyer'));
      await _attendreTexte(tester, '1 événement marqué « [Annulé] » sera supprimé');
      await _toucher(tester, _dansDialogue(find.text('Supprimer')));
      await _attendreTexte(tester, '1 événement supprimé de Google Agenda.');

      expect(env.agendaGoogle.calendriers[agendaGoogle]!.keys, <String>['ptite2']);
      expect(env.agendaGoogle.appels('supprimer'), 1);
      final int dansLApplication = (await env.ecrireEcranOuvert(tester, () => env.agenda.lister())).length;
      expect(dansLApplication, 1);
      await env.fermer(tester);
    });

    testWidgets('rien d’annulé : un message, et aucune suppression', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, evenements: 1, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');
      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);

      await _toucher(tester, _cle('agenda-google-nettoyer'));
      await _attendreTexte(tester, 'il n’y a rien à nettoyer');

      expect(find.byType(AlertDialog), findsNothing);
      expect(env.agendaGoogle.appels('supprimer'), 0);
      await env.fermer(tester);
    });

    testWidgets('le nettoyage n’est proposé qu’une fois l’agenda créé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparer(tester, env, active: true);
      await _ouvrirEcran(tester, env, attendre: 'agenda-google-synchroniser');

      expect(_cle('agenda-google-nettoyer'), findsNothing);

      await _toucher(tester, _cle('agenda-google-synchroniser'));
      await _attendreFinDeSynchro(tester);
      await attendreJusqua(tester, () => _cle('agenda-google-nettoyer').evaluate().isNotEmpty);

      expect(_cle('agenda-google-nettoyer'), findsOneWidget);
      await env.fermer(tester);
    });
  });
}
