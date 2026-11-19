import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Partage d'un fichier quelconque (sauvegarde .zip, export CSV ou JSON) par la feuille de partage d'Android :
/// messagerie, e-mail, Drive, enregistrement... Les écrans passent par cette interface : les tests la remplacent
/// par un faux service, car la feuille de partage est celle du téléphone.
abstract interface class ServicePartageFichiers {
  Future<void> partager({
    required String cheminFichier,
    required String nomFichier,
    required String typeMime,
    required String sujet,
  });
}

class ServicePartageFichiersSysteme implements ServicePartageFichiers {
  @override
  Future<void> partager({
    required String cheminFichier,
    required String nomFichier,
    required String typeMime,
    required String sujet,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(cheminFichier, mimeType: typeMime, name: nomFichier)],
        subject: sujet,
      ),
    );
  }
}

/// Windows : pas de feuille de partage, mais la fenêtre « Enregistrer sous… » de l'ordinateur. La personne choisit où
/// ranger le fichier (le bureau, une clé USB, un dossier synchronisé...) ; c'est ainsi qu'une sauvegarde passe du PC au
/// téléphone, ou l'inverse. Annuler la fenêtre n'enregistre rien et n'est pas une erreur.
class ServicePartageFichiersBureau implements ServicePartageFichiers {
  @override
  Future<void> partager({
    required String cheminFichier,
    required String nomFichier,
    required String typeMime,
    required String sujet,
  }) => enregistrerSous(cheminFichier: cheminFichier, nomFichier: nomFichier);
}

/// Au-delà de cette taille, le fichier n'est pas chargé en mémoire pour la fenêtre « Enregistrer sous… » (une sauvegarde avec
/// des vidéos peut peser plusieurs centaines de Mo) : il est copié ensuite.
const int _tailleMaxEnMemoire = 32 * 1024 * 1024;

/// Ouvre « Enregistrer sous… » et y range le fichier. Ne fait rien si la personne annule.
///
/// `file_picker` (version 12 et suivantes) exige les octets du fichier et les écrit lui-même à l'endroit choisi. Pour un fichier
/// courant (PDF, export, petite sauvegarde), on les lui donne. Pour un gros fichier, on ne lui donne qu'un octet de remplissage,
/// puis on copie le vrai fichier à l'endroit choisi. Dans les deux cas, on vérifie à la fin que le fichier rangé a la bonne taille.
Future<void> enregistrerSous({required String cheminFichier, required String nomFichier}) async {
  final File source = File(cheminFichier);
  final int taille = await source.length();
  final bool petit = taille <= _tailleMaxEnMemoire;
  final Uint8List octets = petit ? await source.readAsBytes() : Uint8List(1);

  final Uri? choix = await FilePicker.saveFile(
    dialogTitle: 'Enregistrer « $nomFichier »',
    fileName: nomFichier,
    bytes: octets,
  );
  if (choix == null) return;

  final String destination = choix.scheme == 'file' ? choix.toFilePath() : choix.path;
  if (destination.isEmpty || destination == cheminFichier) return;
  final File cible = File(destination);
  if (!await cible.exists() || await cible.length() != taille) {
    await source.copy(destination);
  }
}
