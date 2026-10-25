import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/clients/client_fiche_screen.dart';
import 'package:crochet_creations/presentation/entreprise/mon_entreprise_screen.dart';
import 'package:crochet_creations/presentation/factures/facture_detail_screen.dart';
import 'package:crochet_creations/presentation/factures/factures_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_confirmation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

const DonneesEntreprise _profilComplet = DonneesEntreprise(
  nomCommercial: 'Crochet & Créations',
  nomResponsable: 'Camille Martin',
  adresse: '12 rue des Lilas',
  codePostal: '31000',
  ville: 'Toulouse',
  siren: '123456789',
);

/// Numéro d'une facture créée aujourd'hui : `FACT-<année en cours>-000N`.
String numero(int n) => 'FACT-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';

Finder dansVente(Finder cible) => find.descendant(of: find.byType(VenteConfirmationScreen), matching: cible);
Finder dansDetail(Finder cible) => find.descendant(of: find.byType(FactureDetailScreen), matching: cible);
Finder dansListe(Finder cible) => find.descendant(of: find.byType(FacturesScreen), matching: cible);

/// Texte de l'aperçu de remplacement (voir `EnvironnementTest.overrides`) pour ce numéro de facture.
Finder apercu(String numeroFacture) => find.text('Aperçu : %PDF-FAUX $numeroFacture');

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route, {Object? arguments}) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route, arguments: arguments));
  // Pas de pumpAndSettle : l'aperçu d'une facture lit un fichier (vrai travail), l'indicateur d'attente tourne
  // tant qu'il n'est pas fini et le temps simulé ne se « calme » donc jamais. `attendre` suit la suite.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre la vente [venteId] (confirmation) et attend son contenu.
Future<void> ouvrirLaVente(WidgetTester tester, int venteId) async {
  await ouvrirRoute(tester, AppRoutes.venteConfirmation, arguments: venteId);
  await attendre(tester, dansVente(find.text('Total')));
}

Future<void> completerProfil(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.parametres.enregistrerProfil(_profilComplet));

Future<List<Facture>> facturesEnBase(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.factures.lister());

void main() {
  testWidgets('profil incomplet : « Créer la facture » dit ce qui manque et ouvre « Mon entreprise »', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p);
    await ouvrirAccueil(tester, env);
    await ouvrirLaVente(tester, vente.id);

    expect(dansVente(find.text('Cette vente n’a pas encore de facture.')), findsOneWidget);
    await tester.tap(dansVente(find.text('Créer la facture')));
    await tester.pump();
    await attendre(tester, find.text('Informations manquantes'));

    expect(find.textContaining('le nom de l’entreprise'), findsOneWidget);
    expect(find.textContaining('l’adresse'), findsOneWidget);
    expect(find.textContaining('le numéro SIREN'), findsOneWidget);
    expect(find.textContaining('dans « Mon entreprise »'), findsOneWidget);
    expect(await facturesEnBase(tester, env), isEmpty);

    // « Plus tard » ferme la fenêtre sans rien faire.
    await tester.tap(find.widgetWithText(TextButton, 'Plus tard'));
    await tester.pumpAndSettle();
    expect(find.text('Informations manquantes'), findsNothing);
    expect(find.byType(MonEntrepriseScreen), findsNothing);

    // « Ouvrir » mène au profil.
    await tester.tap(dansVente(find.text('Créer la facture')));
    await tester.pump();
    await attendre(tester, find.text('Informations manquantes'));
    await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir « Mon entreprise »'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(find.byType(MonEntrepriseScreen), findsOneWidget);
    expect(await facturesEnBase(tester, env), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('« Créer la facture » établit la facture, ouvre son aperçu et la rattache à la vente', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client camille = await env.creerClient(
      tester,
      const DonneesClient(prenom: 'Camille', nom: 'Martin'),
    );
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p, clientId: camille.id);
    await completerProfil(tester, env);
    await ouvrirAccueil(tester, env);
    await ouvrirLaVente(tester, vente.id);

    await tester.tap(dansVente(find.text('Créer la facture')));
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numero(1))));

    // Aperçu et détail.
    expect(dansDetail(find.text(numero(1))), findsOneWidget); // titre
    expect(dansDetail(find.text('Camille Martin')), findsOneWidget);
    expect(dansDetail(find.text(formatEuros(2500))), findsOneWidget);
    expect(dansDetail(find.text('Émise')), findsOneWidget);
    expect(dansDetail(find.text('Partager')), findsOneWidget);
    expect(dansDetail(find.text('Imprimer')), findsOneWidget);
    expect(dansDetail(find.text('Annuler la facture')), findsOneWidget);
    expect(
      dansDetail(
        find.text(
          'Émise le ${formatDateCourte(DateTime.now())} · vente du ${formatDateCourte(vente.dateVente)}',
        ),
      ),
      findsOneWidget,
    );

    // Le document fabriqué porte les informations de l'entreprise et du client.
    final List<Facture> factures = await facturesEnBase(tester, env);
    expect(factures.single.numero, numero(1));
    expect(env.generateurPdf.dernier?.emetteur.nom, 'Crochet & Créations');
    expect(env.generateurPdf.dernier?.client.nom, 'Camille Martin');

    // De retour sur la vente : la facture remplace le bouton.
    await retourArriere(tester);
    await attendre(tester, dansVente(find.text('Émise le ${formatDateCourte(DateTime.now())}')));
    expect(dansVente(find.text(numero(1))), findsOneWidget);
    expect(dansVente(find.text('Créer la facture')), findsNothing);

    // Un appui sur la facture la rouvre.
    await tester.tap(dansVente(find.text(numero(1))));
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numero(1))));

    await env.fermer(tester);
  });

  testWidgets('partager et imprimer envoient le PDF de la facture', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p);
    await completerProfil(tester, env);
    final Facture facture = await env.travailler(tester, () => env.factures.creer(vente.id));
    await ouvrirAccueil(tester, env);
    await ouvrirRoute(tester, AppRoutes.factureDetail, arguments: facture.id);
    await attendre(tester, dansDetail(apercu(numero(1))));

    await tester.tap(dansDetail(find.text('Partager')));
    await tester.pump();
    await attendreJusqua(tester, () => env.documents.partages.isNotEmpty);
    await tester.pumpAndSettle();
    expect(env.documents.partages, <String>['${numero(1)}.pdf | Facture ${numero(1)}']);
    expect(env.documents.cheminsPartages.single, endsWith('${numero(1)}.pdf'));

    await tester.tap(dansDetail(find.text('Imprimer')));
    await tester.pump();
    await attendreJusqua(tester, () => env.documents.impressions.isNotEmpty);
    await tester.pumpAndSettle();
    expect(env.documents.impressions, <String>['${numero(1)} : %PDF-FAUX ${numero(1)}']);

    await env.fermer(tester);
  });

  testWidgets('annuler la facture : la vente reste, une nouvelle facture peut être créée', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p);
    await completerProfil(tester, env);
    final Facture facture = await env.travailler(tester, () => env.factures.creer(vente.id));
    await ouvrirAccueil(tester, env);
    await ouvrirLaVente(tester, vente.id);
    await tester.tap(dansVente(find.text(numero(1))));
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numero(1))));

    // On garde la facture : rien ne change.
    await tester.tap(dansDetail(find.text('Annuler la facture')));
    await tester.pumpAndSettle();
    expect(find.text('Annuler la facture ${numero(1)} ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Garder la facture'));
    await tester.pumpAndSettle();
    expect(dansDetail(find.text('Émise')), findsOneWidget);
    expect((await facturesEnBase(tester, env)).single.statut, StatutFacture.emise);

    // On l'annule.
    await tester.tap(dansDetail(find.text('Annuler la facture')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Annuler la facture'));
    await tester.pump();
    await attendre(tester, dansDetail(find.text('Annulée')));

    expect(dansDetail(find.textContaining('Cette facture est annulée.')), findsOneWidget);
    expect(dansDetail(find.text('Partager')), findsNothing);
    expect(dansDetail(find.text('Imprimer')), findsNothing);
    expect(dansDetail(find.text('Annuler la facture')), findsNothing);
    await attendre(tester, find.text('Facture ${numero(1)} annulée.'));
    final Facture annulee = (await facturesEnBase(tester, env)).single;
    expect(annulee.id, facture.id);
    expect(annulee.statut, StatutFacture.annulee);
    final Vente venteApres = (await env.travailler(tester, () => env.ventes.obtenir(vente.id)))!;
    expect(venteApres.statut, StatutVente.validee);

    // Sur la vente : la facture annulée est rappelée et on peut en créer une nouvelle.
    await retourArriere(tester);
    await attendre(tester, dansVente(find.text('Facture annulée : ${numero(1)}')));
    expect(dansVente(find.text('Créer la facture')), findsOneWidget);
    await tester.tap(dansVente(find.text('Créer la facture')));
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numero(2))));
    expect((await facturesEnBase(tester, env)).map((Facture f) => f.numero), <String>[
      numero(2),
      numero(1),
    ]);

    await env.fermer(tester);
  });

  testWidgets('si le PDF est introuvable, il est refait à l’ouverture de la facture', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p);
    await completerProfil(tester, env);
    final Facture facture = await env.travailler(tester, () => env.factures.creer(vente.id));
    await env.travailler(tester, () => env.stockageFactures.supprimer(facture.pdfChemin!));
    expect(env.generateurPdf.documents, hasLength(1));
    await ouvrirAccueil(tester, env);

    await ouvrirRoute(tester, AppRoutes.factureDetail, arguments: facture.id);
    await attendre(tester, dansDetail(apercu(numero(1))));

    expect(env.generateurPdf.documents, hasLength(2));

    await env.fermer(tester);
  });

  testWidgets('liste des factures : vide, puis la plus récente d’abord, avec les annulées signalées', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client camille = await env.creerClient(
      tester,
      const DonneesClient(prenom: 'Camille', nom: 'Martin'),
    );
    final Produit p = await env.creerProduit(tester, stock: 10);
    final Vente v1 = await env.validerVente(tester, produit: p, clientId: camille.id);
    final Vente v2 = await env.validerVente(tester, produit: p, quantite: 2);
    await completerProfil(tester, env);
    await ouvrirAccueil(tester, env);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factures'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(find.byType(FacturesScreen), findsOneWidget);
    expect(dansListe(find.text('Aucune facture pour le moment.')), findsOneWidget);

    // Deux factures créées pendant que la liste est ouverte : elle se met à jour toute seule.
    final Facture f1 = await env.ecrireEcranOuvert(tester, () => env.factures.creer(v1.id, date: DateTime(2026, 10, 1)));
    await env.ecrireEcranOuvert(tester, () => env.factures.creer(v2.id, date: DateTime(2026, 10, 20)));
    await env.ecrireEcranOuvert(tester, () => env.factures.annuler(f1.id));
    await attendre(tester, dansListe(find.text('FACT-2026-0002')));

    expect(dansListe(find.text('Aucune facture pour le moment.')), findsNothing);
    expect(dansListe(find.text('FACT-2026-0001')), findsOneWidget);
    expect(dansListe(find.text('Client de passage · ${formatDateCourte(DateTime(2026, 10, 20))}')), findsOneWidget);
    expect(dansListe(find.text('Camille Martin · ${formatDateCourte(DateTime(2026, 10, 1))}')), findsOneWidget);
    expect(dansListe(find.text(formatEuros(5000))), findsOneWidget);
    expect(dansListe(find.text('Annulée')), findsOneWidget);
    // La plus récente est en premier.
    expect(
      tester.getTopLeft(dansListe(find.text('FACT-2026-0002'))).dy,
      lessThan(tester.getTopLeft(dansListe(find.text('FACT-2026-0001'))).dy),
    );

    // Un appui ouvre la facture.
    await tester.tap(dansListe(find.text('FACT-2026-0002')));
    await tester.pump();
    await attendre(tester, dansDetail(apercu('FACT-2026-0002')));
    expect(find.byType(FactureDetailScreen), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('l’historique d’un client ouvre ses factures', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client camille = await env.creerClient(
      tester,
      const DonneesClient(prenom: 'Camille', nom: 'Martin'),
    );
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p, clientId: camille.id);
    await completerProfil(tester, env);
    await env.travailler(tester, () => env.factures.creer(vente.id));
    await ouvrirAccueil(tester, env, taille: const Size(800, 3200));

    await tester.tap(ongletNav('Clients'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await tester.tap(find.text('Camille Martin').hitTestable());
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    expect(find.byType(ClientFicheScreen), findsOneWidget);

    final Finder ligne = find.descendant(of: find.byType(ClientFicheScreen), matching: find.text(numero(1)));
    await attendre(tester, ligne);
    await tester.tap(ligne);
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numero(1))));

    await env.fermer(tester);
  });

  testWidgets('une vente annulée n’offre pas de créer une facture', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit p = await env.creerProduit(tester);
    final Vente vente = await env.validerVente(tester, produit: p);
    await env.travailler(tester, () => env.ventes.annuler(vente.id));
    await ouvrirAccueil(tester, env);
    await ouvrirLaVente(tester, vente.id);

    expect(dansVente(find.text('Vente annulée')), findsOneWidget);
    expect(dansVente(find.text('Créer la facture')), findsNothing);
    expect(dansVente(find.text('Facture')), findsNothing);

    await env.fermer(tester);
  });
}
