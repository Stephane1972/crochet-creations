
import 'package:crochet_creations/core/plateforme.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/agenda_repository.dart';
import 'package:crochet_creations/data/repositories/devis_repository.dart';
import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/agenda/agenda_screen.dart';
import 'package:crochet_creations/presentation/agenda/evenement_form_screen.dart';
import 'package:crochet_creations/presentation/cours/cours_fiche_screen.dart';
import 'package:crochet_creations/presentation/devis/devis_detail_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/notes/notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// « Aujourd'hui » dans tous ces tests : le lundi 23 novembre 2026, à 10 h.
final DateTime _maintenant = DateTime(2026, 11, 23, 10);

Finder _jour(int annee, int mois, int jour) =>
    find.byKey(Key('jour-$annee-${mois.toString().padLeft(2, '0')}-${jour.toString().padLeft(2, '0')}'));

Finder _puce(String libelle) => find.widgetWithText(FilterChip, libelle);

bool _affiche(WidgetTester tester, String libelle) => tester.widget<FilterChip>(_puce(libelle)).selected;

String _texteDe(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

String _titreDuMois(WidgetTester tester) => _texteDe(tester, 'agenda-titre-du-mois');

String _titreDuJour(WidgetTester tester) => _texteDe(tester, 'agenda-titre-du-jour');

Finder _dansFormulaire(Finder cible) => find.descendant(of: find.byType(EvenementFormScreen), matching: cible);

Finder _dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

/// Attend la fin du chargement du calendrier (la barre de progression du mois disparaît), puis laisse finir les animations.
Future<void> _attendreCalendrier(WidgetTester tester) async {
  await attendreJusqua(tester, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Appuie, puis attend que la base ait répondu.
Future<void> _toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pumpAndSettle();
  await tester.tap(cible);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.pumpAndSettle();
}

/// Accueil → tuile « Calendrier ».
Future<void> _ouvrirCalendrier(WidgetTester tester, EnvironnementTest env) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: const Size(800, 1800));
  await _toucher(tester, find.text('Calendrier').hitTestable());
  expect(find.byType(AgendaScreen), findsOneWidget);
  await _attendreCalendrier(tester);
}

/// Prépare ce que le calendrier doit montrer en novembre 2026, avant d'ouvrir l'application : un cours le 25, un devis
/// valable jusqu'au 27, un événement le 28 (la déclaration est le 30).
Future<void> _preparerNovembre(WidgetTester tester, EnvironnementTest env, {bool evenement = true}) async {
  env.maintenant = _maintenant;
  await env.creerCours(tester, titre: 'Initiation au crochet', debut: DateTime(2026, 11, 25, 14), dureeMinutes: 150);
  // Un devis daté du 20 novembre, valable jusqu'au 27 : l'horloge réelle ne doit pas le rendre invalide.
  await env.travailler(
    tester,
    () => env.devis.creer(
      DevisSaisi(
        panier: const Panier().ajouter(
          designation: 'Couverture bébé sur mesure',
          nature: NatureLigne.service,
          prixUnitaireCentimes: 6000,
          quantite: 1,
        ),
        dateEmission: DateTime(2026, 11, 20),
        dateValidite: DateTime(2026, 11, 27),
      ),
    ),
  );
  if (evenement) {
    await env.travailler(
      tester,
      () => env.agenda.creer(
        DonneesEvenement(titre: 'Marché de Noël', jour: DateTime(2026, 11, 28), notes: 'Prévoir la nappe'),
      ),
    );
  }
}

void main() {
  group('l’accueil', () {
    for (final (String nom, Plateforme plateforme) in <(String, Plateforme)>[
      ('Android', const Plateforme.android()),
      ('Windows', const Plateforme.windows()),
    ]) {
      testWidgets('$nom : la tuile « Bloc-notes » ouvre le bloc-notes', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        env.plateforme = plateforme;
        await ouvrirAccueil(tester, env);

        await _toucher(tester, find.text('Bloc-notes').hitTestable());
        await attendreJusqua(tester, () => find.byType(NotesScreen).evaluate().isNotEmpty);

        expect(find.byType(NotesScreen), findsOneWidget);
        await env.fermer(tester);
      });

      testWidgets('$nom : la tuile « Calendrier » ouvre le calendrier, sur le mois en cours', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        env.plateforme = plateforme;
        await _ouvrirCalendrier(tester, env);

        expect(_titreDuMois(tester), 'Novembre 2026');
        expect(_titreDuJour(tester), 'Lundi 23 novembre 2026');
        expect(find.text('Rien de prévu ce jour-là.'), findsOneWidget);
        expect(find.text('Ouvrir Google Agenda'), findsOneWidget);
        await env.fermer(tester);
      });
    }

    testWidgets('l’onglet Plus donne aussi accès au calendrier', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirAccueil(tester, env);

      await _toucher(tester, ongletNav('Plus'));
      await _toucher(tester, find.descendant(of: find.byType(MoreScreen), matching: find.text('Calendrier')));

      expect(find.byType(AgendaScreen), findsOneWidget);
      await env.fermer(tester);
    });
  });

  group('le calendrier', () {
    for (final (String nom, Plateforme plateforme) in <(String, Plateforme)>[
      ('Android', const Plateforme.android()),
      ('Windows', const Plateforme.windows()),
    ]) {
      testWidgets('$nom : chaque jour montre ce qui est prévu (cours, devis, événement, déclaration)', (
        WidgetTester tester,
      ) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        env.plateforme = plateforme;
        await _preparerNovembre(tester, env);
        await _ouvrirCalendrier(tester, env);

        // Le cours du 25 : l'heure, la durée et le lieu.
        await _toucher(tester, _jour(2026, 11, 25));
        expect(_titreDuJour(tester), 'Mercredi 25 novembre 2026');
        expect(find.text('Initiation au crochet'), findsOneWidget);
        expect(find.text('14 h 00 – 16 h 30 · Atelier de Camille'), findsOneWidget);

        // Le devis, le dernier jour de sa validité.
        await _toucher(tester, _jour(2026, 11, 27));
        expect(find.textContaining('Fin de validité du devis'), findsOneWidget);
        expect(find.text('Sans client'), findsOneWidget);

        // L'événement, avec ses précisions.
        await _toucher(tester, _jour(2026, 11, 28));
        expect(find.text('Marché de Noël'), findsOneWidget);
        expect(find.text('Prévoir la nappe'), findsOneWidget);

        // La déclaration : le dernier jour du mois.
        await _toucher(tester, _jour(2026, 11, 30));
        expect(find.text('Déclaration des recettes'), findsOneWidget);

        // Un jour sans rien.
        await _toucher(tester, _jour(2026, 11, 26));
        expect(find.text('Rien de prévu ce jour-là.'), findsOneWidget);
        await env.fermer(tester);
      });
    }

    testWidgets('les filtres masquent un type d’entrées ; le choix est gardé dans les réglages', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparerNovembre(tester, env);
      await _ouvrirCalendrier(tester, env);

      for (final String libelle in <String>['Cours', 'Devis', 'Déclaration', 'Mes événements']) {
        expect(_affiche(tester, libelle), isTrue, reason: libelle);
      }

      await _toucher(tester, _puce('Devis'));
      await attendreJusqua(tester, () => !_affiche(tester, 'Devis'));
      expect(_affiche(tester, 'Devis'), isFalse);
      expect(_affiche(tester, 'Cours'), isTrue);

      // Le devis a disparu du jour 27.
      await _toucher(tester, _jour(2026, 11, 27));
      expect(find.textContaining('Fin de validité du devis'), findsNothing);
      expect(find.text('Rien de prévu ce jour-là.'), findsOneWidget);

      // Le choix est enregistré : un autre écran (ou le prochain démarrage) le retrouve.
      final Entreprise reglages = await env.travailler(tester, () => env.parametres.lire());
      expect(reglages.agendaDevis, isFalse);
      expect(reglages.agendaCours, isTrue);
      expect(reglages.agendaDeclaration, isTrue);
      expect(reglages.agendaEvenements, isTrue);

      // Masquer « Mes événements » puis réafficher « Devis ».
      await _toucher(tester, _puce('Mes événements'));
      await attendreJusqua(tester, () => !_affiche(tester, 'Mes événements'));
      await _toucher(tester, _jour(2026, 11, 28));
      expect(find.text('Marché de Noël'), findsNothing);

      await _toucher(tester, _puce('Devis'));
      await attendreJusqua(tester, () => _affiche(tester, 'Devis'));
      await _toucher(tester, _jour(2026, 11, 27));
      expect(find.textContaining('Fin de validité du devis'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('un filtre masqué avant l’ouverture est appliqué dès l’affichage', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparerNovembre(tester, env);
      await env.travailler(
        tester,
        () => env.parametres.enregistrerFiltresAgenda(const FiltresAgenda(declaration: false, cours: false)),
      );
      await _ouvrirCalendrier(tester, env);

      expect(_affiche(tester, 'Cours'), isFalse);
      expect(_affiche(tester, 'Déclaration'), isFalse);
      expect(_affiche(tester, 'Devis'), isTrue);

      await _toucher(tester, _jour(2026, 11, 25));
      expect(find.text('Initiation au crochet'), findsNothing);
      await _toucher(tester, _jour(2026, 11, 30));
      expect(find.text('Déclaration des recettes'), findsNothing);
      await env.fermer(tester);
    });

    testWidgets('mois précédent, mois suivant et « Aujourd’hui »', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);

      await _toucher(tester, find.byTooltip('Mois suivant'));
      await _attendreCalendrier(tester);
      expect(_titreDuMois(tester), 'Décembre 2026');
      expect(_titreDuJour(tester), 'Mercredi 23 décembre 2026');

      await _toucher(tester, find.byTooltip('Mois précédent'));
      await _toucher(tester, find.byTooltip('Mois précédent'));
      await _attendreCalendrier(tester);
      expect(_titreDuMois(tester), 'Octobre 2026');

      await _toucher(tester, find.byTooltip('Aujourd’hui'));
      await _attendreCalendrier(tester);
      expect(_titreDuMois(tester), 'Novembre 2026');
      expect(_titreDuJour(tester), 'Lundi 23 novembre 2026');
      await env.fermer(tester);
    });

    testWidgets('d’un mois de 31 jours à février, le jour choisi suit sans dépasser le mois', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.maintenant = DateTime(2027, 1, 31, 9);
      await ouvrirAccueil(tester, env, taille: const Size(800, 1800));
      await _toucher(tester, find.text('Calendrier').hitTestable());
      await _attendreCalendrier(tester);
      expect(_titreDuJour(tester), 'Dimanche 31 janvier 2027');

      await _toucher(tester, find.byTooltip('Mois suivant'));
      await _attendreCalendrier(tester);

      expect(_titreDuMois(tester), 'Février 2027');
      expect(_titreDuJour(tester), 'Dimanche 28 février 2027');
      await env.fermer(tester);
    });

    testWidgets('un jour des semaines voisines, touché dans la grille, fait passer à son mois', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);

      // La grille de novembre 2026 commence le lundi 26 octobre.
      await _toucher(tester, _jour(2026, 10, 31));
      await _attendreCalendrier(tester);

      expect(_titreDuMois(tester), 'Octobre 2026');
      expect(_titreDuJour(tester), 'Samedi 31 octobre 2026');
      // Le 31 octobre est aussi le jour de déclaration d'octobre.
      expect(find.text('Déclaration des recettes'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('ce qui est créé pendant que le calendrier est ouvert apparaît tout de suite', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);
      expect(find.text('Rien de prévu ce jour-là.'), findsOneWidget);

      await env.ecrireEcranOuvert(
        tester,
        () => env.agenda.creer(DonneesEvenement(titre: 'Livraison de laine', jour: DateTime(2026, 11, 23))),
      );
      await attendreJusqua(tester, () => find.text('Livraison de laine').evaluate().isNotEmpty);

      expect(find.text('Livraison de laine'), findsOneWidget);
      expect(find.text('Rien de prévu ce jour-là.'), findsNothing);
      await env.fermer(tester);
    });

    testWidgets('un appui sur un cours ou sur un devis ouvre sa fiche', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparerNovembre(tester, env, evenement: false);
      await _ouvrirCalendrier(tester, env);

      await _toucher(tester, _jour(2026, 11, 25));
      await _toucher(tester, find.text('Initiation au crochet'));
      await attendreJusqua(tester, () => find.byType(CoursFicheScreen).evaluate().isNotEmpty);
      expect(find.byType(CoursFicheScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(CoursFicheScreen))).pop();
      await tester.pumpAndSettle();
      await _attendreCalendrier(tester);

      await _toucher(tester, _jour(2026, 11, 27));
      await _toucher(tester, find.textContaining('Fin de validité du devis'));
      await attendreJusqua(tester, () => find.byType(DevisDetailScreen).evaluate().isNotEmpty);
      expect(find.byType(DevisDetailScreen), findsOneWidget);
      await env.fermer(tester);
    });
  });

  group('liens vers Google Agenda', () {
    testWidgets('« Ouvrir Google Agenda » ouvre le mois du jour choisi dans le navigateur', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, _jour(2026, 11, 28));

      await _toucher(tester, find.text('Ouvrir Google Agenda'));

      expect(env.ouvreurAdresse.ouvertes.map((Uri u) => u.toString()), <String>[
        'https://calendar.google.com/calendar/r/month/2026/11/28',
      ]);
      await env.fermer(tester);
    });

    testWidgets('« Ajouter à Google Agenda » : l’événement arrive déjà rempli (titre, heures, lieu)', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparerNovembre(tester, env);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, _jour(2026, 11, 25));

      await _toucher(tester, find.byTooltip('Ajouter à Google Agenda'));

      final Uri adresse = env.ouvreurAdresse.ouvertes.single;
      expect(adresse.scheme, 'https');
      expect(adresse.host, 'calendar.google.com');
      expect(adresse.path, '/calendar/render');
      expect(adresse.queryParameters['action'], 'TEMPLATE');
      expect(adresse.queryParameters['text'], 'Initiation au crochet');
      expect(adresse.queryParameters['location'], 'Atelier de Camille');
      final List<String> dates = adresse.queryParameters['dates']!.split('/');
      expect(DateTime.parse(dates[0]), DateTime(2026, 11, 25, 14).toUtc());
      expect(DateTime.parse(dates[1]), DateTime(2026, 11, 25, 16, 30).toUtc());
      await env.fermer(tester);
    });

    testWidgets('la déclaration des recettes s’ajoute à Google Agenda en se répétant chaque mois', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, _jour(2026, 11, 30));

      await _toucher(tester, find.byTooltip('Ajouter à Google Agenda'));

      final Uri adresse = env.ouvreurAdresse.ouvertes.single;
      expect(adresse.queryParameters['text'], 'Déclaration des recettes');
      expect(adresse.queryParameters['dates'], '20261130/20261201');
      expect(adresse.queryParameters['recur'], 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1');
      await env.fermer(tester);
    });

    testWidgets('si le navigateur ne s’ouvre pas, un message le dit', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.ouvreurAdresse.reussit = false;
      await _ouvrirCalendrier(tester, env);

      await _toucher(tester, find.text('Ouvrir Google Agenda'));

      expect(find.textContaining('Impossible d’ouvrir Google Agenda'), findsOneWidget);
      await env.fermer(tester);
    });
  });

  group('mes événements', () {
    testWidgets('un nouvel événement est créé au jour affiché, sur toute la journée', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, _jour(2026, 11, 26));

      await _toucher(tester, find.text('Nouvel événement'));
      expect(find.byType(EvenementFormScreen), findsOneWidget);
      expect(find.text('jeudi 26 novembre 2026'), findsOneWidget); // le jour du formulaire
      expect(find.text('Début'), findsNothing);

      await saisir(tester, 'Titre *', 'Salon du fait main');
      await saisir(tester, 'Précisions (lieu, matériel à prévoir...)', 'Stand 14');
      await _toucher(tester, find.widgetWithText(TextButton, 'Enregistrer'));
      await attendreJusqua(tester, () => find.byType(EvenementFormScreen).evaluate().isEmpty);
      await _attendreCalendrier(tester);

      // De retour sur le calendrier : l'événement est là, au jour affiché.
      expect(find.byType(AgendaScreen), findsOneWidget);
      expect(_titreDuJour(tester), 'Jeudi 26 novembre 2026');
      expect(find.text('Salon du fait main'), findsOneWidget);
      expect(find.text('Stand 14'), findsOneWidget);
      final List<EvenementAgenda> enBase = await env.travailler(tester, () => env.agenda.lister());
      expect(enBase.single.titre, 'Salon du fait main');
      expect(enBase.single.debutLe, DateTime(2026, 11, 26));
      expect(enBase.single.journeeEntiere, isTrue);
      await env.fermer(tester);
    });

    testWidgets('sans titre, rien n’est enregistré et le champ est signalé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, find.text('Nouvel événement'));

      await _toucher(tester, find.widgetWithText(TextButton, 'Enregistrer'));

      expect(find.byType(EvenementFormScreen), findsOneWidget);
      expect(find.text('Le titre est obligatoire.'), findsOneWidget);
      expect(await env.travailler(tester, () => env.agenda.lister()), isEmpty);
      await env.fermer(tester);
    });

    testWidgets('« Toute la journée » décoché : l’heure de début et l’heure de fin (facultative) apparaissent', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, find.text('Nouvel événement'));
      expect(find.text('Début'), findsNothing);

      await _toucher(tester, find.widgetWithText(SwitchListTile, 'Toute la journée'));

      expect(_dansFormulaire(find.text('Début')), findsOneWidget);
      expect(_dansFormulaire(find.text('Fin (facultatif)')), findsOneWidget);
      expect(_dansFormulaire(find.text('9 h 00')), findsOneWidget);
      expect(_dansFormulaire(find.text('Aucune')), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('modifier un événement, puis le supprimer', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparerNovembre(tester, env);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, _jour(2026, 11, 28));

      // Modifier.
      await _toucher(tester, find.text('Marché de Noël'));
      await attendreJusqua(tester, () => find.byType(EvenementFormScreen).evaluate().isNotEmpty);
      await attendreJusqua(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Modifier l’événement'), findsOneWidget);
      expect(texteDuChampEvenement(tester, 'Titre *'), 'Marché de Noël');
      await saisir(tester, 'Titre *', 'Marché de Noël de Saint-Paul');
      await _toucher(tester, find.widgetWithText(TextButton, 'Enregistrer'));
      await attendreJusqua(tester, () => find.byType(EvenementFormScreen).evaluate().isEmpty);
      await _attendreCalendrier(tester);
      expect(find.text('Marché de Noël de Saint-Paul'), findsOneWidget);

      // Supprimer, après confirmation.
      await _toucher(tester, find.text('Marché de Noël de Saint-Paul'));
      await attendreJusqua(tester, () => find.byType(EvenementFormScreen).evaluate().isNotEmpty);
      await attendreJusqua(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.pumpAndSettle();
      await _toucher(tester, find.text('Supprimer l’événement'));
      expect(find.text('Supprimer cet événement ?'), findsOneWidget);
      await _toucher(tester, _dansDialogue(find.text('Supprimer')));
      await attendreJusqua(tester, () => find.byType(EvenementFormScreen).evaluate().isEmpty);
      await _attendreCalendrier(tester);

      expect(find.text('Marché de Noël de Saint-Paul'), findsNothing);
      expect(find.text('Rien de prévu ce jour-là.'), findsOneWidget);
      expect(await env.travailler(tester, () => env.agenda.lister()), isEmpty);
      await env.fermer(tester);
    });

    testWidgets('refuser la suppression garde l’événement', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _preparerNovembre(tester, env);
      await _ouvrirCalendrier(tester, env);
      await _toucher(tester, _jour(2026, 11, 28));
      await _toucher(tester, find.text('Marché de Noël'));
      await attendreJusqua(tester, () => find.byType(EvenementFormScreen).evaluate().isNotEmpty);
      await attendreJusqua(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.pumpAndSettle();

      await _toucher(tester, find.text('Supprimer l’événement'));
      await _toucher(tester, _dansDialogue(find.text('Annuler')));

      expect(find.byType(EvenementFormScreen), findsOneWidget);
      expect(await env.travailler(tester, () => env.agenda.lister()), hasLength(1));
      await env.fermer(tester);
    });
  });
}

String texteDuChampEvenement(WidgetTester tester, String libelle) {
  final TextFormField champ = tester.widget(find.widgetWithText(TextFormField, libelle));
  return champ.controller!.text;
}
