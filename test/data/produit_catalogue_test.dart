import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/produit_vues.dart';
import 'package:crochet_creations/domain/calculs/stock.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

/// Catalogue de l'étape 3 : résumés avec alertes, fiche, duplication, inventaire,
/// photos enregistrées avec le produit et historique des ventes.
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
    tempsFabricationMinutes: 150,
    matieres: 'Coton bio',
    couleur: 'Beige',
    dimensions: '25 cm',
    quantiteStock: 5,
    seuilAlerteStock: 2,
    personnalisable: true,
  );

  Future<void> ajouterVente({
    required int produitId,
    int? varianteId,
    int? clientId,
    int quantite = 1,
    int prix = 2500,
    DateTime? date,
    StatutVente statut = StatutVente.validee,
    String designation = 'Doudou lapin',
  }) async {
    final int venteId = await db
        .into(db.ventes)
        .insert(
          VentesCompanion.insert(
            sousTotalCentimes: prix * quantite,
            totalCentimes: prix * quantite,
            clientId: Value(clientId),
            dateVente: date == null ? const Value.absent() : Value(date),
            statut: Value(statut),
          ),
        );
    await db
        .into(db.lignesVente)
        .insert(
          LignesVenteCompanion.insert(
            venteId: venteId,
            designation: designation,
            quantite: quantite,
            prixUnitaireCentimes: prix,
            totalLigneCentimes: prix * quantite,
            produitId: Value(produitId),
            varianteId: Value(varianteId),
          ),
        );
  }

  group('résumés du catalogue', () {
    test('stock total et alerte d’un produit sans variantes', () async {
      await repo.creer(doudou); // 5 en stock, seuil 2
      await repo.creer(doudou.copyWithStock(2)); // faible
      await repo.creer(doudou.copyWithStock(0)); // épuisé

      final List<ProduitResume> resumes = await repo.observerResumes().first;
      expect(resumes.map((ProduitResume r) => r.stockTotal), <int>[5, 2, 0]);
      expect(resumes.map((ProduitResume r) => r.alerte), <EtatStock?>[
        null,
        EtatStock.faible,
        EtatStock.epuise,
      ]);
      expect(resumes.map((ProduitResume r) => r.aReapprovisionner), <bool>[false, true, true]);
    });

    test('avec variantes, le stock est la somme des variantes (le stock du produit est ignoré)', () async {
      final Produit p = await repo.creer(doudou);
      await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose', quantiteStock: 3));
      await repo.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Bleu', quantiteStock: 0, seuilAlerteStock: 0),
      );

      final ProduitResume resume = (await repo.observerResumes().first).single;
      expect(resume.aDesVariantes, isTrue);
      expect(resume.stockTotal, 3);
      // Rose : 3 > seuil du produit (2) → suffisant ; Bleu : épuisé → globalement « faible ».
      expect(resume.alerte, EtatStock.faible);
    });

    test('une variante archivée ne compte plus', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit rose = await repo.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 10),
      );
      await repo.archiverVariante(rose.id);

      final ProduitResume resume = (await repo.observerResumes().first).single;
      expect(resume.aDesVariantes, isFalse);
      expect(resume.stockTotal, 5); // retour au stock du produit
    });

    test('un produit « sur commande » n’a jamais d’alerte', () async {
      await repo.creer(doudou.copyWithStock(0, statut: StatutProduit.surCommande));
      final ProduitResume resume = (await repo.observerResumes().first).single;
      expect(resume.alerte, isNull);
    });

    test('vendable : ni archivé, ni épuisé, ni sans stock (sauf sur commande)', () async {
      await repo.creer(doudou); // en stock
      await repo.creer(doudou.copyWithStock(0)); // plus de stock
      await repo.creer(doudou.copyWithStock(4, statut: StatutProduit.epuise)); // marqué épuisé
      await repo.creer(doudou.copyWithStock(0, statut: StatutProduit.surCommande)); // à la demande
      final Produit archive = await repo.creer(doudou);
      await repo.archiver(archive.id);

      final List<ProduitResume> resumes = await repo.observerResumes(inclureArchives: true).first;
      expect(resumes.map((ProduitResume r) => r.vendable), <bool>[true, false, false, true, false]);
    });

    test('les produits archivés sont exclus sauf demande contraire', () async {
      final Produit a = await repo.creer(doudou);
      await repo.creer(doudou.copyWithStock(1));
      await repo.archiver(a.id);

      expect((await repo.observerResumes().first).length, 1);
      expect((await repo.observerResumes(inclureArchives: true).first).length, 2);
    });

    test('le flux se met à jour après une création, un changement de stock ou de variante', () async {
      final List<List<ProduitResume>> recus = <List<ProduitResume>>[];
      final StreamSubscription<List<ProduitResume>> abonnement = repo.observerResumes().listen(recus.add);
      addTearDown(abonnement.cancel);
      await pumpEventQueue();
      expect(recus.last, isEmpty);

      final Produit p = await repo.creer(doudou);
      await pumpEventQueue();
      expect(recus.last.single.stockTotal, 5);

      await repo.ajusterStock(produitId: p.id, delta: -4);
      await pumpEventQueue();
      expect(recus.last.single.stockTotal, 1);
      expect(recus.last.single.alerte, EtatStock.faible);

      await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose', quantiteStock: 7));
      await pumpEventQueue();
      expect(recus.last.single.stockTotal, 7);
    });
  });

  group('fiche produit', () {
    test('détail : variantes (archivées comprises) et photos dans l’ordre', () async {
      final Produit p = await repo.creer(
        const DonneesProduit(
          nom: 'Écharpe',
          categorie: CategorieProduit.crochet,
          prixVenteCentimes: 3000,
          photoPrincipaleChemin: 'principale.jpg',
        ),
        photosSecondaires: <String>['a.jpg', 'b.jpg'],
      );
      final VarianteProduit v = await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rouge'));
      await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Vert'));
      await repo.archiverVariante(v.id);

      final ProduitDetail detail = (await repo.observerDetail(p.id).first)!;
      expect(detail.cheminsPhotos, <String>['principale.jpg', 'a.jpg', 'b.jpg']);
      expect(detail.variantes.length, 2);
      expect(detail.variantesActives.map((VarianteProduit x) => x.libelle), <String>['Vert']);
      expect(detail.variantesArchivees.map((VarianteProduit x) => x.libelle), <String>['Rouge']);
    });

    test('un produit inconnu donne « rien »', () async {
      expect(await repo.observerDetail(999).first, isNull);
    });

    test('le flux de la fiche suit les modifications', () async {
      final Produit p = await repo.creer(doudou);
      final List<ProduitDetail?> recus = <ProduitDetail?>[];
      final StreamSubscription<ProduitDetail?> abonnement = repo.observerDetail(p.id).listen(recus.add);
      addTearDown(abonnement.cancel);
      await pumpEventQueue();

      await repo.modifier(p.id, doudou.copyWithStock(5, nom: 'Doudou renard'));
      await pumpEventQueue();
      expect(recus.last!.produit.nom, 'Doudou renard');

      await repo.ajouterPhoto(p.id, 'x.jpg');
      await pumpEventQueue();
      expect(recus.last!.photosSecondaires.single.chemin, 'x.jpg');
    });
  });

  group('photos enregistrées avec le produit', () {
    test('création : photos secondaires ajoutées dans l’ordre', () async {
      final Produit p = await repo.creer(doudou, photosSecondaires: <String>['1.jpg', '2.jpg']);
      final List<PhotoProduit> photos = await repo.photosSecondaires(p.id);
      expect(photos.map((PhotoProduit x) => x.chemin), <String>['1.jpg', '2.jpg']);
      expect(photos.map((PhotoProduit x) => x.position), <int>[0, 1]);
    });

    test('modification : ajouts et suppressions en une seule opération', () async {
      final Produit p = await repo.creer(doudou, photosSecondaires: <String>['1.jpg', '2.jpg']);
      final List<PhotoProduit> avant = await repo.photosSecondaires(p.id);

      await repo.modifier(
        p.id,
        doudou,
        photosAAjouter: <String>['3.jpg'],
        photosASupprimer: <int>[avant.first.id],
      );

      final List<PhotoProduit> apres = await repo.photosSecondaires(p.id);
      expect(apres.map((PhotoProduit x) => x.chemin), <String>['2.jpg', '3.jpg']);
    });

    test('on ne peut pas supprimer la photo d’un autre produit', () async {
      final Produit a = await repo.creer(doudou, photosSecondaires: <String>['a.jpg']);
      final Produit b = await repo.creer(doudou, photosSecondaires: <String>['b.jpg']);
      final PhotoProduit photoDeA = (await repo.photosSecondaires(a.id)).single;

      await repo.modifier(b.id, doudou, photosASupprimer: <int>[photoDeA.id]);

      expect(await repo.photosSecondaires(a.id), hasLength(1));
    });

    test('si la modification échoue, aucune photo n’est ajoutée', () async {
      final Produit p = await repo.creer(doudou);
      await expectLater(
        repo.modifier(
          p.id,
          doudou.copyWithStock(5, nom: '   '),
          photosAAjouter: <String>['x.jpg'],
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(await repo.photosSecondaires(p.id), isEmpty);
    });

    test('modifier un produit inexistant n’ajoute aucune photo', () async {
      await expectLater(
        repo.modifier(999, doudou, photosAAjouter: <String>['x.jpg']),
        throwsA(isA<ElementIntrouvable>()),
      );
      expect(await db.select(db.photosProduit).get(), isEmpty);
    });
  });

  group('noms de variantes', () {
    test('un nom déjà pris est refusé avec un message clair, majuscules ignorées', () async {
      final Produit p = await repo.creer(doudou);
      await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));

      await expectLater(
        repo.ajouterVariante(p.id, const DonneesVariante(libelle: ' rose ')),
        throwsA(
          isA<DonneeInvalide>().having(
            (DonneeInvalide e) => e.message,
            'message',
            contains('existe déjà'),
          ),
        ),
      );
    });

    test('le même nom est possible pour un autre produit', () async {
      final Produit a = await repo.creer(doudou);
      final Produit b = await repo.creer(doudou);
      await repo.ajouterVariante(a.id, const DonneesVariante(libelle: 'Rose'));
      await repo.ajouterVariante(b.id, const DonneesVariante(libelle: 'Rose'));
    });

    test('modifier une variante en gardant son nom est possible, en prenant celui d’une autre non', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit rose = await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));
      await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Bleu'));

      final VarianteProduit modifiee = await repo.modifierVariante(
        rose.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 6),
      );
      expect(modifiee.quantiteStock, 6);

      await expectLater(
        repo.modifierVariante(rose.id, const DonneesVariante(libelle: 'BLEU')),
        throwsA(isA<DonneeInvalide>()),
      );
    });

    test('le nom d’une variante archivée reste réservé', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit rose = await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));
      await repo.archiverVariante(rose.id);
      await expectLater(
        repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose')),
        throwsA(isA<DonneeInvalide>()),
      );
    });
  });

  group('duplication', () {
    test('nouvelle référence, nom « (copie) », stock à zéro, sans photos', () async {
      final Produit original = await repo.creer(
        doudou.copyWithStock(5, photo: 'principale.jpg'),
        photosSecondaires: <String>['a.jpg'],
      );

      final Produit copie = await repo.dupliquer(original.id);

      expect(copie.id, isNot(original.id));
      expect(copie.reference, 'PRD-0002');
      expect(copie.nom, 'Doudou lapin (copie)');
      expect(copie.quantiteStock, 0);
      expect(copie.photoPrincipaleChemin, isNull);
      expect(await repo.photosSecondaires(copie.id), isEmpty);
      // Le reste est repris tel quel.
      expect(copie.categorie, original.categorie);
      expect(copie.prixVenteCentimes, 2500);
      expect(copie.coutMatiereCentimes, 600);
      expect(copie.tempsFabricationMinutes, 150);
      expect(copie.matieres, 'Coton bio');
      expect(copie.couleur, 'Beige');
      expect(copie.dimensions, '25 cm');
      expect(copie.seuilAlerteStock, 2);
      expect(copie.personnalisable, isTrue);
      // L'original n'a pas bougé.
      final Produit relu = (await repo.obtenir(original.id))!;
      expect(relu.quantiteStock, 5);
      expect(relu.nom, 'Doudou lapin');
    });

    test('les variantes actives sont reprises avec un stock à zéro', () async {
      final Produit original = await repo.creer(doudou);
      await repo.ajouterVariante(
        original.id,
        const DonneesVariante(
          libelle: 'Rose',
          couleur: 'Rose',
          taille: 'M',
          prixCentimes: 2800,
          quantiteStock: 4,
          seuilAlerteStock: 1,
        ),
      );
      final VarianteProduit vieille = await repo.ajouterVariante(
        original.id,
        const DonneesVariante(libelle: 'Ancienne', quantiteStock: 9),
      );
      await repo.archiverVariante(vieille.id);

      final Produit copie = await repo.dupliquer(original.id);

      final List<VarianteProduit> variantes = await repo.variantes(copie.id, inclureArchivees: true);
      expect(variantes, hasLength(1));
      expect(variantes.single.libelle, 'Rose');
      expect(variantes.single.taille, 'M');
      expect(variantes.single.prixCentimes, 2800);
      expect(variantes.single.seuilAlerteStock, 1);
      expect(variantes.single.quantiteStock, 0);
    });

    test('dupliquer un produit inconnu', () async {
      await expectLater(repo.dupliquer(999), throwsA(isA<ElementIntrouvable>()));
    });

    test('une copie de copie reste lisible et la référence continue la suite', () async {
      final Produit original = await repo.creer(doudou);
      final Produit copie = await repo.dupliquer(original.id);
      final Produit copieDeCopie = await repo.dupliquer(copie.id);
      expect(copieDeCopie.nom, 'Doudou lapin (copie) (copie)');
      expect(copieDeCopie.reference, 'PRD-0003');
    });
  });

  group('inventaire (définir le stock)', () {
    test('fixe la quantité d’un produit', () async {
      final Produit p = await repo.creer(doudou);
      expect(await repo.definirStock(produitId: p.id, quantite: 12), 12);
      expect((await repo.obtenir(p.id))!.quantiteStock, 12);
      expect(await repo.definirStock(produitId: p.id, quantite: 0), 0);
    });

    test('fixe la quantité d’une variante sans toucher au produit', () async {
      final Produit p = await repo.creer(doudou);
      final VarianteProduit v = await repo.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));
      expect(await repo.definirStock(produitId: p.id, varianteId: v.id, quantite: 8), 8);
      expect((await repo.variantes(p.id)).single.quantiteStock, 8);
      expect((await repo.obtenir(p.id))!.quantiteStock, 5);
    });

    test('une quantité négative est refusée', () async {
      final Produit p = await repo.creer(doudou);
      await expectLater(
        repo.definirStock(produitId: p.id, quantite: -1),
        throwsA(isA<DonneeInvalide>()),
      );
      expect((await repo.obtenir(p.id))!.quantiteStock, 5);
    });

    test('produit ou variante inconnus', () async {
      await expectLater(
        repo.definirStock(produitId: 999, quantite: 1),
        throwsA(isA<ElementIntrouvable>()),
      );
      final Produit p = await repo.creer(doudou);
      await expectLater(
        repo.definirStock(produitId: p.id, varianteId: 999, quantite: 1),
        throwsA(isA<ElementIntrouvable>()),
      );
    });
  });

  group('historique des ventes', () {
    test('ventes validées de ce produit, de la plus récente à la plus ancienne', () async {
      final Produit p = await repo.creer(doudou);
      final Produit autre = await repo.creer(doudou.copyWithStock(1, nom: 'Autre'));
      final int clientId = await db.insererClient(nom: 'Martin');

      await ajouterVente(produitId: p.id, date: DateTime(2026, 3, 1), quantite: 2, clientId: clientId);
      await ajouterVente(produitId: p.id, date: DateTime(2026, 5, 10), prix: 2800);
      await ajouterVente(produitId: autre.id, date: DateTime(2026, 4, 1), designation: 'Autre');
      await ajouterVente(
        produitId: p.id,
        date: DateTime(2026, 6, 1),
        statut: StatutVente.annulee,
      );

      final List<LigneHistoriqueVente> historique = await repo.historiqueVentes(p.id);

      expect(historique, hasLength(2));
      expect(historique.first.dateVente, DateTime(2026, 5, 10));
      expect(historique.first.prixUnitaireCentimes, 2800);
      expect(historique.first.clientNom, isNull); // client de passage
      expect(historique.last.quantite, 2);
      expect(historique.last.totalLigneCentimes, 5000);
      expect(historique.last.clientNom, 'Martin');
    });

    test('un produit jamais vendu a un historique vide', () async {
      final Produit p = await repo.creer(doudou);
      expect(await repo.historiqueVentes(p.id), isEmpty);
    });

    test('le flux de l’historique se met à jour après une vente', () async {
      final Produit p = await repo.creer(doudou);
      final List<List<LigneHistoriqueVente>> recus = <List<LigneHistoriqueVente>>[];
      final StreamSubscription<List<LigneHistoriqueVente>> abonnement = repo
          .observerHistorique(p.id)
          .listen(recus.add);
      addTearDown(abonnement.cancel);
      await pumpEventQueue();
      expect(recus.last, isEmpty);

      await ajouterVente(produitId: p.id);
      await pumpEventQueue();
      expect(recus.last, hasLength(1));
    });
  });

  group('nomClientAffiche', () {
    test('prénom et nom, sinon raison sociale', () {
      expect(nomClientAffiche(prenom: 'Léa', nom: 'Martin'), 'Léa Martin');
      expect(nomClientAffiche(nom: 'Martin'), 'Martin');
      expect(nomClientAffiche(prenom: ' ', nom: '', raisonSociale: 'Atelier Laine'), 'Atelier Laine');
      expect(nomClientAffiche(), '');
    });
  });
}

extension on DonneesProduit {
  /// Variante de la fiche de test avec un autre stock (et, au besoin, un autre nom, statut ou photo).
  DonneesProduit copyWithStock(int stock, {String? nom, StatutProduit? statut, String? photo}) {
    return DonneesProduit(
      nom: nom ?? this.nom,
      categorie: categorie,
      prixVenteCentimes: prixVenteCentimes,
      description: description,
      matieres: matieres,
      couleur: couleur,
      dimensions: dimensions,
      tempsFabricationMinutes: tempsFabricationMinutes,
      coutMatiereCentimes: coutMatiereCentimes,
      quantiteStock: stock,
      seuilAlerteStock: seuilAlerteStock,
      statut: statut ?? this.statut,
      personnalisable: personnalisable,
      photoPrincipaleChemin: photo ?? photoPrincipaleChemin,
    );
  }
}
