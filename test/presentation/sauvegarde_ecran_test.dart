import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ZipDecoder;
import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/sauvegarde/export_csv.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/sauvegarde/sauvegarde_screen.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran (le texte de test est large), sans faire défiler.
const Size _grandEcran = Size(2000, 4000);

// Samedi 31 octobre 2026, 15 h.
final DateTime _maintenant = DateTime(2026, 10, 31, 15);
const String _nomManuelle = 'crochet-creations-manuelle-2026-10-31-150000.zip';

Finder dansEcran(Finder cible) => find.descendant(of: find.byType(SauvegardeScreen), matching: cible);
Finder dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty, essais: 400);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Fait avancer le temps jusqu'à ce que [cible] ait disparu.
Future<void> attendreDisparition(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isEmpty, essais: 400);
  expect(cible, findsNothing, reason: 'Élément qui aurait dû disparaître : $cible');
}

/// Appuie sur un élément, laisse finir les animations et les lectures de la base, sans « pumpAndSettle » (un écran
/// qui travaille affiche une barre de progression qui ne se calme jamais).
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

/// Ouvre l'application (à l'heure fixe) puis l'écran « Sauvegarde et export », liste chargée.
Future<void> ouvrirEcran(WidgetTester tester, EnvironnementTest env) async {
  env.maintenant = _maintenant;
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.sauvegarde);
  await attendre(tester, dansEcran(find.text('Sauvegarder maintenant')));
  await attendreDisparition(tester, find.text('Chargement…'));
}

/// Ouvre le menu ⋮ de la sauvegarde [nom] et choisit [action] (« Partager », « Restaurer », « Supprimer »).
Future<void> choisirDansMenu(WidgetTester tester, String nom, String action) async {
  await toucher(tester, find.byKey(ValueKey<String>('menu-$nom')));
  final Finder entree = find.descendant(
    of: find.byWidgetPredicate((Widget w) => w is PopupMenuItem),
    matching: find.text(action),
  );
  await toucher(tester, entree);
}

/// Les noms des produits de la base. À appeler quand plus aucun écran ne lit la base en direct.
Future<List<String>> nomsDesProduits(WidgetTester tester, EnvironnementTest env) {
  return env.travailler(tester, () async {
    final List<Produit> produits = await env.db.select(env.db.produits).get();
    return produits.map((Produit p) => p.nom).toList()..sort();
  });
}

void main() {
  testWidgets('l’écran est atteint depuis « Plus », puis « Réglages »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Réglages')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);

    await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Sauvegarde et export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);

    expect(find.byType(SauvegardeScreen), findsOneWidget);
    expect(find.text('Bientôt disponible'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('au départ : aucune sauvegarde, et les quatre rubriques', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirEcran(tester, env);

    for (final String titre in <String>[
      'Sauvegarder',
      'Sauvegardes sur ce téléphone',
      'Restaurer',
      'Exporter',
    ]) {
      expect(dansEcran(find.text(titre)), findsOneWidget, reason: titre);
    }
    // La phrase « dernière sauvegarde » et la liste le disent chacune.
    expect(dansEcran(find.text('Aucune sauvegarde pour l’instant.')), findsNWidgets(2));
    expect(dansEcran(find.text('Sauvegarder maintenant')), findsOneWidget);
    expect(dansEcran(find.text('Restaurer depuis un fichier')), findsOneWidget);
    expect(dansEcran(find.text('Exporter en CSV (tableur)')), findsOneWidget);
    expect(dansEcran(find.text('Exporter en JSON (toutes les données)')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('« Sauvegarder maintenant » range une sauvegarde sur le téléphone et l’annonce', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirEcran(tester, env);

    await toucher(tester, dansEcran(find.text('Sauvegarder maintenant')));
    await attendre(tester, find.textContaining('Sauvegarde créée'));
    await attendre(tester, dansEcran(find.text('Dernière sauvegarde : aujourd’hui à 15 h 00')));

    expect(dansEcran(find.text('31/10/2026 à 15 h 00')), findsOneWidget);
    expect(dansEcran(find.textContaining('Manuelle · ')), findsOneWidget);

    final List<SauvegardeLocale> liste = await env.travailler(tester, () => env.sauvegarde.lister());
    expect(liste.map((SauvegardeLocale s) => s.nom).toList(), <String>[_nomManuelle]);
    final Archive archive = ZipDecoder().decodeBytes(
      (await env.travailler(tester, () => liste.single.fichier.readAsBytes())),
    );
    expect(archive.find('donnees.json'), isNotNull);

    await env.fermer(tester);
  });

  testWidgets('partager une sauvegarde ouvre la feuille de partage avec le .zip', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.maintenant = _maintenant;
    await env.travailler(tester, () => env.sauvegarde.creer(TypeSauvegarde.manuelle));
    await ouvrirEcran(tester, env);

    await choisirDansMenu(tester, _nomManuelle, 'Partager');
    await attendreJusqua(tester, () => env.partageFichiers.partages.isNotEmpty);

    expect(env.partageFichiers.partages, <String>[
      '$_nomManuelle | application/zip | Sauvegarde Crochet & Créations du 31/10/2026',
    ]);
    expect(env.partageFichiers.cheminsPartages.single, endsWith(_nomManuelle));

    await env.fermer(tester);
  });

  testWidgets('supprimer une sauvegarde demande confirmation', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.maintenant = _maintenant;
    await env.travailler(tester, () => env.sauvegarde.creer(TypeSauvegarde.manuelle));
    await ouvrirEcran(tester, env);
    expect(dansEcran(find.text('31/10/2026 à 15 h 00')), findsOneWidget);

    // On renonce : la sauvegarde reste.
    await choisirDansMenu(tester, _nomManuelle, 'Supprimer');
    expect(find.text('Supprimer cette sauvegarde ?'), findsOneWidget);
    await toucher(tester, dansDialogue(find.text('Annuler')));
    expect(dansEcran(find.text('31/10/2026 à 15 h 00')), findsOneWidget);
    expect(await env.travailler(tester, () => env.sauvegarde.lister()), hasLength(1));

    // On confirme : elle disparaît du téléphone.
    await choisirDansMenu(tester, _nomManuelle, 'Supprimer');
    await toucher(tester, dansDialogue(find.text('Supprimer')));
    await attendreDisparition(tester, dansEcran(find.text('31/10/2026 à 15 h 00')));
    expect(await env.travailler(tester, () => env.sauvegarde.lister()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('restaurer depuis la liste : confirmation, remplacement des données, retour à l’accueil', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.maintenant = _maintenant;
    await env.creerProduit(tester);
    await env.travailler(tester, () => env.sauvegarde.creer(TypeSauvegarde.manuelle));
    await env.creerProduit(tester, nom: 'Bonnet'); // ajouté après la sauvegarde
    await ouvrirEcran(tester, env);

    await choisirDansMenu(tester, _nomManuelle, 'Restaurer');
    expect(find.text('Restaurer cette sauvegarde ?'), findsOneWidget);
    expect(dansDialogue(find.textContaining('Sauvegarde du 31/10/2026 à 15 h 00')), findsOneWidget);
    expect(dansDialogue(find.textContaining('1 produit')), findsOneWidget);
    expect(dansDialogue(find.textContaining('copie de sécurité')), findsOneWidget);

    await toucher(tester, dansDialogue(find.text('Restaurer')));
    await attendre(tester, find.text('Restauration terminée'));
    expect(dansDialogue(find.textContaining('remis en place')), findsOneWidget);

    await toucher(tester, dansDialogue(find.text('Retour à l’accueil')));
    expect(find.byType(SauvegardeScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // plus aucun écran ne lit la base en direct
    expect(await nomsDesProduits(tester, env), <String>['Doudou lapin']);
    final List<SauvegardeLocale> liste = await env.travailler(tester, () => env.sauvegarde.lister());
    expect(liste.map((SauvegardeLocale s) => s.type), contains(TypeSauvegarde.avantRestauration));

    await env.fermer(tester);
  });

  testWidgets('renoncer à la restauration ne change rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.maintenant = _maintenant;
    await env.creerProduit(tester);
    await env.travailler(tester, () => env.sauvegarde.creer(TypeSauvegarde.manuelle));
    await env.creerProduit(tester, nom: 'Bonnet');
    await ouvrirEcran(tester, env);

    await choisirDansMenu(tester, _nomManuelle, 'Restaurer');
    await toucher(tester, dansDialogue(find.text('Annuler')));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SauvegardeScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(await nomsDesProduits(tester, env), <String>['Bonnet', 'Doudou lapin']);
    final List<SauvegardeLocale> liste = await env.travailler(tester, () => env.sauvegarde.lister());
    expect(liste, hasLength(1), reason: 'aucune copie de sécurité si on renonce');

    await env.fermer(tester);
  });

  testWidgets('restaurer depuis un fichier choisi dans le téléphone', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.maintenant = _maintenant;
    await env.creerProduit(tester);
    env.selecteurFichier.contenu = await env.travailler(tester, () => env.sauvegarde.fabriquerArchive());
    await env.creerProduit(tester, nom: 'Bonnet');
    await ouvrirEcran(tester, env);

    await toucher(tester, dansEcran(find.text('Restaurer depuis un fichier')));
    expect(env.selecteurFichier.appels, 1);
    expect(find.text('Restaurer cette sauvegarde ?'), findsOneWidget);

    await toucher(tester, dansDialogue(find.text('Restaurer')));
    await attendre(tester, find.text('Restauration terminée'));
    await toucher(tester, dansDialogue(find.text('Retour à l’accueil')));

    await tester.pumpWidget(const SizedBox());
    expect(await nomsDesProduits(tester, env), <String>['Doudou lapin']);

    await env.fermer(tester);
  });

  testWidgets('un fichier annulé ou qui n’est pas une sauvegarde ne change rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirEcran(tester, env);

    // La personne ferme le sélecteur sans rien choisir.
    await toucher(tester, dansEcran(find.text('Restaurer depuis un fichier')));
    expect(env.selecteurFichier.appels, 1);
    expect(find.byType(AlertDialog), findsNothing);

    // Elle choisit un fichier quelconque : un message clair, aucune confirmation, rien de remplacé.
    env.selecteurFichier.contenu = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    await toucher(tester, dansEcran(find.text('Restaurer depuis un fichier')));
    expect(env.selecteurFichier.appels, 2);
    expect(find.textContaining('pas une sauvegarde'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.pumpWidget(const SizedBox());
    expect(await nomsDesProduits(tester, env), <String>['Doudou lapin']);
    expect(await env.travailler(tester, () => env.sauvegarde.lister()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('exporter en CSV partage un .zip avec un fichier par type', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirEcran(tester, env);

    await toucher(tester, dansEcran(find.text('Exporter en CSV (tableur)')));
    await attendreJusqua(tester, () => env.partageFichiers.partages.isNotEmpty, essais: 400);

    expect(env.partageFichiers.partages, <String>[
      'crochet-creations-export-csv-2026-10-31.zip | application/zip | Export CSV – Crochet & Créations',
    ]);
    final String chemin = env.partageFichiers.cheminsPartages.single;
    final Uint8List octets = await env.travailler(tester, () => File(chemin).readAsBytes());
    final Archive archive = ZipDecoder().decodeBytes(octets);
    expect(archive.files.map((f) => f.name).toList(), ExportCsv.fichiers);

    await env.fermer(tester);
  });

  testWidgets('exporter en JSON partage un fichier avec toutes les données', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerProduit(tester);
    await ouvrirEcran(tester, env);

    await toucher(tester, dansEcran(find.text('Exporter en JSON (toutes les données)')));
    await attendreJusqua(tester, () => env.partageFichiers.partages.isNotEmpty, essais: 400);

    expect(env.partageFichiers.partages, <String>[
      'crochet-creations-donnees-2026-10-31.json | application/json | Export JSON – Crochet & Créations',
    ]);
    final String contenu = await env.travailler(
      tester,
      () => File(env.partageFichiers.cheminsPartages.single).readAsString(),
    );
    expect(contenu, contains('"crochet-creations"'));
    expect(contenu, contains('Doudou lapin'));

    await env.fermer(tester);
  });
}
