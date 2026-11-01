import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Choix du fichier de sauvegarde à restaurer (le sélecteur de fichiers d'Android). Une interface, pour que
/// les tests puissent la remplacer : ils ne peuvent pas ouvrir le sélecteur du téléphone.
abstract interface class SelecteurFichierSauvegarde {
  /// Contenu du fichier choisi, ou `null` si la personne a annulé.
  Future<Uint8List?> choisir();
}

/// Sélecteur de fichiers du téléphone (paquet `file_picker`). Tous les fichiers sont proposés : certaines
/// applications (messagerie, Drive) enregistrent un `.zip` sous un type que le filtre « zip » ne reconnaît pas.
/// Si le fichier choisi n'est pas une sauvegarde, `ServiceSauvegarde.examiner` le dit tout de suite.
class SelecteurFichierSysteme implements SelecteurFichierSauvegarde {
  @override
  Future<Uint8List?> choisir() async {
    final PlatformFile? fichier = await FilePicker.pickFile();
    if (fichier == null) return null;
    return fichier.readAsBytes();
  }
}
