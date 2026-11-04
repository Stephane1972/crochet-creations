import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/categorie_repository.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late CategorieRepository categories;
  late ProduitRepository produits;

  setUp(() {
    db = creerBaseEnMemoire();
    categories = CategorieRepository(db);
    produits = ProduitRepository(db, NumerotationRepository(db));
  });
  tearDown(() => db.close());

  Future<Produit> produitDans(String cle, {String nom = 'Produit'}) =>
      produits.creer(DonneesProduit(nom: nom, categorie: cle, prixVenteCentimes: 1000));

  Matcher refus(String morceau) =>
      throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains(morceau)));

  Future<List<String>> noms() async => (await categories.lister()).map((CategorieProduit c) => c.nom).toList();

  group('lister', () {
    test('une base neuve a les cinq catégories de départ, dans l’ordre', () async {
      expect(await noms(), <String>['Crochet', 'Doudou', 'Boucles d’oreilles', 'Accessoire', 'Sur mesure']);
      expect((await categories.lister()).map((CategorieProduit c) => c.cle), <String>[
        CleCategorie.crochet,
        CleCategorie.doudou,
        CleCategorie.bouclesOreilles,
        CleCategorie.accessoire,
        CleCategorie.surMesure,
      ]);
    });

    test('parCle et obtenir retrouvent une catégorie, ou rien', () async {
      final CategorieProduit doudou = (await categories.parCle(CleCategorie.doudou))!;
      expect(doudou.nom, 'Doudou');
      expect((await categories.obtenir(doudou.id))!.cle, CleCategorie.doudou);
      expect(await categories.parCle('inconnue'), isNull);
      expect(await categories.obtenir(999), isNull);
    });

    test('le nombre de produits par catégorie compte aussi les produits archivés', () async {
      await produitDans(CleCategorie.doudou);
      final Produit archive = await produitDans(CleCategorie.doudou, nom: 'Vieux doudou');
      await produitDans(CleCategorie.crochet);
      await produits.archiver(archive.id);

      expect(await categories.nombreProduitsParCategorie(), <String, int>{
        CleCategorie.doudou: 2,
        CleCategorie.crochet: 1,
      });
      expect(await categories.nombreProduits(CleCategorie.doudou), 2);
      expect(await categories.nombreProduits(CleCategorie.accessoire), 0);
    });

    test('observer envoie la liste mise à jour après un ajout', () async {
      final Stream<List<CategorieProduit>> flux = categories.observer();
      final Future<void> verification = expectLater(
        flux.map((List<CategorieProduit> l) => l.length),
        emitsThrough(6),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await categories.creer('Peluches');
      await verification;
    });
  });

  group('créer', () {
    test('la nouvelle catégorie passe en dernier, avec une clé à elle', () async {
      final CategorieProduit peluches = await categories.creer('  Peluches ');
      expect(peluches.nom, 'Peluches');
      expect(peluches.cle, startsWith('cat_'));
      expect(peluches.position, 5);
      expect((await noms()).last, 'Peluches');

      final CategorieProduit autre = await categories.creer('Bijoux');
      expect(autre.position, 6);
      expect(autre.cle, isNot(peluches.cle));
    });

    test('un nom vide, trop long ou déjà pris est refusé, sans rien créer', () async {
      await expectLater(categories.creer('  '), refus('Donnez un nom'));
      await expectLater(categories.creer('x' * 61), refus('60 caractères'));
      await expectLater(categories.creer('doudou'), refus('Une catégorie « Doudou » existe déjà.'));
      await expectLater(categories.creer(' BOUCLES  D’OREILLES '), refus('existe déjà'));
      expect(await categories.lister(), hasLength(5));
    });

    test('une catégorie créée est utilisable tout de suite par un produit', () async {
      final CategorieProduit peluches = await categories.creer('Peluches');
      final Produit p = await produitDans(peluches.cle);
      expect(p.categorie, peluches.cle);
    });
  });

  group('renommer', () {
    test('le nom change partout, les produits ne bougent pas', () async {
      final Produit p = await produitDans(CleCategorie.doudou);
      final CategorieProduit doudou = (await categories.parCle(CleCategorie.doudou))!;

      final CategorieProduit renommee = await categories.renommer(doudou.id, ' Peluches douces ');

      expect(renommee.nom, 'Peluches douces');
      expect(renommee.cle, CleCategorie.doudou);
      expect((await produits.obtenir(p.id))!.categorie, CleCategorie.doudou);
      expect(await noms(), contains('Peluches douces'));
      expect(await noms(), isNot(contains('Doudou')));
    });

    test('une catégorie peut changer ses majuscules ou ses accents sans se heurter à elle-même', () async {
      final CategorieProduit crochet = (await categories.parCle(CleCategorie.crochet))!;
      expect((await categories.renommer(crochet.id, 'CROCHET')).nom, 'CROCHET');
      expect((await categories.renommer(crochet.id, 'CROCHET')).nom, 'CROCHET');
    });

    test('le nom d’une autre catégorie, un nom vide ou trop long sont refusés', () async {
      final CategorieProduit crochet = (await categories.parCle(CleCategorie.crochet))!;
      await expectLater(categories.renommer(crochet.id, 'doudou'), refus('existe déjà'));
      await expectLater(categories.renommer(crochet.id, ''), refus('Donnez un nom'));
      await expectLater(categories.renommer(crochet.id, 'y' * 61), refus('60 caractères'));
      expect((await categories.parCle(CleCategorie.crochet))!.nom, 'Crochet');
    });

    test('une catégorie qui n’existe plus', () async {
      await expectLater(categories.renommer(999, 'Peluches'), throwsA(isA<ElementIntrouvable>()));
    });
  });

  group('supprimer', () {
    test('une catégorie vide disparaît simplement', () async {
      final CategorieProduit sur = (await categories.parCle(CleCategorie.surMesure))!;
      expect(await categories.supprimer(sur.id), 0);
      expect(await categories.parCle(CleCategorie.surMesure), isNull);
      expect(await categories.lister(), hasLength(4));
    });

    test('avec des produits : ils sont déplacés (archivés compris), puis la catégorie disparaît', () async {
      final Produit a = await produitDans(CleCategorie.doudou, nom: 'Lapin');
      final Produit b = await produitDans(CleCategorie.doudou, nom: 'Ours');
      await produits.archiver(b.id);
      final Produit ailleurs = await produitDans(CleCategorie.crochet, nom: 'Plaid');
      final CategorieProduit doudou = (await categories.parCle(CleCategorie.doudou))!;

      final int deplaces = await categories.supprimer(doudou.id, deplacerVersCle: CleCategorie.accessoire);

      expect(deplaces, 2);
      expect(await categories.parCle(CleCategorie.doudou), isNull);
      expect((await produits.obtenir(a.id))!.categorie, CleCategorie.accessoire);
      expect((await produits.obtenir(b.id))!.categorie, CleCategorie.accessoire);
      expect((await produits.obtenir(ailleurs.id))!.categorie, CleCategorie.crochet);
    });

    test('avec des produits et sans destination : refusé, rien ne bouge', () async {
      final Produit p = await produitDans(CleCategorie.doudou);
      final CategorieProduit doudou = (await categories.parCle(CleCategorie.doudou))!;

      await expectLater(categories.supprimer(doudou.id), refus('contient 1 produit'));

      expect(await categories.parCle(CleCategorie.doudou), isNotNull);
      expect((await produits.obtenir(p.id))!.categorie, CleCategorie.doudou);
    });

    test('la destination ne peut pas être la catégorie supprimée, ni une catégorie qui n’existe pas', () async {
      final Produit p = await produitDans(CleCategorie.doudou);
      final CategorieProduit doudou = (await categories.parCle(CleCategorie.doudou))!;

      await expectLater(categories.supprimer(doudou.id, deplacerVersCle: CleCategorie.doudou), refus('une autre catégorie'));
      await expectLater(
        categories.supprimer(doudou.id, deplacerVersCle: 'cat_fantome'),
        throwsA(isA<ElementIntrouvable>()),
      );

      expect(await categories.parCle(CleCategorie.doudou), isNotNull);
      expect((await produits.obtenir(p.id))!.categorie, CleCategorie.doudou);
    });

    test('une catégorie qui n’existe plus', () async {
      await expectLater(categories.supprimer(999), throwsA(isA<ElementIntrouvable>()));
    });

    test('toutes les catégories peuvent être supprimées s’il n’y a aucun produit', () async {
      for (final CategorieProduit c in await categories.lister()) {
        await categories.supprimer(c.id);
      }
      expect(await categories.lister(), isEmpty);
    });

    test('une catégorie supprimée ne peut plus recevoir de produit', () async {
      final CategorieProduit sur = (await categories.parCle(CleCategorie.surMesure))!;
      await categories.supprimer(sur.id);
      await expectLater(produitDans(CleCategorie.surMesure), refus('n’existe plus'));
    });
  });
}
