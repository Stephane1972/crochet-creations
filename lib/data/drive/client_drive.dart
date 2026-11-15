import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../domain/drive_envoi.dart';
import 'compte_google.dart';

/// Les opérations sur Drive dont l'application a besoin : retrouver ou créer un dossier, lister ses fichiers, envoyer un
/// fichier, télécharger un fichier. Rien d'autre : **aucune suppression, aucun partage**.
abstract class ClientDrive {
  /// Identifiant du dossier [nom] (dans [parentId], ou à la racine de « Mon Drive »), `null` s'il n'existe pas.
  Future<String?> trouverDossier(String nom, {String? parentId});

  /// Crée le dossier [nom] (dans [parentId], ou à la racine de « Mon Drive ») et retourne son identifiant.
  Future<String> creerDossier(String nom, {String? parentId});

  /// Les fichiers (pas les sous-dossiers) du dossier [dossierId], en excluant la corbeille.
  Future<List<FichierDistant>> lister(String dossierId);

  /// Envoie [fichier] sous le nom [nom] dans [dossierId], en flux (le fichier n'est jamais entièrement en mémoire). Avec
  /// [idExistant], le contenu de ce fichier Drive est remplacé (l'ancienne version reste dans son historique).
  /// [empreinte] (SHA-256) est notée sur le fichier Drive quand elle est connue. [progression] reçoit le nombre d'octets lus.
  /// Lève une [ErreurDrive] en cas d'échec.
  Future<void> envoyer({
    required File fichier,
    required String nom,
    required String dossierId,
    String? empreinte,
    String? idExistant,
    void Function(int octetsEnvoyes)? progression,
  });

  /// Télécharge le fichier Drive [id] vers [destination], en flux (jamais entièrement en mémoire). Le fichier est écrit
  /// sous un nom provisoire puis renommé : [destination] n'existe jamais à moitié écrit, et un fichier déjà là est remplacé
  /// seulement si le téléchargement est complet. [progression] reçoit le nombre d'octets reçus.
  /// Lève une [ErreurDrive] en cas d'échec (rien n'est alors laissé).
  Future<void> telecharger({
    required String id,
    required File destination,
    void Function(int octetsRecus)? progression,
  });
}

/// Type de contenu d'un fichier d'après son extension (pour que Drive l'affiche correctement).
String typeMimeDrive(String nom) {
  final int point = nom.lastIndexOf('.');
  final String extension = point < 0 ? '' : nom.substring(point + 1).toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'pdf':
      return 'application/pdf';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case '3gp':
      return 'video/3gpp';
    case 'txt':
      return 'text/plain';
    case 'csv':
      return 'text/csv';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    default:
      return 'application/octet-stream';
  }
}

/// Protège une valeur placée entre apostrophes dans une requête Drive (`q`).
String protegerPourRequeteDrive(String valeur) => valeur.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

/// Ajoute à chaque requête le jeton d'accès du compte Google connecté.
class _ClientAuthentifie extends http.BaseClient {
  _ClientAuthentifie(this._base, this._compte);

  final http.Client _base;
  final CompteGoogle _compte;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer ${await _compte.jetonAcces()}';
    return _base.send(request);
  }

  @override
  void close() => _base.close();
}

/// [ClientDrive] réel : l'API Drive v3 de Google (paquet `googleapis`), avec le seul droit `drive.file`.
class ClientDriveGoogle implements ClientDrive {
  ClientDriveGoogle(this._compte, {http.Client? base}) : _base = base ?? http.Client();

  final CompteGoogle _compte;
  final http.Client _base;
  drive.DriveApi? _apiMemorisee;

  static const String _typeDossier = 'application/vnd.google-apps.folder';

  drive.DriveApi get _api => _apiMemorisee ??= drive.DriveApi(_ClientAuthentifie(_base, _compte));

  /// Exécute [operation] ; un refus d'autorisation (401) est retenté une fois avec un jeton neuf. Toute erreur sort en
  /// [ErreurDrive] lisible.
  Future<T> _executer<T>(Future<T> Function() operation) async {
    try {
      try {
        return await operation();
      } on drive.DetailedApiRequestError catch (erreur) {
        if (erreur.status != 401) rethrow;
        _compte.invaliderJeton();
        return await operation();
      }
    } on ErreurDrive {
      rethrow;
    } on drive.DetailedApiRequestError catch (erreur) {
      throw _traduireApi(erreur);
    } on drive.ApiRequestError catch (erreur) {
      throw ErreurDrive('Google Drive a répondu de façon inattendue : ${erreur.message ?? 'sans détail'}');
    } on SocketException {
      throw const ErreurDrive('Pas de connexion à Internet.');
    } on http.ClientException {
      throw const ErreurDrive('Pas de connexion à Internet.');
    } on TimeoutException {
      throw const ErreurDrive('La connexion à Google est trop lente. Réessayez.');
    } on FileSystemException catch (erreur) {
      throw ErreurDrive('Fichier illisible : ${erreur.message}');
    }
  }

  ErreurDrive _traduireApi(drive.DetailedApiRequestError erreur) {
    final int? statut = erreur.status;
    final String message = (erreur.message ?? '').toLowerCase();
    if (statut == 401) {
      return const ErreurDrive('L’autorisation Google Drive a expiré. Reconnectez-vous.', autorisationAExpire: true);
    }
    if (statut == 403) {
      if (message.contains('ratelimit') || message.contains('rate limit') || message.contains('per minute')) {
        return const ErreurDrive('Google demande de ralentir. Réessayez dans quelques minutes.');
      }
      if (message.contains('quota')) {
        return const ErreurDrive('Votre Drive est plein : libérez de la place puis réessayez.');
      }
      return ErreurDrive(
        'Google Drive a refusé l’accès (${erreur.message ?? 'accès refusé'}). '
        'Vérifiez que l’API Google Drive est activée dans le projet Google Cloud.',
      );
    }
    if (statut == 404) return const ErreurDrive('Le fichier ou le dossier est introuvable sur Drive.');
    if (statut == 429) return const ErreurDrive('Google demande de ralentir. Réessayez dans quelques minutes.');
    if (statut != null && statut >= 500) {
      return const ErreurDrive('Google Drive est momentanément indisponible. Réessayez plus tard.');
    }
    return ErreurDrive('Google Drive a répondu une erreur (${statut ?? '?'}) : ${erreur.message ?? 'sans détail'}');
  }

  @override
  Future<String?> trouverDossier(String nom, {String? parentId}) => _executer(() async {
    final drive.FileList liste = await _api.files.list(
      q:
          "mimeType = '$_typeDossier' and name = '${protegerPourRequeteDrive(nom)}' "
          "and '${parentId ?? 'root'}' in parents and trashed = false",
      spaces: 'drive',
      pageSize: 10,
      $fields: 'files(id)',
    );
    return liste.files?.firstOrNull?.id;
  });

  @override
  Future<String> creerDossier(String nom, {String? parentId}) => _executer(() async {
    final drive.File cree = await _api.files.create(
      drive.File(name: nom, mimeType: _typeDossier, parents: <String>[parentId ?? 'root']),
      $fields: 'id',
    );
    final String? id = cree.id;
    if (id == null) throw const ErreurDrive('Google Drive n’a pas créé le dossier.');
    return id;
  });

  @override
  Future<List<FichierDistant>> lister(String dossierId) => _executer(() async {
    final List<FichierDistant> resultat = <FichierDistant>[];
    String? page;
    do {
      final drive.FileList liste = await _api.files.list(
        q: "'${protegerPourRequeteDrive(dossierId)}' in parents and trashed = false and mimeType != '$_typeDossier'",
        spaces: 'drive',
        pageSize: 1000,
        pageToken: page,
        $fields: 'nextPageToken, files(id,name,size,appProperties)',
      );
      for (final drive.File f in liste.files ?? const <drive.File>[]) {
        final String? id = f.id;
        final String? nom = f.name;
        if (id == null || nom == null) continue;
        resultat.add(
          FichierDistant(
            id: id,
            nom: nom,
            octets: int.tryParse(f.size ?? ''),
            empreinte: f.appProperties?[proprieteEmpreinteDrive],
          ),
        );
      }
      page = liste.nextPageToken;
    } while (page != null && page.isNotEmpty);
    return resultat;
  });

  @override
  Future<void> envoyer({
    required File fichier,
    required String nom,
    required String dossierId,
    String? empreinte,
    String? idExistant,
    void Function(int octetsEnvoyes)? progression,
  }) => _executer(() async {
    final int longueur = await fichier.length();
    int lus = 0;
    // Le flux est relu à chaque tentative : un nouveau flux, un compteur remis à zéro.
    final Stream<List<int>> flux = fichier.openRead().map((List<int> morceau) {
      lus += morceau.length;
      progression?.call(lus);
      return morceau;
    });
    final drive.Media contenu = drive.Media(flux, longueur, contentType: typeMimeDrive(nom));
    final Map<String, String>? proprietes = empreinte == null ? null : <String, String>{proprieteEmpreinteDrive: empreinte};
    if (idExistant == null) {
      await _api.files.create(
        drive.File(name: nom, parents: <String>[dossierId], appProperties: proprietes),
        uploadMedia: contenu,
        uploadOptions: drive.ResumableUploadOptions(),
        $fields: 'id',
      );
    } else {
      await _api.files.update(
        drive.File(appProperties: proprietes),
        idExistant,
        uploadMedia: contenu,
        uploadOptions: drive.ResumableUploadOptions(),
        $fields: 'id',
      );
    }
  });

  @override
  Future<void> telecharger({
    required String id,
    required File destination,
    void Function(int octetsRecus)? progression,
  }) => _executer(() async {
    await destination.parent.create(recursive: true);
    final File provisoire = File('${destination.path}.tmp');
    IOSink? sortie;
    Future<void> nettoyer() async {
      try {
        await sortie?.close();
      } catch (_) {
        // Le fichier provisoire est effacé juste après : peu importe l'état de sa fermeture.
      }
      try {
        if (await provisoire.exists()) await provisoire.delete();
      } on FileSystemException {
        // Un fichier provisoire oublié est écrasé au prochain essai.
      }
    }

    try {
      // Un nouveau flux et un nouveau fichier provisoire à chaque tentative.
      final Object reponse = await _api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia);
      if (reponse is! drive.Media) throw const ErreurDrive('Google Drive n’a pas renvoyé le contenu du fichier.');
      final IOSink fichierEcrit = provisoire.openWrite();
      sortie = fichierEcrit;
      int recus = 0;
      await for (final List<int> morceau in reponse.stream) {
        fichierEcrit.add(morceau);
        recus += morceau.length;
        progression?.call(recus);
      }
      await fichierEcrit.flush();
      await fichierEcrit.close();
      sortie = null;
      final int? annonce = reponse.length;
      if (annonce != null && annonce != recus) {
        throw const ErreurDrive('Le téléchargement s’est arrêté avant la fin. Réessayez.');
      }
      if (await destination.exists()) await destination.delete();
      await provisoire.rename(destination.path);
    } on FileSystemException catch (erreur) {
      await nettoyer();
      throw ErreurDrive('Impossible d’écrire le fichier sur le téléphone (place insuffisante ?) : ${erreur.message}');
    } catch (_) {
      await nettoyer();
      rethrow;
    }
  });
}
