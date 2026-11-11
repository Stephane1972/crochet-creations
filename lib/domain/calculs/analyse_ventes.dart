import 'statistiques.dart';

/// Analyse détaillée de l'argent encaissé : regroupé par année, par mois, par lieu de vente ou par catégorie de
/// produits, avec des filtres qui se croisent (année, mois, lieu, catégorie).
///
/// Même base que l'écran Statistiques : **le chiffre d'affaires est l'argent encaissé** à la date du paiement,
/// remboursements déduits, réparti entre les éléments d'une vente au prorata de ce qu'ils valent après remise
/// (`composantsDeVente`). Le coût matière est imputé de la même façon, d'où la marge estimée.
///
/// Les encaissements d'une vente sont additionnés **dans la fenêtre du regroupement** (l'année, le mois, ou toute la
/// période filtrée) avant d'être répartis : pour une période identique, les chiffres sont donc les mêmes, au centime
/// près, que ceux de l'écran Statistiques. La somme des lignes est toujours égale à l'argent encaissé de la période.

// -----------------------------------------------------------------------------
// Choix de l'utilisatrice
// -----------------------------------------------------------------------------

/// Comment regrouper les chiffres.
enum DimensionAnalyse {
  annee('Année'),
  mois('Mois'),
  lieu('Lieu'),
  categorie('Catégorie');

  const DimensionAnalyse(this.libelle);

  final String libelle;
}

/// Un filtre sur une valeur : tout accepter, n'accepter qu'une valeur, ou n'accepter que « rien » (une vente sans
/// lieu, un article sans catégorie).
class ChoixFiltre<T> {
  const ChoixFiltre.tous() : tous = true, valeur = null;

  /// Ne garde que les éléments sans valeur (« Non renseigné », « Sans catégorie »).
  const ChoixFiltre.sans() : tous = false, valeur = null;

  const ChoixFiltre.valeur(T this.valeur) : tous = false;

  final bool tous;
  final T? valeur;

  /// Vrai si [candidat] passe le filtre.
  bool accepte(T? candidat) => tous || candidat == valeur;

  @override
  bool operator ==(Object other) => other is ChoixFiltre<T> && other.tous == tous && other.valeur == valeur;

  @override
  int get hashCode => Object.hash(tous, valeur);
}

/// Les critères qui limitent ce qu'on analyse. Tous sont facultatifs : sans critère, on analyse tout.
class FiltreAnalyse {
  const FiltreAnalyse({
    this.annee,
    this.mois,
    this.lieu = const ChoixFiltre<int>.tous(),
    this.categorie = const ChoixFiltre<String>.tous(),
  });

  /// Année du paiement (`null` : toutes les années).
  final int? annee;

  /// Mois du paiement, de 1 à 12 (`null` : tous les mois). Sans année, ce sont tous les mêmes mois de toutes les années.
  final int? mois;

  /// Lieu de la vente (identifiant).
  final ChoixFiltre<int> lieu;

  /// Catégorie du produit vendu (clé).
  final ChoixFiltre<String> categorie;

  bool accepteDate(DateTime date) =>
      (annee == null || date.year == annee) && (mois == null || date.month == mois);
}

// -----------------------------------------------------------------------------
// Résultats
// -----------------------------------------------------------------------------

/// Une ligne de l'analyse : ce que rapporte un groupe (une année, un mois, un lieu ou une catégorie).
///
/// Seul le champ qui correspond à la [dimension] est renseigné : [annee] pour une année, [annee] et [mois] pour un
/// mois, [lieuId] pour un lieu (`null` : « Non renseigné »), [categorie] pour une catégorie (`null` : « Sans
/// catégorie », c'est-à-dire lignes libres, cours et frais de port).
class LigneAnalyse {
  const LigneAnalyse({
    required this.dimension,
    this.annee,
    this.mois,
    this.lieuId,
    this.categorie,
    this.encaisseCentimes = 0,
    this.coutCentimes = 0,
  });

  final DimensionAnalyse dimension;
  final int? annee;
  final int? mois;
  final int? lieuId;
  final String? categorie;

  /// Argent encaissé, remboursements déduits.
  final int encaisseCentimes;

  /// Coût matière des articles correspondant à l'argent encaissé.
  final int coutCentimes;

  /// Marge estimée : encaissé moins coût matière.
  int get margeCentimes => encaisseCentimes - coutCentimes;
}

/// Le résultat d'une analyse : les lignes et leurs totaux.
class AnalyseVentes {
  const AnalyseVentes({required this.dimension, required this.lignes});

  final DimensionAnalyse dimension;
  final List<LigneAnalyse> lignes;

  int get encaisseTotalCentimes => lignes.fold(0, (int s, LigneAnalyse l) => s + l.encaisseCentimes);
  int get coutTotalCentimes => lignes.fold(0, (int s, LigneAnalyse l) => s + l.coutCentimes);
  int get margeTotalCentimes => encaisseTotalCentimes - coutTotalCentimes;

  /// Vrai s'il n'y a rien à montrer (aucun encaissement ne correspond aux critères).
  bool get vide => lignes.isEmpty;

  /// Part de [ligne] dans l'argent encaissé, en pour cent arrondi ; `null` si le total n'est pas positif.
  int? partEnPourcent(LigneAnalyse ligne) {
    final int total = encaisseTotalCentimes;
    if (total <= 0) return null;
    return diviserArrondi(ligne.encaisseCentimes * 100, total);
  }
}

// -----------------------------------------------------------------------------
// Calculs
// -----------------------------------------------------------------------------

/// Les années où de l'argent a été encaissé (ou remboursé), de la plus récente à la plus ancienne.
List<int> anneesAvecEncaissements(List<VenteCompta> ventes) {
  final Set<int> annees = <int>{
    for (final VenteCompta v in ventes)
      for (final PaiementCompta p in v.paiements)
        if (p.montantCentimes != 0) p.date.year,
  };
  return annees.toList()..sort((int a, int b) => b.compareTo(a));
}

class _Cumul {
  int encaisse = 0;
  int cout = 0;

  bool get nul => encaisse == 0 && cout == 0;
}

/// Calcule l'analyse de [ventes] regroupée selon [dimension] et limitée par [filtre].
///
/// [ordreLieux] (identifiants) et [ordreCategories] (clés) donnent l'ordre d'affichage habituel : il sert à départager
/// les lignes de même montant. Un lieu ou une catégorie qui n'y figure plus passe après, par identifiant ou par clé.
AnalyseVentes calculerAnalyse({
  required List<VenteCompta> ventes,
  required DimensionAnalyse dimension,
  FiltreAnalyse filtre = const FiltreAnalyse(),
  List<int> ordreLieux = const <int>[],
  List<String> ordreCategories = const <String>[],
}) {
  // Clé de groupe : l'année, année × 100 + mois, l'identifiant du lieu (`null` : sans lieu) ou la clé de la catégorie
  // (`null` : sans catégorie).
  final Map<Object?, _Cumul> cumuls = <Object?, _Cumul>{};

  for (final VenteCompta vente in ventes) {
    if (!filtre.lieu.accepte(vente.lieuId)) continue;
    final List<ComposantVente> composants = composantsDeVente(vente);
    final int total = composants.fold(0, (int s, ComposantVente c) => s + c.poidsCentimes);
    if (total <= 0) continue;

    // Argent encaissé par fenêtre : l'année, le mois, ou (0) toute la période filtrée.
    final Map<int, int> parFenetre = <int, int>{};
    for (final PaiementCompta p in vente.paiements) {
      if (!filtre.accepteDate(p.date)) continue;
      final int fenetre = switch (dimension) {
        DimensionAnalyse.annee => p.date.year,
        DimensionAnalyse.mois => p.date.year * 100 + p.date.month,
        DimensionAnalyse.lieu || DimensionAnalyse.categorie => 0,
      };
      parFenetre[fenetre] = (parFenetre[fenetre] ?? 0) + p.montantCentimes;
    }

    final List<int> poids = <int>[for (final ComposantVente c in composants) c.poidsCentimes];
    for (final MapEntry<int, int> fenetre in parFenetre.entries) {
      final int encaisse = fenetre.value;
      if (encaisse == 0) continue;
      final List<int> parts = repartirProportionnellement(encaisse, poids);
      for (int i = 0; i < composants.length; i++) {
        final ComposantVente c = composants[i];
        if (!filtre.categorie.accepte(c.categorie)) continue;
        final Object? cle = switch (dimension) {
          DimensionAnalyse.annee || DimensionAnalyse.mois => fenetre.key,
          DimensionAnalyse.lieu => vente.lieuId,
          DimensionAnalyse.categorie => c.categorie,
        };
        final _Cumul cumul = cumuls.putIfAbsent(cle, _Cumul.new);
        cumul.encaisse += parts[i];
        cumul.cout += diviserArrondi(c.coutCentimes * encaisse, total);
      }
    }
  }

  if (cumuls.isEmpty) return AnalyseVentes(dimension: dimension, lignes: const <LigneAnalyse>[]);

  switch (dimension) {
    case DimensionAnalyse.annee:
      return AnalyseVentes(dimension: dimension, lignes: _lignesParAnnee(cumuls));
    case DimensionAnalyse.mois:
      return AnalyseVentes(dimension: dimension, lignes: _lignesParMois(cumuls, filtre));
    case DimensionAnalyse.lieu:
      return AnalyseVentes(dimension: dimension, lignes: _lignesParLieu(cumuls, ordreLieux));
    case DimensionAnalyse.categorie:
      return AnalyseVentes(dimension: dimension, lignes: _lignesParCategorie(cumuls, ordreCategories));
  }
}

/// Une ligne par année, de la première à la dernière année qui a des chiffres (une année sans rien y est à zéro).
List<LigneAnalyse> _lignesParAnnee(Map<Object?, _Cumul> cumuls) {
  final List<int> annees = <int>[for (final Object? k in cumuls.keys) k! as int]..sort();
  return <LigneAnalyse>[
    for (int a = annees.first; a <= annees.last; a++)
      LigneAnalyse(
        dimension: DimensionAnalyse.annee,
        annee: a,
        encaisseCentimes: cumuls[a]?.encaisse ?? 0,
        coutCentimes: cumuls[a]?.cout ?? 0,
      ),
  ];
}

/// Une ligne par mois, dans l'ordre du calendrier. Avec une année choisie : ses douze mois (ou le seul mois choisi).
/// Sans année : de la première à la dernière année qui a des chiffres ; les mois vides du début et de la fin sont
/// retirés, ceux du milieu restent à zéro.
List<LigneAnalyse> _lignesParMois(Map<Object?, _Cumul> cumuls, FiltreAnalyse filtre) {
  final List<int> cles = <int>[for (final Object? k in cumuls.keys) k! as int]..sort();
  final int premiereAnnee = filtre.annee ?? cles.first ~/ 100;
  final int derniereAnnee = filtre.annee ?? cles.last ~/ 100;
  final List<int> mois = filtre.mois != null ? <int>[filtre.mois!] : <int>[for (int m = 1; m <= 12; m++) m];

  final List<int> candidats = <int>[
    for (int a = premiereAnnee; a <= derniereAnnee; a++)
      for (final int m in mois) a * 100 + m,
  ];
  int debut = 0;
  int fin = candidats.length;
  if (filtre.annee == null) {
    while (debut < fin && !cumuls.containsKey(candidats[debut])) {
      debut++;
    }
    while (fin > debut && !cumuls.containsKey(candidats[fin - 1])) {
      fin--;
    }
  }
  return <LigneAnalyse>[
    for (final int cle in candidats.sublist(debut, fin))
      LigneAnalyse(
        dimension: DimensionAnalyse.mois,
        annee: cle ~/ 100,
        mois: cle % 100,
        encaisseCentimes: cumuls[cle]?.encaisse ?? 0,
        coutCentimes: cumuls[cle]?.cout ?? 0,
      ),
  ];
}

/// Une ligne par lieu qui a des chiffres, du plus rentable au moins rentable (« Non renseigné » est un lieu comme
/// les autres, sans identifiant).
List<LigneAnalyse> _lignesParLieu(Map<Object?, _Cumul> cumuls, List<int> ordre) {
  final List<int?> cles = <int?>[
    for (final Object? k in cumuls.keys)
      if (!cumuls[k]!.nul) k as int?,
  ];
  int rang(int? id) {
    if (id == null) return 1 << 30; // « Non renseigné » en dernier à montant égal
    final int position = ordre.indexOf(id);
    return position >= 0 ? position : (1 << 20) + id;
  }

  cles.sort((int? a, int? b) {
    final int parMontant = cumuls[b]!.encaisse.compareTo(cumuls[a]!.encaisse);
    return parMontant != 0 ? parMontant : rang(a).compareTo(rang(b));
  });
  return <LigneAnalyse>[
    for (final int? id in cles)
      LigneAnalyse(
        dimension: DimensionAnalyse.lieu,
        lieuId: id,
        encaisseCentimes: cumuls[id]!.encaisse,
        coutCentimes: cumuls[id]!.cout,
      ),
  ];
}

/// Une ligne par catégorie qui a des chiffres, de la plus rentable à la moins rentable.
List<LigneAnalyse> _lignesParCategorie(Map<Object?, _Cumul> cumuls, List<String> ordre) {
  final List<String?> cles = <String?>[
    for (final Object? k in cumuls.keys)
      if (!cumuls[k]!.nul) k as String?,
  ];
  // Les catégories connues d'abord, dans l'ordre de la liste ; les disparues ensuite, par clé.
  String ordreDe(String? cle) {
    if (cle == null) return '3';
    final int position = ordre.indexOf(cle);
    return position >= 0 ? '1${position.toString().padLeft(6, '0')}' : '2$cle';
  }

  cles.sort((String? a, String? b) {
    final int parMontant = cumuls[b]!.encaisse.compareTo(cumuls[a]!.encaisse);
    return parMontant != 0 ? parMontant : ordreDe(a).compareTo(ordreDe(b));
  });
  return <LigneAnalyse>[
    for (final String? cle in cles)
      LigneAnalyse(
        dimension: DimensionAnalyse.categorie,
        categorie: cle,
        encaisseCentimes: cumuls[cle]!.encaisse,
        coutCentimes: cumuls[cle]!.cout,
      ),
  ];
}
