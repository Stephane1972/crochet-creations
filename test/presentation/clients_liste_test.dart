import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/clients/client_fiche_screen.dart';
import 'package:crochet_creations/presentation/clients/client_form_screen.dart';
import 'package:crochet_creations/presentation/clients/clients_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

/// Cherche dans l'onglet Clients uniquement (les autres onglets restent construits mais masqués).
Finder dansClients(Finder cible) => find.descendant(of: find.byType(ClientsScreen), matching: cible);

Future<void> ouvrirClients(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env);
  await tester.tap(ongletNav('Clients'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Trois clients : une particulière, une boutique (professionnelle) et une autre particulière.
Future<void> garnirClients(WidgetTester tester, EnvironnementTest env) async {
  await env.creerClient(
    tester,
    const DonneesClient(
      civilite: Civilite.madame,
      prenom: 'Camille',
      nom: 'Martin',
      telephone: '06 12 34 56 78',
      codePostal: '31000',
      ville: 'Toulouse',
    ),
  );
  await env.creerClient(
    tester,
    const DonneesClient(
      typeClient: TypeClient.professionnel,
      raisonSociale: 'Boutique La Pelote',
      prenom: 'Julie',
      nom: 'Roux',
      email: 'julie@lapelote.fr',
    ),
  );
  await env.creerClient(tester, const DonneesClient(prenom: 'Zoé', nom: 'Bernard'));
}

Future<void> chercher(WidgetTester tester, String texte) async {
  await tester.enterText(dansClients(find.byType(TextField)), texte);
  await tester.pump();
}

void main() {
  testWidgets('aucun client : message d’accueil et bouton « Ajouter »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirClients(tester, env);

    expect(find.text('Aucun client pour le moment'), findsOneWidget);
    expect(find.textContaining('client de passage'), findsOneWidget);
    expect(dansClients(find.text('Ajouter')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('la liste affiche nom, coordonnées et étiquettes, triés par nom', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirClients(tester, env);
    await ouvrirClients(tester, env);

    // Un professionnel s'affiche sous sa raison sociale, avec la personne à contacter dessous.
    expect(find.text('Boutique La Pelote'), findsOneWidget);
    expect(find.text('Julie Roux'), findsOneWidget);
    expect(find.text('Camille Martin'), findsOneWidget);
    expect(find.text('06 12 34 56 78 · 31000 Toulouse'), findsOneWidget);
    expect(find.text('Zoé Bernard'), findsOneWidget);
    expect(find.text('Professionnel'), findsOneWidget); // l'étiquette de la boutique

    // Ordre alphabétique du nom affiché : Boutique, Camille, Zoé.
    final double boutique = tester.getTopLeft(find.text('Boutique La Pelote')).dy;
    final double camille = tester.getTopLeft(find.text('Camille Martin')).dy;
    final double zoe = tester.getTopLeft(find.text('Zoé Bernard')).dy;
    expect(boutique, lessThan(camille));
    expect(camille, lessThan(zoe));

    await env.fermer(tester);
  });

  testWidgets('la recherche ignore accents et majuscules, trouve aussi par téléphone', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirClients(tester, env);
    await ouvrirClients(tester, env);

    await chercher(tester, 'ZOE');
    expect(find.text('Zoé Bernard'), findsOneWidget);
    expect(find.text('Camille Martin'), findsNothing);

    // Le numéro est trouvé même sans les espaces.
    await chercher(tester, '0612');
    expect(find.text('Camille Martin'), findsOneWidget);
    expect(find.text('Zoé Bernard'), findsNothing);

    // Cherche aussi dans l'e-mail (julie@lapelote.fr).
    await chercher(tester, 'lapelote');
    expect(find.text('Boutique La Pelote'), findsOneWidget);
    expect(find.text('Camille Martin'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('aucun résultat : message et bouton pour retirer les filtres', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirClients(tester, env);
    await ouvrirClients(tester, env);

    await chercher(tester, 'introuvable');
    expect(find.text('Aucun client trouvé'), findsOneWidget);
    expect(find.text('Aucun client pour le moment'), findsNothing);

    await tester.tap(find.text('Retirer les filtres'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun client trouvé'), findsNothing);
    expect(find.text('Camille Martin'), findsOneWidget);
    expect(find.text('Zoé Bernard'), findsOneWidget);
    // La zone de recherche a été vidée.
    expect(tester.widget<TextField>(dansClients(find.byType(TextField))).controller!.text, isEmpty);

    await env.fermer(tester);
  });

  testWidgets('filtres « Particuliers » et « Professionnels »', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirClients(tester, env);
    await ouvrirClients(tester, env);

    await tester.tap(dansClients(find.text('Professionnels')));
    await tester.pumpAndSettle();
    expect(find.text('Boutique La Pelote'), findsOneWidget);
    expect(find.text('Camille Martin'), findsNothing);
    expect(find.text('Zoé Bernard'), findsNothing);

    await tester.tap(dansClients(find.text('Particuliers')));
    await tester.pumpAndSettle();
    expect(find.text('Boutique La Pelote'), findsNothing);
    expect(find.text('Camille Martin'), findsOneWidget);
    expect(find.text('Zoé Bernard'), findsOneWidget);

    await tester.tap(dansClients(find.text('Tous')));
    await tester.pumpAndSettle();
    expect(find.text('Boutique La Pelote'), findsOneWidget);
    expect(find.text('Camille Martin'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('les clients archivés sont masqués, sauf avec le filtre « Archivés »', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirClients(tester, env);
    final clients = await env.travailler(tester, () => env.clients.lister());
    final zoe = clients.firstWhere((c) => c.prenom == 'Zoé');
    await env.travailler(tester, () => env.clients.archiver(zoe.id));
    await ouvrirClients(tester, env);

    expect(find.text('Zoé Bernard'), findsNothing);
    expect(find.text('Camille Martin'), findsOneWidget);

    await tester.tap(dansClients(find.text('Archivés')));
    await tester.pumpAndSettle();
    expect(find.text('Zoé Bernard'), findsOneWidget);
    expect(find.text('Archivé'), findsOneWidget); // l'étiquette sur sa carte

    await env.fermer(tester);
  });

  testWidgets('un client ajouté apparaît tout de suite dans la liste ouverte', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirClients(tester, env);
    expect(find.text('Aucun client pour le moment'), findsOneWidget);

    await env.creerClient(tester, const DonneesClient(prenom: 'Léa', nom: 'Roux'));
    await laisserFinir(tester);

    expect(find.text('Aucun client pour le moment'), findsNothing);
    expect(find.text('Léa Roux'), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('toucher un client ouvre sa fiche', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await garnirClients(tester, env);
    await ouvrirClients(tester, env);

    await tester.tap(dansClients(find.text('Camille Martin')));
    await tester.pumpAndSettle();
    await laisserFinir(tester);

    expect(find.byType(ClientFicheScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ClientFicheScreen), matching: find.text('Coordonnées')),
      findsOneWidget,
    );

    await env.fermer(tester);
  });

  testWidgets('« Ajouter » ouvre le formulaire de nouveau client', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirClients(tester, env);

    await tester.tap(dansClients(find.text('Ajouter')));
    await tester.pumpAndSettle();

    expect(find.byType(ClientFormScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ClientFormScreen), matching: find.text('Nouveau client')),
      findsOneWidget,
    );

    await env.fermer(tester);
  });
}
