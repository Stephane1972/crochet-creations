import 'dart:io';

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

/// Ouvre « Enregistrer sous… » et y copie le fichier. Ne fait rien si la personne annule.
Future<void> enregistrerSous({required String cheminFichier, required String nomFichier}) async {
  final Uri? choix = await FilePicker.saveFile(dialogTitle: 'Enregistrer « $nomFichier »', fileName: nomFichier);
  if (choix == null) return;
  final String destination = choix.scheme == 'file' ? choix.toFilePath() : choix.path;
  if (destination.isEmpty || destination == cheminFichier) return;
  await File(cheminFichier).copy(destination);
}
