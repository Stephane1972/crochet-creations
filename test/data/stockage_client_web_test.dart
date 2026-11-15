import 'dart:io';

import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/stockage_client_web.dart';
import 'package:crochet_creations/domain/id_client_google.dart';
import 'package:flutter_test/flutter_test.dart';

const String _id = '123456789012-abcdefghijklmnopqrstuvwxyz012345$suffixeIdClientGoogle';
const String _autreId = '987654321098-zyxwvutsrqponmlkjihgfedcba543210$suffixeIdClientGoogle';
const String _fourni = '555555555555-fournifournifournifourni00000000$suffixeIdClientGoogle';

void main() {
  late Directory dossier;
  late StockageClientWeb stockage;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('client_web_');
    stockage = StockageClientWeb(File('${dossier.path}/drive/client_web.txt'));
  });

  tearDown(() {
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  group('StockageClientWeb', () {
    test('rien d’enregistré au départ', () async {
      expect(await stockage.lire(), isNull);
    });

    test('un ID écrit se relit, même avec une nouvelle instance (le lancement suivant)', () async {
      await stockage.ecrire(_id);
      expect(await stockage.lire(), _id);
      expect(await StockageClientWeb(stockage.fichier).lire(), _id);
    });

    test('écrire remplace l’ID précédent et ne laisse aucun fichier provisoire', () async {
      await stockage.ecrire(_id);
      await stockage.ecrire(_autreId);
      expect(await stockage.lire(), _autreId);
      expect(File('${stockage.fichier.path}.tmp').existsSync(), isFalse);
    });

    test('effacer oublie l’ID, et effacer sans rien d’enregistré ne lève rien', () async {
      await stockage.effacer();
      await stockage.ecrire(_id);
      await stockage.effacer();
      expect(await stockage.lire(), isNull);
      expect(stockage.fichier.existsSync(), isFalse);
    });

    test('un fichier qui n’a pas la forme d’un ID est ignoré', () async {
      await stockage.fichier.parent.create(recursive: true);
      await stockage.fichier.writeAsString('n’importe quoi');
      expect(await stockage.lire(), isNull);
      await stockage.fichier.writeAsString('');
      expect(await stockage.lire(), isNull);
    });

    test('un fichier modifié à la main (espaces, retour à la ligne) se relit proprement', () async {
      await stockage.fichier.parent.create(recursive: true);
      await stockage.fichier.writeAsString('  $_id\n');
      expect(await stockage.lire(), _id);
    });
  });

  group('CompteGoogleReel : ID client Web saisi dans l’application', () {
    CompteGoogleReel compte({String fourni = '', String? enregistre}) =>
        CompteGoogleReel(clientWeb: fourni, clientWebEnregistre: enregistre, stockage: stockage);

    test('sans rien : pas configuré', () {
      final CompteGoogleReel c = compte();
      expect(c.configure, isFalse);
      expect(c.clientWeb, isEmpty);
      expect(c.clientWebEnregistre, isFalse);
      expect(c.redemarrageNecessaire, isFalse);
    });

    test('enregistrer un ID le nettoie, le garde sur le téléphone et configure la connexion', () async {
      final CompteGoogleReel c = compte();
      await c.enregistrerClientWeb('  $_id \n');

      expect(c.configure, isTrue);
      expect(c.clientWeb, _id);
      expect(c.clientWebEnregistre, isTrue);
      expect(c.redemarrageNecessaire, isFalse); // Google n'a pas encore été configuré depuis le lancement
      expect(await stockage.lire(), _id);

      // Au lancement suivant, main.dart relit le fichier.
      final CompteGoogleReel suivant = compte(enregistre: await stockage.lire());
      expect(suivant.configure, isTrue);
      expect(suivant.clientWeb, _id);
    });

    test('ce qui n’est pas un ID client est refusé, et rien n’est enregistré', () async {
      final CompteGoogleReel c = compte(fourni: _fourni);
      for (final String saisie in <String>['', 'bonjour', '${debutCodeSecretGoogle}AbCdEfGhIjKlMnOpQrStUvWxYz12']) {
        await expectLater(
          c.enregistrerClientWeb(saisie),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.annulee, 'annulee', isFalse)),
          reason: saisie,
        );
      }
      expect(await stockage.lire(), isNull);
      expect(c.clientWeb, _fourni);
      expect(c.clientWebEnregistre, isFalse);
    });

    test('l’ID saisi passe avant celui fourni avec l’application, et l’oublier revient au second', () async {
      final CompteGoogleReel c = compte(fourni: _fourni);
      expect(c.clientWeb, _fourni);

      await c.enregistrerClientWeb(_id);
      expect(c.clientWeb, _id);
      expect(c.clientWebEnregistre, isTrue);

      await c.oublierClientWeb();
      expect(c.clientWeb, _fourni);
      expect(c.clientWebEnregistre, isFalse);
      expect(await stockage.lire(), isNull);
    });

    test('oublier sans ID fourni : plus configuré', () async {
      final CompteGoogleReel c = compte();
      await c.enregistrerClientWeb(_id);
      await c.oublierClientWeb();
      expect(c.configure, isFalse);
    });

    test('un ID enregistré avant le lancement est utilisé tout de suite', () {
      final CompteGoogleReel c = compte(fourni: _fourni, enregistre: _autreId);
      expect(c.clientWeb, _autreId);
      expect(c.clientWebEnregistre, isTrue);
    });

    test('un enregistrement qui échoue (disque plein, dossier impossible) le dit, sans changer l’ID utilisé', () async {
      // Un fichier à la place du dossier « drive » : impossible d'y écrire.
      File('${dossier.path}/drive').writeAsStringSync('je suis un fichier');
      final CompteGoogleReel c = compte(fourni: _fourni);
      await expectLater(
        c.enregistrerClientWeb(_id),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Impossible d’enregistrer'))),
      );
      expect(c.clientWeb, _fourni);
      expect(c.clientWebEnregistre, isFalse);
    });
  });
}
