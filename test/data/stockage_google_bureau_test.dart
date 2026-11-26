import 'dart:convert';
import 'dart:io';

import 'package:crochet_creations/data/drive/stockage_google_bureau.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dossier;
  late StockageGoogleBureau stockage;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('stockage_bureau_test');
    // Un sous-dossier qui n'existe pas encore : le stockage doit le créer.
    stockage = StockageGoogleBureau(File('${dossier.path}${Platform.pathSeparator}drive${Platform.pathSeparator}google_bureau.json'));
  });

  tearDown(() => dossier.deleteSync(recursive: true));

  test('sans fichier : des réglages vides', () async {
    final ReglagesGoogleBureau r = await stockage.lire();

    expect(r.clientId, isEmpty);
    expect(r.codeSecret, isEmpty);
    expect(r.jetonActualisation, isNull);
    expect(r.email, isEmpty);
    expect(r.nom, isNull);
    expect(r.agenda, isFalse);
  });

  test('le droit « Google Agenda » est gardé ; un ancien fichier qui n’en parle pas le donne comme non accordé', () async {
    await stockage.ecrire(
      const ReglagesGoogleBureau(clientId: 'id.apps.googleusercontent.com', jetonActualisation: 'actualisation', agenda: true),
    );
    expect((await stockage.lire()).agenda, isTrue);

    await stockage.fichier.writeAsString(
      jsonEncode(<String, Object?>{'clientId': 'id.apps.googleusercontent.com', 'jetonActualisation': 'actualisation'}),
    );
    expect((await stockage.lire()).agenda, isFalse);

    // Oublier l'autorisation (déconnexion) oublie aussi le droit « agenda ».
    const ReglagesGoogleBureau connecte = ReglagesGoogleBureau(jetonActualisation: 'actualisation', agenda: true);
    expect(connecte.copier(oublierJeton: true).agenda, isFalse);
    expect(connecte.copier(email: 'stef@exemple.fr').agenda, isTrue);
    expect(connecte.copier(agenda: false).agenda, isFalse);
  });

  test('ce qui est écrit est relu à l’identique, accents compris, sans fichier provisoire oublié', () async {
    await stockage.ecrire(
      const ReglagesGoogleBureau(
        clientId: 'id.apps.googleusercontent.com',
        codeSecret: 'GOCSPX-secret',
        jetonActualisation: 'actualisation',
        email: 'stef@exemple.fr',
        nom: 'Stéphane',
      ),
    );

    final ReglagesGoogleBureau r = await stockage.lire();
    expect(r.clientId, 'id.apps.googleusercontent.com');
    expect(r.codeSecret, 'GOCSPX-secret');
    expect(r.jetonActualisation, 'actualisation');
    expect(r.email, 'stef@exemple.fr');
    expect(r.nom, 'Stéphane');
    expect(File('${stockage.fichier.path}.tmp').existsSync(), isFalse);
  });

  test('un fichier abîmé ou d’une autre forme est ignoré : réglages vides, sans erreur', () async {
    await stockage.fichier.parent.create(recursive: true);
    await stockage.fichier.writeAsString('{ pas du json');
    expect((await stockage.lire()).clientId, isEmpty);

    await stockage.fichier.writeAsString(jsonEncode(<String>['liste', 'au', 'lieu', 'd’un', 'objet']));
    expect((await stockage.lire()).clientId, isEmpty);

    await stockage.fichier.writeAsString(jsonEncode(<String, Object?>{'clientId': 42, 'jetonActualisation': '', 'nom': ''}));
    final ReglagesGoogleBureau r = await stockage.lire();
    expect(r.clientId, isEmpty);
    expect(r.jetonActualisation, isNull);
    expect(r.nom, isNull);
  });

  test('copier remplace ce qu’on lui donne et oublierJeton retire l’autorisation et le compte, pas l’accès', () {
    const ReglagesGoogleBureau depart = ReglagesGoogleBureau(
      clientId: 'id',
      codeSecret: 'secret',
      jetonActualisation: 'actualisation',
      email: 'a@b.fr',
      nom: 'A',
    );

    final ReglagesGoogleBureau autre = depart.copier(clientId: 'autre');
    expect(autre.clientId, 'autre');
    expect(autre.jetonActualisation, 'actualisation');

    final ReglagesGoogleBureau deconnecte = depart.copier(oublierJeton: true);
    expect(deconnecte.clientId, 'id');
    expect(deconnecte.codeSecret, 'secret');
    expect(deconnecte.jetonActualisation, isNull);
    expect(deconnecte.email, isEmpty);
    expect(deconnecte.nom, isNull);
  });

  test('effacer supprime le fichier, et ne se plaint pas s’il n’existe pas', () async {
    await stockage.effacer();
    await stockage.ecrire(const ReglagesGoogleBureau(clientId: 'id'));
    expect(stockage.fichier.existsSync(), isTrue);

    await stockage.effacer();

    expect(stockage.fichier.existsSync(), isFalse);
  });
}
