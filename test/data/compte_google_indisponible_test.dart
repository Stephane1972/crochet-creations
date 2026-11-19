import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/compte_google_indisponible.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompteGoogleIndisponible', () {
    const CompteGoogleIndisponible compte = CompteGoogleIndisponible();

    test('n’est jamais connecté et ne se configure pas', () async {
      expect(compte.configure, isFalse);
      expect(compte.clientWeb, isEmpty);
      expect(compte.clientWebEnregistre, isFalse);
      expect(compte.redemarrageNecessaire, isFalse);
      expect(await compte.restaurer(), isNull);
    });

    test('se connecter, saisir un ID ou demander un jeton : une erreur claire, sans rien contacter', () async {
      await expectLater(compte.seConnecter(), throwsA(isA<ErreurDrive>().having((e) => e.message, 'message', contains('Windows'))));
      await expectLater(compte.enregistrerClientWeb('abc'), throwsA(isA<ErreurDrive>()));
      await expectLater(compte.jetonAcces(), throwsA(isA<ErreurDrive>()));
    });

    test('se déconnecter, oublier l’ID ou invalider le jeton ne fait rien', () async {
      await compte.seDeconnecter();
      await compte.oublierClientWeb();
      compte.invaliderJeton();
    });
  });
}
