import 'package:crochet_creations/domain/lieux_vente.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lieux de départ', () {
    test('quatre lieux, dans l’ordre, sans doublon', () {
      expect(lieuxDeDepart.map((LieuDeDepart l) => l.nom), <String>['Marché', 'Salon', 'Boutique', 'Vente en ligne']);
      expect(lieuxDeDepart.map((LieuDeDepart l) => l.nom).toSet(), hasLength(lieuxDeDepart.length));
    });

    test('aucun lieu de départ n’est refusé par les règles de nom', () {
      for (final LieuDeDepart l in lieuxDeDepart) {
        expect(erreurNomLieu(l.nom), isNull, reason: l.nom);
      }
    });
  });

  group('nettoyerNomLieu', () {
    test('retire les espaces au début, à la fin et en double', () {
      expect(nettoyerNomLieu('  Marché   de   Noël  '), 'Marché de Noël');
      expect(nettoyerNomLieu('Salon\t des\n artisans'), 'Salon des artisans');
    });

    test('un nom absent devient un texte vide', () {
      expect(nettoyerNomLieu(null), '');
      expect(nettoyerNomLieu('   '), '');
    });
  });

  group('erreurNomLieu', () {
    test('un nom ordinaire est accepté', () {
      expect(erreurNomLieu('Marché de Noël'), isNull);
      expect(erreurNomLieu('  Fête du village '), isNull);
    });

    test('un nom vide ou fait d’espaces est refusé', () {
      expect(erreurNomLieu(null), contains('Donnez un nom'));
      expect(erreurNomLieu(''), contains('Donnez un nom'));
      expect(erreurNomLieu('   '), contains('Donnez un nom'));
    });

    test('un nom trop long est refusé, à la limite exacte il passe', () {
      expect(erreurNomLieu('a' * longueurMaxNomLieu), isNull);
      expect(erreurNomLieu('a' * (longueurMaxNomLieu + 1)), contains('limité à $longueurMaxNomLieu'));
    });

    test('« Non renseigné » est réservé, quelles que soient les majuscules et les accents', () {
      expect(erreurNomLieu('Non renseigné'), isNotNull);
      expect(erreurNomLieu('  NON  RENSEIGNE '), isNotNull);
      expect(erreurNomLieu('non renseigné'), contains('vente sans lieu'));
    });
  });

  group('memeNomLieu', () {
    test('ignore les majuscules, les accents et les espaces', () {
      expect(memeNomLieu('Marché', 'marche'), isTrue);
      expect(memeNomLieu(' Vente  en ligne ', 'VENTE EN LIGNE'), isTrue);
    });

    test('deux noms différents ne se confondent pas', () {
      expect(memeNomLieu('Marché', 'Salon'), isFalse);
      expect(memeNomLieu('Marché', 'Marchés'), isFalse);
    });
  });
}
