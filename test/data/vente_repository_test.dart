import 'dart:async';

import 'package:crochet_creations/core/utils/money.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/client_vues.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/data/repositories/vente_vues.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late ProduitRepository produits;
  late ClientRepository clients;
  late VenteRepository ventes;

  setUp(() {
    db = creerBaseEnMemoire();
    produits = ProduitRepository(db, NumerotationRepository(db));
    clients = ClientRepository(db);
    ventes = VenteRepository(db, produits);
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

  /// Panier d'un produit du catalogue, comme le construit l'écran de vente.
  Panier panierDe(Produit p, {int quantite = 1, int? stock}) => const Panier().ajouter(
    produitId: p.id,
    designation: p.nom,
    prixUnitaireCentimes: p.prixVenteCentimes,
    quantite: quantite,
    stockDisponible: stock ?? p.quantiteStock,
  );

  Future<int> stockDe(int produitId) async => (await produits.obtenir(produitId))!.quantiteStock;

  Future<int> nombreDeVentes() async => (await db.select(db.ventes).get()).length;

  group('valider', () {
    test('enregistre la vente, ses lignes, le paiement et décrémente le stock', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(
        panier: panierDe(p, quantite: 2),
        paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 5000),
        date: DateTime(2026, 10, 5, 10),
      );

      expect(v.statut, StatutVente.validee);
      expect(v.clientId, isNull); // client de passage
      expect(v.sousTotalCentimes, 5000);
      expect(v.remiseCentimes, 0);
      expect(v.totalCentimes, 5000);
      expect(v.statutPaiement, StatutPaiement.payee);
      expect(v.dateVente, DateTime(2026, 10, 5, 10));

      final VenteDetail d = (await ventes.detail(v.id))!;
      expect(d.lignes, hasLength(1));
      final LigneVente l = d.lignes.single;
      expect(l.designation, 'Doudou lapin');
      expect(l.quantite, 2);
      expect(l.prixUnitaireCentimes, 2500);
      expect(l.totalLigneCentimes, 5000);
      expect(l.coutUnitaireCentimes, 600); // relevé au catalogue pour la marge
      expect(l.nature, NatureLigne.bien);
      expect(l.produitId, p.id);
      expect(d.paiements, hasLength(1));
      expect(d.paiements.single.montantCentimes, 5000);
      expect(d.paiements.single.modePaiement, ModePaiement.especes);

      expect(await stockDe(p.id), 3);
    });

    test('remise en pourcentage et frais de port sont enregistrés et le total est exact', () async {
      final Produit p = await produits.creer(doudou);
      final Panier panier = panierDe(p, quantite: 2).avecRemise(RemiseType.pourcentage, 1000).avecFraisPort(450);
      final Vente v = await ventes.valider(panier: panier);

      expect(v.sousTotalCentimes, 5000);
      expect(v.remiseType, RemiseType.pourcentage);
      expect(v.remiseValeur, 1000);
      expect(v.remiseCentimes, 500);
      expect(v.fraisPortCentimes, 450);
      expect(v.totalCentimes, 4950);
    });

    test('remise en montant', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p, quantite: 2).avecRemise(RemiseType.montant, 300));
      expect(v.remiseType, RemiseType.montant);
      expect(v.remiseCentimes, 300);
      expect(v.totalCentimes, 4700);
    });

    test('un acompte rend la vente partiellement payée, sans paiement elle est impayée', () async {
      final Produit p = await produits.creer(doudou);
      final Vente acompte = await ventes.valider(
        panier: panierDe(p),
        paiement: const PaiementSaisi(mode: ModePaiement.virement, montantCentimes: 1000),
      );
      expect(acompte.statutPaiement, StatutPaiement.partiellementPayee);

      final Vente differee = await ventes.valider(panier: panierDe(p, stock: 10));
      expect(differee.statutPaiement, StatutPaiement.impayee);
      expect(await db.select(db.paiements).get(), hasLength(1));
    });

    test('une prestation libre ne touche à aucun stock', () async {
      final Produit p = await produits.creer(doudou);
      final Panier panier = panierDe(p).ajouter(
        designation: 'Retouche d’un doudou',
        description: 'Recoudre un bras',
        nature: NatureLigne.service,
        prixUnitaireCentimes: 1200,
      );
      final Vente v = await ventes.valider(panier: panier);

      final VenteDetail d = (await ventes.detail(v.id))!;
      expect(d.lignes, hasLength(2));
      final LigneVente service = d.lignes.last;
      expect(service.nature, NatureLigne.service);
      expect(service.produitId, isNull);
      expect(service.description, 'Recoudre un bras');
      expect(service.coutUnitaireCentimes, 0);
      expect(service.position, 1);
      expect(v.totalCentimes, 3700);
      expect(await stockDe(p.id), 4); // seul le doudou a été décompté
    });

    test('une vente à un client enregistre son identifiant et apparaît dans son historique', () async {
      final Produit p = await produits.creer(doudou);
      final Client c = await clients.creer(const DonneesClient(prenom: 'Camille', nom: 'Martin'));
      final Vente v = await ventes.valider(
        clientId: c.id,
        panier: panierDe(p),
        paiement: const PaiementSaisi(mode: ModePaiement.carte, montantCentimes: 2500),
      );

      expect(v.clientId, c.id);
      final HistoriqueClient h = await clients.historique(c.id);
      expect(h.ventes.map((VenteClient x) => x.venteId), <int>[v.id]);
      expect(h.paiements, hasLength(1));
      expect((await ventes.detail(v.id))!.client!.nom, 'Martin');
    });

    test('un produit « sur commande » n’est pas décompté du stock', () async {
      final Produit p = await produits.creer(
        const DonneesProduit(
          nom: 'Plaid sur mesure',
          categorie: CategorieProduit.surMesure,
          prixVenteCentimes: 9000,
          statut: StatutProduit.surCommande,
        ),
      );
      final Vente v = await ventes.valider(panier: panierDe(p, quantite: 3, stock: null));
      expect(v.totalCentimes, 27000);
      expect(await stockDe(p.id), 0);
    });

    test('un produit à variantes se vend par variante : le stock de la variante diminue', () async {
      final Produit p = await produits.creer(doudou);
      final VarianteProduit rose = await produits.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 4, prixCentimes: 2800),
      );
      final Panier panier = const Panier().ajouter(
        produitId: p.id,
        varianteId: rose.id,
        designation: 'Doudou lapin – Rose',
        prixUnitaireCentimes: 2800,
        quantite: 3,
        stockDisponible: 4,
      );
      final Vente v = await ventes.valider(panier: panier);

      expect(v.totalCentimes, 8400);
      expect((await produits.observerDetail(p.id).first)!.variantes.single.quantiteStock, 1);
      expect((await ventes.detail(v.id))!.lignes.single.varianteId, rose.id);
    });
  });

  group('valider : refus (rien n’est enregistré)', () {
    test('panier vide', () async {
      await expectLater(ventes.valider(panier: const Panier()), throwsA(isA<DonneeInvalide>()));
      expect(await nombreDeVentes(), 0);
    });

    test('stock insuffisant : tout ou rien, même pour les articles précédents', () async {
      final Produit a = await produits.creer(doudou);
      final Produit b = await produits.creer(
        const DonneesProduit(
          nom: 'Boucles roses',
          categorie: CategorieProduit.bouclesOreilles,
          prixVenteCentimes: 1500,
          quantiteStock: 1,
        ),
      );
      // Le panier a été rempli avec un stock qui a changé depuis (plafond absent) : 2 demandés, 1 en stock.
      final Panier panier = panierDe(a).ajouter(
        produitId: b.id,
        designation: b.nom,
        prixUnitaireCentimes: 1500,
        quantite: 2,
      );
      await expectLater(ventes.valider(panier: panier), throwsA(isA<StockInsuffisant>()));

      expect(await nombreDeVentes(), 0);
      expect(await db.select(db.lignesVente).get(), isEmpty);
      expect(await stockDe(a.id), 5);
      expect(await stockDe(b.id), 1);
    });

    test('paiement supérieur au total', () async {
      final Produit p = await produits.creer(doudou);
      await expectLater(
        ventes.valider(
          panier: panierDe(p),
          paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 2501),
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(await nombreDeVentes(), 0);
      expect(await stockDe(p.id), 5);
    });

    test('remise impossible', () async {
      final Produit p = await produits.creer(doudou);
      await expectLater(
        ventes.valider(panier: panierDe(p).avecRemise(RemiseType.montant, 9999)),
        throwsA(isA<RemiseInvalide>()),
      );
      expect(await nombreDeVentes(), 0);
    });

    test('client inexistant ou archivé', () async {
      final Produit p = await produits.creer(doudou);
      await expectLater(
        ventes.valider(clientId: 999, panier: panierDe(p)),
        throwsA(isA<ElementIntrouvable>()),
      );
      final Client c = await clients.creer(const DonneesClient(nom: 'Martin'));
      await clients.archiver(c.id);
      await expectLater(
        ventes.valider(clientId: c.id, panier: panierDe(p)),
        throwsA(
          isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('archivé')),
        ),
      );
      expect(await nombreDeVentes(), 0);
    });

    test('produit archivé ou épuisé', () async {
      final Produit archive = await produits.creer(doudou);
      final Panier panierArchive = panierDe(archive);
      await produits.archiver(archive.id);
      await expectLater(
        ventes.valider(panier: panierArchive),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('plus en vente'))),
      );

      final Produit epuise = await produits.creer(
        const DonneesProduit(
          nom: 'Écharpe',
          categorie: CategorieProduit.accessoire,
          prixVenteCentimes: 3000,
          quantiteStock: 2,
          statut: StatutProduit.epuise,
        ),
      );
      await expectLater(ventes.valider(panier: panierDe(epuise)), throwsA(isA<DonneeInvalide>()));
      expect(await nombreDeVentes(), 0);
      expect(await stockDe(epuise.id), 2);
    });

    test('produit à variantes vendu sans variante, ou variante archivée', () async {
      final Produit p = await produits.creer(doudou);
      final VarianteProduit rose = await produits.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 4),
      );
      await expectLater(
        ventes.valider(panier: panierDe(p)),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('variante'))),
      );

      final Panier avecRose = const Panier().ajouter(
        produitId: p.id,
        varianteId: rose.id,
        designation: 'Doudou lapin – Rose',
        prixUnitaireCentimes: 2500,
        stockDisponible: 4,
      );
      await produits.archiverVariante(rose.id);
      await expectLater(ventes.valider(panier: avecRose), throwsA(isA<DonneeInvalide>()));
      expect(await nombreDeVentes(), 0);
    });
  });

  group('annuler', () {
    test('remet le stock, rembourse le net encaissé et marque la vente annulée', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(
        panier: panierDe(p, quantite: 2),
        paiement: const PaiementSaisi(mode: ModePaiement.carte, montantCentimes: 5000),
      );
      expect(await stockDe(p.id), 3);

      await ventes.annuler(v.id);

      expect(await stockDe(p.id), 5);
      final VenteDetail d = (await ventes.detail(v.id))!;
      expect(d.estAnnulee, isTrue);
      expect(d.vente.statutPaiement, StatutPaiement.remboursee);
      expect(d.paiements.map((Paiement x) => x.montantCentimes), <int>[5000, -5000]);
      expect(d.paiements.last.modePaiement, ModePaiement.carte);
      expect(d.encaisseCentimes, 0);
      expect(d.soldeDuCentimes, 0);
      expect(d.peutEncaisser, isFalse);
      expect(d.lignes, hasLength(1)); // la vente reste lisible
    });

    test('une vente impayée est annulée sans remboursement', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p));
      await ventes.annuler(v.id);

      expect(await stockDe(p.id), 5);
      expect(await db.select(db.paiements).get(), isEmpty);
      final Vente apres = (await ventes.obtenir(v.id))!;
      expect(apres.statut, StatutVente.annulee);
      expect(apres.statutPaiement, StatutPaiement.impayee);
    });

    test('un acompte est remboursé à l’annulation', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(
        panier: panierDe(p),
        paiement: const PaiementSaisi(mode: ModePaiement.virement, montantCentimes: 1000),
      );
      await ventes.annuler(v.id);

      final VenteDetail d = (await ventes.detail(v.id))!;
      expect(d.paiements.map((Paiement x) => x.montantCentimes), <int>[1000, -1000]);
      expect(d.vente.statutPaiement, StatutPaiement.remboursee);
    });

    test('remet aussi le stock d’une variante, et d’un produit archivé depuis', () async {
      final Produit p = await produits.creer(doudou);
      final VarianteProduit rose = await produits.ajouterVariante(
        p.id,
        const DonneesVariante(libelle: 'Rose', quantiteStock: 4),
      );
      final Vente v = await ventes.valider(
        panier: const Panier().ajouter(
          produitId: p.id,
          varianteId: rose.id,
          designation: 'Doudou lapin – Rose',
          prixUnitaireCentimes: 2500,
          quantite: 3,
          stockDisponible: 4,
        ),
      );
      expect((await produits.observerDetail(p.id).first)!.variantes.single.quantiteStock, 1);

      await produits.archiver(p.id);
      await ventes.annuler(v.id);
      expect((await produits.observerDetail(p.id).first)!.variantes.single.quantiteStock, 4);
    });

    test('un produit « sur commande » n’a pas de stock à remettre', () async {
      final Produit p = await produits.creer(
        const DonneesProduit(
          nom: 'Plaid sur mesure',
          categorie: CategorieProduit.surMesure,
          prixVenteCentimes: 9000,
          statut: StatutProduit.surCommande,
        ),
      );
      final Vente v = await ventes.valider(panier: panierDe(p, stock: null));
      await ventes.annuler(v.id);
      expect(await stockDe(p.id), 0);
    });

    test('annule aussi la facture émise pour cette vente', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p));
      await db
          .into(db.factures)
          .insert(
            FacturesCompanion.insert(
              numero: 'FACT-2026-0001',
              venteId: v.id,
              dateVentePrestation: DateTime(2026, 10, 5),
              totalCentimes: v.totalCentimes,
            ),
          );

      await ventes.annuler(v.id);

      expect((await db.select(db.factures).getSingle()).statut, StatutFacture.annulee);
    });

    test('refuse d’annuler deux fois ou une vente inconnue', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p));
      await ventes.annuler(v.id);

      await expectLater(ventes.annuler(v.id), throwsA(isA<DonneeInvalide>()));
      await expectLater(ventes.annuler(999), throwsA(isA<ElementIntrouvable>()));
      expect(await stockDe(p.id), 5); // le stock n'a été remis qu'une fois
    });
  });

  group('encaisser', () {
    test('acompte puis solde : la vente devient payée', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p, quantite: 2));
      expect(v.statutPaiement, StatutPaiement.impayee);

      await ventes.encaisser(venteId: v.id, mode: ModePaiement.virement, montantCentimes: 2000);
      expect((await ventes.obtenir(v.id))!.statutPaiement, StatutPaiement.partiellementPayee);
      expect((await ventes.detail(v.id))!.soldeDuCentimes, 3000);

      final Paiement solde = await ventes.encaisser(
        venteId: v.id,
        mode: ModePaiement.especes,
        montantCentimes: 3000,
        note: 'Soldé en main propre',
      );
      expect(solde.note, 'Soldé en main propre');
      final VenteDetail d = (await ventes.detail(v.id))!;
      expect(d.vente.statutPaiement, StatutPaiement.payee);
      expect(d.soldeDuCentimes, 0);
      expect(d.peutEncaisser, isFalse);
      expect(d.paiements.map((Paiement x) => x.modePaiement), <ModePaiement>[
        ModePaiement.virement,
        ModePaiement.especes,
      ]);
    });

    test('refuse un montant nul, supérieur au solde, ou une vente déjà payée ou annulée', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p));

      await expectLater(
        ventes.encaisser(venteId: v.id, mode: ModePaiement.carte, montantCentimes: 0),
        throwsA(isA<DonneeInvalide>()),
      );
      await expectLater(
        ventes.encaisser(venteId: v.id, mode: ModePaiement.carte, montantCentimes: 2501),
        throwsA(
          isA<DonneeInvalide>().having(
            (DonneeInvalide e) => e.message,
            'message',
            contains('solde dû (${formatEuros(2500)})'),
          ),
        ),
      );

      await ventes.encaisser(venteId: v.id, mode: ModePaiement.carte, montantCentimes: 2500);
      await expectLater(
        ventes.encaisser(venteId: v.id, mode: ModePaiement.carte, montantCentimes: 100),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('déjà'))),
      );

      final Vente autre = await ventes.valider(panier: panierDe(p, stock: 10));
      await ventes.annuler(autre.id);
      await expectLater(
        ventes.encaisser(venteId: autre.id, mode: ModePaiement.carte, montantCentimes: 100),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('annulée'))),
      );
      await expectLater(
        ventes.encaisser(venteId: 999, mode: ModePaiement.carte, montantCentimes: 100),
        throwsA(isA<ElementIntrouvable>()),
      );
      expect(await db.select(db.paiements).get(), hasLength(1));
    });
  });

  group('détail', () {
    test('une vente inconnue n’a pas de détail', () async {
      expect(await ventes.detail(999), isNull);
    });

    test('le détail suit les paiements en direct', () async {
      final Produit p = await produits.creer(doudou);
      final Vente v = await ventes.valider(panier: panierDe(p));

      final List<int> encaisse = <int>[];
      Completer<void> prochain = Completer<void>();
      final StreamSubscription<VenteDetail?> abonnement = ventes.observerDetail(v.id).listen((VenteDetail? d) {
        encaisse.add(d!.encaisseCentimes);
        if (!prochain.isCompleted) prochain.complete();
      });

      await prochain.future.timeout(const Duration(seconds: 5));
      expect(encaisse, <int>[0]);

      prochain = Completer<void>();
      await ventes.encaisser(venteId: v.id, mode: ModePaiement.cheque, montantCentimes: 1000);
      await prochain.future.timeout(const Duration(seconds: 5));
      expect(encaisse.last, 1000);

      await abonnement.cancel();
    });
  });
}
