import 'dart:io';
import 'dart:typed_data';

/// Dossier où sont rangés des PDF (un dossier pour les factures, un autre pour les devis), dans l'espace
/// privé de l'application.
///
/// Un fichier par document, nommé d'après son numéro (`FACT-2026-0001.pdf`, `DEVIS-2026-0001.pdf`) : c'est
/// aussi le nom que verra la personne qui reçoit le PDF. La base ne garde que le **nom du fichier**, pas le
/// chemin complet (comme pour les photos) : le dossier peut changer de place sans casser les documents.
class StockagePdf {
  StockagePdf(this.dossier);

  /// Dossier de destination (créé au premier document).
  final Directory dossier;

  /// Écrit le PDF du document [numero] et retourne le nom du fichier. Un fichier du même nom est remplacé.
  Future<String> enregistrer(String numero, Uint8List octets) async {
    await dossier.create(recursive: true);
    final String nom = '$numero.pdf';
    // On écrit dans un fichier provisoire puis on le renomme : un PDF jamais à moitié écrit.
    final File provisoire = File('${_cheminComplet(nom)}.tmp');
    await provisoire.writeAsBytes(octets, flush: true);
    await provisoire.rename(_cheminComplet(nom));
    return nom;
  }

  /// Fichier correspondant à un nom enregistré en base. Un chemin déjà absolu est conservé tel quel.
  File fichier(String nomEnregistre) {
    if (nomEnregistre.startsWith('/') || nomEnregistre.contains(':\\')) return File(nomEnregistre);
    return File(_cheminComplet(nomEnregistre));
  }

  /// Contenu du PDF, ou `null` s'il n'existe plus (fichier effacé, sauvegarde restaurée sans les PDF).
  Future<Uint8List?> lire(String nomEnregistre) async {
    try {
      final File f = fichier(nomEnregistre);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Supprime un PDF. Sans erreur s'il n'existe déjà plus.
  Future<void> supprimer(String nomEnregistre) async {
    try {
      final File f = fichier(nomEnregistre);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Un fichier impossible à supprimer reste simplement orphelin.
    }
  }

  String _cheminComplet(String nom) => '${dossier.path}${Platform.pathSeparator}$nom';
}
