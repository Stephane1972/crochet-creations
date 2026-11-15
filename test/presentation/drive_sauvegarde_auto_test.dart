import 'dart:io';

import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/service_sauvegarde_drive.dart';
import 'package:crochet_creations/domain/drive_sauvegardes.dart';
import 'package:crochet_creations/presentation/drive/drive_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Vendredi 13 novembre 2026, 12 h 30.
final DateTime _maintenant = DateTime(2026, 11, 13, 12, 30);

const ProfilGoogle _camille = ProfilGoogle(email: 'camille@exemple.fr', nom: 'Camille');

/// Un téléphone avec une photo, connecté à Google, dont l'envoi automatique est [automatique].
Future<EnvironnementTest> _telephone(WidgetTester tester, {required bool automatique, bool connecte = true}) async {
  final EnvironnementTest env = await EnvironnementTest.creer(tester);
  env.maintenant = _maintenant;
  if (connecte) env.compteGoogle.dejaConnecte = _camille;
  await env.travailler(tester, () async {
    await env.dossierPhotos.create(recursive: true);
    await File('${env.dossierPhotos.path}/photo_1.jpg').writeAsString('photo un');
    if (automatique) await env.serviceSauvegardeDrive.reglerEnvoiAutomatique(actif: true);
  });
  return env;
}

/// « Ouvre l'application » : un conteneur tout neuf (les réglages, eux, sont ceux gardés sur le téléphone), puis ce que fait
/// l'application à son ouverture.
Future<SuiviSauvegardeDrive> _ouvrirApplication(WidgetTester tester, EnvironnementTest env) async {
  final ProviderContainer conteneur = ProviderContainer(overrides: env.overrides);
  addTearDown(conteneur.dispose);
  await env.travailler(tester, () => conteneur.read(sauvegardeDriveProvider.notifier).lancerSiBesoin());
  return conteneur.read(sauvegardeDriveProvider);
}

void main() {
  group('envoi automatique à l’ouverture de l’application', () {
    testWidgets('activé et connecté : la sauvegarde part toute seule', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephone(tester, automatique: true);

      final SuiviSauvegardeDrive suivi = await _ouvrirApplication(tester, env);

      expect(suivi.phase, PhaseSauvegardeDrive.termine);
      expect(suivi.automatique, isTrue);
      expect(suivi.resultat!.issue, IssueSauvegardeDrive.faite);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), <String>[nomSauvegardeDrive(_maintenant)]);
      expect(env.clientDrive.nomsDans('Photos des produits'), <String>['photo_1.jpg']);

      await env.fermer(tester);
    });

    testWidgets('désactivé (c’est le réglage de départ) : rien ne part', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephone(tester, automatique: false);

      final SuiviSauvegardeDrive suivi = await _ouvrirApplication(tester, env);

      expect(suivi.phase, PhaseSauvegardeDrive.repos);
      expect(env.clientDrive.envoyes, isEmpty);
      expect(env.clientDrive.fichiers, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('pas connecté à Google : rien ne part, et rien n’est dit', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephone(tester, automatique: true, connecte: false);

      final SuiviSauvegardeDrive suivi = await _ouvrirApplication(tester, env);

      expect(suivi.phase, PhaseSauvegardeDrive.repos);
      expect(env.clientDrive.envoyes, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('une seule fois par jour ; le lendemain, rien de neuf : pas de nouvelle sauvegarde', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephone(tester, automatique: true);
      await _ouvrirApplication(tester, env);
      final int envoyes = env.clientDrive.envoyes.length;

      // Plus tard le même jour : l'application est rouverte, rien ne se passe.
      env.maintenant = _maintenant.add(const Duration(hours: 5));
      final SuiviSauvegardeDrive memeJour = await _ouvrirApplication(tester, env);
      expect(memeJour.phase, PhaseSauvegardeDrive.repos);
      expect(env.clientDrive.envoyes, hasLength(envoyes));

      // Le lendemain : on regarde, mais comme rien n'a changé, aucune sauvegarde n'est ajoutée.
      env.maintenant = _maintenant.add(const Duration(days: 1, minutes: 1));
      final SuiviSauvegardeDrive lendemain = await _ouvrirApplication(tester, env);
      expect(lendemain.phase, PhaseSauvegardeDrive.termine);
      expect(lendemain.resultat!.issue, IssueSauvegardeDrive.dejaAJour);
      expect(env.clientDrive.nomsDans(nomDossierSauvegardesDrive), hasLength(1));
      expect(env.clientDrive.envoyes, hasLength(envoyes));

      await env.fermer(tester);
    });

    testWidgets('Google injoignable : l’échec est dit, et retenté à la prochaine ouverture', (WidgetTester tester) async {
      final EnvironnementTest env = await _telephone(tester, automatique: true);
      env.clientDrive.panne = const ErreurDrive('Pas de connexion à Internet.');

      final SuiviSauvegardeDrive echec = await _ouvrirApplication(tester, env);
      expect(echec.phase, PhaseSauvegardeDrive.erreur);
      expect(echec.automatique, isTrue);
      expect(echec.erreur, 'Pas de connexion à Internet.');
      expect(env.clientDrive.fichiers, isEmpty);

      // L'échec n'est pas noté comme un passage : même jour, la sauvegarde repart dès que le réseau est revenu.
      env.clientDrive.panne = null;
      final SuiviSauvegardeDrive reussite = await _ouvrirApplication(tester, env);
      expect(reussite.phase, PhaseSauvegardeDrive.termine);
      expect(reussite.resultat!.issue, IssueSauvegardeDrive.faite);

      await env.fermer(tester);
    });
  });
}
