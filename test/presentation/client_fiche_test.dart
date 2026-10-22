import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/clients/client_fiche_screen.dart';
import 'package:crochet_creations/presentation/clients/clients_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Cherche dans la fiche client uniquement.
Finder dansFiche(Finder cible) => find.descendant(of: find.byType(ClientFicheScreen), matching: cible);

/// Ouvre la fiche du client affiché [nom] depuis l'onglet Clients.
Future<void> ouvrirFiche(WidgetTester tester, EnvironnementTest env, String nom) async {
  // Écran très haut : toute la fiche (coordonnées, historique) est construite d'un coup.
  await ouvrirAccueil(tester, env, taille: const Size(800, 3200));
  await tester.tap(ongletNav('Clients'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(find.descendant(of: find.byType(ClientsScreen), matching: find.text(nom)));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

Future<void> ouvrirMenuClient(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus d’actions'));
  await tester.pumpAndSettle();
}

const DonneesClient _camille = DonneesClient(
  civilite: Civilite.madame,
  prenom: 'Camille',
  nom: 'Martin',
  telephone: '06 12 34 56 78',
  email: 'camille@exemple.fr',
  adresse: '12 rue des Lilas',
  codePostal: '31000',
  ville: 'Toulouse',
  notes: 'Aime les doudous beiges',
);

void main() {
  testWidgets('la fiche affiche les coordonnées d’un particulier', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerClient(tester, _camille);
    await ouvrirFiche(tester, env, 'Camille Martin');

    expect(dansFiche(find.text('Camille Martin')), findsWidgets); // titre et en-tête
    for (final String texte in <String>[
      'Coordonnées',
      'Particulier',
      'Madame',
      '06 12 34 56 78',
      'camille@exemple.fr',
      '12 rue des Lilas\n31000 Toulouse',
      'Aime les doudous beiges',
    ]) {
      expect(dansFiche(find.text(texte)), findsOneWidget, reason: texte);
    }
    // Pas de SIREN pour un particulier, ni de bandeau « archivé ».
    expect(dansFiche(find.text('SIREN / SIRET')), findsNothing);
    expect(dansFiche(find.text('Restaurer')), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('la fiche d’un professionnel montre l’entreprise, le SIRET et la personne à contacter', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerClient(
      tester,
      const DonneesClient(
        typeClient: TypeClient.professionnel,
        raisonSociale: 'Boutique La Pelote',
        siret: '123 456 789 00012',
        prenom: 'Julie',
        nom: 'Roux',
      ),
    );
    await ouvrirFiche(tester, env, 'Boutique La Pelote');

    expect(dansFiche(find.text('Boutique La Pelote')), findsWidgets);
    expect(dansFiche(find.text('Julie Roux')), findsOneWidget);
    expect(dansFiche(find.text('Professionnel')), findsWidgets); // étiquette + ligne « Type »
    expect(dansFiche(find.text('SIREN / SIRET')), findsOneWidget);
    expect(dansFiche(find.text('123 456 789 00012')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('sans coordonnées : une phrase invite à les ajouter', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerClient(tester, const DonneesClient(prenom: 'Léa'));
    await ouvrirFiche(tester, env, 'Léa');

    expect(dansFiche(find.textContaining('Aucune coordonnée enregistrée')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('historique vide : un message par rubrique', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerClient(tester, _camille);
    await ouvrirFiche(tester, env, 'Camille Martin');

    for (final String texte in <String>[
      'Historique',
      'Aucune vente.',
      'Aucun paiement.',
      'Aucune facture.',
      'Aucun devis.',
      'Aucune inscription à un cours.',
    ]) {
      expect(dansFiche(find.text(texte)), findsOneWidget, reason: texte);
    }

    await env.fermer(tester);
  });

  testWidgets('l’historique montre ventes, paiements, factures, devis et cours du client', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client camille = await env.creerClient(tester, _camille);
    final Client autre = await env.creerClient(tester, const DonneesClient(prenom: 'Zoé', nom: 'Bernard'));

    // Deux ventes validées (25 € + 15 €), une annulée, une vente d'une autre cliente.
    final int v1 = await env.ajouterVenteClient(
      tester,
      clientId: camille.id,
      total: 2500,
      date: DateTime(2026, 10, 1),
      paiement: ModePaiement.especes,
    );
    await env.ajouterVenteClient(
      tester,
      clientId: camille.id,
      total: 1500,
      date: DateTime(2026, 10, 15),
      paiement: ModePaiement.carte,
    );
    await env.ajouterVenteClient(
      tester,
      clientId: camille.id,
      total: 9900,
      date: DateTime(2026, 10, 20),
      statut: StatutVente.annulee,
    );
    await env.ajouterVenteClient(tester, clientId: autre.id, total: 7700, date: DateTime(2026, 10, 10));

    await env.travailler(tester, () async {
      await env.db
          .into(env.db.factures)
          .insert(
            FacturesCompanion.insert(
              numero: 'FACT-2026-0001',
              venteId: v1,
              dateVentePrestation: DateTime(2026, 10, 1),
              totalCentimes: 2500,
              clientId: Value(camille.id),
              dateEmission: Value(DateTime(2026, 10, 1)),
            ),
          );
      await env.db
          .into(env.db.devis)
          .insert(
            DevisCompanion.insert(
              numero: 'DEVIS-2026-0001',
              sousTotalCentimes: 4000,
              totalCentimes: 4000,
              clientId: Value(camille.id),
              dateEmission: Value(DateTime(2026, 9, 20)),
              statut: const Value(StatutDevis.accepte),
            ),
          );
      final int cours = await env.db
          .into(env.db.cours)
          .insert(
            CoursCompanion.insert(
              titre: 'Initiation au crochet',
              debutLe: DateTime(2026, 11, 7, 14),
              dureeMinutes: 120,
              prixCentimes: 4500,
              places: 6,
            ),
          );
      await env.db
          .into(env.db.inscriptionsCours)
          .insert(InscriptionsCoursCompanion.insert(coursId: cours, clientId: camille.id, prixCentimes: 4500));
    });

    await ouvrirFiche(tester, env, 'Camille Martin');

    // Synthèse : seules les ventes validées comptent.
    expect(dansFiche(find.text('2 ventes validées · ${formatEuros(4000)}')), findsOneWidget);
    // Détail des ventes (la vente annulée est signalée).
    expect(dansFiche(find.text(formatDateCourte(DateTime(2026, 10, 20)))), findsOneWidget);
    expect(dansFiche(find.text('Annulée')), findsOneWidget);
    expect(dansFiche(find.text(formatEuros(9900))), findsOneWidget);
    // Paiements : la date et le mode.
    expect(dansFiche(find.text('Espèces')), findsOneWidget);
    expect(dansFiche(find.text('Carte')), findsOneWidget);
    // Factures, devis, cours.
    expect(dansFiche(find.text('FACT-2026-0001')), findsOneWidget);
    expect(dansFiche(find.text('${formatDateCourte(DateTime(2026, 10, 1))} · Émise')), findsOneWidget);
    expect(dansFiche(find.text('DEVIS-2026-0001')), findsOneWidget);
    expect(dansFiche(find.text('${formatDateCourte(DateTime(2026, 9, 20))} · Accepté')), findsOneWidget);
    expect(dansFiche(find.text('Initiation au crochet')), findsOneWidget);
    expect(dansFiche(find.text('${formatDateCourte(DateTime(2026, 11, 7))} · Confirmée')), findsOneWidget);
    // Plus de message « vide » pour les rubriques remplies.
    expect(dansFiche(find.text('Aucune vente.')), findsNothing);
    expect(dansFiche(find.text('Aucune facture.')), findsNothing);
    // Rien de la vente d'une autre cliente (77 €).
    expect(dansFiche(find.text(formatEuros(7700))), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('au-delà de 5 lignes, « Voir tout » déplie la rubrique', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client c = await env.creerClient(tester, _camille);
    for (int jour = 1; jour <= 7; jour++) {
      await env.ajouterVenteClient(tester, clientId: c.id, total: 1000, date: DateTime(2026, 10, jour));
    }
    await ouvrirFiche(tester, env, 'Camille Martin');

    final Finder lignes = dansFiche(find.byType(ListTile));
    expect(lignes, findsNWidgets(5));
    expect(dansFiche(find.text('7 ventes validées · ${formatEuros(7000)}')), findsOneWidget);

    await tester.tap(dansFiche(find.text('Voir les 7')));
    await tester.pumpAndSettle();
    expect(lignes, findsNWidgets(7));

    await tester.tap(dansFiche(find.text('Voir moins')));
    await tester.pumpAndSettle();
    expect(lignes, findsNWidgets(5));

    await env.fermer(tester);
  });

  testWidgets('l’historique se met à jour quand une vente est ajoutée', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client c = await env.creerClient(tester, _camille);
    await ouvrirFiche(tester, env, 'Camille Martin');
    expect(dansFiche(find.text('Aucune vente.')), findsOneWidget);

    await env.ajouterVenteClient(
      tester,
      clientId: c.id,
      total: 2500,
      date: DateTime(2026, 10, 1),
      ecranOuvert: true,
    );
    await attendreJusqua(tester, () => dansFiche(find.text('Aucune vente.')).evaluate().isEmpty);

    expect(dansFiche(find.text('Aucune vente.')), findsNothing);
    expect(dansFiche(find.text('1 vente validée · ${formatEuros(2500)}')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('archiver demande confirmation, puis le client peut être restauré', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client c = await env.creerClient(tester, _camille);
    await ouvrirFiche(tester, env, 'Camille Martin');

    // On annule : rien ne change.
    await ouvrirMenuClient(tester);
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    expect(find.text('Archiver ce client ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect((await env.travailler(tester, () => env.clients.obtenir(c.id)))!.archiveLe, isNull);

    // On confirme.
    await ouvrirMenuClient(tester);
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archiver'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.text('Client archivé.'), findsOneWidget); // message en bas de l'écran
    expect(dansFiche(find.text('Client archivé : il n’apparaît plus dans la liste.')), findsOneWidget);
    expect(dansFiche(find.text('Archivé')), findsOneWidget); // étiquette
    expect((await env.travailler(tester, () => env.clients.obtenir(c.id)))!.archiveLe, isNotNull);

    // Restauration depuis le bandeau.
    await tester.tap(dansFiche(find.widgetWithText(TextButton, 'Restaurer')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(dansFiche(find.text('Client archivé : il n’apparaît plus dans la liste.')), findsNothing);
    expect(find.text('Client restauré dans la liste.'), findsOneWidget);
    expect((await env.travailler(tester, () => env.clients.obtenir(c.id)))!.archiveLe, isNull);

    await env.fermer(tester);
  });

  testWidgets('le menu d’un client archivé propose « Restaurer »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client c = await env.creerClient(tester, _camille);
    await env.travailler(tester, () => env.clients.archiver(c.id));
    await ouvrirAccueil(tester, env, taille: const Size(800, 3200));
    await tester.tap(ongletNav('Clients'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ClientsScreen), matching: find.text('Archivés')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ClientsScreen), matching: find.text('Camille Martin')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    await ouvrirMenuClient(tester);
    expect(find.text('Archiver'), findsNothing);
    await tester.tap(find.text('Restaurer').last);
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect((await env.travailler(tester, () => env.clients.obtenir(c.id)))!.archiveLe, isNull);

    await env.fermer(tester);
  });
}
