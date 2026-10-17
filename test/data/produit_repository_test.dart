import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late ProduitRepository repo;

  setUp(() {
    db = creerBaseEnMemoire();
    repo = ProduitRepository(db, NumerotationRepository(db));
  });
  tearDown(() => db.close());

  const DonneesProduit doudou = DonneesProduit(
    nom: 'Doudou lapin',
    categorie: CategorieProduit.doudou,
    prixVenteCentimes: 2500,
    coutMatiereCentimes: 600,
    quantiteStock: 5,
    seuilAlerteStock: 2,
  );

  group('produits', () {
    test('création : référence automatique et valeurs enregistrées', () async {
      final Produit p = await repo.creer(doudou);
      expect(p.reference, 'PRD-0001');
      expect(p.nom, 'Doudou lapin');
      expect(p.categorie, CategorieProduit.doudou);
      expect(p.prixVenteCentimes, 2500);
      expect(p.quantiteStock, 5);
      expect(p.statut, StatutProduit.disponible);
      expect(p.personnalisable, isFalse);
      expect(p.archiveLe, isNull);

      expect((await repo.creer(doudou)).reference, 'PRD-0002');
    });

    test('les textes sont nettoyés et les champs vides deviennent « absents »', () async {
      final Produit p = await repo.creer(
        const DonneesProduit(
          nom: '  Boucles soleil  ',
          categorie: CategorieProduit.bouclesOreilles,
          prixVenteCentimes: 1200,
          description: '   ',
          matieres: ' coton ',
        ),
      );
      expect(p.nom, 'Boucles soleil');
      expect(p.description, isNull);
      expect(p.matieres, 'coton');
    });

    test('les saisies invalides sont refusées avec un message clair', () async {
      await expectLater(
        repo.creer(
          const DonneesProduit(nom: '  ', categorie: CategorieProduit.crochet, prixVenteCentimes: 100),
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      await expectLater(
        repo.creer(
          const DonneesProduit(nom: 'X', categorie: CategorieProduit.crochet, prixVenteCentimes: -1),
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(await repo.lister(), isEmpty);
    });

    test('modification : la référence ne change pas', () async {
      final Produit cree = await repo.creer(doudou);
      final Produit modifie = await repo.modifier(
        cree.id,
        const DonneesProduit(
          nom: 'Doudou lapin rose',
          categorie: CategorieProduit.doudou,
          prixVenteCentimes: 2800,
          quantiteStock: 4,
          statut: StatutProduit.surCommande,
          personnalisable: true,
        ),
      );
      expect(modifie.reference, 'PRD-0001');
      expect(modifie.nom, 'Doudou lapin rose');
      expect(modifie.prixVenteCentimes, 2800);
      expect(modifie.statut, StatutProduit.surCommande);
      expect(modifie.personnalisable, isTrue);
    });

    test('modifier un produit inexistant', () async {
      await expectLater(repo.modifier(999, doudou), throwsA(isA<ElementIntrouvable>()));
    });

    test('archivage : le produit disparaît du catalogue mais reste en base', () async {
      final Produit p = await repo.creer(doudou);
      await repo.archiver(p.id);

      expect(await repo.lister(), isEmpty);
      expect(await repo.lister(inclureArchives: true), hasLength(1));
      expect((await repo.obtenir(p.id))!.archiveLe, isNotNull);

      await repo.restaurer(p.id);
      expect(await repo.lister(), hasLength(1));
    });

    test('la liste est triée par nom, sans tenir compte des majuscules', () async {
      await repo.creer(const DonneesProduit(nom: 'bonnet', categorie: CategorieProduit.accessoire, prixVenteCentimes: 1));
      await repo.creer(const DonneesProduit(nom: 'Amigurumi', categorie: CategorieProduit.crochet, prixVenteCentimes: 1));
      await repo.creer(const DonneesProduit(nom: 'Cabas', categorie: CategorieProduit.crochet, prixVenteCentimes: 1));

      final List<Produit> liste = await repo.observerCatalogue().first;
      expect(liste.map((p) => p.nom), <String>['Amigurumi', 'bonnet', 'Cabas']);
    });
  });

  group('stock', () {
    test('décrémentation : la quantité vendue est retirée du stock', () async {
      final Produit p = await repo.creer(doudou); // stock 5
      await repo.consommerStock(produitId: p.id, quantite: 2);
      expect((await repo.obtenir(p.id))!.quantiteStock, 3);
    });

    test('on peut vendre tout le stock restant', () async {
      final Produit p = await repo.creer(doudou);
      await repo.consommerStock(produitId: p.id, quantite: 5);
      expect((await repo.obtenir(p.id))!.quantiteStock, 0);
    });

    test('stock insuffisant : erreur claire et stock inchangé', () async {
      final Produit p = await repo.creer(doudou);
      await expectLater(
        repo.consommerStock(produitId: p.id, quantite: 6),
        throwsA(
          isA<StockInsuffisant>()
              .having((e) => e.disponible, 'disponible', 5)
              .having((e) => e.demande, 'demandé', 6),
        ),
      );
      expect((await repo.obtenir(p.id))!.quantiteStock, 5);
    });

    test('un produit « sur commande » n’est pas décrémenté', () async {
      final Produit p = await repo.creer(
        const DonneesProduit(
          nom: 'Doudou sur mesure',
          categorie: CategorieProduit.surMesure,
          prixVenteCentimes: 4000,
          statut: StatutProduit.surCommande,
        ),
      );
      await repo.consommerStock(produitId: p.id, quantite: 3);
      expect((await repo.obtenir(p.id))!.quantiteStock, 0);
    });

    test('une vente de plusieurs produits est « tout ou rien » : si un stock manque, rien n’est retiré', () async {
      final Produit a = await repo.creer(doudou); // stock 5
      final Produit b = await repo.creer(doudou.copieAvecStock(1));

      await expectLater(
        db.transaction(() async {
          await repo.consommerStock(produitId: a.id, quantite: 2);
          await repo.consommerStock(produitId: b.id, quantite: 3); // manque de stock
        }),
        throwsA(isA<StockInsuffisant>()),
      );

      expect((await repo.obtenir(a.id))!.quantiteStock, 5);
      expect((await repo.obtenir(b.id))!.quantiteStock, 1);
    });

    test('réapprovisionnement et correction manuelle', () async {
      final Produit p = await repo.creer(doudou);
      expect(await repo.ajusterStock(produitId: p.id, delta: 10), 15);
      expect(await repo.ajusterStock(produitId: p.id, delta: -4), 11);
      await expectLater(
        repo.ajusterStock(produitId: p.id, delta: -12),
        throwsA(isA<StockInsuffisant>()),
      );
      expect((await repo.obtenir(p.id))!.quantiteStock, 11);
    });

    test('quantité vendue nulle ou produit inconnu', () async {
      final Produit p = await repo.creer(doudou);
      await expectLater(
        repo.consommerStock(produitId: p.id, quantite: 0),
        throwsA(isA<DonneeInvalide>()),
      );
      await expectLater(
        repo.consommerStock(produitId: 999, quantite: 1),
        throwsA(isA<ElementIntrouvable>()),
      );
    });
  });

  group('variantes', () {
    test('chaque variante a son propre stock, indépendant de celui du produit', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit rose = await repo.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Rose', couleur: 'Rose', quantiteStock: 3),
      );
      final VarianteProduit vert = await repo.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Vert sauge', quantiteStock: 2, prixCentimes: 2700),
      );

      await repo.consommerStock(produitId: p.id, varianteId: rose.id, quantite: 2);

      final List<VarianteProduit> variantes = await repo.variantes(p.id);
      expect(variantes.map((v) => '${v.libelle}:${v.quantiteStock}'), <String>['Rose:1', 'Vert sauge:2']);
      expect(vert.prixCentimes, 2700);
      expect((await repo.obtenir(p.id))!.quantiteStock, 5);
    });

    test('stock de variante insuffisant', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit v = await repo.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 1),
      );
      await expectLater(
        repo.consommerStock(produitId: p.id, varianteId: v.id, quantite: 2),
        throwsA(isA<StockInsuffisant>()),
      );
    });

    test('une variante d’un autre produit est refusée', () async {
      final Produit a = await repo.creer(doudou);
      final Produit b = await repo.creer(doudou);
      final VarianteProduit v = await repo.ajouterVariante(
        a.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 1),
      );
      await expectLater(
        repo.ajusterStock(produitId: b.id, varianteId: v.id, delta: -1),
        throwsA(isA<DonneeInvalide>()),
      );
    });

    test('libellé unique par produit, archivage d’une variante', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit v = await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));
      await expectLater(
        repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose')),
        throwsException,
      );

      await repo.archiverVariante(v.id);
      expect(await repo.variantes(p.id), isEmpty);
      expect(await repo.variantes(p.id, inclureArchivees: true), hasLength(1));
    });
  });

  group('photos secondaires', () {
    test('ajout dans l’ordre et suppression', () async {
      final Produit p = await repo.creer(doudou);
      final PhotoProduit a = await repo.ajouterPhoto(p.id, '/photos/a.jpg');
      final PhotoProduit b = await repo.ajouterPhoto(p.id, '/photos/b.jpg');
      expect(a.position, 0);
      expect(b.position, 1);

      await repo.supprimerPhoto(a.id);
      final List<PhotoProduit> restantes = await repo.photosSecondaires(p.id);
      expect(restantes.map((x) => x.chemin), <String>['/photos/b.jpg']);
    });
  });
}

extension on DonneesProduit {
  DonneesProduit copieAvecStock(int stock) => DonneesProduit(
    nom: nom,
    categorie: categorie,
    prixVenteCentimes: prixVenteCentimes,
    quantiteStock: stock,
  );
}
