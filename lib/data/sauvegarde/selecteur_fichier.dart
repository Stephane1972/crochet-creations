import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Choix du fichier de sauvegarde à restaurer (le sélecteur de fichiers d'Android). Une interface, pour que
/// les tests puissent la remplacer : ils ne peuvent pas ouvrir le sélecteur du téléphone.
abstract interface class SelecteurFichierSauvegarde {
  /// Une **copie de travail** du fichier choisi (dans le dossier temporaire du téléphone), ou `null` si la
  /// personne a annulé. Celui qui l'appelle supprime cette copie quand il a fini.
  Future<File?> choisir();
}

/// Sélecteur de fichiers du téléphone (paquet `file_picker`). Tous les fichiers sont proposés : certaines
/// applications (messagerie, Drive) enregistrent un `.zip` sous un type que le filtre « zip » ne reconnaît pas.
/// Si le fichier choisi n'est pas une sauvegarde, `ServiceSauvegarde.examiner` le dit tout de suite.
///
/// Le fichier choisi est recopié **en flux** dans le dossier temporaire : une sauvegarde avec des vidéos ne
/// passe jamais entièrement par la mémoire.
class SelecteurFichierSysteme implements SelecteurFichierSauvegarde {
  @override
  Future<File?> choisir() async {
    final PlatformFile? choisi = await FilePicker.pickFile();
    if (choisi == null) return null;

    final Directory temporaire = await getTemporaryDirectory();
    final File copie = File(
      '${temporaire.path}${Platform.pathSeparator}restauration-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    try {
      final IOSink sortie = copie.openWrite();
      try {
        await sortie.addStream(choisi.readAsByteStream());
      } finally {
        await sortie.close();
      }
    } catch (_) {
      if (await copie.exists()) await copie.delete();
      rethrow;
    }
    return copie;
  }
}
