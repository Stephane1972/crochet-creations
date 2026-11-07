/// Bloc-notes : des notes (titre + texte) rangées dans des catégories que l'on crée soi-même.
///
/// Trois notions à ne pas confondre :
/// - la **catégorie d'une note** (ce fichier) : « Futures commandes », « Documents entreprise »... ;
/// - la **catégorie d'un produit** (`categories_produit.dart`) : doudou, boucles d'oreilles... ;
/// - le **lieu d'une vente** (`lieux_vente.dart`) : marché, salon, boutique...
///
/// Une note sans catégorie est « Sans catégorie » : c'est le choix par défaut, et ce qu'il reste quand on supprime
/// une catégorie en gardant ses notes.
library;

import '../core/utils/recherche.dart';

/// Ce qu'on affiche quand une note n'a pas de catégorie.
const String libelleSansCategorieNote = 'Sans catégorie';

/// Une catégorie de notes créée au premier lancement (ou à la mise à jour qui apporte le bloc-notes).
/// Elles se renomment et se suppriment comme les autres.
class CategorieNoteDeDepart {
  const CategorieNoteDeDepart(this.nom);

  final String nom;
}

/// Les catégories de départ, dans l'ordre où elles s'affichent.
const List<CategorieNoteDeDepart> categoriesNoteDeDepart = <CategorieNoteDeDepart>[
  CategorieNoteDeDepart('Futures commandes'),
  CategorieNoteDeDepart('Documents entreprise'),
];

/// Longueur maximale du nom d'une catégorie de notes.
const int longueurMaxNomCategorieNote = 60;

/// Longueur maximale du titre d'une note.
const int longueurMaxTitreNote = 120;

// --- Catégories ------------------------------------------------------------------

/// Nom de catégorie prêt à enregistrer (espaces superflus retirés).
String nettoyerNomCategorieNote(String? nom) => (nom ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// Ce qui ne va pas dans [nom] (`null` si tout va bien), sans tenir compte des doublons : voir [memeNomCategorieNote].
String? erreurNomCategorieNote(String? nom) {
  final String propre = nettoyerNomCategorieNote(nom);
  if (propre.isEmpty) return 'Donnez un nom à la catégorie de notes.';
  if (propre.length > longueurMaxNomCategorieNote) {
    return 'Le nom d’une catégorie de notes est limité à $longueurMaxNomCategorieNote caractères.';
  }
  // « Sans catégorie » est le libellé d'une note qui n'a pas de catégorie : une vraie catégorie qui porterait ce nom
  // prêterait à confusion.
  if (memeNomCategorieNote(propre, libelleSansCategorieNote)) {
    return '« $libelleSansCategorieNote » désigne une note sans catégorie : choisissez un autre nom.';
  }
  return null;
}

/// Deux noms désignent la même catégorie s'ils ne diffèrent que par les majuscules, les accents ou les espaces.
bool memeNomCategorieNote(String a, String b) =>
    normaliserPourRecherche(nettoyerNomCategorieNote(a)) == normaliserPourRecherche(nettoyerNomCategorieNote(b));

// --- Notes -----------------------------------------------------------------------

/// Titre de note prêt à enregistrer (espaces superflus retirés).
String nettoyerTitreNote(String? titre) => (titre ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// Ce qui ne va pas dans [titre] (`null` si tout va bien).
String? erreurTitreNote(String? titre) {
  final String propre = nettoyerTitreNote(titre);
  if (propre.isEmpty) return 'Donnez un titre à la note.';
  if (propre.length > longueurMaxTitreNote) {
    return 'Le titre d’une note est limité à $longueurMaxTitreNote caractères.';
  }
  return null;
}

/// Texte d'une note prêt à enregistrer : les espaces et lignes vides au début et à la fin sont retirés, les retours à
/// la ligne du milieu sont conservés tels quels.
String nettoyerContenuNote(String? contenu) => (contenu ?? '').trim();
