import 'package:crochet_creations/domain/id_client_google.dart';
import 'package:flutter_test/flutter_test.dart';

const String _id = '123456789012-abcdefghijklmnopqrstuvwxyz012345$suffixeIdClientGoogle';

void main() {
  group('nettoyerIdClientWeb', () {
    test('ne change pas un ID propre', () {
      expect(nettoyerIdClientWeb(_id), _id);
    });

    test('retire les espaces, les retours à la ligne et les tabulations', () {
      expect(nettoyerIdClientWeb('  $_id \n'), _id);
      expect(nettoyerIdClientWeb('123456789012-abcdefghijkl\n  mnopqrstuvwxyz012345.apps.\tgoogleusercontent.com'), _id);
    });

    test('retire les guillemets et les virgules autour', () {
      expect(nettoyerIdClientWeb('"$_id"'), _id);
      expect(nettoyerIdClientWeb('“$_id”,'), _id);
      expect(nettoyerIdClientWeb("'$_id';"), _id);
    });

    test('du vide reste vide', () {
      expect(nettoyerIdClientWeb('   \n'), '');
    });
  });

  group('erreurIdClientWeb', () {
    test('un ID client Google est accepté', () {
      expect(erreurIdClientWeb(_id), isNull);
      expect(erreurIdClientWeb('987654321-a1b2c3d4e5f6$suffixeIdClientGoogle'), isNull);
      expect(erreurIdClientWeb('123456789012-abc_def-ghi123$suffixeIdClientGoogle'), isNull);
    });

    test('vide : on demande de le coller', () {
      expect(erreurIdClientWeb(''), contains('Collez l’ID client Web'));
    });

    test('un code secret est refusé, avec une explication', () {
      final String? erreur = erreurIdClientWeb('${debutCodeSecretGoogle}AbCdEfGhIjKlMnOpQrStUvWxYz12');
      expect(erreur, contains('code secret'));
      expect(erreur, contains('ne le collez pas'));
    });

    test('ce qui ne se termine pas comme un ID client est refusé', () {
      expect(erreurIdClientWeb('bonjour'), contains('doit se terminer par $suffixeIdClientGoogle'));
      expect(erreurIdClientWeb('123456789012-abcdefgh'), contains('doit se terminer par'));
      expect(erreurIdClientWeb('$_id.txt'), contains('doit se terminer par'));
    });

    test('une forme impossible est refusée : il manque le numéro, le tiret ou la suite', () {
      for (final String id in <String>[
        'abcdefgh$suffixeIdClientGoogle',
        '123456789012$suffixeIdClientGoogle',
        '123456789012-$suffixeIdClientGoogle',
        '123456789012-abc$suffixeIdClientGoogle',
        'projet-abcdefghij$suffixeIdClientGoogle',
        '123456789012-abcdé fghij$suffixeIdClientGoogle',
      ]) {
        expect(erreurIdClientWeb(id), contains('pas la forme attendue'), reason: id);
      }
    });
  });
}
