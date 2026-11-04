import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catégories de départ', () {
    test('les cinq clés sont celles de l’ancien enum : les produits et les anciennes sauvegardes les utilisent', () {
      expect(<String>[
        CleCategorie.crochet,
        CleCategorie.doudou,
        CleCategorie.bouclesOreilles,
        CleCategorie.accessoire,
        CleCategorie.surMesure,
      ], <String>['crochet', 'doudou', 'bouclesOreilles', 'accessoire', 'surMesure']);
    });

    test('elles s’affichent dans l’ordre habituel, avec les noms habituels', () {
      expect(categoriesDeDepart.map((CategorieDeDepart c) => c.cle), <String>[
        'crochet',
        'doudou',
        'bouclesOreilles',
        'accessoire',
        'surMesure',
      ]);
      expect(categoriesDeDepart.map((CategorieDeDepart c) => c.nom), <String>[
        'Crochet',
        'Doudou',
        'Boucles d’oreilles',
        'Accessoire',
        'Sur mesure',
      ]);
    });
  });

  group('nom d’une catégorie', () {
    test('les espaces en trop sont retirés', () {
      expect(nettoyerNomCategorie('  Pochettes   en   coton '), 'Pochettes en coton');
      expect(nettoyerNomCategorie(null), '');
    });

    test('un nom vide est refusé', () {
      expect(erreurNomCategorie(''), 'Donnez un nom à la catégorie.');
      expect(erreurNomCategorie('   '), 'Donnez un nom à la catégorie.');
      expect(erreurNomCategorie(null), 'Donnez un nom à la catégorie.');
    });

    test('60 caractères au plus', () {
      expect(erreurNomCategorie('a' * 60), isNull);
      expect(erreurNomCategorie('a' * 61), 'Le nom d’une catégorie est limité à 60 caractères.');
    });

    test('un nom ordinaire est accepté', () {
      expect(erreurNomCategorie('Peluches'), isNull);
    });

    test('deux noms ne différant que par les majuscules, les accents ou les espaces sont les mêmes', () {
      expect(memeNomCategorie('Doudou', ' doudou '), isTrue);
      expect(memeNomCategorie('Écharpes', 'echarpes'), isTrue);
      expect(memeNomCategorie('Sur  mesure', 'sur mesure'), isTrue);
      expect(memeNomCategorie('Doudou', 'Doudous'), isFalse);
    });
  });
}
