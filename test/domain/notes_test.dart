import 'package:crochet_creations/domain/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catégories de départ', () {
    test('deux catégories, dans l’ordre, sans doublon', () {
      expect(
        categoriesNoteDeDepart.map((CategorieNoteDeDepart c) => c.nom),
        <String>['Futures commandes', 'Documents entreprise'],
      );
    });

    test('aucune catégorie de départ n’est refusée par les règles de nom', () {
      for (final CategorieNoteDeDepart c in categoriesNoteDeDepart) {
        expect(erreurNomCategorieNote(c.nom), isNull, reason: c.nom);
      }
    });
  });

  group('nettoyerNomCategorieNote', () {
    test('retire les espaces au début, à la fin et en double', () {
      expect(nettoyerNomCategorieNote('  Idées   de   modèles  '), 'Idées de modèles');
      expect(nettoyerNomCategorieNote('Papiers\t de\n l’entreprise'), 'Papiers de l’entreprise');
    });

    test('un nom absent devient un texte vide', () {
      expect(nettoyerNomCategorieNote(null), '');
      expect(nettoyerNomCategorieNote('   '), '');
    });
  });

  group('erreurNomCategorieNote', () {
    test('un nom ordinaire est accepté', () {
      expect(erreurNomCategorieNote('Modèles à essayer'), isNull);
      expect(erreurNomCategorieNote('  Marchés 2027 '), isNull);
    });

    test('un nom vide ou fait d’espaces est refusé', () {
      expect(erreurNomCategorieNote(null), contains('Donnez un nom'));
      expect(erreurNomCategorieNote(''), contains('Donnez un nom'));
      expect(erreurNomCategorieNote('   '), contains('Donnez un nom'));
    });

    test('un nom trop long est refusé, à la limite exacte il passe', () {
      expect(erreurNomCategorieNote('a' * longueurMaxNomCategorieNote), isNull);
      expect(
        erreurNomCategorieNote('a' * (longueurMaxNomCategorieNote + 1)),
        contains('limité à $longueurMaxNomCategorieNote'),
      );
    });

    test('« Sans catégorie » est réservé, quelles que soient les majuscules et les accents', () {
      expect(erreurNomCategorieNote('Sans catégorie'), isNotNull);
      expect(erreurNomCategorieNote('  SANS  CATEGORIE '), isNotNull);
      expect(erreurNomCategorieNote('sans catégorie'), contains('note sans catégorie'));
    });
  });

  group('memeNomCategorieNote', () {
    test('ignore les majuscules, les accents et les espaces', () {
      expect(memeNomCategorieNote('Documents entreprise', 'documents  ENTREPRISE'), isTrue);
      expect(memeNomCategorieNote('Idées', 'idees'), isTrue);
    });

    test('deux noms différents ne se confondent pas', () {
      expect(memeNomCategorieNote('Futures commandes', 'Commandes'), isFalse);
      expect(memeNomCategorieNote('Idée', 'Idées'), isFalse);
    });
  });

  group('titre d’une note', () {
    test('un titre ordinaire est accepté', () {
      expect(erreurTitreNote('Doudou pour Léa'), isNull);
      expect(erreurTitreNote('  Devis   mercerie '), isNull);
    });

    test('un titre vide ou fait d’espaces est refusé', () {
      expect(erreurTitreNote(null), contains('Donnez un titre'));
      expect(erreurTitreNote(''), contains('Donnez un titre'));
      expect(erreurTitreNote('  \n '), contains('Donnez un titre'));
    });

    test('un titre trop long est refusé, à la limite exacte il passe', () {
      expect(erreurTitreNote('a' * longueurMaxTitreNote), isNull);
      expect(erreurTitreNote('a' * (longueurMaxTitreNote + 1)), contains('limité à $longueurMaxTitreNote'));
    });

    test('nettoyerTitreNote retire les espaces superflus', () {
      expect(nettoyerTitreNote('  Doudou   pour\tLéa '), 'Doudou pour Léa');
      expect(nettoyerTitreNote(null), '');
    });
  });

  group('texte d’une note', () {
    test('seuls les blancs au début et à la fin sont retirés : les retours à la ligne du milieu restent', () {
      expect(nettoyerContenuNote('\n  Laine bleue\n\n2 pelotes  \n'), 'Laine bleue\n\n2 pelotes');
      expect(nettoyerContenuNote(null), '');
      expect(nettoyerContenuNote('   '), '');
    });
  });
}
