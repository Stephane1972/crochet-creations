import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/depense_repository.dart';
import 'package:crochet_creations/data/repositories/depense_vues.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late DepenseRepository depenses;

  // Un « aujourd'hui » fixe : les tests ne dépendent pas de la date réelle.
  final DateTime maintenant = DateTime(2026, 10, 29, 15);

  setUp(() {
    db = creerBaseEnMemoire();
    depenses = DepenseRepository(db);
  });
  tearDown(() => db.close());

  DonneesDepense donnees({
    DateTime? date,
    CategorieDepense categorie = CategorieDepense.laineFil,
    int montant = 2490,
    String? fournisseur = 'Mercerie du Port',
    String? description = '10 pelotes de coton',
    String? photo,
    int? produitId,
  }) => DonneesDepense(
    date: date ?? DateTime(2026, 10, 20),
    categorie: categorie,
    montantCentimes: montant,
    fournisseur: fournisseur,
    description: description,
    photoTicketChemin: photo,
    produitId: produitId,
  );

  Future<Depense> creer(DonneesDepense d) => depenses.creer(d, maintenant: maintenant);

  Future<String> message(Future<Object?> Function() action) async {
    try {
      await action();
    } on ErreurMetier catch (erreur) {
      return erreur.message;
    }
    fail('Une erreur était attendue.');
  }

  Future<ListeDepenses> octobre({CategorieDepense? categorie, bool archivees = false}) =>
      depenses.lister(annee: 2026, mois: 10, categorie: categorie, archivees: archivees);

  group('créer et modifier une dépense', () {
    test('enregistre la dépense, texte nettoyé et champs vides remplacés par rien', () async {
      final Depense d = await creer(
        donnees(date: DateTime(2026, 10, 20, 17, 45), fournisseur: '  Mercerie  ', description: '   ', photo: 'ticket.jpg'),
      );
      expect(d.dateDepense, DateTime(2026, 10, 20));
      expect(d.categorie, CategorieDepense.laineFil);
      expect(d.montantCentimes, 2490);
      expect(d.fournisseur, 'Mercerie');
      expect(d.description, isNull);
      expect(d.photoTicketChemin, 'ticket.jpg');
      expect(d.produitId, isNull);
      expect(d.archiveLe, isNull);
    });

    test('toutes les catégories sont acceptées', () async {
      for (final CategorieDepense c in CategorieDepense.values) {
        final Depense d = await creer(donnees(categorie: c));
        expect(d.categorie, c);
      }
      expect((await octobre()).lignes.length, CategorieDepense.values.length);
    });

    test('refuse un montant nul ou négatif, une date future, rien n’est enregistré', () async {
      expect(await message(() => creer(donnees(montant: 0))), contains('supérieur à 0'));
      expect(await message(() => creer(donnees(montant: -5))), contains('supérieur à 0'));
      expect(await message(() => creer(donnees(date: DateTime(2026, 10, 30)))), contains('dans le futur'));
      expect((await octobre()).vide, isTrue);
    });

    test('accepte la date du jour', () async {
      final Depense d = await creer(donnees(date: DateTime(2026, 10, 29, 9)));
      expect(d.dateDepense, DateTime(2026, 10, 29));
    });

    test('lie un produit existant, refuse un produit inconnu', () async {
      final int produitId = await db.insererProduit();
      final Depense d = await creer(donnees(produitId: produitId));
      expect(d.produitId, produitId);

      expect(await message(() => creer(donnees(produitId: 9999))), 'Ce produit n’existe plus.');
      expect((await octobre()).lignes.length, 1);
    });

    test('lier un produit ne modifie ni son coût matière ni son stock', () async {
      final int produitId = await db.insererProduit(stock: 5);
      final Produit avant = await (db.select(db.produits)..where((t) => t.id.equals(produitId))).getSingle();
      await creer(donnees(produitId: produitId, montant: 9900));
      final Produit apres = await (db.select(db.produits)..where((t) => t.id.equals(produitId))).getSingle();
      expect(apres.coutMatiereCentimes, avant.coutMatiereCentimes);
      expect(apres.quantiteStock, avant.quantiteStock);
    });

    test('modifie tous les champs', () async {
      final int produitId = await db.insererProduit();
      final Depense d = await creer(donnees());
      final Depense m = await depenses.modifier(
        d.id,
        donnees(
          date: DateTime(2026, 10, 2),
          categorie: CategorieDepense.standMarche,
          montant: 3500,
          fournisseur: 'Mairie',
          description: 'Emplacement marché de Noël',
          photo: 'recu.jpg',
          produitId: produitId,
        ),
        maintenant: maintenant,
      );
      expect(m.id, d.id);
      expect(m.dateDepense, DateTime(2026, 10, 2));
      expect(m.categorie, CategorieDepense.standMarche);
      expect(m.montantCentimes, 3500);
      expect(m.fournisseur, 'Mairie');
      expect(m.photoTicketChemin, 'recu.jpg');
      expect(m.produitId, produitId);
    });

    test('retirer la photo et le produit à la modification', () async {
      final int produitId = await db.insererProduit();
      final Depense d = await creer(donnees(photo: 'ticket.jpg', produitId: produitId));
      final Depense m = await depenses.modifier(d.id, donnees(), maintenant: maintenant);
      expect(m.photoTicketChemin, isNull);
      expect(m.produitId, isNull);
    });

    test('modifier refuse les mêmes valeurs et une dépense inconnue', () async {
      final Depense d = await creer(donnees());
      expect(
        await message(() => depenses.modifier(d.id, donnees(montant: 0), maintenant: maintenant)),
        contains('supérieur à 0'),
      );
      expect(
        await message(() => depenses.modifier(999, donnees(), maintenant: maintenant)),
        'Cette dépense n’existe plus.',
      );
      expect((await depenses.obtenir(d.id))!.montantCentimes, 2490);
    });
  });

  group('liste et total du mois', () {
    test('ne garde que le mois demandé, la plus récente d’abord, avec le total', () async {
      await creer(donnees(date: DateTime(2026, 10, 3), montant: 1000));
      await creer(donnees(date: DateTime(2026, 10, 25), montant: 2000));
      await creer(donnees(date: DateTime(2026, 10, 25), montant: 500));
      await creer(donnees(date: DateTime(2026, 9, 30), montant: 7000));
      await creer(donnees(date: DateTime(2025, 10, 10), montant: 9000));

      final ListeDepenses liste = await octobre();
      expect(liste.lignes.map((DepenseLigne l) => l.depense.montantCentimes), <int>[500, 2000, 1000]);
      expect(liste.totalCentimes, 3500);

      final ListeDepenses septembre = await depenses.lister(annee: 2026, mois: 9);
      expect(septembre.totalCentimes, 7000);
    });

    test('le premier et le dernier jour du mois en font partie', () async {
      await creer(donnees(date: DateTime(2026, 10, 1), montant: 100));
      await creer(donnees(date: DateTime(2026, 9, 30), montant: 200));
      expect((await octobre()).totalCentimes, 100);
      expect((await depenses.lister(annee: 2026, mois: 9)).totalCentimes, 200);
    });

    test('un mois sans dépense : liste vide, total à zéro', () async {
      final ListeDepenses liste = await depenses.lister(annee: 2026, mois: 1);
      expect(liste.vide, isTrue);
      expect(liste.totalCentimes, 0);
    });

    test('le filtre de catégorie réduit la liste et le total', () async {
      await creer(donnees(categorie: CategorieDepense.laineFil, montant: 1000));
      await creer(donnees(categorie: CategorieDepense.laineFil, montant: 2000));
      await creer(donnees(categorie: CategorieDepense.emballage, montant: 450));

      final ListeDepenses laine = await octobre(categorie: CategorieDepense.laineFil);
      expect(laine.lignes.length, 2);
      expect(laine.totalCentimes, 3000);
      expect((await octobre(categorie: CategorieDepense.emballage)).totalCentimes, 450);
      expect((await octobre(categorie: CategorieDepense.publicite)).vide, isTrue);
      expect((await octobre()).totalCentimes, 3450);
    });

    test('une ligne donne le produit concerné (ou aucun)', () async {
      final int produitId = await db.insererProduit(reference: 'PRD-0007');
      await creer(donnees(produitId: produitId, montant: 100));
      await creer(donnees(montant: 200));

      final ListeDepenses liste = await octobre();
      final DepenseLigne sansProduit = liste.lignes.firstWhere((DepenseLigne l) => l.depense.montantCentimes == 200);
      final DepenseLigne avecProduit = liste.lignes.firstWhere((DepenseLigne l) => l.depense.montantCentimes == 100);
      expect(sansProduit.produit, isNull);
      expect(avecProduit.produit?.reference, 'PRD-0007');
    });
  });

  group('archiver et restaurer', () {
    test('une dépense archivée quitte la liste et le total, puis revient', () async {
      final Depense a = await creer(donnees(montant: 1000));
      await creer(donnees(montant: 2000));

      await depenses.archiver(a.id);
      expect((await depenses.obtenir(a.id))!.archiveLe, isNotNull);
      expect((await octobre()).totalCentimes, 2000);
      final ListeDepenses archivees = await octobre(archivees: true);
      expect(archivees.lignes.single.depense.id, a.id);
      expect(archivees.totalCentimes, 1000);

      await depenses.restaurer(a.id);
      expect((await depenses.obtenir(a.id))!.archiveLe, isNull);
      expect((await octobre()).totalCentimes, 3000);
      expect((await octobre(archivees: true)).vide, isTrue);
    });

    test('archiver ou restaurer une dépense inconnue est refusé', () async {
      expect(await message(() => depenses.archiver(404)), 'Cette dépense n’existe plus.');
      expect(await message(() => depenses.restaurer(404)), 'Cette dépense n’existe plus.');
    });

    test('une dépense archivée peut encore être modifiée', () async {
      final Depense a = await creer(donnees());
      await depenses.archiver(a.id);
      final Depense m = await depenses.modifier(a.id, donnees(montant: 777), maintenant: maintenant);
      expect(m.montantCentimes, 777);
      expect(m.archiveLe, isNotNull);
    });
  });

  group('suivi en direct', () {
    test('la liste se met à jour toute seule quand on ajoute ou archive une dépense', () async {
      final List<int> totaux = <int>[];
      Completer<void> prochain = Completer<void>();
      final StreamSubscription<ListeDepenses> abonnement = depenses.observerListe(annee: 2026, mois: 10).listen((
        ListeDepenses l,
      ) {
        totaux.add(l.totalCentimes);
        if (!prochain.isCompleted) prochain.complete();
      });

      await prochain.future.timeout(const Duration(seconds: 5));
      expect(totaux, <int>[0]);

      prochain = Completer<void>();
      final Depense d = await creer(donnees(montant: 1500));
      await prochain.future.timeout(const Duration(seconds: 5));
      expect(totaux.last, 1500);

      prochain = Completer<void>();
      await depenses.archiver(d.id);
      await prochain.future.timeout(const Duration(seconds: 5));
      expect(totaux.last, 0);

      await abonnement.cancel();
    });
  });
}
