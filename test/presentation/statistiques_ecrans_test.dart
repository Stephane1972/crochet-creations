import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/factures/factures_screen.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/statistiques/statistiques_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran (le texte de test est large), sans faire défiler.
const Size _grandEcran = Size(2000, 4000);

// Jeudi 29 octobre 2026, 15 h : la semaine va du lundi 26 octobre au dimanche 1er novembre.
final DateTime _maintenant = DateTime(2026, 10, 29, 15);

Finder _cle(String cle) => find.byKey(Key(cle));

/// Le texte affiché par le widget `Text` portant cette clé.
String _texte(String cle) {
  final Widget widget = _cle(cle).evaluate().single.widget;
  return (widget as Text).data!;
}

/// Fait avancer le temps, en laissant la base travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Attend que le `Text` portant cette clé affiche [attendu].
Future<void> attendreTexte(WidgetTester tester, String cle, String attendu) async {
  await attendreJusqua(tester, () {
    final Iterable<Element> trouves = _cle(cle).evaluate();
    return trouves.isNotEmpty && (trouves.first.widget as Text).data == attendu;
  });
  expect(_texte(cle), attendu);
}

/// Appuie sur un élément, laisse finir les animations et les lectures de la base.
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

/// Ouvre l'application (à l'heure fixe) puis l'écran Statistiques.
Future<void> ouvrirStatistiques(WidgetTester tester, EnvironnementTest env) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.statistiques);
  await attendre(tester, _cle('stat-ca'));
}

// -----------------------------------------------------------------------------
// Préparation des données (hors temps simulé, avant d'ouvrir l'application)
// -----------------------------------------------------------------------------

Future<Produit> produit(
  WidgetTester tester,
  EnvironnementTest env, {
  required String nom,
  required CategorieProduit categorie,
  required int prix,
  int cout = 0,
  int stock = 10,
  int seuil = 2,
}) => env.travailler(
  tester,
  () => env.produits.creer(
    DonneesProduit(
      nom: nom,
      categorie: categorie,
      prixVenteCentimes: prix,
      coutMatiereCentimes: cout,
      quantiteStock: stock,
      seuilAlerteStock: seuil,
    ),
  ),
);

/// Vend [quantite] de ce produit à cette date. Payée en entier par défaut ; [paye] donne la somme encaissée
/// (0 = pas encore payée).
Future<Vente> vendre(
  WidgetTester tester,
  EnvironnementTest env,
  Produit p, {
  required DateTime date,
  int quantite = 1,
  int? paye,
}) {
  final int encaisse = paye ?? p.prixVenteCentimes * quantite;
  return env.travailler(
    tester,
    () => env.ventes.valider(
      panier: const Panier().ajouter(
        produitId: p.id,
        designation: p.nom,
        prixUnitaireCentimes: p.prixVenteCentimes,
        quantite: quantite,
        stockDisponible: p.quantiteStock,
      ),
      paiement: encaisse == 0 ? null : PaiementSaisi(mode: ModePaiement.especes, montantCentimes: encaisse),
      date: date,
    ),
  );
}

/// Une inscription à un cours, payée à cette date.
Future<void> vendreCours(WidgetTester tester, EnvironnementTest env, {required DateTime date, int prix = 4500}) async {
  final CoursFiche cours = await env.creerCours(tester, prix: prix);
  await env.travailler(tester, () async {
    final int venteId = await env.db
        .into(env.db.ventes)
        .insert(VentesCompanion.insert(sousTotalCentimes: prix, totalCentimes: prix, dateVente: Value(date)));
    await env.db
        .into(env.db.lignesVente)
        .insert(
          LignesVenteCompanion.insert(
            venteId: venteId,
            designation: 'Cours : ${cours.titre}',
            quantite: 1,
            prixUnitaireCentimes: prix,
            totalLigneCentimes: prix,
            nature: const Value(NatureLigne.service),
            coursId: Value(cours.id),
          ),
        );
    await env.db
        .into(env.db.paiements)
        .insert(
          PaiementsCompanion.insert(
            venteId: venteId,
            montantCentimes: prix,
            modePaiement: ModePaiement.especes,
            datePaiement: Value(date),
          ),
        );
  });
}

/// Une facture émise pour cette vente.
Future<void> facturer(WidgetTester tester, EnvironnementTest env, Vente v, String numero) => env.travailler(
  tester,
  () => env.db
      .into(env.db.factures)
      .insert(
        FacturesCompanion.insert(
          numero: numero,
          venteId: v.id,
          dateVentePrestation: v.dateVente,
          totalCentimes: v.totalCentimes,
        ),
      ),
);

/// Une vente payée en entier, d'un seul article libre : à insérer avec `travailler`, ou avec `ecrireEcranOuvert`
/// quand l'écran est déjà ouvert.
Future<void> Function() insererVentePayee(
  EnvironnementTest env, {
  required DateTime date,
  required int montant,
  NatureLigne nature = NatureLigne.bien,
}) => () async {
  final int venteId = await env.db
      .into(env.db.ventes)
      .insert(VentesCompanion.insert(sousTotalCentimes: montant, totalCentimes: montant, dateVente: Value(date)));
  await env.db
      .into(env.db.lignesVente)
      .insert(
        LignesVenteCompanion.insert(
          venteId: venteId,
          designation: 'Vente importante',
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
          modePaiement: ModePaiement.virement,
          datePaiement: Value(date),
        ),
      );
};

void main() {
  // ---------------------------------------------------------------------------
  // Écran Statistiques (écran 20)
  // ---------------------------------------------------------------------------

  testWidgets('ouvert depuis « Plus » : tout est à zéro tant qu’il n’y a rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.maintenant = _maintenant;
    await ouvrirAccueil(tester, env, taille: _grandEcran);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Statistiques')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, _cle('stat-ca'));
    await attendre(tester, find.text('Aucun produit à réapprovisionner.'));

    expect(find.byType(StatistiquesScreen), findsOneWidget);
    expect(_texte('stat-periode'), 'Ce mois-ci · octobre 2026');
    expect(_texte('stat-ca'), formatEuros(0));
    expect(_texte('stat-objets'), formatEuros(0));
    expect(_texte('stat-prestations'), formatEuros(0));
    expect(_texte('stat-marge'), formatEuros(0));
    expect(_texte('stat-panier'), '—');
    expect(_texte('stat-cours'), formatEuros(0));
    expect(find.text('Aucune vente sur cette période.'), findsOneWidget);
    expect(find.text('Aucun produit du catalogue encaissé sur cette période.'), findsOneWidget);
    expect(find.text('Aucune dépense sur cette période.'), findsOneWidget);
    expect(find.text('Aucune facture impayée.'), findsOneWidget);
    expect(find.text('Franchise de TVA'), findsOneWidget);
    expect(_texte('franchise-part-objets'), '0 % du seuil');
    expect(_cle('franchise-etiquette-objets'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('les chiffres changent avec la période : jour, semaine, mois, année', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit doudou = await produit(
      tester,
      env,
      nom: 'Doudou lapin',
      categorie: CategorieProduit.doudou,
      prix: 2500,
      cout: 600,
    );
    final Produit bonnet = await produit(
      tester,
      env,
      nom: 'Bonnet',
      categorie: CategorieProduit.crochet,
      prix: 3000,
      cout: 500,
    );
    await vendre(tester, env, doudou, date: DateTime(2026, 10, 12, 10), quantite: 2); // ce mois-ci
    await vendre(tester, env, bonnet, date: DateTime(2026, 10, 28, 11)); // cette semaine
    await vendre(tester, env, doudou, date: DateTime(2026, 10, 29, 9)); // aujourd'hui
    await vendre(tester, env, bonnet, date: DateTime(2026, 3, 3, 16)); // cette année
    await vendreCours(tester, env, date: DateTime(2026, 10, 27, 14)); // cette semaine
    await env.creerDepense(tester, date: DateTime(2026, 10, 3), categorie: CategorieDepense.laineFil, montant: 2490);
    await env.creerDepense(
      tester,
      date: DateTime(2026, 10, 20),
      categorie: CategorieDepense.standMarche,
      montant: 5000,
    );
    await env.creerDepense(tester, date: DateTime(2026, 9, 15), categorie: CategorieDepense.transport, montant: 900);

    await ouvrirStatistiques(tester, env);

    // --- Ce mois-ci (par défaut) ---
    expect(_texte('stat-periode'), 'Ce mois-ci · octobre 2026');
    expect(_texte('stat-ca'), formatEuros(15000)); // 50 + 30 + 25 + 45 euros
    expect(_texte('stat-objets'), formatEuros(10500));
    expect(_texte('stat-prestations'), formatEuros(4500));
    expect(_texte('stat-cours'), formatEuros(4500));
    expect(_texte('stat-cout'), formatEuros(2300)); // 3 doudous à 6 € + 1 bonnet à 5 €
    expect(_texte('stat-marge'), formatEuros(12700));
    expect(_texte('stat-panier'), formatEuros(3750)); // 4 ventes
    expect(_texte('stat-depenses'), formatEuros(7490));
    expect(find.text('Laine / fil'), findsOneWidget);
    expect(find.text('Stand / marché'), findsOneWidget);
    expect(find.text('Transport'), findsNothing);
    // Meilleures ventes : trois doudous, un bonnet ; le cours n'y est pas.
    expect(find.text('Doudou lapin'), findsOneWidget);
    expect(find.text('× 3'), findsOneWidget);
    expect(find.text('Bonnet'), findsOneWidget);
    expect(find.text('× 1'), findsOneWidget);
    expect(find.textContaining('Cours : '), findsNothing);
    // Catégories : doudous (marge 57 €) avant crochet (marge 25 €).
    expect(find.text('Encaissé ${formatEuros(7500)} · matière ${formatEuros(1800)}'), findsOneWidget);
    expect(find.text('Encaissé ${formatEuros(3000)} · matière ${formatEuros(500)}'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Doudou')).dy, lessThan(tester.getTopLeft(find.text('Crochet')).dy));
    // Franchise : toute l'année, objets d'un côté, cours et prestations de l'autre.
    expect(
      _texte('franchise-montant-objets'),
      '${formatEuros(13500, avecCentimes: false)} / ${formatEuros(8500000, avecCentimes: false)}',
    );
    expect(
      _texte('franchise-montant-prestations'),
      '${formatEuros(4500, avecCentimes: false)} / ${formatEuros(3750000, avecCentimes: false)}',
    );

    // --- Cette semaine ---
    await toucher(tester, find.text('Semaine'));
    expect(_texte('stat-periode'), 'Cette semaine · du 26/10/2026 au 01/11/2026');
    expect(_texte('stat-ca'), formatEuros(10000));
    expect(_texte('stat-objets'), formatEuros(5500));
    expect(_texte('stat-prestations'), formatEuros(4500));
    expect(_texte('stat-cout'), formatEuros(1100));
    expect(_texte('stat-marge'), formatEuros(8900));
    expect(_texte('stat-panier'), formatEuros(3333)); // 3 ventes
    expect(find.text('Aucune dépense sur cette période.'), findsOneWidget);
    // À quantité égale, le bonnet (30 €) passe avant le doudou (25 €).
    expect(tester.getTopLeft(find.text('Bonnet')).dy, lessThan(tester.getTopLeft(find.text('Doudou lapin')).dy));

    // --- Aujourd'hui ---
    await toucher(tester, find.text('Jour'));
    expect(_texte('stat-periode'), 'Aujourd’hui · jeudi 29 octobre');
    expect(_texte('stat-ca'), formatEuros(2500));
    expect(_texte('stat-marge'), formatEuros(1900));
    expect(_texte('stat-panier'), formatEuros(2500));
    expect(_texte('stat-cours'), formatEuros(0));

    // --- Cette année ---
    await toucher(tester, find.text('Année'));
    expect(_texte('stat-periode'), 'Cette année · 2026');
    expect(_texte('stat-ca'), formatEuros(18000));
    expect(_texte('stat-marge'), formatEuros(15200));
    expect(_texte('stat-panier'), formatEuros(3600)); // 5 ventes
    expect(_texte('stat-depenses'), formatEuros(8390));
    expect(find.text('Transport'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('stock faible et factures impayées, avec accès à la liste des factures', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit plaid = await produit(
      tester,
      env,
      nom: 'Plaid',
      categorie: CategorieProduit.crochet,
      prix: 4000,
      stock: 3,
    );
    final Produit bonnet = await produit(
      tester,
      env,
      nom: 'Bonnet',
      categorie: CategorieProduit.crochet,
      prix: 3000,
      stock: 1,
    );
    final Produit doudou = await produit(
      tester,
      env,
      nom: 'Doudou lapin',
      categorie: CategorieProduit.doudou,
      prix: 2500,
    );
    final Vente partielle = await vendre(tester, env, plaid, date: DateTime(2026, 10, 20), quantite: 2, paye: 1000);
    final Vente impayee = await vendre(tester, env, bonnet, date: DateTime(2026, 10, 21), paye: 0);
    final Vente payee = await vendre(tester, env, doudou, date: DateTime(2026, 10, 22));
    await facturer(tester, env, partielle, 'FACT-2026-0001');
    await facturer(tester, env, impayee, 'FACT-2026-0002');
    await facturer(tester, env, payee, 'FACT-2026-0003');

    await ouvrirStatistiques(tester, env);
    await attendre(tester, _cle('stat-stock-faible'));

    // Plaid : 1 restant (seuil 2) ; Bonnet : épuisé ; le doudou est largement en stock.
    expect(_texte('stat-stock-faible'), '2 produits à réapprovisionner');
    expect(find.text('Reste 1'), findsOneWidget);
    expect(find.text('Épuisé'), findsOneWidget);
    // Deux factures pas soldées : 70 € restant sur le plaid, 30 € sur le bonnet.
    expect(_texte('stat-impayees'), '2 factures impayées');
    expect(_texte('stat-impayees-montant'), '${formatEuros(10000)} à encaisser');

    await toucher(tester, find.text('Factures impayées'));
    await attendre(tester, find.byType(FacturesScreen));
    expect(find.descendant(of: find.byType(FacturesScreen), matching: find.text('Factures')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('franchise de TVA : le seuil approche puis est dépassé, sans quitter l’écran', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirStatistiques(tester, env);
    expect(_texte('franchise-message'), contains('Une alerte s’affichera'));

    // 70 000 € d'objets encaissés en janvier : 82 % du seuil de 85 000 €.
    await env.ecrireEcranOuvert(
      tester,
      insererVentePayee(env, date: DateTime(2026, 1, 15, 10), montant: 7000000),
    );
    await attendreTexte(tester, 'franchise-part-objets', '82 % du seuil');
    expect(_texte('franchise-message'), contains('approchez d’un seuil'));
    expect(
      find.descendant(of: _cle('franchise-etiquette-objets'), matching: find.text('Seuil approché')),
      findsOneWidget,
    );
    expect(_texte('franchise-part-prestations'), '0 % du seuil');
    expect(_cle('franchise-etiquette-prestations'), findsNothing);

    // 86 000 € : le seuil est dépassé.
    await env.ecrireEcranOuvert(
      tester,
      insererVentePayee(env, date: DateTime(2026, 2, 3, 10), montant: 1600000),
    );
    await attendreTexte(tester, 'franchise-part-objets', '101 % du seuil');
    expect(_texte('franchise-message'), contains('est dépassé'));
    expect(
      find.descendant(of: _cle('franchise-etiquette-objets'), matching: find.text('Seuil dépassé')),
      findsOneWidget,
    );

    // 31 000 € de cours et prestations : 82 % du seuil de 37 500 €.
    await env.ecrireEcranOuvert(
      tester,
      insererVentePayee(env, date: DateTime(2026, 5, 4, 10), montant: 3100000, nature: NatureLigne.service),
    );
    await attendreTexte(tester, 'franchise-part-prestations', '82 % du seuil');
    expect(
      find.descendant(of: _cle('franchise-etiquette-prestations'), matching: find.text('Seuil approché')),
      findsOneWidget,
    );

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Accueil
  // ---------------------------------------------------------------------------

  testWidgets('accueil : les chiffres du mois, les factures impayées et la franchise de TVA', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit doudou = await produit(
      tester,
      env,
      nom: 'Doudou lapin',
      categorie: CategorieProduit.doudou,
      prix: 2500,
    );
    final Produit bonnet = await produit(
      tester,
      env,
      nom: 'Bonnet',
      categorie: CategorieProduit.crochet,
      prix: 3000,
    );
    await vendre(tester, env, doudou, date: DateTime(2026, 10, 12, 10), quantite: 2);
    await vendreCours(tester, env, date: DateTime(2026, 10, 27, 14));
    final Vente impayee = await vendre(tester, env, bonnet, date: DateTime(2026, 10, 20), paye: 0);
    await facturer(tester, env, impayee, 'FACT-2026-0001');

    env.maintenant = _maintenant;
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    Finder tuile(String libelle) => find.widgetWithText(Card, libelle);
    await attendreJusqua(
      tester,
      () => find.descendant(of: tuile('Ventes du mois'), matching: find.text(formatEuros(5000))).evaluate().isNotEmpty,
    );

    // Ventes du mois : l'argent encaissé hors cours ; cours du mois : les inscriptions encaissées.
    expect(find.descendant(of: tuile('Ventes du mois'), matching: find.text(formatEuros(5000))), findsOneWidget);
    expect(find.descendant(of: tuile('Cours du mois'), matching: find.text(formatEuros(4500))), findsOneWidget);
    expect(find.descendant(of: tuile('Factures impayées'), matching: find.text('1')), findsOneWidget);
    expect(
      find.descendant(of: tuile('Factures impayées'), matching: find.text('${formatEuros(3000)} à encaisser')),
      findsOneWidget,
    );
    expect(_texte('franchise-montant-objets'), '${formatEuros(5000, avecCentimes: false)} / 85 000 €');
    expect(_texte('franchise-montant-prestations'), '${formatEuros(4500, avecCentimes: false)} / 37 500 €');

    await env.fermer(tester);
  });

  testWidgets('accueil : les tuiles ouvrent les statistiques et les factures', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Produit doudou = await produit(
      tester,
      env,
      nom: 'Doudou lapin',
      categorie: CategorieProduit.doudou,
      prix: 2500,
    );
    await vendre(tester, env, doudou, date: DateTime(2026, 10, 12, 10));
    await vendreCours(tester, env, date: DateTime(2026, 10, 27, 14));

    env.maintenant = _maintenant;
    await ouvrirAccueil(tester, env, taille: _grandEcran);

    await tester.tap(find.widgetWithText(Card, 'Ventes du mois'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, _cle('stat-ca'));
    expect(find.byType(StatistiquesScreen), findsOneWidget);
    expect(_texte('stat-ca'), formatEuros(7000)); // doudou 25 € + cours 45 €

    await retourArriere(tester);
    await tester.tap(find.widgetWithText(Card, 'Cours du mois'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, _cle('stat-cours'));
    expect(_texte('stat-cours'), formatEuros(4500));

    await retourArriere(tester);
    await tester.tap(find.widgetWithText(Card, 'Factures impayées'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, find.byType(FacturesScreen));

    await env.fermer(tester);
  });
}
