import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ce que la machine où tourne l'application sait faire (ou ne sait pas faire).
///
/// Il n'y a que deux cas : **Android** (le téléphone, l'application telle qu'elle a toujours été) et **Windows**
/// (l'ordinateur : la même application dans une fenêtre). Tout ce qui n'est pas Windows se comporte comme Android :
/// c'est le cas des tests, qui tournent sur Linux, et ils restent donc exactement ce qu'ils étaient.
///
/// Les écrans et les services lisent ces indications au lieu de tester `Platform.isWindows` partout : un seul endroit
/// dit ce qui change sous Windows, et les tests peuvent simuler Windows en remplaçant [plateformeProvider].
class Plateforme {
  const Plateforme._({required this.nom, required this.appareilPhoto, required this.googleDrive, required this.fenetreDeBureau});

  /// Le téléphone Android : tout est disponible.
  const Plateforme.android() : this._(nom: 'Android', appareilPhoto: true, googleDrive: true, fenetreDeBureau: false);

  /// L'ordinateur Windows : pas d'appareil photo, une fenêtre redimensionnable. Google Drive y est disponible, par une connexion
  /// dans le navigateur (accès Google de type « application de bureau »).
  const Plateforme.windows() : this._(nom: 'Windows', appareilPhoto: false, googleDrive: true, fenetreDeBureau: true);

  /// La machine sur laquelle l'application tourne.
  factory Plateforme.courante() => Platform.isWindows ? const Plateforme.windows() : const Plateforme.android();

  /// « Android » ou « Windows ».
  final String nom;

  /// Vrai si l'on peut prendre une photo ou filmer une vidéo avec l'application (un téléphone) ; faux sur un ordinateur :
  /// on choisit alors un fichier existant.
  final bool appareilPhoto;

  /// Vrai si la connexion à Google Drive (étapes 6 à 8) est disponible. Elle l'est sur Android (Google Play Services) comme sous
  /// Windows (connexion dans le navigateur) ; les données peuvent toujours aussi passer d'un appareil à l'autre par le fichier
  /// de sauvegarde `.zip`.
  final bool googleDrive;

  /// Vrai si l'application vit dans une fenêtre d'ordinateur : le contenu garde alors la largeur d'un téléphone,
  /// centré dans la fenêtre, et les données sont rangées dans le dossier « données d'application » de l'utilisateur.
  final bool fenetreDeBureau;

  /// Largeur maximale du contenu dans une fenêtre d'ordinateur (un grand téléphone ou une petite tablette).
  static const double largeurMaxContenu = 640;
}

/// La plateforme courante. Les tests la remplacent pour simuler Windows.
final plateformeProvider = Provider<Plateforme>((ref) => Plateforme.courante());
