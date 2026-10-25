import '../../domain/enums.dart';
import '../database/app_database.dart';

/// Tout ce qu'affiche le détail d'une vente : lignes, client, paiements.
class VenteDetail {
  const VenteDetail({
    required this.vente,
    required this.lignes,
    required this.paiements,
    this.client,
    this.factures = const <Facture>[],
  });

  final Vente vente;

  /// Lignes dans l'ordre de saisie.
  final List<LigneVente> lignes;

  /// Encaissements et remboursements, du plus ancien au plus récent.
  final List<Paiement> paiements;

  /// `null` pour un client de passage.
  final Client? client;

  /// Factures établies pour cette vente, la plus récente d'abord (les annulées comprises).
  final List<Facture> factures;

  /// La facture en cours de validité de cette vente, s'il y en a une.
  Facture? get factureEmise {
    for (final Facture f in factures) {
      if (f.statut == StatutFacture.emise) return f;
    }
    return null;
  }

  bool get estAnnulee => vente.statut == StatutVente.annulee;

  /// Net encaissé : les paiements moins les remboursements (montants négatifs).
  int get encaisseCentimes => paiements.fold(0, (int somme, Paiement p) => somme + p.montantCentimes);

  /// Reste à payer. Une vente annulée ne doit plus rien.
  int get soldeDuCentimes {
    if (estAnnulee) return 0;
    final int solde = vente.totalCentimes - encaisseCentimes;
    return solde < 0 ? 0 : solde;
  }

  bool get peutEncaisser => !estAnnulee && soldeDuCentimes > 0;
}
