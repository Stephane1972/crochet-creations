import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

import '../../domain/drive_envoi.dart';
import 'compte_google.dart';

/// Ouvre une adresse dans le navigateur de la personne (sous Windows : son navigateur habituel).
typedef OuvreurNavigateur = Future<void> Function(Uri adresse);

/// Où la personne se connecte et accorde le droit (page de Google, dans son navigateur).
const String adresseAutorisationGoogle = 'https://accounts.google.com/o/oauth2/v2/auth';

/// Où l'application échange le code reçu contre les jetons, et les renouvelle.
const String adresseJetonGoogle = 'https://oauth2.googleapis.com/token';

/// Où l'application dit à Google d'oublier une autorisation (à la déconnexion).
const String adresseRevocationGoogle = 'https://oauth2.googleapis.com/revoke';

/// Ce que l'application demande : le seul droit Drive (`drive.file`), plus l'identité (adresse e-mail et nom) pour afficher
/// « Connecté en tant que… ». Aucun autre droit Drive.
const List<String> porteesConnexionBureau = <String>['openid', 'email', 'profile', porteeDrive];

/// Ce que Google rend après une connexion ou un renouvellement.
class JetonsGoogle {
  const JetonsGoogle({required this.jetonAcces, required this.expireLe, this.jetonActualisation, this.jetonIdentite, this.portees});

  /// Le jeton qui autorise les appels à Drive (valable environ une heure).
  final String jetonAcces;

  /// Quand [jetonAcces] cesse d'être valable.
  final DateTime expireLe;

  /// Le jeton qui permet d'en obtenir un neuf sans redemander la connexion (donné à la connexion, pas au renouvellement).
  final String? jetonActualisation;

  /// L'identité (JWT) : adresse e-mail et nom de la personne.
  final String? jetonIdentite;

  /// Les droits accordés, séparés par des espaces.
  final String? portees;
}

/// L'adresse e-mail et le nom lus dans le jeton d'identité ; vides si le jeton est absent ou illisible. Ce jeton vient
/// directement de Google, par une connexion chiffrée : on n'en vérifie pas la signature, on n'y lit que l'affichage.
({String email, String? nom}) identiteDuJeton(String? jetonIdentite) {
  if (jetonIdentite == null) return (email: '', nom: null);
  try {
    final List<String> morceaux = jetonIdentite.split('.');
    if (morceaux.length < 2) return (email: '', nom: null);
    final Object? donnees = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(morceaux[1]))));
    if (donnees is! Map<String, Object?>) return (email: '', nom: null);
    final Object? email = donnees['email'];
    final Object? nom = donnees['name'];
    return (email: email is String ? email : '', nom: nom is String && nom.isNotEmpty ? nom : null);
  } on FormatException {
    return (email: '', nom: null);
  }
}

/// Une chaîne aléatoire sûre (lettres, chiffres, « - » et « _ ») de 64 caractères : la « preuve » PKCE et l'état de la connexion.
String chaineAleatoireSure(Random hasard) =>
    base64Url.encode(List<int>.generate(48, (_) => hasard.nextInt(256)));

/// Le « défi » PKCE d'une preuve : son empreinte SHA-256, en base 64 sans remplissage (RFC 7636).
String defiPkce(String preuve) => base64Url.encode(sha256.convert(ascii.encode(preuve)).bytes).replaceAll('=', '');

/// L'adresse de la page Google où la personne se connecte.
Uri adresseDeConnexion({
  required String clientId,
  required String redirection,
  required String defi,
  required String etat,
  List<String> portees = porteesConnexionBureau,
}) {
  return Uri.parse(adresseAutorisationGoogle).replace(
    queryParameters: <String, String>{
      'client_id': clientId,
      'redirect_uri': redirection,
      'response_type': 'code',
      'scope': portees.join(' '),
      'code_challenge': defi,
      'code_challenge_method': 'S256',
      'state': etat,
      // « offline » + « consent » : Google donne à chaque connexion un jeton d'actualisation, pour ne pas se reconnecter
      // toutes les heures.
      'access_type': 'offline',
      'prompt': 'consent',
    },
  );
}

/// La connexion à Google « application de bureau » : la personne se connecte dans son navigateur, et Google renvoie le résultat
/// vers une adresse de cet ordinateur (`http://127.0.0.1:<port>`) que l'application écoute pendant la connexion. C'est la méthode
/// que Google prévoit pour les applications installées (PKCE + adresse de retour locale).
///
/// Tout est injectable (connexion Internet, navigateur, hasard, horloge) pour être testé sans réseau.
class ClientOAuthBureau {
  ClientOAuthBureau({
    http.Client? clientHttp,
    OuvreurNavigateur? ouvreur,
    Random? hasard,
    DateTime Function()? horloge,
    this.delaiAttente = const Duration(minutes: 3),
    this.delaiReseau = const Duration(seconds: 30),
  }) : _http = clientHttp ?? _clientParDefaut(),
       _ouvreur = ouvreur ?? ouvrirDansLeNavigateur,
       _hasard = hasard ?? Random.secure(),
       _horloge = horloge ?? DateTime.now;

  static http.Client _clientParDefaut() => http.Client();

  final http.Client _http;
  final OuvreurNavigateur _ouvreur;
  final Random _hasard;
  final DateTime Function() _horloge;

  /// Combien de temps on attend que la personne termine dans son navigateur.
  final Duration delaiAttente;

  /// Délai maximal d'une réponse de Google.
  final Duration delaiReseau;

  HttpServer? _serveur;
  Completer<void>? _annulation;

  /// Abandonne la connexion en cours (s'il y en a une) : l'attente se termine par une [ErreurDrive] « annulée ».
  void annulerConnexionEnCours() {
    final Completer<void>? annulation = _annulation;
    if (annulation != null && !annulation.isCompleted) annulation.complete();
  }

  /// Ouvre le navigateur sur la page de Google, attend le retour, puis échange le code contre les jetons.
  ///
  /// Lève une [ErreurDrive] : `annulee` si la personne refuse ou ferme (ou relance la connexion), un message lisible sinon.
  ///
  /// [portees] : les droits demandés (par défaut [porteesConnexionBureau] : Drive seul). Google laisse la personne décocher
  /// chaque droit : à l'appelant de lire [JetonsGoogle.portees] pour savoir ce qui a été accordé (Drive est vérifié ici).
  Future<JetonsGoogle> autoriser({
    required String clientId,
    required String codeSecret,
    List<String> portees = porteesConnexionBureau,
  }) async {
    annulerConnexionEnCours();
    final Completer<void> annulation = Completer<void>();
    _annulation = annulation;

    final String preuve = chaineAleatoireSure(_hasard);
    final String etat = chaineAleatoireSure(_hasard);
    final HttpServer serveur;
    try {
      serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException {
      throw const ErreurDrive(
        'Impossible de préparer la connexion sur cet ordinateur (un pare-feu ou un antivirus bloque peut-être l’application).',
      );
    }
    _serveur = serveur;
    final String redirection = 'http://127.0.0.1:${serveur.port}';
    try {
      final Future<String> retour = _attendreRetour(serveur, etat, annulation.future);
      // Si le navigateur ne s'ouvre pas, ce retour n'est jamais attendu : son échec ne doit alors pas remonter tout seul.
      retour.ignore();
      try {
        await _ouvreur(
          adresseDeConnexion(clientId: clientId, redirection: redirection, defi: defiPkce(preuve), etat: etat, portees: portees),
        );
      } catch (_) {
        annulation.complete();
        throw const ErreurDrive('Impossible d’ouvrir votre navigateur. Ouvrez-le, puis réessayez.');
      }
      final String code = await retour;
      return await _echangerCode(clientId: clientId, codeSecret: codeSecret, code: code, preuve: preuve, redirection: redirection);
    } finally {
      if (identical(_serveur, serveur)) _serveur = null;
      if (identical(_annulation, annulation)) _annulation = null;
      // Rien ne doit rester à l'écoute (ni minuteur) une fois la connexion finie, réussie ou non.
      if (!annulation.isCompleted) annulation.complete();
      await serveur.close(force: true);
    }
  }

  /// Attend la requête de Google sur l'adresse locale ; rend le code reçu.
  Future<String> _attendreRetour(HttpServer serveur, String etatAttendu, Future<void> annulation) {
    final Completer<String> fini = Completer<String>();
    final StreamSubscription<HttpRequest> ecoute = serveur.listen((HttpRequest requete) async {
      final Map<String, String> parametres = requete.uri.queryParameters;
      final bool estLeRetour = parametres.containsKey('code') || parametres.containsKey('error');
      // Toute autre requête (icône de l'onglet, page ouverte au hasard) : ignorée. Un état différent aussi : ce n'est pas Google.
      if (!estLeRetour || parametres['state'] != etatAttendu) {
        requete.response.statusCode = HttpStatus.notFound;
        await requete.response.close();
        return;
      }
      final String? erreur = parametres['error'];
      final String? code = parametres['code'];
      requete.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..write(_pageDeRetour(reussi: erreur == null && code != null));
      await requete.response.close();
      if (fini.isCompleted) return;
      if (erreur != null) {
        fini.completeError(
          erreur == 'access_denied'
              ? const ErreurDrive('Connexion annulée.', annulee: true)
              : ErreurDrive('Google a refusé la connexion ($erreur).'),
        );
      } else if (code != null) {
        fini.complete(code);
      }
    });
    final Timer delai = Timer(delaiAttente, () {
      if (!fini.isCompleted) {
        fini.completeError(const ErreurDrive('La connexion n’a pas abouti dans le temps imparti. Réessayez.'));
      }
    });
    annulation.then((_) {
      if (!fini.isCompleted) fini.completeError(const ErreurDrive('Connexion annulée.', annulee: true));
    });
    return fini.future.whenComplete(() {
      delai.cancel();
      ecoute.cancel();
    });
  }

  static String _pageDeRetour({required bool reussi}) {
    final String titre = reussi ? 'Connexion réussie' : 'Connexion non terminée';
    final String texte = reussi
        ? 'Vous pouvez fermer cet onglet et revenir à l’application « Un p’tit crochet dans les stocks ».'
        : 'La connexion n’a pas été terminée. Vous pouvez fermer cet onglet et réessayer depuis l’application.';
    return '<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>$titre</title>'
        '<meta name="viewport" content="width=device-width,initial-scale=1"></head>'
        '<body style="font-family:sans-serif;max-width:32em;margin:3em auto;padding:0 1em">'
        '<h1>$titre</h1><p>$texte</p></body></html>';
  }

  Future<JetonsGoogle> _echangerCode({
    required String clientId,
    required String codeSecret,
    required String code,
    required String preuve,
    required String redirection,
  }) async {
    final JetonsGoogle jetons = await _demanderJetons(<String, String>{
      'code': code,
      'client_id': clientId,
      'client_secret': codeSecret,
      'redirect_uri': redirection,
      'grant_type': 'authorization_code',
      'code_verifier': preuve,
    });
    final String portees = jetons.portees ?? '';
    // Google laisse décocher chaque droit : sans le droit Drive, la connexion ne servirait à rien.
    if (!portees.split(' ').contains(porteeDrive)) {
      throw const ErreurDrive(
        'Le droit d’accès à Google Drive n’a pas été accordé. Recommencez la connexion et laissez la case Drive cochée.',
      );
    }
    if (jetons.jetonActualisation == null) {
      throw const ErreurDrive('Google n’a pas fourni d’autorisation durable. Recommencez la connexion.');
    }
    return jetons;
  }

  /// Obtient un nouveau jeton d'accès avec le jeton d'actualisation. Lève une [ErreurDrive] (`autorisationAExpire`) si Google
  /// refuse (autorisation retirée ou expirée).
  Future<JetonsGoogle> actualiser({
    required String clientId,
    required String codeSecret,
    required String jetonActualisation,
  }) async {
    final JetonsGoogle jetons = await _demanderJetons(<String, String>{
      'client_id': clientId,
      'client_secret': codeSecret,
      'refresh_token': jetonActualisation,
      'grant_type': 'refresh_token',
    });
    // Au renouvellement, Google ne rend pas le jeton d'actualisation : on garde celui qu'on a.
    return JetonsGoogle(
      jetonAcces: jetons.jetonAcces,
      expireLe: jetons.expireLe,
      jetonActualisation: jetons.jetonActualisation ?? jetonActualisation,
      jetonIdentite: jetons.jetonIdentite,
      portees: jetons.portees,
    );
  }

  /// Dit à Google d'oublier cette autorisation. Au mieux : une panne de réseau n'empêche pas de se déconnecter.
  Future<void> revoquer(String jeton) async {
    try {
      await _http.post(Uri.parse(adresseRevocationGoogle), body: <String, String>{'token': jeton}).timeout(delaiReseau);
    } catch (_) {
      // Rien de plus à faire : l'application a déjà oublié le jeton.
    }
  }

  Future<JetonsGoogle> _demanderJetons(Map<String, String> formulaire) async {
    final http.Response reponse;
    try {
      reponse = await _http.post(Uri.parse(adresseJetonGoogle), body: formulaire).timeout(delaiReseau);
    } on TimeoutException {
      throw const ErreurDrive('Google ne répond pas. Vérifiez la connexion Internet, puis réessayez.');
    } on SocketException {
      throw const ErreurDrive('Google est injoignable. Vérifiez la connexion Internet, puis réessayez.');
    } on HandshakeException {
      throw const ErreurDrive('La connexion sécurisée à Google a échoué (l’heure de l’ordinateur est-elle juste ?).');
    } on http.ClientException {
      throw const ErreurDrive('Google est injoignable. Vérifiez la connexion Internet, puis réessayez.');
    }

    Map<String, Object?> corps = const <String, Object?>{};
    try {
      final Object? lu = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (lu is Map<String, Object?>) corps = lu;
    } on FormatException {
      // Corps illisible : on s'en tient au code de réponse.
    }

    if (reponse.statusCode != 200) throw _erreurDeGoogle(corps, reponse.statusCode);

    final Object? acces = corps['access_token'];
    if (acces is! String || acces.isEmpty) {
      throw const ErreurDrive('Réponse inattendue de Google : réessayez dans un instant.');
    }
    final Object? duree = corps['expires_in'];
    final int secondes = duree is num ? duree.toInt() : 3600;
    final Object? actualisation = corps['refresh_token'];
    final Object? identite = corps['id_token'];
    final Object? portees = corps['scope'];
    return JetonsGoogle(
      jetonAcces: acces,
      // Une minute de marge : le jeton est renouvelé avant que Drive ne le refuse.
      expireLe: _horloge().add(Duration(seconds: secondes)).subtract(const Duration(minutes: 1)),
      jetonActualisation: actualisation is String && actualisation.isNotEmpty ? actualisation : null,
      jetonIdentite: identite is String ? identite : null,
      portees: portees is String ? portees : null,
    );
  }

  ErreurDrive _erreurDeGoogle(Map<String, Object?> corps, int code) {
    final Object? erreur = corps['error'];
    final Object? detail = corps['error_description'];
    final String nom = erreur is String ? erreur : 'HTTP $code';
    switch (nom) {
      case 'invalid_grant':
        return const ErreurDrive(
          'L’autorisation Google a expiré ou a été retirée. Reconnectez-vous.',
          autorisationAExpire: true,
        );
      case 'invalid_client':
      case 'unauthorized_client':
        return const ErreurDrive(
          'Google refuse l’ID client ou le code secret. Vérifiez qu’ils viennent du même accès de type « application de '
          'bureau » dans la console Google Cloud.',
        );
      case 'invalid_request':
      case 'redirect_uri_mismatch':
        return ErreurDrive('Google refuse la demande de connexion (${detail is String ? detail : nom}). L’accès doit être de type « application de bureau ».');
      default:
        return ErreurDrive('Connexion à Google impossible (${detail is String ? detail : nom}).');
    }
  }
}

/// Ouvre [adresse] dans le navigateur habituel de Windows.
Future<void> ouvrirDansLeNavigateur(Uri adresse) async {
  if (!Platform.isWindows) throw UnsupportedError('Ouverture du navigateur : Windows seulement.');
  // `rundll32 url.dll,FileProtocolHandler` : l'adresse est transmise telle quelle (les « & » ne posent pas de problème).
  await Process.start('rundll32', <String>['url.dll,FileProtocolHandler', adresse.toString()], mode: ProcessStartMode.detached);
}
