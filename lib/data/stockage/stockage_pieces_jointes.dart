import 'dart:async';
import 'dart:io';

import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/pieces_jointes.dart';

/// Un fichier choisi par la personne (photo, vidéo, document), pas encore rangé dans l'application.
///
/// Le contenu se lit **en flux** ([lire]) : une vidéo de 150 Mo ne passe jamais entièrement par la mémoire.
class FichierChoisi {
  const FichierChoisi({required this.nom, required this.type, required this.lire, this.octets});

  /// Nom du fichier d'origine.
  final String nom;
  final TypePieceJointe type;

  /// Taille annoncée par le sélecteur, si elle est connue : un fichier trop gros est alors refusé sans rien copier.
  final int? octets;

  /// Ouvre le contenu. Appelée une seule fois.
  final Stream<List<int>> Function() lire;
}

/// Un fichier rangé dans le dossier des pièces jointes : ce que `NoteRepository` enregistre en base.
class PieceRangee {
  const PieceRangee({
    required this.nomFichier,
    required this.nomAffiche,
    required this.type,
    required this.octets,
  });

  /// Nom du fichier rangé (dans le dossier de [StockagePiecesJointes]).
  final String nomFichier;

  /// Nom que la personne reconnaît.
  final String nomAffiche;
  final TypePieceJointe type;
  final int octets;
}

/// Dossier où sont rangées les pièces jointes des notes, dans l'espace privé de l'application.
///
/// Comme pour les photos des produits (`StockagePhotos`), un fichier choisi est **copié** ici et la base ne garde
/// que son **nom** : le dossier peut changer de place (réinstallation, restauration d'une sauvegarde) sans rien
/// casser. La copie se fait en flux, dans un fichier provisoire (`.tmp`, ignoré par la sauvegarde) renommé à la
/// fin : on ne voit jamais un fichier à moitié copié.
class StockagePiecesJointes {
  StockagePiecesJointes(this.dossier);

  /// Dossier de destination (créé au besoin lors de la première copie).
  final Directory dossier;

  static int _compteur = 0;

  /// Copie le fichier choisi dans le dossier. Lance [DonneeInvalide] s'il est vide ou trop gros (rien n'est alors
  /// conservé), ou si le téléphone n'a plus de place.
  Future<PieceRangee> enregistrer(FichierChoisi choisi) async {
    final String nomAffiche = nettoyerNomPieceJointe(choisi.nom);
    final TypePieceJointe type = choisi.type;
    final int limite = limiteOctets(type);

    final int? annonce = choisi.octets;
    if (annonce != null) {
      final String? probleme = erreurTaillePieceJointe(type, annonce, nom: nomAffiche);
      if (probleme != null) throw DonneeInvalide(probleme);
    }

    await dossier.create(recursive: true);
    final String nom = _nomUnique(nomAffiche);
    final File definitif = File(_cheminComplet(nom));
    final File provisoire = File('${definitif.path}.tmp');

    int total = 0;
    try {
      final IOSink sortie = provisoire.openWrite();
      try {
        await for (final List<int> bloc in choisi.lire()) {
          total += bloc.length;
          if (total > limite) throw DonneeInvalide(messageFichierTropGros(type, nom: nomAffiche));
          sortie.add(bloc);
        }
      } finally {
        await sortie.close();
      }
      final String? probleme = erreurTaillePieceJointe(type, total, nom: nomAffiche);
      if (probleme != null) throw DonneeInvalide(probleme);
      await provisoire.rename(definitif.path);
    } on FileSystemException catch (erreur) {
      await _effacer(provisoire);
      if (_plusDePlace(erreur)) {
        throw const DonneeInvalide('Le téléphone n’a plus assez de place pour ranger ce fichier.');
      }
      rethrow;
    } catch (_) {
      await _effacer(provisoire);
      rethrow;
    }

    return PieceRangee(nomFichier: nom, nomAffiche: nomAffiche, type: type, octets: total);
  }

  /// Fichier correspondant à un nom enregistré en base. Par prudence, un éventuel chemin est ramené à son dernier
  /// morceau : on ne sort jamais du dossier.
  File fichier(String nomEnregistre) => File(_cheminComplet(_dernierMorceau(nomEnregistre)));

  /// Supprime un fichier. Sans erreur s'il n'existe déjà plus.
  Future<void> supprimer(String nomEnregistre) async {
    try {
      final File f = fichier(nomEnregistre);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Un fichier impossible à supprimer n'empêche pas de continuer : il reste simplement orphelin.
    }
  }

  /// Supprime plusieurs fichiers (sans erreur si certains n'existent plus).
  Future<void> supprimerTous(Iterable<String> nomsEnregistres) async {
    for (final String nom in nomsEnregistres) {
      await supprimer(nom);
    }
  }

  String _cheminComplet(String nom) => '${dossier.path}${Platform.pathSeparator}$nom';

  static String _dernierMorceau(String nom) => nom.split(RegExp(r'[/\\]')).last;

  static Future<void> _effacer(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Rien de plus à faire : un fichier provisoire oublié est ignoré par la sauvegarde.
    }
  }

  /// Le système a refusé d'écrire parce qu'il n'y a plus de place (ENOSPC).
  static bool _plusDePlace(FileSystemException erreur) {
    final OSError? os = erreur.osError;
    return os != null && (os.errorCode == 28 || os.message.toLowerCase().contains('no space'));
  }

  static String _nomUnique(String nomAffiche) {
    _compteur++;
    return 'piece_${DateTime.now().microsecondsSinceEpoch}_$_compteur.${extensionDeStockage(nomAffiche)}';
  }
}
