import 'dart:async';
import 'dart:io';

import '../../domain/id_client_google.dart';
import 'compte_google.dart';
import 'oauth_bureau.dart';
import 'stockage_google_bureau.dart';

/// Le compte Google sous Windows : la connexion « application de bureau » (voir [ClientOAuthBureau]).
///
/// La personne crée un accès de type « application de bureau » dans son projet Google Cloud (gratuit) et colle son **ID client**
/// et son **code secret** dans l'écran Google Drive. Elle se connecte ensuite dans son navigateur ; l'application garde
/// l'autorisation durable dans un petit fichier du dossier de données de l'utilisateur ([StockageGoogleBureau]) pour ne pas
/// redemander la connexion à chaque lancement. Le seul droit Drive demandé est `drive.file` : l'application ne voit que les
/// fichiers qu'elle a elle-même mis sur Drive.
class CompteGoogleBureau implements CompteGoogle, CompteAvecCodeSecret {
  CompteGoogleBureau({
    required StockageGoogleBureau stockage,
    ReglagesGoogleBureau reglages = const ReglagesGoogleBureau(),
    ClientOAuthBureau? oauth,
    DateTime Function()? horloge,
  }) : _stockage = stockage,
       _reglages = reglages,
       _oauth = oauth ?? ClientOAuthBureau(),
       _horloge = horloge ?? DateTime.now;

  final StockageGoogleBureau _stockage;
  final ClientOAuthBureau _oauth;
  final DateTime Function() _horloge;
  ReglagesGoogleBureau _reglages;

  String? _jeton;
  DateTime? _jetonExpireLe;
  Future<String>? _actualisation;

  @override
  bool get configure => _reglages.clientId.isNotEmpty && _reglages.codeSecret.isNotEmpty;

  @override
  String get clientWeb => _reglages.clientId;

  @override
  bool get clientWebEnregistre => _reglages.clientId.isNotEmpty;

  @override
  bool get codeSecretEnregistre => _reglages.codeSecret.isNotEmpty;

  /// Google se configure ici à chaque connexion : aucun redémarrage n'est jamais nécessaire.
  @override
  bool get redemarrageNecessaire => false;

  Future<void> _ecrire(ReglagesGoogleBureau reglages) async {
    try {
      await _stockage.ecrire(reglages);
    } on FileSystemException {
      throw const ErreurDrive('Impossible d’enregistrer sur cet ordinateur : y a-t-il encore de la place ?');
    }
    _reglages = reglages;
  }

  @override
  Future<void> enregistrerClientWeb(String saisie) async {
    final String id = nettoyerIdClientWeb(saisie);
    final String? probleme = erreurIdClientWeb(id, nom: 'ID client');
    if (probleme != null) throw ErreurDrive(probleme);
    // Un autre accès : l'autorisation donnée à l'ancien ne vaut plus rien.
    final bool change = id != _reglages.clientId;
    await _ecrire(_reglages.copier(clientId: id, oublierJeton: change));
    if (change) invaliderJeton();
  }

  @override
  Future<void> enregistrerCodeSecret(String saisie) async {
    final String code = nettoyerCodeSecretGoogle(saisie);
    final String? probleme = erreurCodeSecretGoogle(code);
    if (probleme != null) throw ErreurDrive(probleme);
    await _ecrire(_reglages.copier(codeSecret: code));
    invaliderJeton();
  }

  @override
  Future<void> oublierClientWeb() async {
    final String? jeton = _reglages.jetonActualisation;
    await _stockage.effacer();
    _reglages = const ReglagesGoogleBureau();
    invaliderJeton();
    if (jeton != null) unawaited(_oauth.revoquer(jeton));
  }

  ProfilGoogle _profil() =>
      ProfilGoogle(email: _reglages.email.isEmpty ? 'Compte Google' : _reglages.email, nom: _reglages.nom);

  @override
  Future<ProfilGoogle?> restaurer() async {
    if (!configure || _reglages.jetonActualisation == null) return null;
    return _profil();
  }

  @override
  Future<ProfilGoogle> seConnecter() async {
    if (!configure) {
      throw const ErreurDrive('Renseignez d’abord l’ID client et le code secret de l’accès « application de bureau ».');
    }
    final JetonsGoogle jetons = await _oauth.autoriser(clientId: _reglages.clientId, codeSecret: _reglages.codeSecret);
    final ({String email, String? nom}) identite = identiteDuJeton(jetons.jetonIdentite);
    await _ecrire(
      _reglages.copier(jetonActualisation: jetons.jetonActualisation, email: identite.email, nom: identite.nom),
    );
    _memoriser(jetons);
    return _profil();
  }

  @override
  Future<void> seDeconnecter() async {
    final String? jeton = _reglages.jetonActualisation;
    invaliderJeton();
    _reglages = _reglages.copier(oublierJeton: true);
    try {
      await _stockage.ecrire(_reglages);
    } on FileSystemException {
      // L'autorisation est déjà oubliée en mémoire ; au pire elle sera redemandée au prochain lancement.
    }
    if (jeton != null) await _oauth.revoquer(jeton);
  }

  @override
  Future<String> jetonAcces() {
    final String? jeton = _jeton;
    final DateTime? expire = _jetonExpireLe;
    if (jeton != null && expire != null && expire.isAfter(_horloge())) return Future<String>.value(jeton);
    // Deux appels en même temps ne demandent qu'un seul renouvellement.
    return _actualisation ??= _actualiser().whenComplete(() => _actualisation = null);
  }

  Future<String> _actualiser() async {
    final String? jetonActualisation = _reglages.jetonActualisation;
    if (!configure || jetonActualisation == null) {
      throw const ErreurDrive('La connexion à Google est perdue. Reconnectez-vous.', autorisationAExpire: true);
    }
    try {
      final JetonsGoogle jetons = await _oauth.actualiser(
        clientId: _reglages.clientId,
        codeSecret: _reglages.codeSecret,
        jetonActualisation: jetonActualisation,
      );
      _memoriser(jetons);
      return jetons.jetonAcces;
    } on ErreurDrive catch (erreur) {
      if (erreur.autorisationAExpire) {
        // Google a retiré l'autorisation : on l'oublie ici aussi, pour que l'écran repasse à « Non connecté ».
        _reglages = _reglages.copier(oublierJeton: true);
        invaliderJeton();
        try {
          await _stockage.ecrire(_reglages);
        } on FileSystemException {
          // Rien de plus à faire.
        }
      }
      rethrow;
    }
  }

  void _memoriser(JetonsGoogle jetons) {
    _jeton = jetons.jetonAcces;
    _jetonExpireLe = jetons.expireLe;
  }

  @override
  void invaliderJeton() {
    _jeton = null;
    _jetonExpireLe = null;
  }
}
