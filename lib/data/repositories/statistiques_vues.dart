import '../../domain/calculs/statistiques.dart';

/// Tout ce que montrent l'écran des statistiques et l'accueil, calculé à un instant donné.
class Statistiques {
  const Statistiques({
    required this.maintenant,
    required this.periodes,
    this.facturesImpayeesNombre = 0,
    this.facturesImpayeesCentimes = 0,
  });

  /// Instant du calcul : les périodes (aujourd'hui, cette semaine...) sont celles qui le contiennent.
  final DateTime maintenant;

  /// Les chiffres de chaque période.
  final Map<PeriodeStats, StatsPeriode> periodes;

  /// Factures émises dont la vente n'est pas entièrement payée, et ce qu'il reste à encaisser.
  final int facturesImpayeesNombre;
  final int facturesImpayeesCentimes;

  StatsPeriode periode(PeriodeStats p) => periodes[p]!;

  /// Franchise de TVA : argent encaissé depuis le 1er janvier, objets (frais de port compris).
  int get franchiseObjetsCentimes => periode(PeriodeStats.annee).encaisseObjetsCentimes;

  /// Franchise de TVA : argent encaissé depuis le 1er janvier, prestations (cours compris).
  int get franchisePrestationsCentimes => periode(PeriodeStats.annee).encaissePrestationsCentimes;
}
