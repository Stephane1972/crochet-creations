import '../enums.dart';

/// Déduit le statut de paiement d'une vente à partir de son total et de ses paiements.
///
/// [montantsPaiements] : montants en centimes ; positifs pour un encaissement,
/// **négatifs pour un remboursement**.
///
/// - encaissé puis intégralement remboursé → [StatutPaiement.remboursee] ;
/// - net encaissé ≥ total → [StatutPaiement.payee] (une vente à 0 € est considérée payée) ;
/// - net encaissé > 0 → [StatutPaiement.partiellementPayee] ;
/// - sinon → [StatutPaiement.impayee].
StatutPaiement calculerStatutPaiement({
  required int totalCentimes,
  required Iterable<int> montantsPaiements,
}) {
  int encaisse = 0;
  int rembourse = 0;
  for (final int montant in montantsPaiements) {
    if (montant >= 0) {
      encaisse += montant;
    } else {
      rembourse += -montant;
    }
  }
  final int net = encaisse - rembourse;

  if (rembourse > 0 && net <= 0) return StatutPaiement.remboursee;
  if (net >= totalCentimes) return StatutPaiement.payee;
  if (net > 0) return StatutPaiement.partiellementPayee;
  return StatutPaiement.impayee;
}
