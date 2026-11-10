import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Ce qui s'est passé quand on a demandé d'ouvrir un fichier.
enum ResultatOuverture { ouvert, aucuneApplication, introuvable, echec }

/// Ouverture d'une pièce jointe (vidéo, document) dans une application du téléphone. Une interface, pour que les
/// tests puissent la remplacer : ils ne peuvent pas lancer d'autre application.
abstract interface class OuvreurPieceJointe {
  /// Ouvre [fichier] (qui porte déjà la bonne extension) dans l'application que choisit Android.
  Future<ResultatOuverture> ouvrir(File fichier);
}

/// Ouverture par Android (paquet `open_filex`, gratuit).
///
/// Le fichier est d'abord **copié dans le dossier temporaire** du téléphone, puis c'est cette copie qui est ouverte :
/// l'espace privé de l'application n'est pas lisible par les autres applications, alors que le dossier temporaire
/// est partagé de façon sûre par `open_filex`. Android vide ce dossier de lui-même quand il manque de place.
class OuvreurPieceJointeSysteme implements OuvreurPieceJointe {
  const OuvreurPieceJointeSysteme();

  @override
  Future<ResultatOuverture> ouvrir(File fichier) async {
    try {
      if (!await fichier.exists()) return ResultatOuverture.introuvable;

      final Directory temporaire = await getTemporaryDirectory();
      final Directory dossier = Directory('${temporaire.path}${Platform.pathSeparator}pieces_jointes_ouvertes');
      await dossier.create(recursive: true);
      final String nom = fichier.uri.pathSegments.last;
      final File copie = File('${dossier.path}${Platform.pathSeparator}$nom');
      // Une copie déjà là, de la même taille, est réutilisée (les noms sont uniques et le contenu ne change pas).
      if (!await copie.exists() || await copie.length() != await fichier.length()) {
        await fichier.copy(copie.path);
      }

      final OpenResult resultat = await OpenFilex.open(copie.path);
      switch (resultat.type) {
        case ResultType.done:
          return ResultatOuverture.ouvert;
        case ResultType.noAppToOpen:
          return ResultatOuverture.aucuneApplication;
        case ResultType.fileNotFound:
          return ResultatOuverture.introuvable;
        default:
          debugPrint('Ouverture impossible : ${resultat.type} ${resultat.message}');
          return ResultatOuverture.echec;
      }
    } catch (erreur, pile) {
      debugPrint('Ouverture impossible : $erreur\n$pile');
      return ResultatOuverture.echec;
    }
  }
}
