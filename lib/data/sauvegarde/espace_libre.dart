import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/foundation.dart';

/// Place libre sur le téléphone, pour vérifier **avant** d'écrire une sauvegarde (ou de restaurer) qu'il y a
/// assez de place. Une interface, pour que les tests puissent la remplacer : ils ne parlent pas à Android.
abstract interface class ControleEspaceLibre {
  /// Octets libres à l'endroit de [dossier], ou `null` si on ne sait pas les mesurer. Dans ce cas la sauvegarde
  /// est quand même tentée : si le téléphone se remplit en route, l'écriture échoue proprement (fichier provisoire
  /// effacé, message clair, rien d'abîmé).
  Future<int?> octetsLibres(Directory dossier);
}

/// Mesure faite par Android (paquet `disk_space_plus`, gratuit). Toute erreur du paquet est traitée comme
/// « inconnu » : elle ne doit jamais empêcher une sauvegarde.
class ControleEspaceLibreSysteme implements ControleEspaceLibre {
  const ControleEspaceLibreSysteme();

  @override
  Future<int?> octetsLibres(Directory dossier) async {
    try {
      // Le dossier des sauvegardes n'existe pas avant la première : on mesure à l'endroit existant le plus proche.
      Directory mesure = dossier;
      while (!await mesure.exists() && mesure.parent.path != mesure.path) {
        mesure = mesure.parent;
      }
      final double? megaoctets = await DiskSpacePlus().getFreeDiskSpaceForPath(mesure.path);
      if (megaoctets == null || megaoctets < 0) return null;
      return (megaoctets * 1024 * 1024).floor();
    } catch (erreur, pile) {
      debugPrint('Mesure de la place libre impossible : $erreur\n$pile');
      return null;
    }
  }
}

/// Aucune mesure : la place libre est toujours « inconnue » (valeur par défaut du service, et des tests).
class ControleEspaceLibreInconnu implements ControleEspaceLibre {
  const ControleEspaceLibreInconnu();

  @override
  Future<int?> octetsLibres(Directory dossier) async => null;
}
