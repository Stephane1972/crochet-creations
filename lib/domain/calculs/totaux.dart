import '../enums.dart';
import '../erreurs.dart';

/// Une ligne à totaliser : quantité et prix unitaire (en centimes).
class LigneACalculer {
  const LigneACalculer({required this.quantite, required this.prixUnitaireCentimes});

  final int quantite;
  final int prixUnitaireCentimes;

  /// Total de la ligne : quantité × prix unitaire.
  int get totalCentimes => quantite * prixUnitaireCentimes;
}

/// Résultat du calcul d'une vente ou d'un devis. Montants en centimes.
///
/// Aucune TVA : les prix sont des prix finaux (franchise en base de TVA).
class TotauxDocument {
  const TotauxDocument({
    required this.sousTotalCentimes,
    required this.remiseCentimes,
    required this.fraisPortCentimes,
  });

  /// Somme des lignes, avant remise et frais de port.
  final int sousTotalCentimes;

  /// Montant de la remise (toujours ≥ 0, jamais supérieur au sous-total).
  final int remiseCentimes;
  final int fraisPortCentimes;

  /// Sous-total − remise + frais de port.
  int get totalCentimes => sousTotalCentimes - remiseCentimes + fraisPortCentimes;
}

/// Calcule le sous-total, la remise et le total d'une vente ou d'un devis.
///
/// - [remiseValeur] dépend de [remiseType] : centièmes de pour cent (1500 = 15 %)
///   pour un pourcentage, centimes pour un montant ; ignorée si [RemiseType.aucune].
/// - Le pourcentage est arrondi au centime le plus proche (0,5 centime arrondi vers le haut).
/// - Les frais de port ne sont pas remisés.
///
/// Lance [DonneeInvalide] ou [RemiseInvalide] si une valeur est impossible.
TotauxDocument calculerTotaux({
  required Iterable<LigneACalculer> lignes,
  RemiseType remiseType = RemiseType.aucune,
  int remiseValeur = 0,
  int fraisPortCentimes = 0,
}) {
  if (fraisPortCentimes < 0) {
    throw const DonneeInvalide('Les frais de port ne peuvent pas être négatifs.');
  }

  int sousTotal = 0;
  for (final LigneACalculer ligne in lignes) {
    if (ligne.quantite <= 0) {
      throw const DonneeInvalide('La quantité doit être d’au moins 1.');
    }
    if (ligne.prixUnitaireCentimes < 0) {
      throw const DonneeInvalide('Un prix ne peut pas être négatif.');
    }
    sousTotal += ligne.totalCentimes;
  }

  final int remise = switch (remiseType) {
    RemiseType.aucune => 0,
    RemiseType.pourcentage => _remisePourcentage(sousTotal, remiseValeur),
    RemiseType.montant => _remiseMontant(sousTotal, remiseValeur),
  };

  return TotauxDocument(
    sousTotalCentimes: sousTotal,
    remiseCentimes: remise,
    fraisPortCentimes: fraisPortCentimes,
  );
}

int _remisePourcentage(int sousTotal, int centiemesDePourCent) {
  if (centiemesDePourCent < 0 || centiemesDePourCent > 10000) {
    throw const RemiseInvalide('Le pourcentage de remise doit être compris entre 0 et 100 %.');
  }
  // Arithmétique entière : (sousTotal × pourcentage) / 10 000, arrondi à l'entier le plus proche.
  return (sousTotal * centiemesDePourCent + 5000) ~/ 10000;
}

int _remiseMontant(int sousTotal, int montantCentimes) {
  if (montantCentimes < 0) {
    throw const RemiseInvalide('La remise ne peut pas être négative.');
  }
  if (montantCentimes > sousTotal) {
    throw const RemiseInvalide('La remise ne peut pas dépasser le sous-total.');
  }
  return montantCentimes;
}
