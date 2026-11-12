import 'dart:async';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/statistiques/analyse_screen.dart';
import 'package:crochet_creations/presentation/statistiques/statistiques_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(2000, 4000);

// Jeudi 29 octobre 2026 : l'année en cours est 2026.
final DateTime _maintenant = DateTime(2026, 10, 29, 15);

Finder _cle(String cle) => find.byKey(Key(cle));

/// Le texte affiché par le widget `Text` portant cette clé.
String _texte(String cle) => (_cle(cle).evaluate().single.widget as Text).data!;

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

/// Ouvre la liste déroulante [cleListe] et choisit [libelle].
Future<void> choisir(WidgetTester tester, String cleListe, String libelle) async {
  await toucher(tester, _cle(cleListe));
  await toucher(tester, find.text(libelle).last);
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre l'application (à l'heure fixe) puis l'écran Analyse détaillée.
Future<void> ouvrirAnalyse(WidgetTester tester, EnvironnementTest env) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.analyse);
  await attendre(tester, find.byType(AnalyseScreen));
  await attendreJusqua(
    tester,
    () => _cle('analyse-total').evaluate().isNotEmpty || _cle('analyse-vide').evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
}

Future<Produit> produit(
  WidgetTester tester,
  EnvironnementTest env, {
  required String nom,
  required String categorie,
  required int prix,
  required int cout,
}) => env.travailler(
  tester,
  () => env.produits.creer(
    DonneesProduit(
      nom: nom,
      categorie: categorie,
      prixVenteCentimes: prix,
      coutMatiereCentimes: cout,
      quantiteStock: 50,
      seuilAlerteStock: 2,
    ),
  ),
);

/// Vend [quantite] de ce produit à cette date, au lieu donné (aucun : « Non renseigné »), payée en entier.
Future<Vente> vendre(
  WidgetTester tester,
  EnvironnementTest env,
  Produit p, {
  required DateTime date,
  int quantite = 1,
  int? lieuId,
}) => env.travailler(
  tester,
  () => env.ventes.valider(
    lieuId: lieuId,
    panier: const Panier().ajouter(
      produitId: p.id,
      designation: p.nom,
      prixUnitaireCentimes: p.prixVenteCentimes,
      quantite: quantite,
      stockDisponible: p.quantiteStock,
    ),
    paiement: PaiementSaisi(mode: ModePaiement.especes, montantCentimes: p.prixVenteCentimes * quantite),
    date: date,
  ),
);

Future<LieuVente> lieu(WidgetTester tester, EnvironnementTest env, String nom) async {
  final List<LieuVente> tous = await env.travailler(tester, () => env.lieux.lister());
  return tous.firstWhere((LieuVente l) => l.nom == nom);
}

/// Une vente payée en entier, d'un article libre, sans lieu : à insérer avec `ecrireEcranOuvert`.
Future<void> Function() insererVentePayee(EnvironnementTest env, {required DateTime date, required int montant}) =>
    () async {
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
              nature: const Value(NatureLigne.bien),
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

/// Prépare les ventes de l'exemple :
///
/// - 12 oct. 2026, Marché : 2 doudous à 25 € (matière 6 € pièce) → 50 €, matière 12 €
/// - 20 oct. 2026, Salon : un plaid de crochet à 40 € (matière 10 €)
/// - 3 mars 2026, sans lieu : un doudou à 25 € (matière 6 €)
/// - 10 juin 2025, Marché : un plaid de crochet à 40 € (matière 10 €)
Future<void> preparerVentes(WidgetTester tester, EnvironnementTest env) async {
  final Produit doudou = await produit(
    tester,
    env,
    nom: 'Doudou lapin',
    categorie: CleCategorie.doudou,
    prix: 2500,
    cout: 600,
  );
  final Produit plaid = await produit(
    tester,
    env,
    nom: 'Plaid',
    categorie: CleCategorie.crochet,
    prix: 4000,
    cout: 1000,
  );
  final LieuVente marche = await lieu(tester, env, 'Marché');
  final LieuVente salon = await lieu(tester, env, 'Salon');
  await vendre(tester, env, doudou, date: DateTime(2026, 10, 12, 10), quantite: 2, lieuId: marche.id);
  await vendre(tester, env, plaid, date: DateTime(2026, 10, 20, 11), lieuId: salon.id);
  await vendre(tester, env, doudou, date: DateTime(2026, 3, 3, 16));
  await vendre(tester, env, plaid, date: DateTime(2025, 6, 10, 9), lieuId: marche.id);
}

void main() {
  testWidgets('accessible depuis l’écran Statistiques ; par défaut : l’année en cours, mois par mois', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    env.maintenant = _maintenant;
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.statistiques);
    await attendre(tester, _cle('stat-ca'));

    expect(find.byType(StatistiquesScreen), findsOneWidget);
    expect(find.text('Analyse détaillée'), findsOneWidget);
    await toucher(tester, _cle('ouvrir-analyse'));
    await attendre(tester, _cle('analyse-total'));

    expect(find.byType(AnalyseScreen), findsOneWidget);
    expect(_texte('analyse-resume'), '2026');
    // 50 € + 40 € en octobre, 25 € en mars : l'année 2025 n'y est pas.
    expect(_texte('analyse-total'), formatEuros(11500));
    expect(_texte('tableau-libelle-2'), 'mars 2026');
    expect(_texte('tableau-encaisse-2'), formatEuros(2500));
    expect(_texte('tableau-libelle-9'), 'octobre 2026');
    expect(_texte('tableau-encaisse-9'), formatEuros(9000));
    expect(_texte('tableau-cout-9'), formatEuros(2200)); // 2 doudous à 6 € + un plaid à 10 €
    expect(_texte('tableau-marge-9'), formatEuros(6800));
    expect(_cle('tableau-libelle-11'), findsOneWidget); // douze mois
    expect(_cle('tableau-libelle-12'), findsNothing);
    expect(_texte('tableau-total-encaisse'), formatEuros(11500));
    expect(_texte('tableau-total-cout'), formatEuros(2800));
    expect(_texte('tableau-total-marge'), formatEuros(8700));

    await env.fermer(tester);
  });

  testWidgets('par lieu de vente : classé du plus rentable au moins rentable, avec les parts et les barres', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    await ouvrirAnalyse(tester, env);

    await toucher(tester, _cle('analyse-par-lieu'));

    expect(_texte('graphique-libelle-0'), 'Marché');
    expect(_texte('graphique-montant-0'), formatEuros(5000));
    expect(_texte('graphique-part-0'), '43 %');
    expect(_texte('graphique-libelle-1'), 'Salon');
    expect(_texte('graphique-montant-1'), formatEuros(4000));
    expect(_texte('graphique-part-1'), '35 %');
    expect(_texte('graphique-libelle-2'), 'Non renseigné');
    expect(_texte('graphique-montant-2'), formatEuros(2500));
    expect(_texte('graphique-part-2'), '22 %');
    expect(_cle('graphique-libelle-3'), findsNothing); // Boutique et Vente en ligne : rien vendu

    double largeur(int i) => tester
        .widget<FractionallySizedBox>(
          find.descendant(of: _cle('graphique-piste-$i'), matching: find.byType(FractionallySizedBox)),
        )
        .widthFactor!;
    expect(largeur(0), 1.0);
    expect(largeur(1), closeTo(0.8, 1e-9));
    expect(largeur(2), closeTo(0.5, 1e-9));

    expect(_texte('tableau-libelle-0'), 'Marché');
    expect(_texte('tableau-encaisse-0'), formatEuros(5000));
    expect(_texte('tableau-cout-0'), formatEuros(1200));
    expect(_texte('tableau-marge-0'), formatEuros(3800));
    expect(_texte('tableau-total-encaisse'), formatEuros(11500));

    await env.fermer(tester);
  });

  testWidgets('par catégorie, toutes les années', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    await ouvrirAnalyse(tester, env);

    await choisir(tester, 'analyse-filtre-annee', 'Toutes les années');
    await toucher(tester, _cle('analyse-par-categorie'));

    expect(_texte('analyse-resume'), 'Toutes les années');
    // Crochet : 40 € + 40 € ; doudou : 50 € + 25 €.
    expect(_texte('graphique-libelle-0'), 'Crochet');
    expect(_texte('graphique-montant-0'), formatEuros(8000));
    expect(_texte('graphique-libelle-1'), 'Doudou');
    expect(_texte('graphique-montant-1'), formatEuros(7500));
    expect(_texte('analyse-total'), formatEuros(15500));
    expect(find.textContaining('regroupe les lignes libres'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('par année', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    await ouvrirAnalyse(tester, env);

    await choisir(tester, 'analyse-filtre-annee', 'Toutes les années');
    await toucher(tester, _cle('analyse-par-annee'));

    expect(_texte('tableau-libelle-0'), '2025');
    expect(_texte('tableau-encaisse-0'), formatEuros(4000));
    expect(_texte('tableau-libelle-1'), '2026');
    expect(_texte('tableau-encaisse-1'), formatEuros(11500));
    expect(_texte('tableau-total-encaisse'), formatEuros(15500));

    await env.fermer(tester);
  });

  testWidgets('les filtres se croisent : lieu, catégorie, année et mois', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    await ouvrirAnalyse(tester, env);

    // Toutes les années, par lieu, seulement le crochet : 40 € au Marché (2025) et 40 € au Salon.
    await choisir(tester, 'analyse-filtre-annee', 'Toutes les années');
    await toucher(tester, _cle('analyse-par-lieu'));
    await choisir(tester, 'analyse-filtre-categorie', 'Crochet');
    expect(_texte('analyse-resume'), 'Toutes les années · Crochet');
    expect(_texte('graphique-libelle-0'), 'Marché'); // à montant égal : l'ordre habituel des lieux
    expect(_texte('graphique-montant-0'), formatEuros(4000));
    expect(_texte('graphique-libelle-1'), 'Salon');
    expect(_texte('graphique-montant-1'), formatEuros(4000));
    expect(_texte('analyse-total'), formatEuros(8000));

    // Et en 2026 seulement : plus que le Salon.
    await choisir(tester, 'analyse-filtre-annee', '2026');
    expect(_texte('analyse-resume'), '2026 · Crochet');
    expect(_texte('graphique-libelle-0'), 'Salon');
    expect(_cle('graphique-libelle-1'), findsNothing);
    expect(_texte('analyse-total'), formatEuros(4000));

    // Octobre, tous les lieux, toutes les catégories, par mois : le mois choisi seulement.
    await choisir(tester, 'analyse-filtre-categorie', 'Toutes les catégories');
    await choisir(tester, 'analyse-filtre-mois', 'octobre');
    await toucher(tester, _cle('analyse-par-mois'));
    expect(_texte('analyse-resume'), '2026 · octobre');
    expect(_texte('tableau-libelle-0'), 'octobre 2026');
    expect(_texte('tableau-encaisse-0'), formatEuros(9000));
    expect(_cle('tableau-libelle-1'), findsNothing);

    // Les ventes sans lieu.
    await choisir(tester, 'analyse-filtre-annee', 'Toutes les années');
    await choisir(tester, 'analyse-filtre-mois', 'Tous les mois');
    await choisir(tester, 'analyse-filtre-lieu', 'Non renseigné');
    expect(_texte('analyse-resume'), 'Toutes les années · Non renseigné');
    expect(_texte('analyse-total'), formatEuros(2500));

    await env.fermer(tester);
  });

  testWidgets('aucun encaissement ne correspond aux critères : un message, pas de graphique', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    await ouvrirAnalyse(tester, env);

    await choisir(tester, 'analyse-filtre-lieu', 'Salon');
    await choisir(tester, 'analyse-filtre-mois', 'janvier');

    expect(find.text('Aucun encaissement ne correspond à ces critères.'), findsOneWidget);
    expect(_cle('analyse-total'), findsNothing);
    expect(_cle('tableau-total-encaisse'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('sans aucune vente : l’écran s’ouvre et le dit', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAnalyse(tester, env);

    expect(find.text('Analyse détaillée'), findsOneWidget);
    expect(_cle('analyse-vide'), findsOneWidget);
    // Seule l'année en cours est proposée.
    await toucher(tester, _cle('analyse-filtre-annee'));
    expect(find.text('2026'), findsWidgets);
    expect(find.text('2025'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('les chiffres se mettent à jour quand une vente est enregistrée', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await preparerVentes(tester, env);
    await ouvrirAnalyse(tester, env);
    await toucher(tester, _cle('analyse-par-lieu'));
    expect(_texte('analyse-total'), formatEuros(11500));
    expect(_texte('graphique-montant-2'), formatEuros(2500));

    await env.ecrireEcranOuvert(tester, insererVentePayee(env, date: DateTime(2026, 10, 15, 10), montant: 1000));
    await attendreTexte(tester, 'analyse-total', formatEuros(12500));
    expect(_texte('graphique-libelle-2'), 'Non renseigné');
    expect(_texte('graphique-montant-2'), formatEuros(3500));

    await env.fermer(tester);
  });
}
