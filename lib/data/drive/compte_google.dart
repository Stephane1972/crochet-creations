import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants/google_config.dart';
import '../../domain/drive_envoi.dart';

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

/// [CompteGoogle] réel : `google_sign_in` (Android : Google Play Services).
class CompteGoogleReel implements CompteGoogle {
  CompteGoogleReel({String? clientWeb}) : _clientWeb = clientWeb ?? clientWebGoogle;

  final String _clientWeb;
  GoogleSignInAccount? _compte;
  Future<void>? _initialisation;
  String? _jeton;
  DateTime? _jetonValideJusqua;

  /// Durée pendant laquelle un jeton est réutilisé (il est valable environ une heure).
  static const Duration _dureeJeton = Duration(minutes: 30);

  @override
  bool get configure => _clientWeb.isNotEmpty;

  Future<void> _initialiser() async {
    try {
      await (_initialisation ??= GoogleSignIn.instance.initialize(serverClientId: _clientWeb));
    } catch (_) {
      // En cas d'échec, la prochaine tentative recommence au lieu de rejouer l'erreur.
      _initialisation = null;
      rethrow;
    }
  }

  void _memoriser(String jeton) {
    _jeton = jeton;
    _jetonValideJusqua = DateTime.now().add(_dureeJeton);
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
    _jeton = null;
    _jetonValideJusqua = null;
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
