import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants/google_config.dart';
import '../../domain/agenda_google.dart';
import '../../domain/drive_envoi.dart';
import '../../domain/id_client_google.dart';
import 'stockage_client_web.dart';

/// Le compte Google connecté.
class ProfilGoogle {
  const ProfilGoogle({required this.email, this.nom});

  final String email;
  final String? nom;
}

/// Une erreur de connexion à Google ou d'envoi vers Drive, avec un message lisible tel quel par la personne.
class ErreurDrive implements Exception {
  const ErreurDrive(this.message, {this.autorisationAExpire = false, this.annulee = false});

  final String message;

  /// Vrai si la connexion à Google doit être refaite (autorisation retirée ou expirée) : inutile de réessayer tel quel.
  final bool autorisationAExpire;

  /// Vrai si la personne a elle-même annulé (fermé la fenêtre de connexion) : ce n'est pas une panne.
  final bool annulee;

  @override
  String toString() => message;
}

/// La connexion au compte Google, avec le seul droit « fichiers créés par l'application » (`drive.file`).
abstract class CompteGoogle {
  /// Vrai si l'application connaît l'ID client Web du projet Google Cloud (voir `google_config.dart`).
  bool get configure;

  /// L'ID client Web utilisé (vide : aucun).
  String get clientWeb;

  /// Vrai si l'ID utilisé a été saisi dans l'application (sinon il a été fourni avec elle, ou il n'y en a pas).
  bool get clientWebEnregistre;

  /// Vrai si un nouvel ID n'est pris en compte qu'après avoir fermé complètement l'application : Google ne se laisse
  /// configurer qu'une fois par lancement.
  bool get redemarrageNecessaire;

  /// Enregistre l'ID client Web saisi (nettoyé et vérifié ici) sur le téléphone, et l'utilise. Lève une [ErreurDrive] si
  /// ce n'est pas un ID client ou si l'enregistrement échoue.
  Future<void> enregistrerClientWeb(String saisie);

  /// Oublie l'ID enregistré : l'application revient à celui qui lui a été fourni (s'il y en a un).
  Future<void> oublierClientWeb();

  /// Retrouve, sans rien afficher, le compte déjà connecté (au lancement). `null` : il faut se connecter.
  Future<ProfilGoogle?> restaurer();

  /// Ouvre la fenêtre de connexion Google (choix du compte, accord du droit Drive).
  Future<ProfilGoogle> seConnecter();

  /// Oublie le compte sur ce téléphone (les fichiers déjà envoyés restent sur Drive).
  Future<void> seDeconnecter();

  /// Jeton qui autorise les appels à Drive. Lève une [ErreurDrive] (`autorisationAExpire`) si la connexion est perdue.
  Future<String> jetonAcces();

  /// Oublie le jeton en mémoire (Drive l'a refusé) : le prochain appel en demande un neuf.
  void invaliderJeton();
}

/// Un compte Google qui, en plus de l'ID client, demande le « code secret du client » : l'accès de type « application de
/// bureau » (Windows). Sur Android, l'ID client Web suffit et ce code n'est jamais demandé.
abstract class CompteAvecCodeSecret {
  /// Vrai si un code secret est enregistré sur cet appareil.
  bool get codeSecretEnregistre;

  /// Enregistre le code secret saisi (nettoyé et vérifié ici). Lève une [ErreurDrive] si ce n'en est pas un ou si
  /// l'enregistrement échoue.
  Future<void> enregistrerCodeSecret(String saisie);
}

/// Un compte Google qui sait aussi demander le droit « Google Agenda » (`calendar.app.created`), à part du droit Drive : la
/// personne ne l'accorde que si elle active la synchronisation du calendrier vers Google Agenda. Ce droit ne donne accès qu'à
/// l'agenda créé par l'application, jamais aux autres agendas de la personne.
abstract class CompteAvecAgenda {
  /// Vrai si le droit « agenda » est déjà accordé (sans rien afficher).
  Future<bool> agendaAutorise();

  /// Demande le droit « agenda » (fenêtre de Google sur Android, page dans le navigateur sous Windows). Lève une [ErreurDrive] :
  /// `annulee` si la personne ferme, un message lisible si Google refuse ou si le droit n'a pas été accordé.
  Future<void> autoriserAgenda();

  /// Le jeton qui autorise les appels à Google Agenda. Lève une [ErreurDrive] (`autorisationAExpire`) si le droit n'est pas
  /// (ou plus) accordé ou si la connexion est perdue.
  Future<String> jetonAgenda();
}

/// [CompteGoogle] réel : `google_sign_in` (Android : Google Play Services).
class CompteGoogleReel implements CompteGoogle, CompteAvecAgenda {
  /// [clientWeb] : l'ID fourni avec l'application ; [clientWebEnregistre] : celui que la personne a saisi (il passe avant) et
  /// que [stockage] garde d'un lancement à l'autre.
  CompteGoogleReel({String? clientWeb, String? clientWebEnregistre, StockageClientWeb? stockage})
    : _clientWebFourni = clientWeb ?? clientWebGoogle,
      _clientWebSaisi = (clientWebEnregistre ?? '').isEmpty ? null : clientWebEnregistre,
      _stockage = stockage;

  final String _clientWebFourni;
  final StockageClientWeb? _stockage;
  String? _clientWebSaisi;
  GoogleSignInAccount? _compte;
  Future<void>? _initialisation;

  /// L'ID avec lequel Google a été configuré depuis le lancement (`null` : pas encore).
  String? _clientWebInitialise;
  String? _jeton;
  DateTime? _jetonValideJusqua;
  String? _jetonAgenda;
  DateTime? _jetonAgendaValideJusqua;

  /// Durée pendant laquelle un jeton est réutilisé (il est valable environ une heure).
  static const Duration _dureeJeton = Duration(minutes: 30);

  String get _clientWeb => _clientWebSaisi ?? _clientWebFourni;

  @override
  bool get configure => _clientWeb.isNotEmpty;

  @override
  String get clientWeb => _clientWeb;

  @override
  bool get clientWebEnregistre => _clientWebSaisi != null;

  @override
  bool get redemarrageNecessaire => _clientWebInitialise != null && _clientWebInitialise != _clientWeb;

  @override
  Future<void> enregistrerClientWeb(String saisie) async {
    final String id = nettoyerIdClientWeb(saisie);
    final String? probleme = erreurIdClientWeb(id);
    if (probleme != null) throw ErreurDrive(probleme);
    try {
      await _stockage?.ecrire(id);
    } on FileSystemException {
      throw const ErreurDrive('Impossible d’enregistrer l’ID sur le téléphone : y a-t-il encore de la place ?');
    }
    _clientWebSaisi = id;
    invaliderJeton();
  }

  @override
  Future<void> oublierClientWeb() async {
    await _stockage?.effacer();
    _clientWebSaisi = null;
    invaliderJeton();
  }

  Future<void> _initialiser() async {
    if (redemarrageNecessaire) {
      throw const ErreurDrive(
        'Le nouvel ID client Web sera pris en compte au prochain lancement : fermez complètement l’application '
        '(retirez-la des applications récentes), puis rouvrez-la.',
      );
    }
    try {
      await (_initialisation ??= _initialiserAvec(_clientWeb));
    } catch (_) {
      // En cas d'échec, la prochaine tentative recommence au lieu de rejouer l'erreur.
      _initialisation = null;
      _clientWebInitialise = null;
      rethrow;
    }
  }

  Future<void> _initialiserAvec(String id) {
    _clientWebInitialise = id;
    return GoogleSignIn.instance.initialize(serverClientId: id);
  }

  void _memoriser(String jeton) {
    _jeton = jeton;
    _jetonValideJusqua = DateTime.now().add(_dureeJeton);
  }

  void _memoriserAgenda(String jeton) {
    _jetonAgenda = jeton;
    _jetonAgendaValideJusqua = DateTime.now().add(_dureeJeton);
  }

  ProfilGoogle _profil(GoogleSignInAccount compte) => ProfilGoogle(email: compte.email, nom: compte.displayName);

  @override
  Future<ProfilGoogle?> restaurer() async {
    if (!configure) return null;
    try {
      await _initialiser();
      final Future<GoogleSignInAccount?>? essai = GoogleSignIn.instance.attemptLightweightAuthentication();
      final GoogleSignInAccount? compte = essai == null ? null : await essai;
      if (compte == null) return null;
      // Le droit Drive doit déjà avoir été accordé : sinon il faut se reconnecter (sans fenêtre au lancement).
      final GoogleSignInClientAuthorization? droit = await compte.authorizationClient.authorizationForScopes(
        const <String>[porteeDrive],
      );
      if (droit == null) return null;
      _compte = compte;
      _memoriser(droit.accessToken);
      return _profil(compte);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ProfilGoogle> seConnecter() async {
    if (!configure) {
      throw const ErreurDrive('Google Drive n’est pas encore configuré dans cette version de l’application.');
    }
    try {
      await _initialiser();
      final GoogleSignInAccount compte = await GoogleSignIn.instance.authenticate();
      final GoogleSignInClientAuthorization droit = await compte.authorizationClient.authorizeScopes(
        const <String>[porteeDrive],
      );
      _compte = compte;
      _memoriser(droit.accessToken);
      return _profil(compte);
    } on GoogleSignInException catch (erreur) {
      throw _traduire(erreur);
    }
  }

  @override
  Future<void> seDeconnecter() async {
    _compte = null;
    invaliderJeton();
    if (!configure) return;
    try {
      await _initialiser();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Rien à faire de plus : le compte est déjà oublié par l'application.
    }
  }

  @override
  Future<String> jetonAcces() async {
    final String? jeton = _jeton;
    final DateTime? valable = _jetonValideJusqua;
    if (jeton != null && valable != null && valable.isAfter(DateTime.now())) return jeton;

    final GoogleSignInAccount? compte = _compte;
    if (compte == null) {
      throw const ErreurDrive('La connexion à Google est perdue. Reconnectez-vous.', autorisationAExpire: true);
    }
    try {
      final GoogleSignInClientAuthorization? droit = await compte.authorizationClient.authorizationForScopes(
        const <String>[porteeDrive],
      );
      if (droit == null) {
        throw const ErreurDrive('L’autorisation Google Drive a expiré. Reconnectez-vous.', autorisationAExpire: true);
      }
      _memoriser(droit.accessToken);
      return droit.accessToken;
    } on GoogleSignInException catch (erreur) {
      throw _traduire(erreur);
    }
  }

  @override
  void invaliderJeton() {
    _jeton = null;
    _jetonValideJusqua = null;
    _jetonAgenda = null;
    _jetonAgendaValideJusqua = null;
  }

  @override
  Future<bool> agendaAutorise() async {
    final GoogleSignInAccount? compte = _compte;
    if (compte == null) return false;
    try {
      final GoogleSignInClientAuthorization? droit = await compte.authorizationClient.authorizationForScopes(
        const <String>[porteeAgenda],
      );
      if (droit == null) return false;
      _memoriserAgenda(droit.accessToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> autoriserAgenda() async {
    final GoogleSignInAccount? compte = _compte;
    if (compte == null) {
      throw const ErreurDrive('Connectez-vous d’abord à Google (Réglages › Google Drive).', autorisationAExpire: true);
    }
    try {
      final GoogleSignInClientAuthorization droit = await compte.authorizationClient.authorizeScopes(
        const <String>[porteeAgenda],
      );
      _memoriserAgenda(droit.accessToken);
    } on GoogleSignInException catch (erreur) {
      throw _traduire(erreur);
    }
  }

  @override
  Future<String> jetonAgenda() async {
    final String? jeton = _jetonAgenda;
    final DateTime? valable = _jetonAgendaValideJusqua;
    if (jeton != null && valable != null && valable.isAfter(DateTime.now())) return jeton;

    final GoogleSignInAccount? compte = _compte;
    if (compte == null) {
      throw const ErreurDrive('La connexion à Google est perdue. Reconnectez-vous.', autorisationAExpire: true);
    }
    try {
      final GoogleSignInClientAuthorization? droit = await compte.authorizationClient.authorizationForScopes(
        const <String>[porteeAgenda],
      );
      if (droit == null) {
        throw const ErreurDrive(
          'Le droit « Google Agenda » n’est pas (ou plus) accordé. Autorisez-le de nouveau.',
          autorisationAExpire: true,
        );
      }
      _memoriserAgenda(droit.accessToken);
      return droit.accessToken;
    } on GoogleSignInException catch (erreur) {
      throw _traduire(erreur);
    }
  }

  ErreurDrive _traduire(GoogleSignInException erreur) {
    final String detail = erreur.description ?? erreur.code.name;
    switch (erreur.code.name) {
      case 'canceled':
        return const ErreurDrive('Connexion annulée.', annulee: true);
      case 'clientConfigurationError':
      case 'providerConfigurationError':
        return ErreurDrive(
          'La configuration Google de l’application est incorrecte (ID client Web, accès Android ou empreinte de la clé '
          'de signature). Détail : $detail',
        );
      case 'uiUnavailable':
        return const ErreurDrive('Impossible d’afficher la connexion Google : aucun compte Google sur ce téléphone ?');
      case 'interrupted':
        return const ErreurDrive('La connexion a été interrompue. Réessayez.');
      default:
        return ErreurDrive('Connexion à Google impossible : $detail', autorisationAExpire: true);
    }
  }
}
