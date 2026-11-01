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
