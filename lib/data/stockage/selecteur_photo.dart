import 'package:image_picker/image_picker.dart';

/// D'où vient la photo.
enum SourcePhoto { appareil, galerie }

/// Choix d'une photo par l'utilisatrice. Une interface, pour que les tests puissent la remplacer.
abstract interface class SelecteurPhoto {
  /// Chemin du fichier choisi, ou `null` si elle a annulé.
  Future<String?> choisir(SourcePhoto source);
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
}
