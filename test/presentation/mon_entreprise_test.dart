import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/regles_entreprise.dart';
import 'package:crochet_creations/presentation/entreprise/mon_entreprise_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

Finder dansProfil(Finder cible) => find.descendant(of: find.byType(MonEntrepriseScreen), matching: cible);

Finder champ(String libelle) => find.widgetWithText(TextFormField, libelle);

String texteDuChamp(WidgetTester tester, String libelle) =>
    tester.widget<TextFormField>(champ(libelle)).controller!.text;

/// Onglet Plus → Réglages → Mon entreprise.
Future<void> ouvrirProfil(WidgetTester tester, EnvironnementTest env) async {
  // Écran très haut : tout le formulaire est construit d'un coup.
  await ouvrirAccueil(tester, env, taille: const Size(800, 2400));
  await tester.tap(ongletNav('Plus'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Réglages'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mon entreprise'));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// « Enregistrer » de la barre du haut.
Future<void> enregistrer(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
  await tester.pump();
  await laisserFinir(tester);
  await tester.pumpAndSettle();
}

Future<Entreprise> profilEnregistre(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.parametres.lire());

void main() {
  testWidgets('le formulaire propose les champs du profil, avec les valeurs par défaut', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);

    expect(dansProfil(find.text('Mon entreprise')), findsOneWidget);
    for (final String libelle in <String>[
      'Nom de l’entreprise',
      'Votre nom (facultatif)',
      'SIREN',
      'Adresse',
      'Code postal',
      'Ville',
      'Téléphone (facultatif)',
      'E-mail (facultatif)',
      'Conditions de paiement',
      'IBAN (facultatif)',
      'Message de remerciement',
    ]) {
      expect(champ(libelle), findsOneWidget, reason: libelle);
    }
    expect(texteDuChamp(tester, 'Conditions de paiement'), conditionsPaiementParDefaut);
    expect(texteDuChamp(tester, 'Message de remerciement'), remerciementParDefaut);
    expect(texteDuChamp(tester, 'Nom de l’entreprise'), isEmpty);
    // La mention de franchise de TVA est automatique : on l'affiche, on ne la demande pas.
    expect(dansProfil(find.textContaining('TVA non applicable, article 293 B du CGI')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('enregistre le profil, SIREN sans espaces et IBAN mis en forme, puis revient aux réglages', (
    WidgetTester tester,
  ) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);

    await saisir(tester, 'Nom de l’entreprise', 'Crochet & Créations');
    await saisir(tester, 'Votre nom (facultatif)', 'Camille Martin');
    await saisir(tester, 'SIREN', '123 456 789');
    await saisir(tester, 'Adresse', '12 rue des Lilas');
    await saisir(tester, 'Code postal', '31000');
    await saisir(tester, 'Ville', 'Toulouse');
    await saisir(tester, 'Téléphone (facultatif)', '06 12 34 56 78');
    await saisir(tester, 'E-mail (facultatif)', 'contact@exemple.fr');
    await saisir(tester, 'IBAN (facultatif)', 'fr1420041010050500013m02606');
    await saisir(tester, 'Message de remerciement', 'Merci et à bientôt !');
    await enregistrer(tester);

    expect(find.byType(MonEntrepriseScreen), findsNothing);
    expect(find.text('Profil enregistré.'), findsWidgets);
    final Entreprise e = await profilEnregistre(tester, env);
    expect(e.nomCommercial, 'Crochet & Créations');
    expect(e.nomResponsable, 'Camille Martin');
    expect(e.siren, '123456789');
    expect(e.adresse, '12 rue des Lilas');
    expect(e.codePostal, '31000');
    expect(e.ville, 'Toulouse');
    expect(e.iban, 'FR14 2004 1010 0505 0001 3M02 606');
    expect(e.messageRemerciement, 'Merci et à bientôt !');
    expect(e.conditionsPaiement, conditionsPaiementParDefaut);

    await env.fermer(tester);
  });

  testWidgets('rouvre le profil avec ce qui a été enregistré', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await env.travailler(
      tester,
      () => env.parametres.enregistrerProfil(
        const DonneesEntreprise(nomCommercial: 'Atelier Laine', siren: '987654321', ville: 'Lyon'),
      ),
    );
    await ouvrirProfil(tester, env);

    expect(texteDuChamp(tester, 'Nom de l’entreprise'), 'Atelier Laine');
    expect(texteDuChamp(tester, 'SIREN'), '987654321');
    expect(texteDuChamp(tester, 'Ville'), 'Lyon');
    expect(texteDuChamp(tester, 'Adresse'), isEmpty);

    await env.fermer(tester);
  });

  testWidgets('un SIREN trop court est signalé et rien n’est enregistré', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);

    await saisir(tester, 'Nom de l’entreprise', 'Atelier Laine');
    await saisir(tester, 'SIREN', '1234');
    await enregistrer(tester);

    expect(find.byType(MonEntrepriseScreen), findsOneWidget);
    expect(dansProfil(find.text('Le SIREN comporte 9 chiffres.')), findsOneWidget);
    expect(find.text('Corrigez les champs signalés en rouge.'), findsWidgets);
    expect((await profilEnregistre(tester, env)).nomCommercial, '');

    await env.fermer(tester);
  });

  testWidgets('un SIRET saisi à la place du SIREN est expliqué', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);

    await saisir(tester, 'SIREN', '123 456 789 00012');
    await enregistrer(tester);

    expect(dansProfil(find.textContaining('C’est un SIRET (14 chiffres)')), findsOneWidget);

    await env.fermer(tester);
  });

  testWidgets('un IBAN dont la clé est fausse est refusé', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);

    await saisir(tester, 'IBAN (facultatif)', 'FR14 2004 1010 0505 0001 3M02 607');
    await enregistrer(tester);

    expect(dansProfil(find.text('IBAN incorrect : vérifiez les chiffres et les lettres.')), findsOneWidget);
    expect((await profilEnregistre(tester, env)).iban, isNull);

    await env.fermer(tester);
  });

  testWidgets('quitter sans rien changer ne demande rien', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);

    await retourArriere(tester);

    expect(find.byType(MonEntrepriseScreen), findsNothing);
    expect(find.text('Abandonner les modifications ?'), findsNothing);

    await env.fermer(tester);
  });

  testWidgets('quitter après une modification demande confirmation', (WidgetTester tester) async {
    final EnvironnementTest env = await EnvironnementTest.creer(tester);
    await ouvrirProfil(tester, env);
    await saisir(tester, 'Nom de l’entreprise', 'Atelier Laine');

    await retourArriere(tester);
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);

    // On continue la saisie : le formulaire reste ouvert, avec le texte saisi.
    await tester.tap(find.widgetWithText(TextButton, 'Continuer la saisie'));
    await tester.pumpAndSettle();
    expect(find.byType(MonEntrepriseScreen), findsOneWidget);
    expect(texteDuChamp(tester, 'Nom de l’entreprise'), 'Atelier Laine');

    // On abandonne : retour aux réglages, rien d'enregistré.
    await retourArriere(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
    await tester.pumpAndSettle();
    expect(find.byType(MonEntrepriseScreen), findsNothing);
    expect((await profilEnregistre(tester, env)).nomCommercial, '');

    await env.fermer(tester);
  });
}
