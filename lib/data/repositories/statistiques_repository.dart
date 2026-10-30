import 'package:drift/drift.dart';

import '../../domain/calculs/statistiques.dart';
import '../../domain/enums.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import 'statistiques_vues.dart';

typedef _Bornes = ({DateTime debut, DateTime fin});

/// Statistiques : lit les ventes, paiements, dépenses et factures, puis laisse `domain/calculs/statistiques.dart`
/// faire les calculs. Ce dépôt ne modifie jamais rien.
class StatistiquesRepository {
  StatistiquesRepository(this._db);

  final AppDatabase _db;

  /// Au plus ce nombre d'identifiants par requête (SQLite limite le nombre de paramètres d'une requête).
  static const int _tailleLot = 500;

  /// Calcule les chiffres des quatre périodes qui contiennent [maintenant] (par défaut : l'instant présent).
  Future<Statistiques> calculer({DateTime? maintenant}) async {
    final DateTime instant = maintenant ?? DateTime.now();
    final Map<PeriodeStats, _Bornes> bornes = <PeriodeStats, _Bornes>{
      for (final PeriodeStats p in PeriodeStats.values) p: bornesPeriode(p, instant),
    };
    // La période la plus longue commence le 1er janvier, sauf début janvier où la semaine peut commencer en décembre.
    final DateTime depuis = bornes.values
        .map((_Bornes b) => b.debut)
        .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);

    final List<VenteCompta> ventes = await _ventesComptables(depuis);
    final List<DepenseCompta> depenses = await _depensesComptables(depuis);
    final ({int nombre, int totalCentimes}) impayees = await _facturesImpayees();

    return Statistiques(
      maintenant: instant,
      periodes: <PeriodeStats, StatsPeriode>{
        for (final PeriodeStats p in PeriodeStats.values)
          p: calculerStatsPeriode(
            periode: p,
            debut: bornes[p]!.debut,
            fin: bornes[p]!.fin,
            ventes: ventes,
            depenses: depenses,
          ),
      },
      facturesImpayeesNombre: impayees.nombre,
      facturesImpayeesCentimes: impayees.totalCentimes,
    );
  }

  /// Chiffres mis à jour automatiquement (vente, paiement, remboursement, dépense, facture, produit modifiés).
  Stream<Statistiques> observer({DateTime Function()? horloge}) => observerTables(
    _db,
    <ResultSetImplementation>{
      _db.ventes,
      _db.lignesVente,
      _db.paiements,
      _db.depenses,
      _db.factures,
      _db.produits,
    },
    () => calculer(maintenant: horloge?.call()),
  );

  // --- Lecture ----------------------------------------------------------------

  /// Les ventes qui comptent à partir de [depuis] : celles faites depuis cette date, et les plus anciennes dont un
  /// paiement ou un remboursement est arrivé depuis (leur argent compte à la date où il a été encaissé).
  Future<List<VenteCompta>> _ventesComptables(DateTime depuis) async {
    final List<Paiement> paiements = await (_db.select(
      _db.paiements,
    )..where((t) => t.datePaiement.isBiggerOrEqualValue(depuis))).get();
    final List<Vente> recentes = await (_db.select(
      _db.ventes,
    )..where((t) => t.dateVente.isBiggerOrEqualValue(depuis))).get();

    final Map<int, Vente> ventes = <int, Vente>{for (final Vente v in recentes) v.id: v};
    final List<int> manquantes = <int>{
      for (final Paiement p in paiements)
        if (!ventes.containsKey(p.venteId)) p.venteId,
    }.toList();
    for (final List<int> lot in _enLots(manquantes)) {
      for (final Vente v in await (_db.select(_db.ventes)..where((t) => t.id.isIn(lot))).get()) {
        ventes[v.id] = v;
      }
    }
    if (ventes.isEmpty) return <VenteCompta>[];

    final Map<int, CategorieProduit> categories = <int, CategorieProduit>{
      for (final Produit p in await _db.select(_db.produits).get()) p.id: p.categorie,
    };

    final Map<int, List<LigneCompta>> lignesParVente = <int, List<LigneCompta>>{};
    for (final List<int> lot in _enLots(ventes.keys.toList())) {
      final List<LigneVente> lignes =
          await (_db.select(_db.lignesVente)
                ..where((t) => t.venteId.isIn(lot))
                ..orderBy([(t) => OrderingTerm.asc(t.position), (t) => OrderingTerm.asc(t.id)]))
              .get();
      for (final LigneVente l in lignes) {
        final int? produitId = l.produitId;
        lignesParVente
            .putIfAbsent(l.venteId, () => <LigneCompta>[])
            .add(
              LigneCompta(
                nature: l.nature,
                designation: l.designation,
                quantite: l.quantite,
                totalCentimes: l.totalLigneCentimes,
                coutUnitaireCentimes: l.coutUnitaireCentimes,
                produitId: produitId,
                categorie: produitId == null ? null : categories[produitId],
                coursId: l.coursId,
              ),
            );
      }
    }

    final Map<int, List<PaiementCompta>> paiementsParVente = <int, List<PaiementCompta>>{};
    for (final Paiement p in paiements) {
      paiementsParVente
          .putIfAbsent(p.venteId, () => <PaiementCompta>[])
          .add(PaiementCompta(date: p.datePaiement, montantCentimes: p.montantCentimes));
    }

    return <VenteCompta>[
      for (final Vente v in ventes.values)
        VenteCompta(
          date: v.dateVente,
          annulee: v.statut == StatutVente.annulee,
          lignes: lignesParVente[v.id] ?? <LigneCompta>[],
          paiements: paiementsParVente[v.id] ?? <PaiementCompta>[],
          remiseCentimes: v.remiseCentimes,
          fraisPortCentimes: v.fraisPortCentimes,
        ),
    ];
  }

  /// Les dépenses actives (non archivées) à partir de [depuis].
  Future<List<DepenseCompta>> _depensesComptables(DateTime depuis) async {
    final List<Depense> depenses =
        await (_db.select(_db.depenses)..where((t) => t.dateDepense.isBiggerOrEqualValue(depuis) & t.archiveLe.isNull())).get();
    return <DepenseCompta>[
      for (final Depense d in depenses)
        DepenseCompta(date: d.dateDepense, categorie: d.categorie, montantCentimes: d.montantCentimes),
    ];
  }

  /// Factures émises dont la vente (non annulée) n'est pas entièrement payée : leur nombre et ce qu'il reste à encaisser.
  /// Une vente comptée une seule fois, même si elle a eu plusieurs factures.
  Future<({int nombre, int totalCentimes})> _facturesImpayees() async {
    final List<Facture> emises = await (_db.select(
      _db.factures,
    )..where((t) => t.statut.equalsValue(StatutFacture.emise))).get();
    final List<int> venteIds = <int>{for (final Facture f in emises) f.venteId}.toList();
    if (venteIds.isEmpty) return (nombre: 0, totalCentimes: 0);

    int nombre = 0;
    int total = 0;
    for (final List<int> lot in _enLots(venteIds)) {
      final List<Vente> ventes = await (_db.select(_db.ventes)..where((t) => t.id.isIn(lot))).get();
      final Map<int, int> encaisse = <int, int>{};
      for (final Paiement p in await (_db.select(_db.paiements)..where((t) => t.venteId.isIn(lot))).get()) {
        encaisse[p.venteId] = (encaisse[p.venteId] ?? 0) + p.montantCentimes;
      }
      for (final Vente v in ventes) {
        if (v.statut == StatutVente.annulee) continue;
        final int solde = v.totalCentimes - (encaisse[v.id] ?? 0);
        if (solde > 0) {
          nombre++;
          total += solde;
        }
      }
    }
    return (nombre: nombre, totalCentimes: total);
  }

  Iterable<List<int>> _enLots(List<int> ids) sync* {
    for (int i = 0; i < ids.length; i += _tailleLot) {
      yield ids.sublist(i, i + _tailleLot > ids.length ? ids.length : i + _tailleLot);
    }
  }
}
