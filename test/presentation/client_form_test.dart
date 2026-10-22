import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/clients/client_fiche_screen.dart';
import 'package:crochet_creations/presentation/clients/client_form_screen.dart';
import 'package:crochet_creations/presentation/clients/clients_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

Finder dansFormulaire(Finder cible) =>
    find.descendant(of: find.byType(ClientFormScreen), matching: cible);

Finder dansFiche(Finder cible) => find.descendant(of: find.byType(ClientFicheScreen), matching: cible);

/// Ouvre le formulaire de nouveau client depuis l'onglet Clients.
Future<void> ouvrirNouveauClient(WidgetTester tester, EnvironnementTest env) async {
  // Écran très haut : tout le formulaire est construit d'un coup.
  await ouvrirAccueil(tester, env, taille: const Size(800, 2400));
  await tester.tap(ongletNav('Clients'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(find.descendant(of: find.byType(ClientsScreen), matching: find.text('Ajouter')));
  await tester.pumpAndSettle();
}

/// Ouvre le formulaire de modification du client affiché [nom] : liste, fiche, puis « Modifier ».
Future<void> ouvrirModification(WidgetTester tester, EnvironnementTest env, String nom) async {
  await ouvrirAccueil(tester, env, taille: const Size(800, 2400));
  await tester.tap(ongletNav('Clients'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(find.descendant(of: find.byType(ClientsScreen), matching: find.text(nom)));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.tap(find.byTooltip('Modifier'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

String texteDuChamp(WidgetTester tester, String libelle) {
  return tester.widget<TextFormField>(find.widgetWithText(TextFormField, libelle)).controller!.text;
}

Future<void> appuyerSur(WidgetTester tester, String libelleBouton) async {
  await appuyer(tester, dansFormulaire(find.text(libelleBouton)));
}

Future<List<Client>> clientsEnregistres(WidgetTester tester, EnvironnementTest env) {
  return env.travailler(tester, () => env.clients.lister(inclureArchives: true));
}

void main() {
  testWidgets('le formulaire propose les champs d’un particulier', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    for (final String libelle in <String>[
      'Prénom',
      'Nom',
      'Téléphone',
      'E-mail',
      'Adresse',
      'Code postal',
      'Ville',
      'Notes',
    ]) {
      expect(find.widgetWithText(TextFormField, libelle), findsOneWidget, reason: libelle);
    }
    // Raison sociale et SIREN/SIRET : réservés aux professionnels.
    expect(find.widgetWithText(TextFormField, 'Raison sociale'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'SIREN ou SIRET'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('créer un particulier ouvre sa fiche', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    // Civilité : liste déroulante.
    await tester.tap(find.text('Non précisée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Madame').last);
    await tester.pumpAndSettle();

    await saisir(tester, 'Prénom', 'Camille');
    await saisir(tester, 'Nom', 'Martin');
    await saisir(tester, 'Téléphone', '06 12 34 56 78');
    await saisir(tester, 'E-mail', 'camille@exemple.fr');
    await saisir(tester, 'Adresse', '12 rue des Lilas');
    await saisir(tester, 'Code postal', '31000');
    await saisir(tester, 'Ville', 'Toulouse');
    await saisir(tester, 'Notes', 'Aime le beige');
    await appuyerSur(tester, 'Ajouter le client');
    await laisserFinir(tester);

    // On arrive sur la fiche du nouveau client.
    expect(find.byType(ClientFormScreen), findsNothing);
    expect(find.byType(ClientFicheScreen), findsOneWidget);
    expect(dansFiche(find.text('Camille Martin')), findsWidgets);
    expect(dansFiche(find.text('Madame')), findsOneWidget);
    expect(dansFiche(find.text('12 rue des Lilas\n31000 Toulouse')), findsOneWidget);
    expect(find.text('Client ajouté.'), findsOneWidget);

    final List<Client> clients = await clientsEnregistres(tester, env);
    expect(clients, hasLength(1));
    expect(clients.single.civilite, Civilite.madame);
    expect(clients.single.typeClient, TypeClient.particulier);
    expect(clients.single.telephone, '06 12 34 56 78');
    expect(clients.single.notes, 'Aime le beige');
    expect(clients.single.raisonSociale, isNull);
    expect(clients.single.siret, isNull);

    await env.fermer(tester);
  });

  testWidgets('sans nom, rien n’est enregistré et le champ le signale', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    await saisir(tester, 'Téléphone', '06 12 34 56 78');
    await appuyerSur(tester, 'Ajouter le client');

    expect(find.text('Indiquez au moins un prénom ou un nom.'), findsOneWidget);
    expect(find.text('Corrigez les champs signalés en rouge.'), findsOneWidget);
    expect(find.byType(ClientFormScreen), findsOneWidget);
    expect(await clientsEnregistres(tester, env), isEmpty);

    // Un prénom suffit.
    await saisir(tester, 'Prénom', 'Léa');
    await appuyerSur(tester, 'Ajouter le client');
    await laisserFinir(tester);
    expect(await clientsEnregistres(tester, env), hasLength(1));

    await env.fermer(tester);
  });

  testWidgets('e-mail, téléphone et code postal incorrects sont signalés', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    await saisir(tester, 'Prénom', 'Camille');
    await saisir(tester, 'Téléphone', 'abc');
    await saisir(tester, 'E-mail', 'camille-at-exemple');
    await saisir(tester, 'Code postal', '!!');
    await appuyerSur(tester, 'Ajouter le client');

    expect(find.text('Le numéro de téléphone n’est pas valide.'), findsOneWidget);
    expect(find.text('L’adresse e-mail n’est pas valide.'), findsOneWidget);
    expect(find.text('Le code postal n’est pas valide.'), findsOneWidget);
    expect(await clientsEnregistres(tester, env), isEmpty);

    // Une fois corrigés, l'enregistrement passe.
    await saisir(tester, 'Téléphone', '06 12 34 56 78');
    await saisir(tester, 'E-mail', 'camille@exemple.fr');
    await saisir(tester, 'Code postal', '31000');
    await appuyerSur(tester, 'Ajouter le client');
    await laisserFinir(tester);
    expect(await clientsEnregistres(tester, env), hasLength(1));

    await env.fermer(tester);
  });

  testWidgets('un professionnel : raison sociale et SIRET apparaissent et sont contrôlés', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    await tester.tap(dansFormulaire(find.text('Professionnel')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Raison sociale'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'SIREN ou SIRET'), findsOneWidget);
    expect(dansFormulaire(find.text('Personne à contacter')), findsOneWidget);

    // Sans nom d'entreprise, ni prénom, ni nom : refusé.
    await appuyerSur(tester, 'Ajouter le client');
    expect(find.text('Indiquez au moins une raison sociale, un prénom ou un nom.'), findsOneWidget);

    // SIRET incorrect : refusé.
    await saisir(tester, 'Raison sociale', 'Boutique La Pelote');
    await saisir(tester, 'SIREN ou SIRET', '1234');
    await appuyerSur(tester, 'Ajouter le client');
    expect(
      find.text('Le SIREN (9 chiffres) ou le SIRET (14 chiffres) n’est pas valide.'),
      findsOneWidget,
    );
    expect(await clientsEnregistres(tester, env), isEmpty);

    await saisir(tester, 'SIREN ou SIRET', '123 456 789 00012');
    await appuyerSur(tester, 'Ajouter le client');
    await laisserFinir(tester);

    expect(dansFiche(find.text('Boutique La Pelote')), findsWidgets);
    expect(dansFiche(find.text('123 456 789 00012')), findsOneWidget);
    final List<Client> clients = await clientsEnregistres(tester, env);
    expect(clients.single.typeClient, TypeClient.professionnel);
    expect(clients.single.raisonSociale, 'Boutique La Pelote');
    expect(clients.single.siret, '123 456 789 00012');

    await env.fermer(tester);
  });

  testWidgets('repasser en « Particulier » n’enregistre ni raison sociale ni SIRET', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    await tester.tap(dansFormulaire(find.text('Professionnel')));
    await tester.pumpAndSettle();
    await saisir(tester, 'Raison sociale', 'Atelier Test');
    await saisir(tester, 'SIREN ou SIRET', '123456789');
    await tester.tap(dansFormulaire(find.text('Particulier')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Raison sociale'), findsNothing);

    await saisir(tester, 'Prénom', 'Camille');
    await appuyerSur(tester, 'Ajouter le client');
    await laisserFinir(tester);

    final Client client = (await clientsEnregistres(tester, env)).single;
    expect(client.typeClient, TypeClient.particulier);
    expect(client.raisonSociale, isNull);
    expect(client.siret, isNull);

    await env.fermer(tester);
  });

  testWidgets('modifier un client : champs préremplis, puis retour à la fiche mise à jour', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    final Client c = await env.creerClient(
      tester,
      const DonneesClient(
        civilite: Civilite.madame,
        prenom: 'Camille',
        nom: 'Martin',
        telephone: '06 12 34 56 78',
        ville: 'Toulouse',
      ),
    );
    await ouvrirModification(tester, env, 'Camille Martin');

    expect(find.byType(ClientFormScreen), findsOneWidget);
    expect(dansFormulaire(find.text('Modifier le client')), findsOneWidget);
    expect(texteDuChamp(tester, 'Prénom'), 'Camille');
    expect(texteDuChamp(tester, 'Nom'), 'Martin');
    expect(texteDuChamp(tester, 'Téléphone'), '06 12 34 56 78');
    expect(texteDuChamp(tester, 'Ville'), 'Toulouse');
    expect(dansFormulaire(find.text('Madame')), findsOneWidget);

    await saisir(tester, 'Ville', 'Albi');
    await appuyerSur(tester, 'Enregistrer les modifications');
    await laisserFinir(tester);

    // On revient sur la fiche, qui montre la nouvelle ville.
    expect(find.byType(ClientFormScreen), findsNothing);
    expect(find.byType(ClientFicheScreen), findsOneWidget);
    expect(dansFiche(find.text('Albi')), findsOneWidget);
    expect(find.text('Modifications enregistrées.'), findsOneWidget);
    expect((await env.travailler(tester, () => env.clients.obtenir(c.id)))!.ville, 'Albi');

    await env.fermer(tester);
  });

  testWidgets('quitter un formulaire modifié demande confirmation', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    await saisir(tester, 'Nom', 'Martin');

    // On choisit de continuer la saisie.
    await retourArriere(tester);
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);
    await tester.tap(find.text('Continuer la saisie'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientFormScreen), findsOneWidget);
    expect(texteDuChamp(tester, 'Nom'), 'Martin');

    // On abandonne : on revient à la liste, rien n'est enregistré.
    await retourArriere(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientFormScreen), findsNothing);
    expect(await clientsEnregistres(tester, env), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('quitter un formulaire intact ne demande rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirNouveauClient(tester, env);

    await retourArriere(tester);

    expect(find.text('Abandonner les modifications ?'), findsNothing);
    expect(find.byType(ClientFormScreen), findsNothing);

    await env.fermer(tester);
  });
}
