import 'dart:io';

/// Dossier où sont rangées les photos des produits, dans l'espace privé de l'application.
///
/// Une photo choisie dans la galerie ou prise avec l'appareil est **copiée** ici : elle reste
/// disponible même si l'originale est supprimée de la galerie. La base de données ne
/// conserve que le **nom du fichier** (chemin relatif), pas le chemin complet : le dossier
/// peut ainsi changer de place (réinstallation, restauration d'une sauvegarde) sans casser les fiches.
class StockagePhotos {
  StockagePhotos(this.dossier);

  /// Dossier de destination (créé au besoin lors de la première copie).
  final Directory dossier;

  static int _compteur = 0;

  static const Set<String> _extensionsAcceptees = <String>{'jpg', 'jpeg', 'png', 'webp', 'heic'};

  /// Copie [cheminSource] dans le dossier et retourne le nom du nouveau fichier.
  Future<String> enregistrer(String cheminSource) async {
    final File source = File(cheminSource);
    if (!await source.exists()) {
      throw const FileSystemException('La photo choisie est introuvable.');
    }
    await dossier.create(recursive: true);
    final String nom = _nomUnique(cheminSource);
    await source.copy(_cheminComplet(nom));
    return nom;
  }

  /// Fichier correspondant à un chemin enregistré en base. Un chemin déjà absolu est conservé tel quel.
  File fichier(String cheminEnregistre) {
    if (cheminEnregistre.startsWith('/') || cheminEnregistre.contains(':\\')) {
      return File(cheminEnregistre);
    }
    return File(_cheminComplet(cheminEnregistre));
  }

  /// Supprime le fichier d'une photo. Sans erreur si le fichier n'existe déjà plus.
  Future<void> supprimer(String cheminEnregistre) async {
    try {
      final File f = fichier(cheminEnregistre);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Un fichier impossible à supprimer n'empêche pas de continuer : il reste simplement orphelin.
    }
  }

  String _cheminComplet(String nom) => '${dossier.path}${Platform.pathSeparator}$nom';

  String _nomUnique(String cheminSource) {
    final String nomSource = cheminSource.split(RegExp(r'[/\\]')).last;
    final int point = nomSource.lastIndexOf('.');
    final String extension = point >= 0 ? nomSource.substring(point + 1).toLowerCase() : '';
    final String suffixe = _extensionsAcceptees.contains(extension) ? extension : 'jpg';
    _compteur++;
    return 'photo_${DateTime.now().microsecondsSinceEpoch}_$_compteur.$suffixe';
  }
}
