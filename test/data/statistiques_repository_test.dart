import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/statistiques_repository.dart';
import 'package:crochet_creations/data/repositories/statistiques_vues.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/calculs/statistiques.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

/// Une ligne de vente à préparer.
class _L {
  const _L(
    this.designation, {
    this.nature = NatureLigne.bien,
    this.quantite = 1,
    this.prix = 1000,
    this.cout = 0,
    this.produitId,
    this.coursId,
  });

  final String designation;
  final NatureLigne nature;
  final int quantite;
  final int prix;
  final int cout;
  final int? produitId;
  final int? coursId;
}

/// Un encaissement (montant positif) ou un remboursement (négatif).
class _P {
  const _P(this.date, this.montant);

  final DateTime date;
  final int montant;
}

void main() {
  late AppDatabase db;
  late StatistiquesRepository stats;
  int numeroProduit = 0;
  int numeroFacture = 0;

  // Jeudi 29 octobre 2026 : la semaine va du lundi 26 octobre au dimanche 1er novembre.
  final DateTime maintenant = DateTime(2026, 10, 29, 15);

  setUp(() {
    db = creerBaseEnMemoire();
    stats = StatistiquesRepository(db);
    numeroProduit = 0;
    numeroFacture = 0;
  });
  tearDown(() => db.close());

  Future<int> produit(CategorieProduit categorie) => db
      .into(db.produits)
      .insert(
        ProduitsCompanion.insert(
          reference: 'PRD-${++numeroProduit}',
          nom: 'Produit $numeroProduit',
          categorie: categorie,
          prixVenteCentimes: 1000,
        ),
      );

  Future<int> cours() => db
      .into(db.cours)
      .insert(
        CoursCompanion.insert(
          titre: 'Initiation',
          debutLe: DateTime(2026, 11, 14, 14),
          dureeMinutes: 120,
          prixCentimes: 4500,
          places: 6,
        ),
      );

  /// Insère une vente telle que la valideraient les écrans, avec une date et des paiements choisis.
  Future<int> vente({
    required DateTime date,
    required List<_L> lignes,
    List<_P> paiements = const <_P>[],
    int remise = 0,
    int port = 0,
    bool annulee = false,
  }) async {
    final int sousTotal = lignes.fold(0, (int s, _L l) => s + l.quantite * l.prix);
    final int id = await db
        .into(db.ventes)
        .insert(
          VentesCompanion.insert(
            sousTotalCentimes: sousTotal,
            totalCentimes: sousTotal - remise + port,
            dateVente: Value(date),
            statut: Value(annulee ? StatutVente.annulee : StatutVente.validee),
            remiseType: Value(remise > 0 ? RemiseType.montant : RemiseType.aucune),
            remiseValeur: Value(remise),
            remiseCentimes: Value(remise),
            fraisPortCentimes: Value(port),
          ),
        );
    for (int i = 0; i < lignes.length; i++) {
      final _L l = lignes[i];
      await db
          .into(db.lignesVente)
          .insert(
            LignesVenteCompanion.insert(
              venteId: id,
              designation: l.designation,
              quantite: l.quantite,
              prixUnitaireCentimes: l.prix,
              totalLigneCentimes: l.quantite * l.prix,
              position: Value(i),
              nature: Value(l.nature),
              produitId: Value(l.produitId),
              coursId: Value(l.coursId),
              coutUnitaireCentimes: Value(l.cout),
            ),
          );
    }
    for (final _P p in paiements) {
      await db
          .into(db.paiements)
          .insert(
            PaiementsCompanion.insert(
              venteId: id,
              montantCentimes: p.montant,
              modePaiement: ModePaiement.especes,
              datePaiement: Value(p.date),
            ),
          );
    }
    return id;
  }

  Future<void> facture(int venteId, {StatutFacture statut = StatutFacture.emise}) async {
    final Vente v = await (db.select(db.ventes)..where((t) => t.id.equals(venteId))).getSingle();
    await db
        .into(db.factures)
        .insert(
          FacturesCompanion.insert(
            numero: 'FACT-2026-${(++numeroFacture).toString().padLeft(4, '0')}',
            venteId: venteId,
            dateVentePrestation: v.dateVente,
            totalCentimes: v.totalCentimes,
            statut: Value(statut),
          ),
        );
  }

  Future<void> depense(DateTime date, CategorieDepense categorie, int montant, {bool archivee = false}) => db
      .into(db.depenses)
      .insert(
        DepensesCompanion.insert(
          dateDepense: date,
          categorie: categorie,
          montantCentimes: montant,
          archiveLe: Value(archivee ? DateTime(2026, 10, 28) : null),
        ),
      );

  Future<Statistiques> calculer() => stats.calculer(maintenant: maintenant);

  group('base vide', () {
    test('tout est à zéro, sans panier moyen', () async {
      final Statistiques s = await calculer();
      for (final PeriodeStats p in PeriodeStats.values) {
        final StatsPeriode v = s.periode(p);
        expect(v.encaisseTotalCentimes, 0, reason: '$p');
        expect(v.coutCentimes, 0);
        expect(v.nombreVentes, 0);
        expect(v.panierMoyenCentimes, isNull);
        expect(v.meilleuresVentes, isEmpty);
        expect(v.categories, isEmpty);
        expect(v.depenses, isEmpty);
      }
      expect(s.facturesImpayeesNombre, 0);
      expect(s.facturesImpayeesCentimes, 0);
      expect(s.franchiseObjetsCentimes, 0);
      expect(s.franchisePrestationsCentimes, 0);
    });
  });

  group('argent encaissé par période', () {
    test('chaque paiement compte dans le jour, la semaine, le mois et l’année qui le contiennent', () async {
      final int doudou = await produit(CategorieProduit.doudou);
      _L article(int prix) => _L('Doudou', prix: prix, cout: 100, produitId: doudou);

      final DateTime aujourdhui = DateTime(2026, 10, 29, 10);
      final DateTime cetteSemaine = DateTime(2026, 10, 27, 11);
      final DateTime ceMois = DateTime(2026, 10, 5, 9);
      final DateTime cetteAnnee = DateTime(2026, 3, 3, 16);
      final DateTime anneeDerniere = DateTime(2025, 12, 30, 12);
      for (final _P v in <_P>[
        _P(aujourdhui, 5000),
        _P(cetteSemaine, 2000),
        _P(ceMois, 3000),
        _P(cetteAnnee, 4000),
        _P(anneeDerniere, 9000),
      ]) {
        await vente(date: v.date, lignes: <_L>[article(v.montant)], paiements: <_P>[v]);
      }

      final Statistiques s = await calculer();
      expect(s.periode(PeriodeStats.jour).encaisseTotalCentimes, 5000);
      expect(s.periode(PeriodeStats.semaine).encaisseTotalCentimes, 7000);
      expect(s.periode(PeriodeStats.mois).encaisseTotalCentimes, 10000);
      expect(s.periode(PeriodeStats.annee).encaisseTotalCentimes, 14000);
      expect(s.franchiseObjetsCentimes, 14000);
      expect(s.franchisePrestationsCentimes, 0);
      // 100 centimes de coût par article vendu, au prorata de l'encaissé.
      expect(s.periode(PeriodeStats.annee).coutCentimes, 400);
      expect(s.periode(PeriodeStats.annee).margeCentimes, 13600);
    });

    test('un acompte puis le solde : chaque paiement compte dans sa propre période', () async {
      final int plaid = await produit(CategorieProduit.crochet);
      await vente(
        date: DateTime(2026, 9, 28, 10),
        lignes: <_L>[_L('Plaid', prix: 10000, cout: 3000, produitId: plaid)],
        paiements: <_P>[_P(DateTime(2026, 9, 28, 10), 4000), _P(DateTime(2026, 10, 27, 17), 6000)],
      );

      final Statistiques s = await calculer();
      expect(s.periode(PeriodeStats.mois).encaisseTotalCentimes, 6000);
      expect(s.periode(PeriodeStats.mois).coutCentimes, 1800);
      expect(s.periode(PeriodeStats.mois).nombreVentes, 0); // vendu en septembre
      expect(s.periode(PeriodeStats.annee).encaisseTotalCentimes, 10000);
      expect(s.periode(PeriodeStats.annee).coutCentimes, 3000);
      expect(s.periode(PeriodeStats.annee).nombreVentes, 1);
    });

    test('un remboursement retire l’argent dans la période où il est fait', () async {
      await vente(
        date: DateTime(2026, 10, 5, 10),
        annulee: true,
        lignes: <_L>[const _L('Bonnet', prix: 5000, cout: 1500)],
        paiements: <_P>[_P(DateTime(2026, 10, 5, 10), 5000), _P(DateTime(2026, 10, 27, 9), -5000)],
      );

      final Statistiques s = await calculer();
      expect(s.periode(PeriodeStats.mois).encaisseTotalCentimes, 0);
      expect(s.periode(PeriodeStats.mois).coutCentimes, 0);
      expect(s.periode(PeriodeStats.semaine).encaisseTotalCentimes, -5000);
      expect(s.periode(PeriodeStats.semaine).coutCentimes, -1500);
      expect(s.periode(PeriodeStats.semaine).margeCentimes, -3500);
      expect(s.periode(PeriodeStats.mois).nombreVentes, 0);
      expect(s.periode(PeriodeStats.mois).meilleuresVentes, isEmpty);
      expect(s.periode(PeriodeStats.annee).encaisseTotalCentimes, 0);
    });

    test('annuler une vraie vente efface son chiffre d’affaires du jour', () async {
      final ProduitRepository produits = ProduitRepository(db, NumerotationRepository(db));
      final VenteRepository ventes = VenteRepository(db, produits);
      final Produit doudou = await produits.creer(
        const DonneesProduit(
          nom: 'Doudou lapin',
          categorie: CategorieProduit.doudou,
          prixVenteCentimes: 2500,
          coutMatiereCentimes: 600,
          quantiteStock: 5,
        ),
      );
      final Vente v = await ventes.valider(
        panier: const Panier().ajouter(
          produitId: doudou.id,
          designation: doudou.nom,
          prixUnitaireCentimes: 2500,
          quantite: 2,
          stockDisponible: 5,
        ),
        paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 5000),
      );

      final DateTime maintenantReel = DateTime.now();
      Statistiques s = await stats.calculer(maintenant: maintenantReel);
      expect(s.periode(PeriodeStats.jour).encaisseObjetsCentimes, 5000);
      expect(s.periode(PeriodeStats.jour).coutCentimes, 1200);
      expect(s.periode(PeriodeStats.jour).nombreVentes, 1);
      expect(s.periode(PeriodeStats.jour).meilleuresVentes.single.designation, 'Doudou lapin');

      await ventes.annuler(v.id);
      s = await stats.calculer(maintenant: maintenantReel);
      expect(s.periode(PeriodeStats.jour).encaisseTotalCentimes, 0);
      expect(s.periode(PeriodeStats.jour).coutCentimes, 0);
      expect(s.periode(PeriodeStats.jour).nombreVentes, 0);
      expect(s.periode(PeriodeStats.jour).meilleuresVentes, isEmpty);
    });

    test('la semaine qui chevauche deux années compte les paiements de décembre', () async {
      await vente(
        date: DateTime(2026, 12, 29, 10),
        lignes: <_L>[const _L('Écharpe', prix: 3000)],
        paiements: <_P>[_P(DateTime(2026, 12, 29, 10), 3000)],
      );
      await vente(
        date: DateTime(2027, 1, 1, 10),
        lignes: <_L>[const _L('Bonnet', prix: 2000)],
        paiements: <_P>[_P(DateTime(2027, 1, 1, 10), 2000)],
      );

      final Statistiques s = await stats.calculer(maintenant: DateTime(2027, 1, 1, 18));
      expect(s.periode(PeriodeStats.semaine).encaisseTotalCentimes, 5000);
      expect(s.periode(PeriodeStats.mois).encaisseTotalCentimes, 2000);
      expect(s.periode(PeriodeStats.annee).encaisseTotalCentimes, 2000);
      expect(s.franchiseObjetsCentimes, 2000);
    });
  });

  group('objets, prestations, cours, catégories', () {
    test('un encaissement est réparti entre les lignes, la remise et les frais de port compris', () async {
      final int doudou = await produit(CategorieProduit.doudou);
      final int unCours = await cours();
      final DateTime date = DateTime(2026, 10, 28, 10);
      await vente(
        date: date,
        lignes: <_L>[
          _L('Doudou', quantite: 2, prix: 1500, cout: 400, produitId: doudou),
          _L('Cours : Initiation', nature: NatureLigne.service, prix: 4500, coursId: unCours),
          const _L('Retouche', nature: NatureLigne.service),
        ],
        remise: 500,
        port: 300,
        paiements: <_P>[_P(date, 8300)],
      );

      final StatsPeriode mois = (await calculer()).periode(PeriodeStats.mois);
      // Remise de 5 € répartie : 1,76 € sur le doudou, 2,65 € sur le cours, 0,59 € sur la retouche.
      expect(mois.encaisseObjetsCentimes, 3124); // doudou 28,24 € + frais de port 3 €
      expect(mois.encaissePrestationsCentimes, 5176); // cours 42,35 € + retouche 9,41 €
      expect(mois.encaisseCoursCentimes, 4235);
      expect(mois.encaisseTotalCentimes, 8300);
      expect(mois.coutCentimes, 800);
      expect(mois.margeCentimes, 7500);
      expect(mois.categories, hasLength(1));
      expect(mois.categories.single.categorie, CategorieProduit.doudou);
      expect(mois.categories.single.encaisseCentimes, 2824);
      expect(mois.categories.single.coutCentimes, 800);
      expect(mois.categories.single.margeCentimes, 2024);
    });

    test('catégories classées par marge', () async {
      final int doudou = await produit(CategorieProduit.doudou);
      final int plaid = await produit(CategorieProduit.crochet);
      final DateTime date = DateTime(2026, 10, 10, 10);
      await vente(
        date: date,
        lignes: <_L>[
          _L('Doudou', prix: 3000, cout: 1000, produitId: doudou),
          _L('Plaid', prix: 10000, cout: 3000, produitId: plaid),
        ],
        paiements: <_P>[_P(date, 13000)],
      );

      final StatsPeriode mois = (await calculer()).periode(PeriodeStats.mois);
      expect(mois.categories.map((CategorieRentable c) => c.categorie), <CategorieProduit>[
        CategorieProduit.crochet,
        CategorieProduit.doudou,
      ]);
      expect(mois.categories.first.margeCentimes, 7000);
      expect(mois.categories.last.margeCentimes, 2000);
    });
  });

  group('ventes faites pendant la période', () {
    test('meilleures ventes et panier moyen ne comptent que les ventes validées du mois', () async {
      final int bonnet = await produit(CategorieProduit.crochet);
      final int echarpe = await produit(CategorieProduit.crochet);
      final DateTime octobre = DateTime(2026, 10, 12, 10);
      await vente(
        date: octobre,
        lignes: <_L>[
          _L('Bonnet', quantite: 2, prix: 2000, produitId: bonnet),
          _L('Écharpe', prix: 3500, produitId: echarpe),
        ],
      );
      await vente(date: octobre, lignes: <_L>[_L('Bonnet', prix: 2000, produitId: bonnet)]);
      await vente(date: DateTime(2026, 9, 12), lignes: <_L>[_L('Bonnet', quantite: 9, prix: 2000, produitId: bonnet)]);
      await vente(date: octobre, annulee: true, lignes: <_L>[_L('Bonnet', quantite: 9, prix: 2000, produitId: bonnet)]);

      final StatsPeriode mois = (await calculer()).periode(PeriodeStats.mois);
      expect(mois.nombreVentes, 2);
      expect(mois.totalVentesCentimes, 7500 + 2000);
      expect(mois.panierMoyenCentimes, 4750);
      expect(mois.meilleuresVentes.map((VenteProduit v) => '${v.designation}×${v.quantite}'), <String>[
        'Bonnet×3',
        'Écharpe×1',
      ]);
      expect(mois.meilleuresVentes.first.totalCentimes, 6000);
    });

    test('les cours ne sont pas dans les meilleures ventes', () async {
      final int unCours = await cours();
      await vente(
        date: DateTime(2026, 10, 12, 10),
        lignes: <_L>[_L('Cours : Initiation', nature: NatureLigne.service, prix: 4500, coursId: unCours)],
      );
      final StatsPeriode mois = (await calculer()).periode(PeriodeStats.mois);
      expect(mois.meilleuresVentes, isEmpty);
      expect(mois.nombreVentes, 1);
    });
  });

  group('dépenses', () {
    test('par catégorie et par période, sans les dépenses archivées', () async {
      await depense(DateTime(2026, 10, 27), CategorieDepense.laineFil, 2490);
      await depense(DateTime(2026, 10, 3), CategorieDepense.laineFil, 1000);
      await depense(DateTime(2026, 10, 3), CategorieDepense.standMarche, 5000);
      await depense(DateTime(2026, 10, 3), CategorieDepense.emballage, 700, archivee: true);
      await depense(DateTime(2026, 9, 30), CategorieDepense.transport, 900);

      final Statistiques s = await calculer();
      final StatsPeriode mois = s.periode(PeriodeStats.mois);
      expect(mois.depenses.map((DepenseParCategorie d) => d.categorie), <CategorieDepense>[
        CategorieDepense.standMarche,
        CategorieDepense.laineFil,
      ]);
      expect(mois.depenses.last.totalCentimes, 3490);
      expect(mois.depensesTotalCentimes, 8490);
      expect(s.periode(PeriodeStats.semaine).depensesTotalCentimes, 2490);
      expect(s.periode(PeriodeStats.jour).depensesTotalCentimes, 0);
      expect(s.periode(PeriodeStats.annee).depensesTotalCentimes, 9390);
    });
  });

  group('factures impayées', () {
    test('factures émises dont la vente n’est pas soldée : nombre et reste à encaisser', () async {
      final DateTime date = DateTime(2026, 10, 10, 10);
      final int impayee = await vente(date: date, lignes: <_L>[const _L('A', prix: 5000)]);
      final int partielle = await vente(
        date: date,
        lignes: <_L>[const _L('B', prix: 4000)],
        paiements: <_P>[_P(date, 1500)],
      );
      final int payee = await vente(
        date: date,
        lignes: <_L>[const _L('C', prix: 3000)],
        paiements: <_P>[_P(date, 3000)],
      );
      final int annulee = await vente(
        date: date,
        annulee: true,
        lignes: <_L>[const _L('D', prix: 2000)],
      );
      final int factureAnnulee = await vente(date: date, lignes: <_L>[const _L('E', prix: 1000)]);
      await vente(date: date, lignes: <_L>[const _L('F', prix: 800)]); // pas de facture

      await facture(impayee);
      await facture(partielle);
      await facture(payee);
      await facture(annulee);
      await facture(factureAnnulee, statut: StatutFacture.annulee);

      final Statistiques s = await calculer();
      expect(s.facturesImpayeesNombre, 2);
      expect(s.facturesImpayeesCentimes, 5000 + 2500);
    });

    test('un remboursement partiel rouvre le solde de la facture', () async {
      final DateTime date = DateTime(2026, 10, 10, 10);
      final int id = await vente(
        date: date,
        lignes: <_L>[const _L('G', prix: 6000)],
        paiements: <_P>[_P(date, 6000), _P(DateTime(2026, 10, 11), -2000)],
      );
      await facture(id);

      final Statistiques s = await calculer();
      expect(s.facturesImpayeesNombre, 1);
      expect(s.facturesImpayeesCentimes, 2000);
    });
  });

  group('en direct', () {
    test('le flux se met à jour quand une vente est payée', () async {
      final DateTime date = DateTime(2026, 10, 29, 10);
      final int id = await vente(date: date, lignes: <_L>[const _L('Bonnet', prix: 2000)]);

      final List<int> encaisses = <int>[];
      Completer<void> prochain = Completer<void>();
      final StreamSubscription<Statistiques> abonnement = stats.observer(horloge: () => maintenant).listen((Statistiques s) {
        encaisses.add(s.periode(PeriodeStats.jour).encaisseTotalCentimes);
        if (!prochain.isCompleted) prochain.complete();
      });

      await prochain.future.timeout(const Duration(seconds: 5));
      expect(encaisses, <int>[0]);

      prochain = Completer<void>();
      await db
          .into(db.paiements)
          .insert(
            PaiementsCompanion.insert(
              venteId: id,
              montantCentimes: 2000,
              modePaiement: ModePaiement.carte,
              datePaiement: Value(date),
            ),
          );
      await prochain.future.timeout(const Duration(seconds: 5));
      expect(encaisses.last, 2000);

      await abonnement.cancel();
    });
  });
}
