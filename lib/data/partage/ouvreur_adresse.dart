import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../drive/oauth_bureau.dart' show ouvrirDansLeNavigateur;

/// Ouverture d'une adresse web dans le navigateur. Une interface, pour que les tests puissent la remplacer : ils ne
/// peuvent pas lancer de navigateur.
abstract interface class OuvreurAdresse {
  /// Ouvre [adresse] dans le navigateur. Retourne `false` si elle n'a pas pu être ouverte (aucun navigateur, par exemple).
  Future<bool> ouvrir(Uri adresse);
}

/// Ouverture par le système : le navigateur habituel de Windows (comme pour la connexion à Google), ou celui d'Android
/// (paquet `url_launcher`, gratuit). Seules les adresses en `https` sont ouvertes.
class OuvreurAdresseSysteme implements OuvreurAdresse {
  const OuvreurAdresseSysteme();

  @override
  Future<bool> ouvrir(Uri adresse) async {
    if (adresse.scheme != 'https') return false;
    try {
      if (Platform.isWindows) {
        await ouvrirDansLeNavigateur(adresse);
        return true;
      }
      return await launchUrl(adresse, mode: LaunchMode.externalApplication);
    } catch (erreur, pile) {
      debugPrint('Ouverture de l’adresse impossible : $erreur\n$pile');
      return false;
    }
  }
}
