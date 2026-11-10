/// Pièces jointes d'une note : photos, vidéos et documents (PDF, Word, tableur...) rangés dans le téléphone.
///
/// Règles (affichées à l'écran avant l'ajout, et rappelées dans le message de refus) :
/// - une photo ou un document : **25 Mo** au plus ;
/// - une vidéo : **150 Mo** au plus ;
/// - **20 pièces jointes** au plus par note.
///
/// Rien n'est redimensionné ni compressé : le fichier est rangé tel quel, et refusé s'il dépasse la limite.
library;

import 'enums.dart';

const int _octetsParKo = 1024;
const int _octetsParMo = 1024 * 1024;

/// Taille maximale d'une photo.
const int limiteOctetsPhoto = 25 * _octetsParMo;

/// Taille maximale d'une vidéo.
const int limiteOctetsVideo = 150 * _octetsParMo;

/// Taille maximale d'un document.
const int limiteOctetsDocument = 25 * _octetsParMo;

/// Nombre maximal de pièces jointes d'une note.
const int nombreMaxPiecesJointes = 20;

/// Longueur maximale du nom affiché d'une pièce jointe.
const int longueurMaxNomPieceJointe = 120;

/// Taille maximale d'une pièce jointe de ce [type].
int limiteOctets(TypePieceJointe type) => switch (type) {
  TypePieceJointe.photo => limiteOctetsPhoto,
  TypePieceJointe.video => limiteOctetsVideo,
  TypePieceJointe.document => limiteOctetsDocument,
};

/// « 850 o », « 12 Ko », « 1,4 Mo ».
String formaterTailleFichier(int octets) {
  if (octets < _octetsParKo) return '$octets o';
  if (octets < _octetsParMo) return '${(octets / _octetsParKo).round()} Ko';
  return '${(octets / _octetsParMo).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// « 25 Mo », « 150 Mo ».
String libelleLimite(TypePieceJointe type) => '${limiteOctets(type) ~/ _octetsParMo} Mo';

/// Les limites, en une phrase, à afficher près du bouton d'ajout.
String libelleLimitesPiecesJointes() =>
    'Photos et documents : ${libelleLimite(TypePieceJointe.photo)} au plus chacun. '
    'Vidéos : ${libelleLimite(TypePieceJointe.video)} au plus. '
    '$nombreMaxPiecesJointes pièces jointes au plus par note.';

// --- Type et nom ---------------------------------------------------------------------

const Set<String> _extensionsPhoto = <String>{'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp'};
const Set<String> _extensionsVideo = <String>{'mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv', 'avi'};

/// L'extension d'un nom de fichier, en minuscules et sans le point (vide s'il n'y en a pas).
String extensionDeFichier(String nom) {
  final String dernier = nom.split(RegExp(r'[/\\]')).last;
  final int point = dernier.lastIndexOf('.');
  if (point < 0 || point == dernier.length - 1) return '';
  return dernier.substring(point + 1).toLowerCase();
}

/// Photo, vidéo ou document, d'après l'extension du nom. Tout ce qui n'est ni une photo ni une vidéo est un document.
TypePieceJointe typePieceJointeDepuisNom(String nom) {
  final String extension = extensionDeFichier(nom);
  if (_extensionsPhoto.contains(extension)) return TypePieceJointe.photo;
  if (_extensionsVideo.contains(extension)) return TypePieceJointe.video;
  return TypePieceJointe.document;
}

/// Nom affiché d'une pièce jointe, prêt à enregistrer : le dernier morceau d'un éventuel chemin, sans espaces
/// superflus, raccourci s'il est trop long (l'extension est gardée). « Sans nom » si rien ne reste.
String nettoyerNomPieceJointe(String? nom) {
  final String propre = (nom ?? '').split(RegExp(r'[/\\]')).last.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (propre.isEmpty) return 'Sans nom';
  if (propre.length <= longueurMaxNomPieceJointe) return propre;
  final String extension = extensionDeFichier(propre);
  final String suffixe = extension.isEmpty || extension.length > 10 ? '' : '.$extension';
  return '${propre.substring(0, longueurMaxNomPieceJointe - suffixe.length)}$suffixe';
}

/// L'extension à donner au fichier rangé dans le téléphone : celle du fichier d'origine si elle est sûre
/// (lettres et chiffres, 10 au plus), sinon `bin`. Elle aide Android à choisir l'application qui l'ouvre.
String extensionDeStockage(String nom) {
  final String extension = extensionDeFichier(nom);
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ? extension : 'bin';
}

// --- Contrôles -----------------------------------------------------------------------

/// Ce qui ne va pas dans un fichier de [octets] octets pour ce [type] (`null` si tout va bien).
String? erreurTaillePieceJointe(TypePieceJointe type, int octets, {String? nom}) {
  final String designation = nom == null ? 'Ce fichier' : '« ${nettoyerNomPieceJointe(nom)} »';
  if (octets <= 0) return '$designation est vide : il n’a pas été ajouté.';
  if (octets > limiteOctets(type)) {
    return '$designation pèse ${formaterTailleFichier(octets)} : la limite est de ${libelleLimite(type)} '
        'pour les ${type.libellePluriel}.';
  }
  return null;
}

/// Le fichier est plus gros que la limite, sans qu'on en connaisse la taille exacte (elle n'est constatée qu'en cours
/// de copie).
String messageFichierTropGros(TypePieceJointe type, {String? nom}) {
  final String designation = nom == null ? 'Ce fichier' : '« ${nettoyerNomPieceJointe(nom)} »';
  return '$designation dépasse la limite de ${libelleLimite(type)} pour les ${type.libellePluriel}.';
}

/// Ce qui ne va pas si une note en a [nombre] au total (`null` si tout va bien).
String? erreurNombrePiecesJointes(int nombre) {
  if (nombre > nombreMaxPiecesJointes) {
    return 'Une note peut avoir $nombreMaxPiecesJointes pièces jointes au plus.';
  }
  return null;
}
