import '../enums.dart';
import '../erreurs.dart';
import 'totaux.dart';

/// Une ligne du panier : un produit (éventuellement une variante) ou une prestation libre.
///
/// Désignation et prix sont ceux affichés à l'utilisatrice au moment de l'ajout : ils sont
/// recopiés dans la vente à la validation (modifier le catalogue ensuite ne change rien).
class LignePanier {
  const LignePanier({
    required this.idLigne,
    required this.designation,
    required this.prixUnitaireCentimes,
    required this.quantite,
    this.produitId,
    this.varianteId,
    this.description,
    this.nature = NatureLigne.bien,
    this.stockDisponible,
  });

  /// Identifiant local au panier (pour modifier ou retirer la ligne).
  final int idLigne;
  final int? produitId;
  final int? varianteId;
  final String designation;
  final String? description;
  final NatureLigne nature;
  final int prixUnitaireCentimes;
  final int quantite;

  /// Quantité en stock au moment de l'ajout ; `null` = pas de limite (produit « sur commande »,
  /// prestation libre).
  final int? stockDisponible;

  /// Total de la ligne : quantité × prix unitaire.
  int get totalCentimes => quantite * prixUnitaireCentimes;

  bool get estUnProduit => produitId != null;

  LignePanier avecQuantite(int nouvelleQuantite) => _copie(nouvelleQuantite, stockDisponible);

  /// Même ligne avec un stock disponible à jour (`null` = plus de limite).
  LignePanier avecStock(int? stock) => _copie(quantite, stock);

  LignePanier _copie(int nouvelleQuantite, int? stock) => LignePanier(
    idLigne: idLigne,
    designation: designation,
    prixUnitaireCentimes: prixUnitaireCentimes,
    quantite: nouvelleQuantite,
    produitId: produitId,
    varianteId: varianteId,
    description: description,
    nature: nature,
    stockDisponible: stock,
  );
}

/// Le panier d'une vente en cours de préparation : lignes, remise et frais de port.
/// Immuable : chaque modification retourne un nouveau panier.
///
/// - Un même produit (ou une même variante) n'apparaît qu'une fois : l'ajouter de nouveau
///   augmente la quantité.
/// - La quantité d'un article suivi en stock ne peut pas dépasser le stock disponible.
/// - Les prestations libres ne sont jamais regroupées.
class Panier {
  const Panier({
    this.lignes = const <LignePanier>[],
    this.remiseType = RemiseType.aucune,
    this.remiseValeur = 0,
    this.fraisPortCentimes = 0,
    this.prochainId = 1,
  });

  final List<LignePanier> lignes;
  final RemiseType remiseType;

  /// Pourcentage : centièmes de pour cent (1500 = 15 %). Montant : centimes.
  final int remiseValeur;
  final int fraisPortCentimes;
  final int prochainId;

  bool get estVide => lignes.isEmpty;

  /// Nombre d'articles (somme des quantités).
  int get nombreArticles => lignes.fold(0, (int somme, LignePanier l) => somme + l.quantite);

  /// Quantité déjà dans le panier pour ce produit (et cette variante).
  int quantiteDe(int produitId, {int? varianteId}) {
    for (final LignePanier l in lignes) {
      if (l.produitId == produitId && l.varianteId == varianteId) return l.quantite;
    }
    return 0;
  }

  /// Ajoute [quantite] article(s). Lance [DonneeInvalide] si une valeur est impossible et
  /// [StockInsuffisant] si le stock ne suffit pas (le panier est alors inchangé).
  Panier ajouter({
    int? produitId,
    int? varianteId,
    required String designation,
    String? description,
    NatureLigne nature = NatureLigne.bien,
    required int prixUnitaireCentimes,
    int quantite = 1,
    int? stockDisponible,
  }) {
    final String nom = designation.trim();
    if (nom.isEmpty) throw const DonneeInvalide('Indiquez le nom de l’article.');
    if (quantite < 1) throw const DonneeInvalide('La quantité doit être d’au moins 1.');
    if (prixUnitaireCentimes < 0) throw const DonneeInvalide('Un prix ne peut pas être négatif.');
    if (produitId != null && nature != NatureLigne.bien) {
      throw const DonneeInvalide('Un produit du catalogue est toujours un objet.');
    }
    if (produitId == null && varianteId != null) {
      throw const DonneeInvalide('Une variante appartient à un produit.');
    }

    if (produitId != null) {
      final int index = lignes.indexWhere(
        (LignePanier l) => l.produitId == produitId && l.varianteId == varianteId,
      );
      if (index >= 0) {
        final LignePanier existante = lignes[index];
        final LignePanier mise = _avecQuantiteVerifiee(
          existante.avecStock(stockDisponible),
          existante.quantite + quantite,
        );
        return _avecLignes(<LignePanier>[...lignes]..[index] = mise);
      }
    }

    final String? texte = description?.trim();
    final LignePanier nouvelle = _avecQuantiteVerifiee(
      LignePanier(
        idLigne: prochainId,
        designation: nom,
        description: (texte == null || texte.isEmpty) ? null : texte,
        nature: nature,
        produitId: produitId,
        varianteId: varianteId,
        prixUnitaireCentimes: prixUnitaireCentimes,
        quantite: quantite,
        stockDisponible: stockDisponible,
      ),
      quantite,
    );
    return Panier(
      lignes: <LignePanier>[...lignes, nouvelle],
      remiseType: remiseType,
      remiseValeur: remiseValeur,
      fraisPortCentimes: fraisPortCentimes,
      prochainId: prochainId + 1,
    );
  }

  /// Fixe la quantité d'une ligne. Lance [DonneeInvalide] (quantité < 1, ligne absente) ou
  /// [StockInsuffisant].
  Panier avecQuantite(int idLigne, int quantite) {
    if (quantite < 1) throw const DonneeInvalide('La quantité doit être d’au moins 1.');
    final int index = lignes.indexWhere((LignePanier l) => l.idLigne == idLigne);
    if (index < 0) throw const DonneeInvalide('Cet article n’est plus dans le panier.');
    final LignePanier mise = _avecQuantiteVerifiee(lignes[index], quantite);
    return _avecLignes(<LignePanier>[...lignes]..[index] = mise);
  }

  /// Remplace le contenu d'une ligne libre, à la même place et avec le même identifiant (les devis
  /// reprennent le panier pour leurs lignes). Lance [DonneeInvalide] si une valeur est impossible, si la
  /// ligne n'existe plus ou si c'est un produit du catalogue (on y change seulement la quantité).
  Panier avecLigneModifiee(
    int idLigne, {
    required String designation,
    String? description,
    required NatureLigne nature,
    required int prixUnitaireCentimes,
    required int quantite,
  }) {
    final int index = lignes.indexWhere((LignePanier l) => l.idLigne == idLigne);
    if (index < 0) throw const DonneeInvalide('Cette ligne n’existe plus.');
    if (lignes[index].estUnProduit) {
      throw const DonneeInvalide('Un produit du catalogue ne se modifie pas ici : changez sa quantité.');
    }
    final String nom = designation.trim();
    if (nom.isEmpty) throw const DonneeInvalide('Indiquez le nom de l’article.');
    if (quantite < 1) throw const DonneeInvalide('La quantité doit être d’au moins 1.');
    if (prixUnitaireCentimes < 0) throw const DonneeInvalide('Un prix ne peut pas être négatif.');
    final String? texte = description?.trim();
    final LignePanier modifiee = LignePanier(
      idLigne: idLigne,
      designation: nom,
      description: (texte == null || texte.isEmpty) ? null : texte,
      nature: nature,
      prixUnitaireCentimes: prixUnitaireCentimes,
      quantite: quantite,
    );
    return _avecLignes(<LignePanier>[...lignes]..[index] = modifiee);
  }

  Panier sans(int idLigne) =>
      _avecLignes(lignes.where((LignePanier l) => l.idLigne != idLigne).toList());

  Panier avecRemise(RemiseType type, int valeur) => Panier(
    lignes: lignes,
    remiseType: type,
    remiseValeur: type == RemiseType.aucune ? 0 : valeur,
    fraisPortCentimes: fraisPortCentimes,
    prochainId: prochainId,
  );

  Panier avecFraisPort(int centimes) {
    if (centimes < 0) throw const DonneeInvalide('Les frais de port ne peuvent pas être négatifs.');
    return Panier(
      lignes: lignes,
      remiseType: remiseType,
      remiseValeur: remiseValeur,
      fraisPortCentimes: centimes,
      prochainId: prochainId,
    );
  }

  /// Sous-total, remise, frais de port et total. Lance [RemiseInvalide] si la remise est impossible
  /// (par exemple un montant supérieur au sous-total après le retrait d'un article).
  TotauxDocument get totaux => _calculer();

  /// Message à afficher si la remise est impossible, sinon `null`.
  String? get problemeRemise {
    try {
      _calculer();
      return null;
    } on RemiseInvalide catch (erreur) {
      return erreur.message;
    }
  }

  TotauxDocument _calculer() => calculerTotaux(
    lignes: lignes.map(
      (LignePanier l) => LigneACalculer(quantite: l.quantite, prixUnitaireCentimes: l.prixUnitaireCentimes),
    ),
    remiseType: remiseType,
    remiseValeur: remiseValeur,
    fraisPortCentimes: fraisPortCentimes,
  );

  Panier _avecLignes(List<LignePanier> nouvelles) => Panier(
    lignes: nouvelles,
    remiseType: remiseType,
    remiseValeur: remiseValeur,
    fraisPortCentimes: fraisPortCentimes,
    prochainId: prochainId,
  );

  /// Retourne la ligne avec cette quantité, ou lance [StockInsuffisant] si le stock ne suffit pas.
  LignePanier _avecQuantiteVerifiee(LignePanier ligne, int quantite) {
    final int? stock = ligne.stockDisponible;
    if (stock != null && quantite > stock) {
      throw StockInsuffisant(designation: ligne.designation, disponible: stock, demande: quantite);
    }
    return ligne.avecQuantite(quantite);
  }
}

/// Encaissement saisi à la validation d'une vente : montant et mode de paiement.
/// Pas d'encaissement du tout = vente « impayée » (paiement différé).
class PaiementSaisi {
  const PaiementSaisi({required this.mode, required this.montantCentimes});

  final ModePaiement mode;
  final int montantCentimes;

  /// Lance [DonneeInvalide] si le montant est nul, négatif ou dépasse le total de la vente.
  void verifier(int totalCentimes) {
    if (montantCentimes <= 0) {
      throw const DonneeInvalide('Le montant encaissé doit être supérieur à 0.');
    }
    if (montantCentimes > totalCentimes) {
      throw const DonneeInvalide('Le montant encaissé ne peut pas dépasser le total de la vente.');
    }
  }
}
