import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// D'où vient la photo.
enum SourcePhoto { appareil, galerie }

/// Choix d'une photo par l'utilisatrice. Une interface, pour que les tests puissent la remplacer.
abstract interface class SelecteurPhoto {
  /// Chemin du fichier choisi, ou `null` si elle a annulé.
  Future<String?> choisir(SourcePhoto source);

  /// Photo prise juste avant qu'Android ferme l'application (rare, quand la mémoire du téléphone est pleine) : au
  /// redémarrage, le système la garde de côté. Chemin du fichier, ou `null` s'il n'y en a pas. **À appeler une
  /// seule fois, au démarrage** : le système ne la rend qu'une fois.
  Future<String?> retrouverPhotoPerdue();
}

/// Appareil photo et galerie du téléphone (paquet `image_picker`).
class SelecteurPhotoSysteme implements SelecteurPhoto {
  SelecteurPhotoSysteme([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Les photos sont réduites (1 600 px maximum) : assez nettes pour une fiche produit
  /// et une facture, sans remplir la mémoire du téléphone.
  @override
  Future<String?> choisir(SourcePhoto source) async {
    final XFile? fichier = await _picker.pickImage(
      source: source == SourcePhoto.appareil ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    return fichier?.path;
  }

  @override
  Future<String?> retrouverPhotoPerdue() async {
    try {
      final response = await _picker.retrieveLostData();
      return response.file?.path;
    } catch (erreur, pile) {
      // Pas de photo à retrouver (ou téléphone qui ne sait pas le faire) : on démarre normalement.
      debugPrint('Photo perdue non récupérable : $erreur\n$pile');
      return null;
    }
  }
}
