import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/date_fr.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/devis_vues.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/data/repositories/vente_vues.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/devis/devis_conversion_screen.dart';
import 'package:crochet_creations/presentation/devis/devis_detail_screen.dart';
import 'package:crochet_creations/presentation/devis/devis_form_screen.dart';
import 'package:crochet_creations/presentation/devis/devis_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_confirmation_screen.dart';
import 'package:drift/drift.dart' show Value;
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

/// Numéro d'un devis créé aujourd'hui : `DEVIS-<année en cours>-000N`.
String numeroDevis(int n) => 'DEVIS-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';

/// Numéro d'une facture créée aujourd'hui : `FACT-<année en cours>-000N`.
String numeroFacture(int n) => 'FACT-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';

Finder dansListe(Finder cible) => find.descendant(of: find.byType(DevisScreen), matching: cible);
Finder dansFormulaire(Finder cible) => find.descendant(of: find.byType(DevisFormScreen), matching: cible);
Finder dansDetail(Finder cible) => find.descendant(of: find.byType(DevisDetailScreen), matching: cible);
Finder dansConversion(Finder cible) => find.descendant(of: find.byType(DevisConversionScreen), matching: cible);
Finder dansVente(Finder cible) => find.descendant(of: find.byType(VenteConfirmationScreen), matching: cible);

/// Texte de l'aperçu de remplacement (voir `EnvironnementTest.overrides`) pour ce numéro de devis.
Finder apercu(String numero) => find.text('Aperçu : %PDF-FAUX $numero');

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Comme [attendre], mais attend aussi qu'aucun indicateur d'attente ne tourne plus (un PDF en cours de
/// fabrication lit un fichier : `pumpAndSettle` ne finirait jamais tant qu'il tourne).
Future<void> attendreEtStabiliser(WidgetTester tester, Finder cible) async {
  await attendreJusqua(
    tester,
    () => cible.evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route, {Object? arguments}) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route, arguments: arguments));
  // Pas de pumpAndSettle : l'aperçu d'un devis lit un fichier (vrai travail), l'indicateur d'attente tourne
  // tant qu'il n'est pas fini et le temps simulé ne se « calme » donc jamais. `attendre` suit la suite.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre l'aperçu du devis [id] et attend son PDF.
Future<void> ouvrirLeDevis(WidgetTester tester, DevisFiche devis) async {
  await ouvrirRoute(tester, AppRoutes.devisDetail, arguments: devis.id);
  await attendre(tester, dansDetail(apercu(devis.numero)));
}

/// Passe la date du devis et sa validité dans le passé : la base le permet, l'application non (elle refuse de
/// créer un devis déjà périmé), c'est donc le temps qui est censé le faire.
Future<void> perimer(WidgetTester tester, EnvironnementTest env, int devisId) {
  final DateTime maintenant = DateTime.now();
  return env.travailler(
    tester,
    () => (env.db.update(env.db.devis)..where((t) => t.id.equals(devisId))).write(
      DevisCompanion(
        dateEmission: Value(maintenant.subtract(const Duration(days: 40))),
        dateValidite: Value(maintenant.subtract(const Duration(days: 10))),
      ),
    ),
  );
}

Future<DevisFiche> devisEnBase(WidgetTester tester, EnvironnementTest env, int id) =>
    env.travailler(tester, () async => (await env.devis.obtenir(id))!);

Future<void> completerProfil(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.parametres.enregistrerProfil(_profilComplet));

void main() {
  testWidgets('liste des devis : vide au départ', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

    await ouvrirRoute(tester, AppRoutes.devis);
    await attendre(tester, dansListe(find.text('Aucun devis pour le moment.')));

    expect(dansListe(find.text('Nouveau devis')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('liste des devis : le plus récent d’abord, avec leur statut, les périmés étant « Expiré »', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client lea = await env.creerClient(tester, const DonneesClient(prenom: 'Léa', nom: 'Bernard'));
    final DevisFiche ancien = await env.creerDevis(tester, clientId: lea.id, prix: 6000);
    final DevisFiche recent = await env.creerDevis(tester, designation: 'Bonnet', prix: 1800);
    await perimer(tester, env, ancien.id);
    await ouvrirAccueil(tester, env);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devis'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);
    await attendre(tester, dansListe(find.text(numeroDevis(1))));

    expect(dansListe(find.text(numeroDevis(2))), findsOneWidget);
    expect(dansListe(find.text('Sans client · ${formatDateCourte(DateTime.now())}')), findsOneWidget);
    expect(
      dansListe(
        find.text(
          'Léa Bernard · ${formatDateCourte(DateTime.now().subtract(const Duration(days: 40)))}',
        ),
      ),
      findsOneWidget,
    );
    expect(dansListe(find.text(formatEuros(6000))), findsOneWidget);
    expect(dansListe(find.text(formatEuros(1800))), findsOneWidget);
    expect(dansListe(find.text('Brouillon')), findsOneWidget);
    expect(dansListe(find.text('Expiré')), findsOneWidget);
    // Le plus récent est en premier.
    expect(
      tester.getTopLeft(dansListe(find.text(numeroDevis(2)))).dy,
      lessThan(tester.getTopLeft(dansListe(find.text(numeroDevis(1)))).dy),
    );
    // Le passage en « Expiré » est enregistré.
    expect((await devisEnBase(tester, env, ancien.id)).statut, StatutDevis.expire);
    expect((await devisEnBase(tester, env, recent.id)).statut, StatutDevis.brouillon);

    // Un appui ouvre l'aperçu du devis.
    await tester.tap(dansListe(find.text(numeroDevis(2))));
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numeroDevis(2))));
    expect(find.byType(DevisDetailScreen), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('nouveau devis : lignes, remise, conditions et acompte, puis aperçu du PDF', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env);

    await tester.tap(find.text('Nouveau devis'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau devis'), findsOneWidget);

    // Sans ligne, l'enregistrement est refusé.
    await appuyer(tester, find.widgetWithText(FilledButton, 'Enregistrer le devis'));
    expect(find.text('Ajoutez au moins une ligne au devis.'), findsWidgets);
    // On laisse le message disparaître : il recouvrirait le bouton « Enregistrer » plus bas.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // Une ligne libre : 2 × 60 €.
    await appuyer(tester, find.text('Ajouter une ligne'));
    expect(find.text('Article ou prestation libre'), findsOneWidget);
    await saisir(tester, 'Désignation', 'Couverture bébé sur mesure');
    await saisir(tester, 'Description (facultatif)', 'Coton bio, 80 × 100 cm');
    await saisir(tester, 'Prix unitaire (€)', '60');
    await saisir(tester, 'Quantité', '2');
    await appuyer(tester, find.widgetWithText(FilledButton, 'Ajouter'));
    expect(dansFormulaire(find.text('Couverture bébé sur mesure')), findsOneWidget);
    expect(dansFormulaire(find.text('Coton bio, 80 × 100 cm')), findsOneWidget);
    expect(dansFormulaire(find.text('2 × ${formatEuros(6000)}')), findsOneWidget);

    // Remise de 10 % et 5 € de port : 120 − 12 + 5 = 113 €.
    await appuyer(tester, find.text('En %'));
    await saisir(tester, 'Remise (%)', '10');
    await saisir(tester, 'Frais de port (€)', '5');
    await tester.pumpAndSettle();
    expect(dansFormulaire(find.text('−${formatEuros(1200)}')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(11300)}'), findsOneWidget);

    // Conditions : validité proposée à 30 jours, délai, acompte.
    final DateTime aujourdhui = DateTime.now();
    final DateTime validite = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + 30);
    expect(
      dansFormulaire(find.text('Valable jusqu’au ${formatDateCourte(validite)}')),
      findsOneWidget,
    );
    await saisir(tester, 'Délai de réalisation (facultatif)', '3 semaines');
    await saisir(tester, 'Acompte demandé (€, facultatif)', '40');

    // Un acompte supérieur au total est signalé.
    await saisir(tester, 'Acompte demandé (€, facultatif)', '500');
    await tester.pumpAndSettle();
    expect(find.textContaining('L’acompte ne peut pas dépasser le total'), findsOneWidget);
    await saisir(tester, 'Acompte demandé (€, facultatif)', '40');
    await tester.pumpAndSettle();

    // Enregistrement : le devis est numéroté et son aperçu s'ouvre.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(11300)}'));
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(11300)}'));
    await tester.pump();
    await attendre(tester, dansDetail(apercu(numeroDevis(1))));

    expect(dansDetail(find.text(numeroDevis(1))), findsOneWidget); // titre
    expect(dansDetail(find.text('Sans client')), findsOneWidget);
    expect(dansDetail(find.text(formatEuros(11300))), findsOneWidget);
    expect(dansDetail(find.text('Brouillon')), findsOneWidget);
    expect(dansDetail(find.text('Partager')), findsOneWidget);
    expect(dansDetail(find.text('Imprimer')), findsOneWidget);
    expect(dansDetail(find.text('Modifier')), findsOneWidget);
    expect(dansDetail(find.text('Convertir en commande')), findsOneWidget);

    final DevisFiche enregistre = (await env.travailler(tester, () => env.devis.lister())).single.devis;
    expect(enregistre.numero, numeroDevis(1));
    expect(enregistre.statut, StatutDevis.brouillon);
    expect(enregistre.totalCentimes, 11300);
    expect(enregistre.remiseCentimes, 1200);
    expect(enregistre.fraisPortCentimes, 500);
    expect(enregistre.acompteCentimes, 4000);
    expect(enregistre.delaiRealisation, '3 semaines');
    expect(enregistre.dateValidite, validite);
    final DevisDetail? detail = await env.travailler(tester, () => env.devis.detail(enregistre.id));
    expect(detail!.lignes.single.designation, 'Couverture bébé sur mesure');
    expect(detail.lignes.single.description, 'Coton bio, 80 × 100 cm');
    expect(detail.lignes.single.quantite, 2);
    expect(detail.lignes.single.prixUnitaireCentimes, 6000);
    expect(env.generateurDevisPdf.dernier?.acompteCentimes, 4000);

    await env.fermer(tester);
  });

  testWidgets('modifier un devis : le formulaire reprend ses données, l’enregistrement les change', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client lea = await env.creerClient(tester, const DonneesClient(prenom: 'Léa', nom: 'Bernard'));
    final DevisFiche devis = await env.creerDevis(tester, clientId: lea.id, acompte: 2000, delai: '3 semaines');
    await ouvrirAccueil(tester, env);

    await ouvrirRoute(tester, AppRoutes.devisModifier, arguments: devis.id);
    await attendre(tester, dansFormulaire(find.text('Couverture bébé sur mesure')));

    expect(dansFormulaire(find.text('Modifier le devis')), findsOneWidget);
    expect(dansFormulaire(find.text('Léa Bernard')), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '3 semaines'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '20'), findsOneWidget);

    // Une ligne modifiée garde sa place : on change son prix.
    await appuyer(tester, find.text('Couverture bébé sur mesure'));
    expect(find.text('Modifier la ligne'), findsOneWidget);
    await saisir(tester, 'Prix unitaire (€)', '70');
    await appuyer(tester, find.widgetWithText(FilledButton, 'Enregistrer'));
    expect(dansFormulaire(find.text('1 × ${formatEuros(7000)}')), findsOneWidget);

    await saisir(tester, 'Délai de réalisation (facultatif)', '2 semaines');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(7000)}'));
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(7000)}'));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.byType(DevisFormScreen), findsNothing);
    final DevisFiche modifie = await devisEnBase(tester, env, devis.id);
    expect(modifie.numero, devis.numero);
    expect(modifie.totalCentimes, 7000);
    expect(modifie.delaiRealisation, '2 semaines');
    expect(modifie.acompteCentimes, 2000);
    expect(modifie.clientId, lea.id);

    await env.fermer(tester);
  });

  testWidgets('statuts : envoyé, puis refusé après confirmation, et un devis refusé ne change plus', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final DevisFiche devis = await env.creerDevis(tester);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);
    expect(dansDetail(find.text('Brouillon')), findsOneWidget);

    // Depuis un brouillon : envoyé, accepté ou refusé.
    await appuyer(tester, find.byTooltip('Changer le statut'));
    expect(find.text('Marquer comme envoyé'), findsOneWidget);
    expect(find.text('Marquer comme accepté'), findsOneWidget);
    expect(find.text('Marquer comme refusé'), findsOneWidget);
    await tester.tap(find.text('Marquer comme envoyé'));
    await tester.pump();
    await attendre(tester, dansDetail(find.text('Envoyé')));
    expect((await devisEnBase(tester, env, devis.id)).statut, StatutDevis.envoye);

    // Depuis un devis envoyé : plus « envoyé ». Refuser demande confirmation.
    await appuyer(tester, find.byTooltip('Changer le statut'));
    expect(find.text('Marquer comme envoyé'), findsNothing);
    await tester.tap(find.text('Marquer comme refusé'));
    await tester.pumpAndSettle();
    expect(find.text('Marquer ${devis.numero} comme refusé ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Garder le devis'));
    await tester.pumpAndSettle();
    expect((await devisEnBase(tester, env, devis.id)).statut, StatutDevis.envoye);

    await appuyer(tester, find.byTooltip('Changer le statut'));
    await tester.tap(find.text('Marquer comme refusé'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Marquer comme refusé'));
    await tester.pump();
    await attendre(tester, dansDetail(find.text('Refusé')));

    expect((await devisEnBase(tester, env, devis.id)).statut, StatutDevis.refuse);
    expect(dansDetail(find.textContaining('Ce devis a été refusé')), findsOneWidget);
    expect(find.byTooltip('Changer le statut'), findsNothing);
    expect(dansDetail(find.text('Modifier')), findsNothing);
    expect(dansDetail(find.text('Convertir en commande')), findsNothing);
    // Il reste partageable.
    expect(dansDetail(find.text('Partager')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('partager et imprimer envoient le PDF du devis', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final DevisFiche devis = await env.creerDevis(tester);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);

    await tester.tap(dansDetail(find.text('Partager')));
    await tester.pump();
    await attendreJusqua(tester, () => env.documents.partages.isNotEmpty);
    await tester.pumpAndSettle();
    expect(env.documents.partages, <String>['${devis.numero}.pdf | Devis ${devis.numero}']);
    expect(env.documents.cheminsPartages.single, endsWith('${devis.numero}.pdf'));

    await tester.tap(dansDetail(find.text('Imprimer')));
    await tester.pump();
    await attendreJusqua(tester, () => env.documents.impressions.isNotEmpty);
    await tester.pumpAndSettle();
    expect(env.documents.impressions, <String>['${devis.numero} : %PDF-FAUX ${devis.numero}']);

    await env.fermer(tester);
  });

  testWidgets('un devis expiré ne se convertit pas, mais se modifie pour prolonger sa validité', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final DevisFiche devis = await env.creerDevis(tester);
    await perimer(tester, env, devis.id);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);

    expect(dansDetail(find.text('Expiré')), findsOneWidget);
    expect(dansDetail(find.textContaining('Ce devis est expiré depuis le')), findsOneWidget);
    expect(dansDetail(find.text('Convertir en commande')), findsNothing);
    expect(find.byTooltip('Changer le statut'), findsNothing);
    expect(dansDetail(find.text('Modifier')), findsOneWidget);

    await appuyer(tester, dansDetail(find.text('Modifier')));
    await attendre(tester, dansFormulaire(find.textContaining('Ce devis est expiré. Vérifiez')));
    final DateTime aujourdhui = DateTime.now();
    final DateTime proposee = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + 30);
    expect(dansFormulaire(find.text('Valable jusqu’au ${formatDateCourte(proposee)}')), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(6000)}'));
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer le devis · ${formatEuros(6000)}'));
    await tester.pump();
    await attendreEtStabiliser(tester, dansDetail(find.text('Brouillon')));

    final DevisFiche prolonge = await devisEnBase(tester, env, devis.id);
    expect(prolonge.statut, StatutDevis.brouillon);
    expect(prolonge.dateValidite, proposee);
    expect(dansDetail(find.text('Convertir en commande')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('conversion en commande : l’acompte reçu devient le premier paiement', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client lea = await env.creerClient(tester, const DonneesClient(prenom: 'Léa', nom: 'Bernard'));
    final DevisFiche devis = await env.creerDevis(tester, clientId: lea.id, acompte: 2000);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);

    await tester.tap(dansDetail(find.text('Convertir en commande')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, dansConversion(find.text('Créer la commande')));

    expect(dansConversion(find.text('Devis ${devis.numero}')), findsOneWidget);
    expect(dansConversion(find.text('1 × Couverture bébé sur mesure')), findsOneWidget);
    expect(dansConversion(find.text('Créer la commande et la facture')), findsOneWidget);
    expect(dansConversion(find.text('Acompte reçu')), findsOneWidget);
    expect(dansConversion(find.text('${formatEuros(2000)} demandés par le devis')), findsOneWidget);

    // Acompte reçu, par virement.
    await appuyer(tester, dansConversion(find.text('Acompte reçu')));
    await appuyer(tester, find.byType(DropdownButtonFormField<ModePaiement>));
    await tester.tap(find.text('Virement').last);
    await tester.pumpAndSettle();

    await tester.tap(dansConversion(find.text('Créer la commande')));
    await tester.pump();
    await attendre(tester, dansVente(find.text('Total')));

    // La commande est une vente validée, partiellement payée par l'acompte ; pas de facture.
    final DevisFiche converti = await devisEnBase(tester, env, devis.id);
    expect(converti.statut, StatutDevis.accepte);
    final int venteId = converti.venteId!;
    final VenteDetail? vente = await env.travailler(tester, () => env.ventes.detail(venteId));
    expect(vente!.vente.totalCentimes, 6000);
    expect(vente.vente.clientId, lea.id);
    expect(vente.vente.statutPaiement, StatutPaiement.partiellementPayee);
    expect(vente.paiements.single.montantCentimes, 2000);
    expect(vente.paiements.single.modePaiement, ModePaiement.virement);
    expect(vente.factures, isEmpty);
    expect(await env.travailler(tester, () => env.factures.lister()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('conversion sans acompte reçu : la commande reste impayée, le devis n’est plus convertible', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final DevisFiche devis = await env.creerDevis(tester, acompte: 2000);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);

    await tester.tap(dansDetail(find.text('Convertir en commande')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, dansConversion(find.text('Créer la commande')));

    await tester.tap(dansConversion(find.text('Créer la commande')));
    await tester.pump();
    await attendre(tester, dansVente(find.text('Total')));

    final DevisFiche converti = await devisEnBase(tester, env, devis.id);
    final VenteDetail? vente = await env.travailler(tester, () => env.ventes.detail(converti.venteId!));
    expect(vente!.vente.statutPaiement, StatutPaiement.impayee);
    expect(vente.paiements, isEmpty);

    // Retour sur le devis : converti, il propose de voir la commande et ne se convertit plus.
    await retourArriere(tester);
    await attendreEtStabiliser(tester, dansDetail(find.text('Ce devis a été converti en commande.')));
    expect(dansDetail(find.text('Accepté')), findsOneWidget);
    expect(dansDetail(find.text('Voir la commande')), findsOneWidget);
    expect(dansDetail(find.text('Convertir en commande')), findsNothing);
    expect(dansDetail(find.text('Modifier')), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('conversion en commande et facture : la facture est établie en même temps', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client lea = await env.creerClient(tester, const DonneesClient(prenom: 'Léa', nom: 'Bernard'));
    final DevisFiche devis = await env.creerDevis(tester, clientId: lea.id);
    await completerProfil(tester, env);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);

    await tester.tap(dansDetail(find.text('Convertir en commande')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, dansConversion(find.text('Créer la commande et la facture')));
    // Pas d'acompte demandé : pas de case « Acompte reçu ».
    expect(dansConversion(find.text('Acompte reçu')), findsNothing);

    await tester.tap(dansConversion(find.text('Créer la commande et la facture')));
    await tester.pump();
    await attendre(tester, dansVente(find.text(numeroFacture(1))));

    final DevisFiche converti = await devisEnBase(tester, env, devis.id);
    expect(converti.statut, StatutDevis.accepte);
    final List<Facture> factures = await env.travailler(tester, () => env.factures.lister());
    expect(factures.single.numero, numeroFacture(1));
    expect(factures.single.venteId, converti.venteId);
    expect(env.generateurPdf.dernier?.client.nom, 'Léa Bernard');

    await env.fermer(tester);
  });

  testWidgets('conversion en commande et facture avec un profil incomplet : rien n’est créé', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final DevisFiche devis = await env.creerDevis(tester);
    await ouvrirAccueil(tester, env);
    await ouvrirLeDevis(tester, devis);

    await tester.tap(dansDetail(find.text('Convertir en commande')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, dansConversion(find.text('Créer la commande et la facture')));

    await tester.tap(dansConversion(find.text('Créer la commande et la facture')));
    await tester.pump();
    await attendre(tester, find.text('Informations manquantes'));
    expect(find.textContaining('le nom de l’entreprise'), findsOneWidget);
    expect(find.textContaining('dans « Mon entreprise »'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Plus tard'));
    await tester.pumpAndSettle();
    expect(find.byType(DevisConversionScreen), findsOneWidget);

    final DevisFiche inchange = await devisEnBase(tester, env, devis.id);
    expect(inchange.statut, StatutDevis.brouillon);
    expect(inchange.venteId, isNull);
    expect(await env.travailler(tester, () => env.factures.lister()), isEmpty);
    final List<Vente> ventes = await env.travailler(tester, () => env.db.select(env.db.ventes).get());
    expect(ventes, isEmpty);

    // « Créer la commande » seule reste possible.
    await tester.tap(dansConversion(find.text('Créer la commande')));
    await tester.pump();
    await attendre(tester, dansVente(find.text('Total')));
    expect((await devisEnBase(tester, env, devis.id)).venteId, isNotNull);

    await env.fermer(tester);
  });
}
