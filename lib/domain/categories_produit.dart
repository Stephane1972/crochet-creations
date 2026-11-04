/// Catégories de produits : une **clé** interne qui ne change jamais (c'est elle que les produits enregistrent) et
/// un **nom** que l'on peut modifier à volonté.
library;

import '../core/utils/recherche.dart';

/// Clés des cinq catégories de départ : celles de l'application avant que les catégories deviennent modifiables.
/// Les produits et les anciennes sauvegardes les enregistrent depuis le début, ces valeurs ne doivent donc jamais changer.
abstract final class CleCategorie {
  static const String crochet = 'crochet';
  static const String doudou = 'doudou';
  static const String bouclesOreilles = 'bouclesOreilles';
  static const String accessoire = 'accessoire';
  static const String surMesure = 'surMesure';
}

/// Une catégorie créée au premier lancement (ou à la mise à jour qui apporte les catégories modifiables).
class CategorieDeDepart {
  const CategorieDeDepart(this.cle, this.nom);

  final String cle;
  final String nom;
}

/// Les cinq catégories de départ, dans l'ordre où elles s'affichent.
const List<CategorieDeDepart> categoriesDeDepart = <CategorieDeDepart>[
  CategorieDeDepart(CleCategorie.crochet, 'Crochet'),
  CategorieDeDepart(CleCategorie.doudou, 'Doudou'),
  CategorieDeDepart(CleCategorie.bouclesOreilles, 'Boucles d’oreilles'),
  CategorieDeDepart(CleCategorie.accessoire, 'Accessoire'),
  CategorieDeDepart(CleCategorie.surMesure, 'Sur mesure'),
];

/// Longueur maximale du nom d'une catégorie.
const int longueurMaxNomCategorie = 60;

/// Nom d'une catégorie prêt à enregistrer (espaces superflus retirés).
String nettoyerNomCategorie(String? nom) => (nom ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// Ce qui ne va pas dans [nom] (`null` si tout va bien), sans tenir compte des doublons : voir [memeNomCategorie].
String? erreurNomCategorie(String? nom) {
  final String propre = nettoyerNomCategorie(nom);
  if (propre.isEmpty) return 'Donnez un nom à la catégorie.';
  if (propre.length > longueurMaxNomCategorie) {
    return 'Le nom d’une catégorie est limité à $longueurMaxNomCategorie caractères.';
  }
  return null;
}

/// Deux noms désignent la même catégorie s'ils ne diffèrent que par les majuscules, les accents ou les espaces.
bool memeNomCategorie(String a, String b) =>
    normaliserPourRecherche(nettoyerNomCategorie(a)) == normaliserPourRecherche(nettoyerNomCategorie(b));
