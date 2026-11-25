import 'package:crochet_creations/core/plateforme.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/declaration.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/declaration/declaration_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// « Aujourd'hui » dans tous ces tests : le lundi 23 novembre 2026, à 10 h.
final DateTime _maintenant = DateTime(2026, 11, 23, 10);

final Finder _interrupteur = find.byKey(const Key('rappel-declaration'));
final Finder _boutonTester = find.byKey(const Key('rappel-tester'));
final Finder _prochainRappel = find.byKey(const Key('prochain-rappel'));
final Finder _rappelBloque = find.byKey(const Key('rappel-bloque'));

bool _rappelActif(WidgetTester tester) => tester.widget<SwitchListTile>(_interrupteur).value;

/// Appuie, puis attend que la base ait répondu. (Les messages affichés restent à l'écran : `pumpAndSettle` n'attend pas leur fin.)
Future<void> _toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pumpAndSettle();
  await tester.tap(cible);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.pumpAndSettle();
}

/// Accueil → Plus → « Déclaration des recettes ». On n'attend pas que l'écran « se calme » tant que ses recettes se
/// calculent : leur barre de progression tourne, et `pumpAndSettle` ne s'arrêterait pas.
Future<void> _ouvrirDeclaration(WidgetTester tester, EnvironnementTest env, {DateTime? maintenant}) async {
  env.maintenant = maintenant ?? _maintenant;
  await ouvrirAccueil(tester, env, taille: const Size(800, 1800));
  await _toucher(tester, ongletNav('Plus'));

  final Finder entree = find.descendant(of: find.byType(MoreScreen), matching: find.text('Déclaration des recettes'));
  await tester.ensureVisible(entree);
  await tester.pumpAndSettle();
  await tester.tap(entree);
  await tester.pump();
  await attendreJusqua(
    tester,
    () => find.byType(DeclarationScreen).evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await laisserFinir(tester);
  await tester.pumpAndSettle();
  expect(find.byType(DeclarationScreen), findsOneWidget);
}

/// Un paiement de [montant] centimes encaissé à [date], pour une ligne d'objet ou de prestation. [ecranOuvert] : voir
/// `EnvironnementTest.ecrireEcranOuvert`.
Future<void> _encaisser(
  WidgetTester tester,
  EnvironnementTest env,
  DateTime date,
  int montant, {
  NatureLigne nature = NatureLigne.bien,
  bool ecranOuvert = false,
}) {
  Future<void> ecrire() async {
    final int venteId = await env.db
        .into(env.db.ventes)
        .insert(
          VentesCompanion.insert(
            sousTotalCentimes: montant,
            totalCentimes: montant,
            dateVente: Value(date),
          ),
        );
    await env.db
        .into(env.db.lignesVente)
        .insert(
          LignesVenteCompanion.insert(
            venteId: venteId,
            designation: nature == NatureLigne.bien ? 'Bonnet' : 'Couverture sur mesure',
            quantite: 1,
            prixUnitaireCentimes: montant,
            totalLigneCentimes: montant,
            nature: Value(nature),
          ),
        );
    await env.db
        .into(env.db.paiements)
        .insert(
          PaiementsCompanion.insert(
            venteId: venteId,
            montantCentimes: montant,
            modePaiement: ModePaiement.especes,
            datePaiement: Value(date),
          ),
        );
  }

  return ecranOuvert ? env.ecrireEcranOuvert(tester, ecrire) : env.travailler(tester, ecrire);
}

void main() {
  group('l’écran', () {
    testWidgets('l’onglet Plus y donne accès ; le rappel est désactivé au départ', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirDeclaration(tester, env);

      expect(find.text('Rappel de fin de mois'), findsOneWidget);
      expect(find.text('Me rappeler la déclaration'), findsOneWidget);
      expect(find.textContaining('3 jours avant la fin du mois, puis le dernier jour, à 9 h'), findsOneWidget);
      expect(_rappelActif(tester), isFalse);
      expect(_prochainRappel, findsNothing);
      expect(_rappelBloque, findsNothing);
      expect(_boutonTester, findsOneWidget);
      // Rien n'est programmé, rien n'a été demandé tant que la personne n'a rien choisi.
      expect(env.planificateur.demandes, 0);
      expect(env.planificateur.programmes, isEmpty);
      await env.fermer(tester);
    });

    testWidgets('les recettes de ce mois-ci et du mois dernier : objets, prestations et total', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _encaisser(tester, env, DateTime(2026, 11, 5, 9), 3000);
      await _encaisser(tester, env, DateTime(2026, 11, 20, 14), 4500, nature: NatureLigne.service);
      await _encaisser(tester, env, DateTime(2026, 10, 31, 22), 2000);
      await _encaisser(tester, env, DateTime(2026, 10, 3, 10), 1500, nature: NatureLigne.service);
      await _encaisser(tester, env, DateTime(2026, 9, 30, 12), 999); // septembre : ne compte pas
      await _ouvrirDeclaration(tester, env);

      expect(find.text('Ce mois-ci : novembre 2026'), findsOneWidget);
      expect(find.text('Le mois dernier : octobre 2026'), findsOneWidget);
      expect(find.text('Ventes d’objets'), findsNWidgets(2));
      expect(find.text('Prestations et cours'), findsNWidgets(2));
      expect(find.text('Total encaissé'), findsNWidgets(2));

      expect(find.text(formatEuros(3000)), findsOneWidget);
      expect(find.text(formatEuros(4500)), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('total-2026-11'))).data, formatEuros(7500));
      expect(find.text(formatEuros(2000)), findsOneWidget);
      expect(find.text(formatEuros(1500)), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('total-2026-10'))).data, formatEuros(3500));

      expect(find.textContaining('L’application n’envoie rien à l’organisme'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('sans aucune vente, les deux mois sont à zéro', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirDeclaration(tester, env);

      expect(tester.widget<Text>(find.byKey(const Key('total-2026-11'))).data, formatEuros(0));
      expect(tester.widget<Text>(find.byKey(const Key('total-2026-10'))).data, formatEuros(0));
      await env.fermer(tester);
    });

    testWidgets('en janvier, « le mois dernier » est décembre de l’année d’avant', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _encaisser(tester, env, DateTime(2026, 12, 18, 10), 8000);
      await _ouvrirDeclaration(tester, env, maintenant: DateTime(2027, 1, 12, 9));

      expect(find.text('Ce mois-ci : janvier 2027'), findsOneWidget);
      expect(find.text('Le mois dernier : décembre 2026'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('total-2026-12'))).data, formatEuros(8000));
      await env.fermer(tester);
    });

    testWidgets('un paiement enregistré pendant que l’écran est ouvert met le total à jour', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await _ouvrirDeclaration(tester, env);
      expect(tester.widget<Text>(find.byKey(const Key('total-2026-11'))).data, formatEuros(0));

      await _encaisser(tester, env, DateTime(2026, 11, 22, 11), 6000, ecranOuvert: true);
      await attendreJusqua(
        tester,
        () => tester.widget<Text>(find.byKey(const Key('total-2026-11'))).data == formatEuros(6000),
      );

      expect(tester.widget<Text>(find.byKey(const Key('total-2026-11'))).data, formatEuros(6000));
      await env.fermer(tester);
    });
  });

  group('le rappel', () {
    for (final (String nom, Plateforme plateforme) in <(String, Plateforme)>[
      ('Android', const Plateforme.android()),
      ('Windows', const Plateforme.windows()),
    ]) {
      testWidgets('$nom : activer programme les 12 prochains mois et affiche le prochain rappel', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        env.plateforme = plateforme;
        await _ouvrirDeclaration(tester, env);

        await _toucher(tester, _interrupteur);

        expect(_rappelActif(tester), isTrue);
        expect(env.planificateur.demandes, 1);
        expect(env.planificateur.programmes, prochainsRappelsDeclaration(_maintenant));
        expect(env.planificateur.programmes, hasLength(24));
        expect(await env.travailler(tester, () => env.parametres.lireRappelDeclaration()), isTrue);
        expect(tester.widget<Text>(_prochainRappel).data, 'Prochain rappel : vendredi 27 novembre à 9 h 00.');
        expect(_rappelBloque, findsNothing);
        await env.fermer(tester);
      });

      testWidgets('$nom : « Tester la notification » en affiche une tout de suite', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        env.plateforme = plateforme;
        await _ouvrirDeclaration(tester, env);

        await _toucher(tester, _boutonTester);

        expect(env.planificateur.affichees, hasLength(1));
        expect(env.planificateur.affichees.single.titre, 'Déclaration des recettes');
        expect(find.textContaining('Notification envoyée.'), findsOneWidget);
        // Un essai ne programme rien et n'active pas le rappel.
        expect(env.planificateur.programmes, isEmpty);
        expect(_rappelActif(tester), isFalse);
        await env.fermer(tester);
      });
    }

    testWidgets('désactiver annule les notifications programmées', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.travailler(tester, () => env.parametres.enregistrerRappelDeclaration(true));
      await _ouvrirDeclaration(tester, env);
      expect(_rappelActif(tester), isTrue);
      expect(_prochainRappel, findsOneWidget);

      await _toucher(tester, _interrupteur);

      expect(_rappelActif(tester), isFalse);
      expect(env.planificateur.annulations, 1);
      expect(env.planificateur.programmes, isEmpty);
      expect(_prochainRappel, findsNothing);
      expect(await env.travailler(tester, () => env.parametres.lireRappelDeclaration()), isFalse);
      await env.fermer(tester);
    });

    testWidgets('activé avant l’ouverture de l’écran : il l’affiche activé, avec le prochain rappel', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.travailler(tester, () => env.parametres.enregistrerRappelDeclaration(true));
      await _ouvrirDeclaration(tester, env, maintenant: DateTime(2026, 11, 30, 10));

      expect(_rappelActif(tester), isTrue);
      // Le mois de novembre est passé : le prochain rappel est celui de décembre, 3 jours avant la fin du mois.
      expect(tester.widget<Text>(_prochainRappel).data, 'Prochain rappel : lundi 28 décembre à 9 h 00.');
      await env.fermer(tester);
    });

    testWidgets('si les notifications sont refusées, le rappel reste désactivé et l’écran l’explique', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.planificateur
        ..autorisation = false
        ..reponseALaDemande = false;
      await _ouvrirDeclaration(tester, env);

      await _toucher(tester, _interrupteur);

      expect(_rappelActif(tester), isFalse);
      expect(find.textContaining('Le rappel n’est pas activé. Les notifications sont refusées'), findsOneWidget);
      expect(env.planificateur.demandes, 1);
      expect(env.planificateur.programmes, isEmpty);
      expect(await env.travailler(tester, () => env.parametres.lireRappelDeclaration()), isFalse);
      await env.fermer(tester);
    });

    testWidgets('« Tester la notification » avec les notifications refusées : rien n’est affiché, un message l’explique', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.planificateur
        ..autorisation = false
        ..reponseALaDemande = false;
      await _ouvrirDeclaration(tester, env);

      await _toucher(tester, _boutonTester);

      expect(env.planificateur.affichees, isEmpty);
      expect(find.textContaining('Aucune notification n’a été envoyée. Les notifications sont refusées'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('activé, mais notifications bloquées depuis dans les réglages de l’appareil : un avertissement', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await env.travailler(tester, () => env.parametres.enregistrerRappelDeclaration(true));
      env.planificateur.autorisation = false;
      await _ouvrirDeclaration(tester, env);

      expect(_rappelActif(tester), isTrue);
      expect(_rappelBloque, findsOneWidget);
      expect(find.textContaining('Les notifications sont bloquées pour l’application'), findsOneWidget);
      await env.fermer(tester);
    });

    testWidgets('pas d’avertissement quand le rappel est désactivé, même si les notifications sont bloquées', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.planificateur.autorisation = false;
      await _ouvrirDeclaration(tester, env);

      expect(_rappelActif(tester), isFalse);
      expect(_rappelBloque, findsNothing);
      await env.fermer(tester);
    });

    testWidgets('si le système de notifications échoue, un message l’explique et rien n’est activé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.planificateur.erreurAuRemplacement = StateError('le système ne répond pas');
      await _ouvrirDeclaration(tester, env);

      await _toucher(tester, _interrupteur);

      expect(_rappelActif(tester), isFalse);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(await env.travailler(tester, () => env.parametres.lireRappelDeclaration()), isFalse);
      // L'interrupteur et le bouton sont de nouveau utilisables.
      expect(tester.widget<SwitchListTile>(_interrupteur).onChanged, isNotNull);
      expect(tester.widget<OutlinedButton>(_boutonTester).onPressed, isNotNull);
      await env.fermer(tester);
    });

    testWidgets('appareil sans notifications : l’écran le dit, sans interrupteur ni bouton d’essai', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      env.planificateur.disponible = false;
      await _ouvrirDeclaration(tester, env);

      expect(find.text('Les rappels ne sont pas disponibles sur cet appareil.'), findsOneWidget);
      expect(_interrupteur, findsNothing);
      expect(_boutonTester, findsNothing);
      // Les recettes restent affichées.
      expect(find.byKey(const Key('total-2026-11')), findsOneWidget);
      await env.fermer(tester);
    });
  });
}
