import 'dart:io';

import '../../domain/id_client_google.dart';

/// L'ID client Web saisi dans l'application, gardé dans un petit fichier du téléphone (hors de la base et des sauvegardes :
/// c'est un réglage de l'appareil, pas une donnée de l'activité). Ce n'est pas un secret.
class StockageClientWeb {
  StockageClientWeb(this.fichier);

  final File fichier;

  /// L'ID enregistré, ou `null` s'il n'y en a pas (ou si le fichier est illisible ou n'a pas la forme d'un ID).
  Future<String?> lire() async {
    try {
      if (!await fichier.exists()) return null;
      final String id = nettoyerIdClientWeb(await fichier.readAsString());
      return erreurIdClientWeb(id) == null ? id : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Enregistre [id] (écrit à côté, puis renommé : un arrêt en cours d'écriture ne laisse pas un fichier tronqué).
  Future<void> ecrire(String id) async {
    await fichier.parent.create(recursive: true);
    final File provisoire = File('${fichier.path}.tmp');
    await provisoire.writeAsString(id, flush: true);
    await provisoire.rename(fichier.path);
  }

  /// Oublie l'ID enregistré.
  Future<void> effacer() async {
    try {
      if (await fichier.exists()) await fichier.delete();
    } on FileSystemException {
      // Rien de plus à faire : l'ID sera relu tel quel au prochain démarrage.
    }
  }
}
