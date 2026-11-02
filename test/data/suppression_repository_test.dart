import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/client_vues.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/usage_historique.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_donnees.dart';

/// Supprimer un client ou un produit, même s'il a déjà servi : l'historique (ventes, factures, devis) est conservé,
/// seul le lien avec la fiche supprimée disparaît. Seul un client inscrit à un cours est refusé.
void main() {
  late AppDatabase db;
  late ClientRepository clients;
  late ProduitRepository produits;

  setUp(() {
    db = creerBaseEnMemoire();
    clients = ClientRepository(db);
    produits = ProduitRepository(db, NumerotationRepository(db));
  });
  tearDown(() => db.close());

  const DonneesProduit doudou = DonneesProduit(
    nom: 'Doudou lapin',
    categorie: CategorieProduit.doudou,
    prixVenteCentimes: 2500,
    photoPrincipaleChemin: 'principale.jpg',
  );

  Future<int> ajouterLigneVente(int venteId, {int? produitId, int? varianteId, String designation = 'Article'}) {
    return db
        .into(db.lignesVente)
        .insert(
          LignesVenteCompanion.insert(
            venteId: venteId,
            designation: designation,
            quantite: 1,
            prixUnitaireCentimes: 1000,
            totalLigneCentimes: 1000,
            produitId: Value(produitId),
            varianteId: Value(varianteId),
          ),
        );
  }

  Future<int> ajouterDevis({int? clientId}) => db
      .into(db.devis)
      .insert(
        DevisCompanion.insert(
          numero: 'DEVIS-2026-0001',
          sousTotalCentimes: 6000,
          totalCentimes: 6000,
          clientId: Value(clientId),
        ),
      );

  Future<int> ajouterLigneDevis(int devisId, {int? produitId, int? varianteId}) => db
      .into(db.lignesDevis)
      .insert(
        LignesDevisCompanion.insert(
          devisId: devisId,
          designation: 'Couverture sur mesure',
          quantite: 1,
          prixUnitaireCentimes: 6000,
          totalLigneCentimes: 6000,
          produitId: Value(produitId),
          varianteId: Value(varianteId),
        ),
      );

  Future<int> ajouterFacture(int venteId, int clientId, {String numero = 'FACT-2026-0001'}) => db
      .into(db.factures)
      .insert(
        FacturesCompanion.insert(
          numero: numero,
          venteId: venteId,
          dateVentePrestation: DateTime(2026, 10, 20),
          totalCentimes: 1000,
          clientId: Value(clientId),
          clientNom: const Value('Dupont'),
          clientAdresse: const Value('12 rue des Lilas\n31000 Toulouse'),
          clientSiret: const Value('12345678900011'),
        ),
      );

  group('clients', () {
    test('un client sans historique est supprimé pour de bon', () async {
      final Client c = await clients.creer(const DonneesClient(nom: 'Martin'));
      final Client autre = await clients.creer(const DonneesClient(nom: 'Durand'));

      expect((await clients.usage(c.id)).estUtilise, isFalse);
      await clients.supprimer(c.id);

      expect(await clients.obtenir(c.id), isNull);
      expect(await clients.lister(inclureArchives: true), hasLength(1));
      expect((await clients.lister()).single.id, autre.id);
    });

    test('un client archivé peut être supprimé', () async {
      final Client c = await clients.creer(const DonneesClient(nom: 'Martin'));
      await clients.archiver(c.id);
      await clients.supprimer(c.id);
      expect(await clients.obtenir(c.id), isNull);
    });

    test('un client qui a des ventes est supprimé : les ventes restent, avec son nom', () async {
      final int id = await db.insererClient(nom: 'Dupont');
      final int autre = await db.insererClient(nom: 'Durand');
      final int v1 = await db.insererVente(clientId: id);
      final int v2 = await db.insererVente(clientId: id);
      final int vAutre = await db.insererVente(clientId: autre);

      expect((await clients.usage(id)).enumeration, '2 ventes');
      await clients.supprimer(id);

      expect(await clients.obtenir(id), isNull);
      final List<Vente> ventes = await db.select(db.ventes).get();
      expect(ventes, hasLength(3));
      for (final int venteId in <int>[v1, v2]) {
        final Vente v = ventes.firstWhere((Vente x) => x.id == venteId);
        expect(v.clientId, isNull);
        expect(v.clientNom, 'Dupont');
        expect(v.totalCentimes, 1000);
      }
      final Vente intacte = ventes.firstWhere((Vente x) => x.id == vAutre);
      expect(intacte.clientId, autre);
      expect(intacte.clientNom, isNull);
    });

    test('ses devis restent aussi, avec son nom ; ses factures gardent nom, adresse et SIRET', () async {
      final int id = await db.insererClient(nom: 'Dupont');
      final int vente = await db.insererVente(clientId: id);
      final int facture = await ajouterFacture(vente, id);
      final int devis = await ajouterDevis(clientId: id);

      expect((await clients.usage(id)).enumeration, '1 vente, 1 facture et 1 devis');
      await clients.supprimer(id);

      final DevisFiche d = (await db.select(db.devis).get()).single;
      expect(d.id, devis);
      expect(d.clientId, isNull);
      expect(d.clientNom, 'Dupont');

      final Facture f = (await db.select(db.factures).get()).single;
      expect(f.id, facture);
      expect(f.clientId, isNull);
      expect(f.clientNom, 'Dupont');
      expect(f.clientAdresse, '12 rue des Lilas\n31000 Toulouse');
      expect(f.clientSiret, '12345678900011');
    });

    test('le nom copié est celui qu’on affichait : raison sociale d’un professionnel, sinon « Prénom Nom »', () async {
      final Client pro = await clients.creer(
        const DonneesClient(
          typeClient: TypeClient.professionnel,
          raisonSociale: 'Atelier Soleil',
          nom: 'Bernard',
          prenom: 'Léa',
        ),
      );
      final Client particulier = await clients.creer(const DonneesClient(prenom: 'Marie', nom: 'Dupont'));
      await db.insererVente(clientId: pro.id);
      await db.insererVente(clientId: particulier.id);

      await clients.supprimer(pro.id);
      await clients.supprimer(particulier.id);

      final List<String?> noms = <String?>[for (final Vente v in await db.select(db.ventes).get()) v.clientNom];
      expect(noms, <String?>['Atelier Soleil', 'Marie Dupont']);
    });

    test('un client inscrit à un cours ne peut pas être supprimé : tout est conservé', () async {
      await remplirBase(db);
      final Client c = (await clients.lister()).single;

      final UsageHistorique usage = await clients.usage(c.id);
      expect(usage.enumeration, '1 vente, 1 facture, 1 devis et 1 inscription à un cours');
      expect(await clients.nombreInscriptions(c.id), 1);

      await expectLater(
        clients.supprimer(c.id),
        throwsA(
          isA<SuppressionImpossible>()
              .having((SuppressionImpossible e) => e.cible, 'cible', 'client')
              .having((SuppressionImpossible e) => e.message, 'message', contains('1 inscription à un cours')),
        ),
      );
      // Rien n'a bougé : ni la fiche, ni le lien des ventes, factures et devis.
      expect(await clients.obtenir(c.id), isNotNull);
      expect((await db.select(db.ventes).get()).where((Vente v) => v.clientId == c.id), isNotEmpty);
      expect((await db.select(db.ventes).get()).every((Vente v) => v.clientNom == null), isTrue);
      expect((await db.select(db.devis).get()).single.clientId, c.id);
      expect((await db.select(db.factures).get()).single.clientId, c.id);

      // L'archivage, lui, reste possible, et ne lève pas l'interdiction.
      await clients.archiver(c.id);
      await expectLater(clients.supprimer(c.id), throwsA(isA<SuppressionImpossible>()));
    });

    test('désinscrit, il peut être supprimé', () async {
      await remplirBase(db);
      final Client c = (await clients.lister()).single;
      await db.delete(db.inscriptionsCours).go();

      await clients.supprimer(c.id);

      expect(await clients.obtenir(c.id), isNull);
      expect((await db.select(db.ventes).get()).where((Vente v) => v.clientNom == 'Marie Dupont'), hasLength(1));
    });

    test('une vente « client de passage » n’est pas touchée par la suppression d’un client', () async {
      final int passage = await db.insererVente();
      final Client c = await clients.creer(const DonneesClient(nom: 'Martin'));
      await clients.supprimer(c.id);

      final Vente v = (await db.select(db.ventes).get()).singleWhere((Vente x) => x.id == passage);
      expect(v.clientId, isNull);
      expect(v.clientNom, isNull);
    });

    test('un client inconnu', () async {
      await expectLater(clients.supprimer(4242), throwsA(isA<ElementIntrouvable>()));
    });

    test('nomClientOuCopie : la fiche, sinon le nom copié, sinon le libellé par défaut', () async {
      final Client c = await clients.creer(const DonneesClient(prenom: 'Marie', nom: 'Dupont'));
      expect(nomClientOuCopie(client: c, copie: 'Autre', sinon: 'Client de passage'), 'Marie Dupont');
      expect(nomClientOuCopie(copie: 'Marie Dupont', sinon: 'Client de passage'), 'Marie Dupont (client supprimé)');
      expect(nomClientOuCopie(copie: '  ', sinon: 'Sans client'), 'Sans client');
      expect(nomClientOuCopie(sinon: 'Client de passage'), 'Client de passage');
    });
  });

  group('produits', () {
    test('un produit sans historique est supprimé avec ses variantes et ses photos, les fichiers sont rendus', () async {
      final Produit p = await produits.creer(doudou);
      final Produit autre = await produits.creer(doudou);
      await produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose', quantiteStock: 2));
      await produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Bleu'));
      await produits.ajouterPhoto(p.id, 'secondaire_1.jpg');
      await produits.ajouterPhoto(p.id, 'secondaire_2.jpg');
      await produits.ajouterPhoto(autre.id, 'autre.jpg');

      expect((await produits.usage(p.id)).estUtilise, isFalse);
      final List<String> fichiers = await produits.supprimer(p.id);

      expect(fichiers, unorderedEquals(<String>['principale.jpg', 'secondaire_1.jpg', 'secondaire_2.jpg']));
      expect(await produits.obtenir(p.id), isNull);
      expect(await db.select(db.variantesProduit).get(), isEmpty);
      final List<PhotoProduit> photos = await db.select(db.photosProduit).get();
      expect(photos.map((PhotoProduit x) => x.chemin), <String>['autre.jpg']);
      expect(await produits.obtenir(autre.id), isNotNull);
    });

    test('un produit archivé peut être supprimé', () async {
      final Produit p = await produits.creer(doudou);
      await produits.archiver(p.id);
      await produits.supprimer(p.id);
      expect(await produits.obtenir(p.id), isNull);
    });

    test('la référence d’un produit supprimé n’est pas réutilisée', () async {
      final Produit p = await produits.creer(doudou);
      expect(p.reference, 'PRD-0001');
      await produits.supprimer(p.id);
      expect((await produits.creer(doudou)).reference, 'PRD-0002');
    });

    test('un produit vendu est supprimé : la vente reste, avec sa désignation, sa quantité et son prix', () async {
      final Produit p = await produits.creer(doudou);
      final Produit autre = await produits.creer(doudou);
      final VarianteProduit rose = await produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));
      final int vente = await db.insererVente();
      final int l1 = await ajouterLigneVente(vente, produitId: p.id, varianteId: rose.id, designation: 'Doudou lapin – Rose');
      final int l2 = await ajouterLigneVente(vente, produitId: p.id); // deux lignes, une seule vente
      final int lAutre = await ajouterLigneVente(vente, produitId: autre.id, designation: 'Autre doudou');

      expect((await produits.usage(p.id)).enumeration, '1 vente');
      await produits.supprimer(p.id);

      expect(await produits.obtenir(p.id), isNull);
      expect(await db.select(db.variantesProduit).get(), isEmpty);
      final List<LigneVente> lignes = await db.select(db.lignesVente).get();
      expect(lignes, hasLength(3));
      final LigneVente a = lignes.firstWhere((LigneVente l) => l.id == l1);
      expect(a.produitId, isNull);
      expect(a.varianteId, isNull);
      expect(a.designation, 'Doudou lapin – Rose');
      expect(a.quantite, 1);
      expect(a.prixUnitaireCentimes, 1000);
      expect(lignes.firstWhere((LigneVente l) => l.id == l2).produitId, isNull);
      expect(lignes.firstWhere((LigneVente l) => l.id == lAutre).produitId, autre.id);
      // La vente elle-même n'a pas bougé.
      expect((await db.select(db.ventes).get()).single.totalCentimes, 1000);
    });

    test('une ligne qui ne désigne que l’une de ses variantes compte aussi, et est détachée', () async {
      final Produit p = await produits.creer(doudou);
      final VarianteProduit v = await produits.ajouterVariante(p.id, const DonneesVariante(libelle: 'Rose'));
      final int ligne = await ajouterLigneVente(await db.insererVente(), varianteId: v.id, produitId: p.id);

      expect((await produits.usage(p.id)).enumeration, '1 vente');
      await produits.supprimer(p.id);

      final LigneVente l = (await db.select(db.lignesVente).get()).single;
      expect(l.id, ligne);
      expect(l.produitId, isNull);
      expect(l.varianteId, isNull);
    });

    test('un produit présent dans un devis : le devis reste, ses lignes sont détachées', () async {
      final Produit p = await produits.creer(doudou);
      final int devis = await ajouterDevis();
      await ajouterLigneDevis(devis, produitId: p.id);

      expect((await produits.usage(p.id)).enumeration, '1 devis');
      await produits.supprimer(p.id);

      final LigneDevis l = (await db.select(db.lignesDevis).get()).single;
      expect(l.produitId, isNull);
      expect(l.designation, 'Couverture sur mesure');
      expect(l.totalLigneCentimes, 6000);
      expect((await db.select(db.devis).get()).single.totalCentimes, 6000);
    });

    test('une vente est comptée, puis conservée', () async {
      await remplirBase(db); // ses lignes de devis sont des lignes libres : seule la vente cite le produit
      final Produit p = (await produits.lister()).single;
      expect((await produits.usage(p.id)).enumeration, '1 vente');

      await produits.supprimer(p.id);

      expect(await produits.obtenir(p.id), isNull);
      expect((await db.select(db.lignesVente).get()).every((LigneVente l) => l.produitId == null), isTrue);
      expect((await db.select(db.lignesDevis).get()).every((LigneDevis l) => l.produitId == null), isTrue);
      expect(await db.select(db.ventes).get(), isNotEmpty);
      expect(await db.select(db.devis).get(), isNotEmpty);
    });

    test('les dépenses qui désignent le produit sont conservées, détachées du produit', () async {
      final Produit p = await produits.creer(doudou);
      await db
          .into(db.depenses)
          .insert(
            DepensesCompanion.insert(
              dateDepense: DateTime(2026, 10, 5),
              categorie: CategorieDepense.laineFil,
              montantCentimes: 2490,
              fournisseur: const Value('Mercerie du Port'),
              produitId: Value(p.id),
            ),
          );

      expect(await produits.nombreDepensesLiees(p.id), 1);
      await produits.supprimer(p.id);

      final Depense d = (await db.select(db.depenses).get()).single;
      expect(d.produitId, isNull);
      expect(d.montantCentimes, 2490);
      expect(d.fournisseur, 'Mercerie du Port');
      expect(await produits.nombreDepensesLiees(p.id), 0);
    });

    test('un produit inconnu', () async {
      await expectLater(produits.supprimer(4242), throwsA(isA<ElementIntrouvable>()));
    });
  });
}
