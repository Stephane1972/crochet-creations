import '../enums.dart';

/// Calculs des statistiques, sans base de données ni interface.
///
/// **Le chiffre d'affaires est l'argent encaissé** (paiements reçus moins remboursements) pendant la période.
/// Pour savoir ce qui relève des objets, des prestations ou des cours, chaque encaissement est réparti entre les
/// éléments de la vente (lignes, et frais de port) **au prorata de ce qu'ils valent après remise** : un acompte de
/// 40 % sur une vente de deux lignes compte pour 40 % de chacune. Le coût matière est imputé de la même façon, d'où
/// la **marge estimée** = encaissé − coût matière des articles correspondants.

// -----------------------------------------------------------------------------
// Entrées : ce que les statistiques lisent
// -----------------------------------------------------------------------------

/// Une ligne de vente.
class LigneCompta {
  const LigneCompta({
    required this.nature,
    required this.designation,
    required this.quantite,
    required this.totalCentimes,
    this.coutUnitaireCentimes = 0,
    this.produitId,
    this.categorie,
    this.coursId,
  });

  final NatureLigne nature;
  final String designation;
  final int quantite;

  /// Total de la ligne avant remise.
  final int totalCentimes;

  /// Coût matière unitaire au moment de la vente.
  final int coutUnitaireCentimes;
  final int? produitId;

  /// Catégorie du produit vendu (`null` pour une ligne libre ou un cours).
  final CategorieProduit? categorie;
  final int? coursId;
}

/// Un paiement (positif) ou un remboursement (négatif).
class PaiementCompta {
  const PaiementCompta({required this.date, required this.montantCentimes});

  final DateTime date;
  final int montantCentimes;
}

/// Une vente avec ses lignes et ses paiements.
class VenteCompta {
  const VenteCompta({
    required this.date,
    required this.annulee,
    required this.lignes,
    required this.paiements,
    this.remiseCentimes = 0,
    this.fraisPortCentimes = 0,
  });

  final DateTime date;
  final bool annulee;
  final List<LigneCompta> lignes;
  final List<PaiementCompta> paiements;
  final int remiseCentimes;
  final int fraisPortCentimes;
}

/// Une dépense (non archivée).
class DepenseCompta {
  const DepenseCompta({required this.date, required this.categorie, required this.montantCentimes});

  final DateTime date;
  final CategorieDepense categorie;
  final int montantCentimes;
}

// -----------------------------------------------------------------------------
// Arithmétique en centimes
// -----------------------------------------------------------------------------

/// Division entière arrondie au plus proche (la moitié s'éloigne de zéro). [diviseur] doit être positif.
int diviserArrondi(int dividende, int diviseur) {
  final int signe = dividende < 0 ? -1 : 1;
  return signe * ((dividende.abs() * 2 + diviseur) ~/ (2 * diviseur));
}

/// Partage [montant] entre des parts proportionnelles à [poids], sans perdre un centime : la somme des parts est
/// exactement [montant] (méthode du plus fort reste). Fonctionne aussi pour un montant négatif (remboursement).
/// Si les poids sont tous nuls, tout va à la première part.
List<int> repartirProportionnellement(int montant, List<int> poids) {
  if (poids.isEmpty) return <int>[];
  final int somme = poids.fold(0, (int s, int p) => s + p);
  if (somme <= 0 || montant == 0) {
    return <int>[montant, ...List<int>.filled(poids.length - 1, 0)];
  }
  final int signe = montant < 0 ? -1 : 1;
  final int absolu = montant.abs();
  final List<int> parts = <int>[for (final int p in poids) absolu * p ~/ somme];
  final List<int> restes = <int>[for (final int p in poids) absolu * p % somme];
  int aDistribuer = absolu - parts.fold(0, (int s, int p) => s + p);
  final List<int> ordre = List<int>.generate(poids.length, (int i) => i)
    ..sort((int a, int b) {
      final int parReste = restes[b].compareTo(restes[a]);
      return parReste != 0 ? parReste : a.compareTo(b);
    });
  for (final int i in ordre) {
    if (aDistribuer == 0) break;
    parts[i]++;
    aDistribuer--;
  }
  return <int>[for (final int p in parts) signe * p];
}

// -----------------------------------------------------------------------------
// Éléments d'une vente
// -----------------------------------------------------------------------------

/// Un élément d'une vente : une ligne (remise déduite) ou les frais de port.
class ComposantVente {
  const ComposantVente({
    required this.poidsCentimes,
    required this.coutCentimes,
    required this.nature,
    this.categorie,
    this.estCours = false,
  });

  /// Ce que vaut l'élément dans le total de la vente (après sa part de remise).
  final int poidsCentimes;

  /// Coût matière total de l'élément (quantité comprise).
  final int coutCentimes;
  final NatureLigne nature;
  final CategorieProduit? categorie;
  final bool estCours;
}

/// Les éléments d'une vente. La remise est répartie sur les lignes au prorata de leur total ; les frais de port
/// forment un élément à part, compté avec les objets. La somme des poids est le total de la vente.
List<ComposantVente> composantsDeVente(VenteCompta vente) {
  final List<int> remises = repartirProportionnellement(
    vente.remiseCentimes,
    <int>[for (final LigneCompta l in vente.lignes) l.totalCentimes],
  );
  return <ComposantVente>[
    for (int i = 0; i < vente.lignes.length; i++)
      ComposantVente(
        poidsCentimes: vente.lignes[i].totalCentimes - (i < remises.length ? remises[i] : 0),
        coutCentimes: vente.lignes[i].coutUnitaireCentimes * vente.lignes[i].quantite,
        nature: vente.lignes[i].nature,
        categorie: vente.lignes[i].categorie,
        estCours: vente.lignes[i].coursId != null,
      ),
    if (vente.fraisPortCentimes > 0)
      ComposantVente(poidsCentimes: vente.fraisPortCentimes, coutCentimes: 0, nature: NatureLigne.bien),
  ];
}

/// Total de la vente : somme des éléments.
int totalDeVente(VenteCompta vente) =>
    composantsDeVente(vente).fold(0, (int s, ComposantVente c) => s + c.poidsCentimes);

// -----------------------------------------------------------------------------
// Périodes
// -----------------------------------------------------------------------------

/// Période d'observation : celle qui contient « maintenant ».
enum PeriodeStats {
  jour('Jour', 'Aujourd’hui'),
  semaine('Semaine', 'Cette semaine'),
  mois('Mois', 'Ce mois-ci'),
  annee('Année', 'Cette année');

  const PeriodeStats(this.libelle, this.libelleCourant);

  /// « Semaine » (sélecteur).
  final String libelle;

  /// « Cette semaine » (titre d'une carte).
  final String libelleCourant;
}

/// Début (inclus) et fin (exclue) de la période qui contient [maintenant]. La semaine commence le lundi.
({DateTime debut, DateTime fin}) bornesPeriode(PeriodeStats periode, DateTime maintenant) {
  switch (periode) {
    case PeriodeStats.jour:
      final DateTime jour = DateTime(maintenant.year, maintenant.month, maintenant.day);
      return (debut: jour, fin: DateTime(jour.year, jour.month, jour.day + 1));
    case PeriodeStats.semaine:
      final DateTime lundi = DateTime(maintenant.year, maintenant.month, maintenant.day - (maintenant.weekday - 1));
      return (debut: lundi, fin: DateTime(lundi.year, lundi.month, lundi.day + 7));
    case PeriodeStats.mois:
      return (debut: DateTime(maintenant.year, maintenant.month), fin: DateTime(maintenant.year, maintenant.month + 1));
    case PeriodeStats.annee:
      return (debut: DateTime(maintenant.year), fin: DateTime(maintenant.year + 1));
  }
}

/// Vrai si [date] est dans la période [debut, fin[.
bool dansLaPeriode(DateTime date, DateTime debut, DateTime fin) => !date.isBefore(debut) && date.isBefore(fin);

// -----------------------------------------------------------------------------
// Résultats
// -----------------------------------------------------------------------------

/// Un article (ou une ligne libre) vendu pendant la période.
class VenteProduit {
  const VenteProduit({required this.designation, required this.quantite, required this.totalCentimes});

  final String designation;
  final int quantite;
  final int totalCentimes;
}

/// Une catégorie de produits : ce qu'elle a rapporté pendant la période.
class CategorieRentable {
  const CategorieRentable({required this.categorie, required this.encaisseCentimes, required this.coutCentimes});

  final CategorieProduit categorie;
  final int encaisseCentimes;
  final int coutCentimes;

  int get margeCentimes => encaisseCentimes - coutCentimes;
}

/// Total des dépenses d'une catégorie pendant la période.
class DepenseParCategorie {
  const DepenseParCategorie({required this.categorie, required this.totalCentimes});

  final CategorieDepense categorie;
  final int totalCentimes;
}

/// Tous les chiffres d'une période.
class StatsPeriode {
  const StatsPeriode({
    required this.periode,
    required this.debut,
    required this.fin,
    this.encaisseObjetsCentimes = 0,
    this.encaissePrestationsCentimes = 0,
    this.encaisseCoursCentimes = 0,
    this.coutCentimes = 0,
    this.nombreVentes = 0,
    this.totalVentesCentimes = 0,
    this.meilleuresVentes = const <VenteProduit>[],
    this.categories = const <CategorieRentable>[],
    this.depenses = const <DepenseParCategorie>[],
  });

  final PeriodeStats periode;
  final DateTime debut;
  final DateTime fin;

  /// Argent encaissé sur des objets (frais de port compris), remboursements déduits.
  final int encaisseObjetsCentimes;

  /// Argent encaissé sur des prestations, cours compris.
  final int encaissePrestationsCentimes;

  /// Part des prestations qui vient des cours (inscriptions).
  final int encaisseCoursCentimes;

  /// Coût matière des articles correspondant à l'argent encaissé.
  final int coutCentimes;

  /// Ventes validées faites pendant la période (total supérieur à 0) et leur total, pour le panier moyen.
  final int nombreVentes;
  final int totalVentesCentimes;

  final List<VenteProduit> meilleuresVentes;
  final List<CategorieRentable> categories;
  final List<DepenseParCategorie> depenses;

  /// Chiffre d'affaires : tout l'argent encaissé pendant la période.
  int get encaisseTotalCentimes => encaisseObjetsCentimes + encaissePrestationsCentimes;

  /// Chiffre d'affaires hors cours (objets et prestations libres).
  int get ventesHorsCoursCentimes => encaisseTotalCentimes - encaisseCoursCentimes;

  /// Marge estimée : encaissé moins coût matière.
  int get margeCentimes => encaisseTotalCentimes - coutCentimes;

  /// Total moyen d'une vente ; `null` s'il n'y a eu aucune vente.
  int? get panierMoyenCentimes => nombreVentes == 0 ? null : diviserArrondi(totalVentesCentimes, nombreVentes);

  int get depensesTotalCentimes => depenses.fold(0, (int s, DepenseParCategorie d) => s + d.totalCentimes);
}

/// Combien de « meilleures ventes » on garde.
const int nombreMeilleuresVentes = 5;

/// Calcule les chiffres de la période [debut, fin[.
StatsPeriode calculerStatsPeriode({
  required PeriodeStats periode,
  required DateTime debut,
  required DateTime fin,
  required List<VenteCompta> ventes,
  required List<DepenseCompta> depenses,
}) {
  int objets = 0;
  int prestations = 0;
  int cours = 0;
  int cout = 0;
  int nombreVentes = 0;
  int totalVentes = 0;
  final Map<CategorieProduit, int> encaisseParCategorie = <CategorieProduit, int>{};
  final Map<CategorieProduit, int> coutParCategorie = <CategorieProduit, int>{};
  final Map<String, _Cumul> vendus = <String, _Cumul>{};

  for (final VenteCompta vente in ventes) {
    final List<ComposantVente> composants = composantsDeVente(vente);
    final int total = composants.fold(0, (int s, ComposantVente c) => s + c.poidsCentimes);

    // --- Argent encaissé pendant la période (toutes les ventes, même annulées : le remboursement compte aussi).
    final int encaisse = vente.paiements
        .where((PaiementCompta p) => dansLaPeriode(p.date, debut, fin))
        .fold(0, (int s, PaiementCompta p) => s + p.montantCentimes);
    if (encaisse != 0 && total > 0) {
      final List<int> parts = repartirProportionnellement(
        encaisse,
        <int>[for (final ComposantVente c in composants) c.poidsCentimes],
      );
      for (int i = 0; i < composants.length; i++) {
        final ComposantVente c = composants[i];
        final int coutImpute = diviserArrondi(c.coutCentimes * encaisse, total);
        if (c.nature == NatureLigne.bien) {
          objets += parts[i];
        } else {
          prestations += parts[i];
        }
        if (c.estCours) cours += parts[i];
        cout += coutImpute;
        final CategorieProduit? categorie = c.categorie;
        if (categorie != null) {
          encaisseParCategorie[categorie] = (encaisseParCategorie[categorie] ?? 0) + parts[i];
          coutParCategorie[categorie] = (coutParCategorie[categorie] ?? 0) + coutImpute;
        }
      }
    }

    // --- Ventes faites pendant la période (panier moyen, meilleures ventes) : ventes validées uniquement.
    if (!vente.annulee && dansLaPeriode(vente.date, debut, fin)) {
      if (total > 0) {
        nombreVentes++;
        totalVentes += total;
      }
      for (final LigneCompta ligne in vente.lignes) {
        if (ligne.coursId != null) continue; // les cours ont leur propre rubrique
        final String cle = ligne.produitId != null
            ? 'produit-${ligne.produitId}'
            : 'libre-${ligne.designation.trim().toLowerCase()}';
        final _Cumul cumul = vendus.putIfAbsent(cle, () => _Cumul(ligne.designation.trim()));
        cumul.quantite += ligne.quantite;
        cumul.totalCentimes += ligne.totalCentimes;
      }
    }
  }

  final List<VenteProduit> meilleures = <VenteProduit>[
    for (final _Cumul c in vendus.values)
      VenteProduit(designation: c.designation, quantite: c.quantite, totalCentimes: c.totalCentimes),
  ]
    ..sort((VenteProduit a, VenteProduit b) {
      final int parQuantite = b.quantite.compareTo(a.quantite);
      if (parQuantite != 0) return parQuantite;
      final int parTotal = b.totalCentimes.compareTo(a.totalCentimes);
      return parTotal != 0 ? parTotal : a.designation.compareTo(b.designation);
    });

  final List<CategorieRentable> categories = <CategorieRentable>[
    for (final CategorieProduit c in CategorieProduit.values)
      if ((encaisseParCategorie[c] ?? 0) != 0 || (coutParCategorie[c] ?? 0) != 0)
        CategorieRentable(
          categorie: c,
          encaisseCentimes: encaisseParCategorie[c] ?? 0,
          coutCentimes: coutParCategorie[c] ?? 0,
        ),
  ]..sort((CategorieRentable a, CategorieRentable b) => b.margeCentimes.compareTo(a.margeCentimes));

  final Map<CategorieDepense, int> depensesParCategorie = <CategorieDepense, int>{};
  for (final DepenseCompta d in depenses) {
    if (!dansLaPeriode(d.date, debut, fin)) continue;
    depensesParCategorie[d.categorie] = (depensesParCategorie[d.categorie] ?? 0) + d.montantCentimes;
  }
  final List<DepenseParCategorie> depensesTriees = <DepenseParCategorie>[
    for (final CategorieDepense c in CategorieDepense.values)
      if ((depensesParCategorie[c] ?? 0) != 0) DepenseParCategorie(categorie: c, totalCentimes: depensesParCategorie[c]!),
  ]..sort((DepenseParCategorie a, DepenseParCategorie b) => b.totalCentimes.compareTo(a.totalCentimes));

  return StatsPeriode(
    periode: periode,
    debut: debut,
    fin: fin,
    encaisseObjetsCentimes: objets,
    encaissePrestationsCentimes: prestations,
    encaisseCoursCentimes: cours,
    coutCentimes: cout,
    nombreVentes: nombreVentes,
    totalVentesCentimes: totalVentes,
    meilleuresVentes: meilleures.take(nombreMeilleuresVentes).toList(),
    categories: categories,
    depenses: depensesTriees,
  );
}

class _Cumul {
  _Cumul(this.designation);

  final String designation;
  int quantite = 0;
  int totalCentimes = 0;
}

// -----------------------------------------------------------------------------
// Franchise de TVA
// -----------------------------------------------------------------------------

/// Où en est-on par rapport à un seuil de la franchise de TVA.
enum NiveauFranchise {
  /// Loin du seuil.
  ok,

  /// 80 % du seuil atteint ou plus : il est temps d'y penser.
  approche,

  /// Seuil dépassé.
  depasse,
}

/// Part du seuil (en %) à partir de laquelle l'alerte « le seuil approche » apparaît.
const int pourcentageAlerteFranchise = 80;

/// Niveau d'alerte pour [atteintCentimes] par rapport à [seuilCentimes]. Le seuil lui-même n'est pas « dépassé » :
/// il l'est dès le centime suivant.
NiveauFranchise niveauFranchise(int atteintCentimes, int seuilCentimes) {
  if (atteintCentimes > seuilCentimes) return NiveauFranchise.depasse;
  if (atteintCentimes * 100 >= seuilCentimes * pourcentageAlerteFranchise) return NiveauFranchise.approche;
  return NiveauFranchise.ok;
}

/// Part du seuil atteinte, entre 0 et 1 (pour une barre de progression).
double partDuSeuil(int atteintCentimes, int seuilCentimes) {
  if (seuilCentimes <= 0) return 0;
  return (atteintCentimes / seuilCentimes).clamp(0.0, 1.0).toDouble();
}
