/// Lieux de vente : l'endroit où une vente a été faite (marché, salon, boutique, vente en ligne, ou un lieu à soi).
///
/// À ne pas confondre avec la **catégorie** d'un produit (`categories_produit.dart`), ni avec le « lieu » d'un cours
/// (l'endroit où il se donne) : un lieu de vente se choisit sur chaque **vente**.
///
/// Une vente sans lieu est « Non renseigné » : c'est le cas de toutes les ventes enregistrées avant que les lieux
/// existent, et de celles où l'on n'a rien choisi.
library;

import '../core/utils/recherche.dart';

/// Ce qu'on affiche quand une vente n'a pas de lieu.
const String libelleLieuNonRenseigne = 'Non renseigné';

/// Un lieu créé au premier lancement (ou à la mise à jour qui apporte les lieux de vente), pour gagner du temps.
/// Ils se renomment et se suppriment comme les autres.
class LieuDeDepart {
  const LieuDeDepart(this.nom);

  final String nom;
}

/// Les lieux de départ, dans l'ordre où ils s'affichent.
const List<LieuDeDepart> lieuxDeDepart = <LieuDeDepart>[
  LieuDeDepart('Marché'),
  LieuDeDepart('Salon'),
  LieuDeDepart('Boutique'),
  LieuDeDepart('Vente en ligne'),
];

/// Longueur maximale du nom d'un lieu.
const int longueurMaxNomLieu = 60;

/// Nom d'un lieu prêt à enregistrer (espaces superflus retirés).
String nettoyerNomLieu(String? nom) => (nom ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// Ce qui ne va pas dans [nom] (`null` si tout va bien), sans tenir compte des doublons : voir [memeNomLieu].
String? erreurNomLieu(String? nom) {
  final String propre = nettoyerNomLieu(nom);
  if (propre.isEmpty) return 'Donnez un nom au lieu de vente.';
  if (propre.length > longueurMaxNomLieu) {
    return 'Le nom d’un lieu de vente est limité à $longueurMaxNomLieu caractères.';
  }
  // « Non renseigné » est le libellé d'une vente sans lieu : un vrai lieu qui porterait ce nom prêterait à confusion.
  if (memeNomLieu(propre, libelleLieuNonRenseigne)) {
    return '« $libelleLieuNonRenseigne » désigne une vente sans lieu : choisissez un autre nom.';
  }
  return null;
}

/// Deux noms désignent le même lieu s'ils ne diffèrent que par les majuscules, les accents ou les espaces.
bool memeNomLieu(String a, String b) =>
    normaliserPourRecherche(nettoyerNomLieu(a)) == normaliserPourRecherche(nettoyerNomLieu(b));
