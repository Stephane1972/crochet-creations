import '../../domain/enums.dart';
import '../database/app_database.dart';

/// Ce que la liste des dépenses affiche : un mois, éventuellement une seule catégorie, ou les dépenses archivées.
/// (Un « record » : deux filtres identiques sont égaux, ce qui sert de clé aux providers.)
typedef FiltreDepenses = ({int annee, int mois, CategorieDepense? categorie, bool archivees});

/// Une ligne de la liste : la dépense et le produit concerné (`null` s'il n'y en a pas).
class DepenseLigne {
  const DepenseLigne({required this.depense, this.produit});

  final Depense depense;
  final Produit? produit;
}

/// Les dépenses d'un mois dans l'ordre (la plus récente d'abord), avec leur total.
class ListeDepenses {
  const ListeDepenses({required this.lignes, required this.totalCentimes});

  final List<DepenseLigne> lignes;

  /// Somme des montants des lignes affichées.
  final int totalCentimes;

  bool get vide => lignes.isEmpty;
}
