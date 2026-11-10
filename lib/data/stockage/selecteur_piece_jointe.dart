import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/enums.dart';
import '../../domain/pieces_jointes.dart';
import 'stockage_pieces_jointes.dart';

/// D'où vient la pièce jointe.
enum SourcePieceJointe { photoAppareil, photoGalerie, videoAppareil, videoGalerie, document }

/// Choix d'un fichier à joindre à une note. Une interface, pour que les tests puissent la remplacer : ils ne
/// peuvent pas ouvrir l'appareil photo, la galerie ni le sélecteur de fichiers du téléphone.
abstract interface class SelecteurPieceJointe {
  /// Le fichier choisi, ou `null` si la personne a annulé.
  Future<FichierChoisi?> choisir(SourcePieceJointe source);
}

/// Appareil photo, galerie et sélecteur de fichiers du téléphone (paquets `image_picker` et `file_picker`).
///
/// Les photos et vidéos sont prises **telles quelles** (aucune compression) ; la taille est contrôlée au rangement.
class SelecteurPieceJointeSysteme implements SelecteurPieceJointe {
  SelecteurPieceJointeSysteme([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<FichierChoisi?> choisir(SourcePieceJointe source) async {
    switch (source) {
      case SourcePieceJointe.photoAppareil:
        return _depuisImagePicker(await _picker.pickImage(source: ImageSource.camera), TypePieceJointe.photo);
      case SourcePieceJointe.photoGalerie:
        return _depuisImagePicker(await _picker.pickImage(source: ImageSource.gallery), TypePieceJointe.photo);
      case SourcePieceJointe.videoAppareil:
        return _depuisImagePicker(await _picker.pickVideo(source: ImageSource.camera), TypePieceJointe.video);
      case SourcePieceJointe.videoGalerie:
        return _depuisImagePicker(await _picker.pickVideo(source: ImageSource.gallery), TypePieceJointe.video);
      case SourcePieceJointe.document:
        // Tous les fichiers sont proposés. Une photo ou une vidéo choisie ici est reconnue à son extension.
        final PlatformFile? choisi = await FilePicker.pickFile();
        if (choisi == null) return null;
        return FichierChoisi(
          nom: choisi.name,
          type: typePieceJointeDepuisNom(choisi.name),
          // file_picker 13 : la taille annoncée peut manquer (null) ; elle est alors constatée pendant la copie.
          octets: choisi.lengthSync() ?? await choisi.length(),
          lire: () => choisi.readAsByteStream(),
        );
    }
  }

  Future<FichierChoisi?> _depuisImagePicker(XFile? fichier, TypePieceJointe type) async {
    if (fichier == null) return null;
    return FichierChoisi(
      nom: fichier.name,
      type: type,
      octets: await fichier.length(),
      lire: () => fichier.openRead(),
    );
  }
}
