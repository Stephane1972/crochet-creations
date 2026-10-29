import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/cours_vues.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/clients/client_fiche_screen.dart';
import 'package:crochet_creations/presentation/cours/cours_fiche_screen.dart';
import 'package:crochet_creations/presentation/cours/cours_form_screen.dart';
import 'package:crochet_creations/presentation/cours/cours_inscription_screen.dart';
import 'package:crochet_creations/presentation/cours/cours_screen.dart';
import 'package:crochet_creations/presentation/cours/cours_widgets.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/ventes/vente_confirmation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

const Size _grandEcran = Size(800, 2400);

Finder dansListe(Finder cible) => find.descendant(of: find.byType(CoursScreen), matching: cible);
Finder dansFiche(Finder cible) => find.descendant(of: find.byType(CoursFicheScreen), matching: cible);
Finder dansInscription(Finder cible) => find.descendant(of: find.byType(CoursInscriptionScreen), matching: cible);
Finder dansFormulaire(Finder cible) => find.descendant(of: find.byType(CoursFormScreen), matching: cible);
Finder dansClient(Finder cible) => find.descendant(of: find.byType(ClientFicheScreen), matching: cible);
Finder dansVente(Finder cible) => find.descendant(of: find.byType(VenteConfirmationScreen), matching: cible);

/// Feuille du bas ouverte (choix du client, actions sur une personne).
Finder dansFeuille(Finder cible) => find.descendant(of: find.byType(BottomSheet), matching: cible);

/// Message affiché en bas de l'écran (snackbar).
Finder message(String texte) => find.text(texte);

/// Fait avancer le temps, en laissant la base et les fichiers travailler, jusqu'à ce que [cible] apparaisse.
Future<void> attendre(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Appuie sur un élément, laisse finir les animations et les lectures de la base, sans « pumpAndSettle » (un
/// écran qui charge, ou un bouton qui enregistre, affiche un indicateur d'attente qui ne se calme jamais).
Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.tap(cible);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await laisserFinir(tester);
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route, {Object? arguments}) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route, arguments: arguments));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Ouvre l'application puis la fiche de ce cours.
Future<void> ouvrirFiche(WidgetTester tester, EnvironnementTest env, CoursFiche cours) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await ouvrirRoute(tester, AppRoutes.coursFiche, arguments: cours.id);
  await attendre(tester, dansFiche(find.text('Informations')));
}

/// Depuis la fiche d'un cours : ouvre l'inscription (bouton [bouton]) et y choisit ce client.
Future<void> ouvrirInscriptionEtChoisir(WidgetTester tester, String bouton, String nomClient) async {
  await toucher(tester, dansFiche(find.text(bouton)));
  await attendre(tester, dansInscription(find.text('Choisir la personne à inscrire')));
  await toucher(tester, dansInscription(find.text('Choisir la personne à inscrire')));
  await attendre(tester, dansFeuille(find.text(nomClient)));
  expect(dansFeuille(find.text('Choisir la personne à inscrire')), findsNothing); // pas de « client de passage »
  await toucher(tester, dansFeuille(find.text(nomClient)));
  expect(dansInscription(find.text(nomClient)), findsOneWidget);
}

/// Ouvre le menu « Plus d'actions » de la fiche et choisit [action].
Future<void> choisirDansLeMenu(WidgetTester tester, String action) async {
  await toucher(tester, find.byTooltip('Plus d’actions'));
  await toucher(tester, find.text(action));
}

/// Referme la feuille du bas ouverte, en appuyant à côté.
Future<void> fermerLaFeuille(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 100));
  await tester.pumpAndSettle();
}

Future<Client> unClient(WidgetTester tester, EnvironnementTest env, String prenom, String nom) =>
    env.creerClient(tester, DonneesClient(prenom: prenom, nom: nom));

const PaiementSaisi _toutEnEspeces = PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 4500);
const PaiementSaisi _acompteEnEspeces = PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 1500);

Future<List<Inscription>> inscriptionsEnBase(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.db.select(env.db.inscriptionsCours).get());

Future<List<Vente>> ventesEnBase(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.db.select(env.db.ventes).get());

Future<Vente> venteEnBase(WidgetTester tester, EnvironnementTest env, int id) =>
    env.travailler(tester, () => (env.db.select(env.db.ventes)..where((t) => t.id.equals(id))).getSingle());

/// Net encaissé sur une vente (paiements moins remboursements).
Future<int> netEncaisse(WidgetTester tester, EnvironnementTest env, int venteId) async {
  final List<Paiement> paiements = await env.travailler(
    tester,
    () => (env.db.select(env.db.paiements)..where((t) => t.venteId.equals(venteId))).get(),
  );
  return paiements.fold<int>(0, (int somme, Paiement p) => somme + p.montantCentimes);
}

void main() {
  // ---------------------------------------------------------------------------
  // Liste des cours (écran 16)
  // ---------------------------------------------------------------------------

  testWidgets('liste des cours : vide au départ, ouverte depuis « Plus »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);

    await tester.tap(ongletNav('Plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Cours')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await laisserFinir(tester);
    await attendre(tester, dansListe(find.text('Aucun cours à venir.')));

    expect(dansListe(find.text('Nouveau cours')), findsOneWidget);
    expect(dansListe(find.text('À venir')), findsOneWidget);
    expect(dansListe(find.text('Passés')), findsOneWidget);
    expect(dansListe(find.text('Archivés')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('liste des cours : à venir, places, liste d’attente, annulé ; passés et archivés à part', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final Client bruno = await unClient(tester, env, 'Bruno', 'Petit');
    final Client camille = await unClient(tester, env, 'Camille', 'Martin');
    final DateTime maintenant = DateTime.now();

    final CoursFiche initiation = await env.creerCours(
      tester,
      titre: 'Initiation au crochet',
      debut: maintenant.add(const Duration(days: 10)),
    );
    final CoursFiche doudou = await env.creerCours(
      tester,
      titre: 'Atelier doudou',
      debut: maintenant.add(const Duration(days: 20)),
      places: 2,
      prix: 6000,
    );
    final CoursFiche annule = await env.creerCours(
      tester,
      titre: 'Atelier annulé',
      debut: maintenant.add(const Duration(days: 25)),
    );
    await env.creerCours(
      tester,
      titre: 'Cours de printemps',
      debut: maintenant.subtract(const Duration(days: 30)),
    );
    final CoursFiche ancien = await env.creerCours(
      tester,
      titre: 'Cours de l’an dernier',
      debut: maintenant.subtract(const Duration(days: 400)),
    );
    await env.inscrire(tester, coursId: initiation.id, clientId: alice.id);
    await env.inscrire(tester, coursId: doudou.id, clientId: alice.id);
    await env.inscrire(tester, coursId: doudou.id, clientId: bruno.id);
    await env.inscrire(tester, coursId: doudou.id, clientId: camille.id); // complet : en attente
    await env.travailler(tester, () => env.cours.annulerCours(annule.id));
    await env.travailler(tester, () => env.cours.archiver(ancien.id));

    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.cours);
    await attendre(tester, dansListe(find.text('Initiation au crochet')));

    // À venir : du plus proche au plus lointain.
    expect(dansListe(find.text('Atelier doudou')), findsOneWidget);
    expect(dansListe(find.text('Atelier annulé')), findsOneWidget);
    expect(dansListe(find.text('Cours de printemps')), findsNothing);
    expect(dansListe(find.text('Cours de l’an dernier')), findsNothing);
    final double hautInitiation = tester.getTopLeft(dansListe(find.text('Initiation au crochet'))).dy;
    final double hautDoudou = tester.getTopLeft(dansListe(find.text('Atelier doudou'))).dy;
    final double hautAnnule = tester.getTopLeft(dansListe(find.text('Atelier annulé'))).dy;
    expect(hautInitiation, lessThan(hautDoudou));
    expect(hautDoudou, lessThan(hautAnnule));

    expect(dansListe(find.text('1 / 4 places')), findsOneWidget);
    expect(dansListe(find.text('Complet · 2 / 2 places · 1 en attente')), findsOneWidget);
    expect(dansListe(find.text('0 / 4 places')), findsOneWidget);
    expect(dansListe(find.text('Annulé')), findsOneWidget);
    expect(dansListe(find.text(formatEuros(6000))), findsOneWidget);

    // Passés.
    await tester.tap(dansListe(find.text('Passés')));
    await tester.pump();
    await attendre(tester, dansListe(find.text('Cours de printemps')));
    expect(dansListe(find.text('Initiation au crochet')), findsNothing);
    expect(dansListe(find.text('Cours de l’an dernier')), findsNothing);

    // Archivés.
    await tester.tap(dansListe(find.text('Archivés')));
    await tester.pump();
    await attendre(tester, dansListe(find.text('Cours de l’an dernier')));
    expect(dansListe(find.text('Cours de printemps')), findsNothing);
    expect(dansListe(find.text('Archivé')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('liste des cours : un appui ouvre la fiche du cours', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.creerCours(tester, titre: 'Initiation au crochet');
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.cours);
    await attendre(tester, dansListe(find.text('Initiation au crochet')));

    await toucher(tester, dansListe(find.text('Initiation au crochet')));
    await attendre(tester, dansFiche(find.text('Informations')));

    expect(find.byType(CoursFicheScreen), findsOneWidget);

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Formulaire du cours
  // ---------------------------------------------------------------------------

  testWidgets('nouveau cours : enregistré avec ses informations, puis la fiche s’ouvre', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.coursNouveau);
    expect(dansFormulaire(find.text('Nouveau cours')), findsOneWidget);

    await saisir(tester, 'Titre du cours *', 'Initiation au crochet');
    await saisir(tester, 'Description', 'Les premiers points.');
    await saisir(tester, 'Lieu', 'Atelier de Camille');
    await saisir(tester, 'Prix par personne (€) *', '45');
    await saisir(tester, 'Nombre de places *', '4');
    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, find.byType(CoursFicheScreen));
    await attendre(tester, dansFiche(find.text('Atelier de Camille')));

    expect(message('Cours créé.'), findsWidgets);
    expect(dansFiche(find.text('Les premiers points.')), findsOneWidget);
    expect(dansFiche(find.text('Niveau : Tous niveaux')), findsOneWidget);
    expect(dansFiche(find.text('Matériel non inclus')), findsOneWidget);
    expect(dansFiche(find.text('${formatEuros(4500)} par personne')), findsOneWidget);
    expect(dansFiche(find.text('0 / 4 places · 4 libres')), findsOneWidget);
    expect(dansFiche(find.text('Personne n’est encore inscrit.')), findsOneWidget);

    final List<CoursFiche> tous = await env.travailler(tester, () => env.db.select(env.db.cours).get());
    expect(tous, hasLength(1));
    final CoursFiche c = tous.single;
    expect(c.titre, 'Initiation au crochet');
    expect(c.description, 'Les premiers points.');
    expect(c.lieu, 'Atelier de Camille');
    expect(c.prixCentimes, 4500);
    expect(c.places, 4);
    expect(c.dureeMinutes, 120); // 2 h proposées par défaut
    expect(c.debutLe.hour, 14); // 14 h proposées par défaut
    expect(c.debutLe.minute, 0);
    expect(c.niveau, NiveauCours.tousNiveaux);
    expect(c.materielInclus, isFalse);
    expect(c.statut, StatutCours.planifie);

    await env.fermer(tester);
  });

  testWidgets('nouveau cours : le titre et le prix sont obligatoires, rien n’est enregistré sans eux', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.coursNouveau);

    await toucher(tester, find.text('Enregistrer'));

    expect(message('Corrigez les champs signalés en rouge.'), findsWidgets);
    expect(find.text('Le titre du cours est obligatoire.'), findsOneWidget);
    expect(find.text('Indiquez le prix (0 si c’est gratuit).'), findsOneWidget);
    expect(find.byType(CoursFicheScreen), findsNothing);
    expect(await env.travailler(tester, () => env.db.select(env.db.cours).get()), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('nouveau cours : la photo est copiée dans l’application et enregistrée avec le cours', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    env.selecteur.chemin = await env.photoGalerie(tester, 'IMG_cours.jpg');
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.coursNouveau);

    await saisir(tester, 'Titre du cours *', 'Cours avec photo');
    await saisir(tester, 'Prix par personne (€) *', '0');
    await appuyer(tester, find.text('Ajouter une photo'));
    await appuyer(tester, find.text('Choisir dans la galerie'));
    await laisserFinir(tester);
    expect(env.selecteur.appels, 1);

    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, find.byType(CoursFicheScreen));

    final CoursFiche c = (await env.travailler(tester, () => env.db.select(env.db.cours).get())).single;
    expect(c.photoChemin, isNotNull);
    expect(c.photoChemin, isNot(contains('/'))); // nom de fichier, pas chemin complet
    final bool existe = await env.travailler(
      tester,
      () => File('${env.dossierPhotos.path}/${c.photoChemin}').exists(),
    );
    expect(existe, isTrue);

    await env.fermer(tester);
  });

  testWidgets('modifier un cours : les places ne descendent pas sous les personnes confirmées', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final CoursFiche cours = await env.creerCours(tester, titre: 'Atelier doudou', places: 3);
    for (final (String, String) n in <(String, String)>[('Alice', 'Durand'), ('Bruno', 'Petit'), ('Camille', 'Martin')]) {
      final Client c = await unClient(tester, env, n.$1, n.$2);
      await env.inscrire(tester, coursId: cours.id, clientId: c.id);
    }
    await ouvrirAccueil(tester, env, taille: _grandEcran);
    await ouvrirRoute(tester, AppRoutes.coursModifier, arguments: cours.id);
    await attendre(tester, find.widgetWithText(TextFormField, 'Titre du cours *'));

    final TextFormField titre = tester.widget(find.widgetWithText(TextFormField, 'Titre du cours *'));
    expect(titre.controller!.text, 'Atelier doudou');
    expect(dansFormulaire(find.text('Modifier le cours')), findsOneWidget);

    await saisir(tester, 'Nombre de places *', '2');
    await toucher(tester, find.text('Enregistrer'));
    await attendre(
      tester,
      message('Ce cours compte déjà 3 personnes confirmées : le nombre de places ne peut pas être plus petit.'),
    );
    expect(find.byType(CoursFormScreen), findsOneWidget);
    expect((await env.travailler(tester, () => env.cours.obtenir(cours.id)))!.places, 3);

    await saisir(tester, 'Nombre de places *', '5');
    await saisir(tester, 'Titre du cours *', 'Atelier doudou (2e session)');
    await toucher(tester, find.text('Enregistrer'));
    await attendre(tester, message('Modifications enregistrées.'));

    expect(find.byType(CoursFormScreen), findsNothing);
    final CoursFiche apres = (await env.travailler(tester, () => env.cours.obtenir(cours.id)))!;
    expect(apres.places, 5);
    expect(apres.titre, 'Atelier doudou (2e session)');

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Fiche du cours (écran 17)
  // ---------------------------------------------------------------------------

  testWidgets('fiche d’un cours : informations, inscrits et état de leur paiement', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final Client bruno = await unClient(tester, env, 'Bruno', 'Petit');
    final Client camille = await unClient(tester, env, 'Camille', 'Martin');
    final CoursFiche cours = await env.creerCours(tester, description: 'Les premiers points.');
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id, paiement: _toutEnEspeces);
    await env.inscrire(tester, coursId: cours.id, clientId: bruno.id, paiement: _acompteEnEspeces);
    await env.inscrire(tester, coursId: cours.id, clientId: camille.id);

    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Inscrits (3)')));

    expect(dansFiche(find.text(creneauCours(cours.debutLe, 150))), findsOneWidget);
    expect(dansFiche(find.text('Atelier de Camille')), findsOneWidget);
    expect(dansFiche(find.text('Niveau : Débutant')), findsOneWidget);
    expect(dansFiche(find.text('Matériel non inclus')), findsOneWidget);
    expect(dansFiche(find.text('${formatEuros(4500)} par personne')), findsOneWidget);
    expect(dansFiche(find.text('3 / 4 places · 1 libre')), findsOneWidget);
    expect(dansFiche(find.text('Les premiers points.')), findsOneWidget);

    expect(dansFiche(find.text('Alice Durand')), findsOneWidget);
    expect(dansFiche(find.text('Payé')), findsOneWidget);
    expect(dansFiche(find.text('Acompte versé')), findsOneWidget);
    expect(dansFiche(find.text('À payer')), findsOneWidget);
    expect(dansFiche(find.text(formatEuros(4500))), findsOneWidget); // Alice : payé, rien à régler
    expect(dansFiche(find.text('${formatEuros(4500)} · reste ${formatEuros(3000)}')), findsOneWidget);
    expect(dansFiche(find.text('${formatEuros(4500)} · reste ${formatEuros(4500)}')), findsOneWidget);

    // Le bouton du bas inscrit quelqu'un.
    expect(dansFiche(find.text('Inscrire quelqu’un')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('fiche d’un cours : « Voir la vente et la facture » ouvre la vente de la personne', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id, paiement: _toutEnEspeces);

    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Alice Durand')));
    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Voir la vente et la facture')));
    expect(dansFeuille(find.text('Confirmer l’inscription')), findsNothing); // elle est déjà confirmée
    await toucher(tester, dansFeuille(find.text('Voir la vente et la facture')));
    await attendre(tester, dansVente(find.text('Total')));

    expect(find.byType(VenteConfirmationScreen), findsOneWidget);
    expect(dansVente(find.textContaining('Cours : Initiation au crochet')), findsWidgets);
    expect(dansVente(find.textContaining('Alice Durand')), findsWidgets);

    await env.fermer(tester);
  });

  testWidgets('l’historique d’un client ouvre la fiche du cours auquel il est inscrit', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id);

    await ouvrirAccueil(tester, env, taille: const Size(800, 3200));
    await ouvrirRoute(tester, AppRoutes.clientFiche, arguments: alice.id);
    await attendre(tester, dansClient(find.text('Initiation au crochet')));

    await toucher(tester, dansClient(find.text('Initiation au crochet')));
    await attendre(tester, dansFiche(find.text('Informations')));

    expect(find.byType(CoursFicheScreen), findsOneWidget);
    expect(dansFiche(find.text('Alice Durand')), findsOneWidget);

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Inscription (écran 18)
  // ---------------------------------------------------------------------------

  testWidgets('inscription payée en totalité, au prix convenu pour la personne', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await unClient(tester, env, 'Camille', 'Martin');
    final CoursFiche cours = await env.creerCours(tester);
    await ouvrirFiche(tester, env, cours);

    await ouvrirInscriptionEtChoisir(tester, 'Inscrire quelqu’un', 'Camille Martin');

    // Le prix du cours est proposé ; on peut le changer pour cette personne.
    final TextFormField prix = tester.widget(find.widgetWithText(TextFormField, 'Prix pour cette personne (€)'));
    expect(prix.controller!.text, '45');
    expect(dansInscription(find.text('Paiement')), findsOneWidget);
    await saisir(tester, 'Prix pour cette personne (€)', '40');

    await toucher(tester, dansInscription(find.text('Inscrire')));
    await attendre(tester, message('Inscription de Camille Martin enregistrée.'));
    await attendre(tester, dansFiche(find.text('Inscrits (1)')));

    expect(find.byType(CoursInscriptionScreen), findsNothing);
    expect(dansFiche(find.text('Payé')), findsOneWidget);
    expect(dansFiche(find.text(formatEuros(4000))), findsOneWidget);
    expect(dansFiche(find.text('1 / 4 places · 3 libres')), findsOneWidget);

    final Inscription inscription = (await inscriptionsEnBase(tester, env)).single;
    expect(inscription.statut, StatutInscription.confirmee);
    expect(inscription.prixCentimes, 4000);
    final Vente vente = await venteEnBase(tester, env, inscription.venteId!);
    expect(vente.totalCentimes, 4000);
    expect(vente.statutPaiement, StatutPaiement.payee);
    expect((await env.travailler(tester, () => env.cours.obtenir(cours.id)))!.prixCentimes, 4500);

    await env.fermer(tester);
  });

  testWidgets('inscription avec acompte : un acompte trop élevé est refusé, puis le bon est accepté', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await unClient(tester, env, 'Camille', 'Martin');
    final CoursFiche cours = await env.creerCours(tester);
    await ouvrirFiche(tester, env, cours);
    await ouvrirInscriptionEtChoisir(tester, 'Inscrire quelqu’un', 'Camille Martin');

    await toucher(tester, dansInscription(find.text('Acompte')));
    await saisir(tester, 'Montant de l’acompte (€)', '99');
    await toucher(tester, dansInscription(find.text('Inscrire')));
    await attendre(tester, message('Le montant encaissé ne peut pas dépasser le total de la vente.'));

    expect(find.byType(CoursInscriptionScreen), findsOneWidget);
    expect(await inscriptionsEnBase(tester, env), isEmpty);
    expect(await ventesEnBase(tester, env), isEmpty);

    await saisir(tester, 'Montant de l’acompte (€)', '15');
    await toucher(tester, dansInscription(find.text('Inscrire')));
    await attendre(tester, message('Inscription de Camille Martin enregistrée.'));
    await attendre(tester, dansFiche(find.text('Acompte versé')));

    expect(dansFiche(find.text('${formatEuros(4500)} · reste ${formatEuros(3000)}')), findsOneWidget);
    final Inscription inscription = (await inscriptionsEnBase(tester, env)).single;
    final Vente vente = await venteEnBase(tester, env, inscription.venteId!);
    expect(vente.statutPaiement, StatutPaiement.partiellementPayee);
    expect(await netEncaisse(tester, env, vente.id), 1500);

    await env.fermer(tester);
  });

  testWidgets('inscription à payer plus tard : l’inscription est confirmée, la vente reste impayée', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await unClient(tester, env, 'Camille', 'Martin');
    final CoursFiche cours = await env.creerCours(tester);
    await ouvrirFiche(tester, env, cours);
    await ouvrirInscriptionEtChoisir(tester, 'Inscrire quelqu’un', 'Camille Martin');

    await toucher(tester, dansInscription(find.text('Plus tard')));
    expect(
      dansInscription(find.text('Rien n’est encaissé : l’inscription reste impayée jusqu’au règlement.')),
      findsOneWidget,
    );
    await toucher(tester, dansInscription(find.text('Inscrire')));
    await attendre(tester, dansFiche(find.text('À payer')));

    final Inscription inscription = (await inscriptionsEnBase(tester, env)).single;
    expect(inscription.statut, StatutInscription.confirmee);
    final Vente vente = await venteEnBase(tester, env, inscription.venteId!);
    expect(vente.statutPaiement, StatutPaiement.impayee);
    expect(await netEncaisse(tester, env, vente.id), 0);

    await env.fermer(tester);
  });

  testWidgets('inscription à un cours gratuit : rien à encaisser', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await unClient(tester, env, 'Camille', 'Martin');
    final CoursFiche cours = await env.creerCours(tester, titre: 'Découverte', prix: 0);
    await ouvrirFiche(tester, env, cours);
    await ouvrirInscriptionEtChoisir(tester, 'Inscrire quelqu’un', 'Camille Martin');

    expect(dansInscription(find.text('Paiement')), findsNothing);
    expect(
      dansInscription(find.text('Ce cours est gratuit pour cette personne : rien à encaisser.')),
      findsOneWidget,
    );
    await toucher(tester, dansInscription(find.text('Inscrire')));
    await attendre(tester, dansFiche(find.text('Inscrits (1)')));

    final Inscription inscription = (await inscriptionsEnBase(tester, env)).single;
    expect(inscription.statut, StatutInscription.confirmee);
    expect(inscription.prixCentimes, 0);
    final Vente vente = await venteEnBase(tester, env, inscription.venteId!);
    expect(vente.totalCentimes, 0);
    expect(vente.statutPaiement, StatutPaiement.payee);

    await env.fermer(tester);
  });

  testWidgets('inscription : il faut choisir la personne, et une personne déjà inscrite est refusée', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id);
    await ouvrirFiche(tester, env, cours);

    await toucher(tester, dansFiche(find.text('Inscrire quelqu’un')));
    await attendre(tester, dansInscription(find.text('Choisir la personne à inscrire')));
    await toucher(tester, dansInscription(find.text('Inscrire')));
    expect(message('Choisissez la personne à inscrire.'), findsWidgets);
    expect(find.byType(CoursInscriptionScreen), findsOneWidget);

    await toucher(tester, dansInscription(find.text('Choisir la personne à inscrire')));
    await attendre(tester, dansFeuille(find.text('Alice Durand')));
    await toucher(tester, dansFeuille(find.text('Alice Durand')));
    await toucher(tester, dansInscription(find.text('Inscrire')));
    await attendre(tester, message('Cette personne est déjà inscrite à ce cours.'));

    expect(find.byType(CoursInscriptionScreen), findsOneWidget);
    expect(await inscriptionsEnBase(tester, env), hasLength(1));

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Liste d'attente
  // ---------------------------------------------------------------------------

  testWidgets('cours complet : la personne passe en liste d’attente, sans vente ni paiement', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    await unClient(tester, env, 'Bruno', 'Petit');
    final CoursFiche cours = await env.creerCours(tester, places: 1);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id);
    await ouvrirFiche(tester, env, cours);

    expect(dansFiche(find.text('Ajouter en liste d’attente')), findsOneWidget);
    expect(dansFiche(find.text('Inscrire quelqu’un')), findsNothing);
    await ouvrirInscriptionEtChoisir(tester, 'Ajouter en liste d’attente', 'Bruno Petit');

    expect(dansInscription(find.text('Mettre en liste d’attente')), findsOneWidget);
    expect(dansInscription(find.text('Paiement')), findsNothing);
    expect(find.textContaining('passe en liste d’attente'), findsOneWidget);

    await toucher(tester, dansInscription(find.text('Mettre en liste d’attente')));
    await attendre(tester, message('Bruno Petit est sur la liste d’attente.'));
    await attendre(tester, dansFiche(find.text('Liste d’attente (1)')));

    expect(dansFiche(find.text('Inscrits (1)')), findsOneWidget);
    expect(dansFiche(find.text('En attente · n° 1')), findsOneWidget);
    final List<Inscription> inscriptions = await inscriptionsEnBase(tester, env);
    final Inscription bruno = inscriptions.singleWhere((Inscription i) => i.statut == StatutInscription.listeAttente);
    expect(bruno.venteId, isNull);
    expect(await ventesEnBase(tester, env), hasLength(1)); // celle d'Alice seulement

    await env.fermer(tester);
  });

  testWidgets('liste d’attente : on confirme la première personne quand une place se libère', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final Client bruno = await unClient(tester, env, 'Bruno', 'Petit');
    final CoursFiche cours = await env.creerCours(tester, places: 1);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id, paiement: _toutEnEspeces);
    await env.inscrire(tester, coursId: cours.id, clientId: bruno.id);
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Liste d’attente (1)')));

    // Le cours est complet : la confirmation est refusée, avec la raison.
    await toucher(tester, dansFiche(find.text('Bruno Petit')));
    await attendre(tester, dansFeuille(find.text('Confirmer l’inscription')));
    expect(dansFeuille(find.text('Le cours est complet : aucune place n’est libre pour le moment.')), findsOneWidget);
    await fermerLaFeuille(tester);

    // Alice annule et est remboursée : une place se libère.
    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    expect(find.text('Annuler cette inscription ?'), findsOneWidget);
    await toucher(tester, find.text('Annuler et rembourser'));
    await attendre(tester, message('Inscription annulée, paiement remboursé.'));
    await attendre(tester, dansFiche(find.text('Inscrits (0)')));
    expect(dansFiche(find.text('Inscriptions annulées (1)')), findsOneWidget);

    // Personne n'est confirmé tout seul : on le fait à la main.
    expect(dansFiche(find.text('Liste d’attente (1)')), findsOneWidget);
    await toucher(tester, dansFiche(find.text('Bruno Petit')));
    await attendre(tester, dansFeuille(find.text('Confirmer l’inscription')));
    expect(dansFeuille(find.text('Le cours est complet : aucune place n’est libre pour le moment.')), findsNothing);
    await toucher(tester, dansFeuille(find.text('Confirmer l’inscription')));
    await attendre(tester, dansInscription(find.text('Prix convenu')));
    expect(dansInscription(find.text('Paiement')), findsOneWidget);

    await toucher(tester, find.text('Confirmer l’inscription').last);
    await attendre(tester, message('Inscription de Bruno Petit confirmée.'));
    await attendre(tester, dansFiche(find.text('Inscrits (1)')));

    expect(find.byType(CoursInscriptionScreen), findsNothing);
    expect(dansFiche(find.textContaining('Liste d’attente (')), findsNothing);
    final Inscription apres = (await inscriptionsEnBase(tester, env)).singleWhere((Inscription i) => i.clientId == bruno.id);
    expect(apres.statut, StatutInscription.confirmee);
    final Vente vente = await venteEnBase(tester, env, apres.venteId!);
    expect(vente.statutPaiement, StatutPaiement.payee);

    await env.fermer(tester);
  });

  testWidgets('annuler une personne en liste d’attente : elle quitte la liste', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final Client bruno = await unClient(tester, env, 'Bruno', 'Petit');
    final CoursFiche cours = await env.creerCours(tester, places: 1);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id);
    await env.inscrire(tester, coursId: cours.id, clientId: bruno.id);
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Liste d’attente (1)')));

    await toucher(tester, dansFiche(find.text('Bruno Petit')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    expect(find.text('Bruno Petit quittera la liste d’attente.'), findsOneWidget);
    await toucher(tester, find.widgetWithText(FilledButton, 'Annuler l’inscription'));
    await attendre(tester, message('Inscription annulée.'));
    await attendre(tester, dansFiche(find.text('Inscriptions annulées (1)')));

    expect(dansFiche(find.textContaining('Liste d’attente (')), findsNothing);
    final Inscription i = (await inscriptionsEnBase(tester, env)).singleWhere((Inscription x) => x.clientId == bruno.id);
    expect(i.statut, StatutInscription.annulee);

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Annulation d'une inscription : le choix se fait à chaque fois
  // ---------------------------------------------------------------------------

  testWidgets('annuler une inscription sans paiement : la vente est annulée avec elle', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    final ResultatInscription r = await env.inscrire(tester, coursId: cours.id, clientId: alice.id);
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Alice Durand')));

    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    expect(find.text('Annuler cette inscription ?'), findsOneWidget);
    expect(
      find.text('L’inscription de Alice Durand sera annulée, ainsi que sa vente (rien n’a été encaissé).'),
      findsOneWidget,
    );
    await toucher(tester, find.widgetWithText(FilledButton, 'Annuler l’inscription'));
    await attendre(tester, message('Inscription annulée.'));
    await attendre(tester, dansFiche(find.text('Inscrits (0)')));

    expect(dansFiche(find.text('Inscriptions annulées (1)')), findsOneWidget);
    expect((await inscriptionsEnBase(tester, env)).single.statut, StatutInscription.annulee);
    expect((await venteEnBase(tester, env, r.vente!.id)).statut, StatutVente.annulee);

    await env.fermer(tester);
  });

  testWidgets('annuler une inscription payée : « Annuler et rembourser » rembourse le paiement', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    final ResultatInscription r = await env.inscrire(
      tester,
      coursId: cours.id,
      clientId: alice.id,
      paiement: _toutEnEspeces,
    );
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Alice Durand')));

    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    expect(find.text('Alice Durand a déjà réglé ${formatEuros(4500)}. Que faire de ce paiement ?'), findsOneWidget);
    expect(find.text('Annuler en gardant le paiement'), findsOneWidget);
    await toucher(tester, find.text('Annuler et rembourser'));
    await attendre(tester, message('Inscription annulée, paiement remboursé.'));
    await attendre(tester, dansFiche(find.text('Inscriptions annulées (1)')));

    expect(dansFiche(find.text('Remboursé')), findsOneWidget);
    final Vente vente = await venteEnBase(tester, env, r.vente!.id);
    expect(vente.statut, StatutVente.annulee);
    expect(vente.statutPaiement, StatutPaiement.remboursee);
    expect(await netEncaisse(tester, env, vente.id), 0);
    expect((await inscriptionsEnBase(tester, env)).single.statut, StatutInscription.annulee);

    await env.fermer(tester);
  });

  testWidgets('annuler une inscription payée : « Annuler en gardant le paiement » ne touche pas à l’argent', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    final ResultatInscription r = await env.inscrire(
      tester,
      coursId: cours.id,
      clientId: alice.id,
      paiement: _acompteEnEspeces,
    );
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Alice Durand')));

    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    expect(find.text('Alice Durand a déjà réglé ${formatEuros(1500)}. Que faire de ce paiement ?'), findsOneWidget);
    await toucher(tester, find.text('Annuler en gardant le paiement'));
    await attendre(tester, message('Inscription annulée, paiement conservé.'));
    await attendre(tester, dansFiche(find.text('Inscriptions annulées (1)')));

    expect(dansFiche(find.text('Acompte versé')), findsOneWidget);
    final Vente vente = await venteEnBase(tester, env, r.vente!.id);
    expect(vente.statut, StatutVente.validee);
    expect(await netEncaisse(tester, env, vente.id), 1500);
    expect((await inscriptionsEnBase(tester, env)).single.statut, StatutInscription.annulee);

    await env.fermer(tester);
  });

  testWidgets('annuler une inscription : « Retour » ne change rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id, paiement: _toutEnEspeces);
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Alice Durand')));

    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, find.text('Retour'));

    expect(find.byType(AlertDialog), findsNothing);
    expect((await inscriptionsEnBase(tester, env)).single.statut, StatutInscription.confirmee);

    await env.fermer(tester);
  });

  // ---------------------------------------------------------------------------
  // Le cours lui-même : annuler, rétablir, archiver
  // ---------------------------------------------------------------------------

  testWidgets('annuler un cours : plus d’inscription possible, les inscrits restent à traiter un par un', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client alice = await unClient(tester, env, 'Alice', 'Durand');
    final CoursFiche cours = await env.creerCours(tester);
    await env.inscrire(tester, coursId: cours.id, clientId: alice.id, paiement: _toutEnEspeces);
    await ouvrirFiche(tester, env, cours);
    await attendre(tester, dansFiche(find.text('Alice Durand')));

    await choisirDansLeMenu(tester, 'Annuler le cours');
    expect(find.text('Annuler ce cours ?'), findsOneWidget);
    await toucher(tester, find.widgetWithText(FilledButton, 'Annuler le cours'));
    await attendre(tester, message('Cours annulé.'));
    await attendre(tester, dansFiche(find.text('Annulé')));

    expect(dansFiche(find.textContaining('Ce cours est annulé. Les inscriptions restent affichées')), findsOneWidget);
    expect(dansFiche(find.text('Ce cours est annulé : on ne peut plus y inscrire personne.')), findsOneWidget);
    expect(dansFiche(find.text('Inscrire quelqu’un')), findsNothing);
    // Les inscriptions ne sont pas touchées : Alice reste inscrite et payée.
    expect(dansFiche(find.text('Inscrits (1)')), findsOneWidget);
    expect((await inscriptionsEnBase(tester, env)).single.statut, StatutInscription.confirmee);

    // On peut encore traiter Alice : annuler son inscription et la rembourser.
    await toucher(tester, dansFiche(find.text('Alice Durand')));
    await attendre(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, dansFeuille(find.text('Annuler l’inscription')));
    await toucher(tester, find.text('Annuler et rembourser'));
    await attendre(tester, message('Inscription annulée, paiement remboursé.'));

    // Rétablir le cours le rouvre aux inscriptions.
    await choisirDansLeMenu(tester, 'Rétablir le cours');
    await attendre(tester, message('Cours rétabli.'));
    await attendre(tester, dansFiche(find.text('Inscrire quelqu’un')));
    expect(dansFiche(find.text('Annulé')), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('archiver : refusé pour un cours à venir, accepté pour un cours terminé, puis restauré', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final CoursFiche aVenir = await env.creerCours(tester, titre: 'Cours à venir');
    final CoursFiche passe = await env.creerCours(
      tester,
      titre: 'Cours terminé',
      debut: DateTime.now().subtract(const Duration(days: 10)),
    );

    await ouvrirFiche(tester, env, aVenir);
    await choisirDansLeMenu(tester, 'Archiver');
    await attendre(tester, message('Seul un cours terminé ou annulé peut être archivé.'));
    expect((await env.travailler(tester, () => env.cours.obtenir(aVenir.id)))!.archiveLe, isNull);

    await retourArriere(tester);
    await ouvrirRoute(tester, AppRoutes.coursFiche, arguments: passe.id);
    await attendre(tester, dansFiche(find.text('Terminé')));

    await choisirDansLeMenu(tester, 'Archiver');
    expect(find.text('Archiver ce cours ?'), findsOneWidget);
    await toucher(tester, find.widgetWithText(FilledButton, 'Archiver'));
    await attendre(tester, message('Cours archivé.'));
    await attendre(tester, dansFiche(find.text('Archivé')));
    expect((await env.travailler(tester, () => env.cours.obtenir(passe.id)))!.archiveLe, isNotNull);

    await choisirDansLeMenu(tester, 'Restaurer');
    await attendre(tester, message('Cours restauré dans la liste.'));
    expect((await env.travailler(tester, () => env.cours.obtenir(passe.id)))!.archiveLe, isNull);

    await env.fermer(tester);
  });
}
