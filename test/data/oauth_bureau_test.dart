import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/oauth_bureau.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _jwt(Map<String, Object?> contenu) {
  String b64(String texte) => base64Url.encode(utf8.encode(texte)).replaceAll('=', '');
  return '${b64('{"alg":"RS256"}')}.${b64(jsonEncode(contenu))}.signature';
}

http.Response _json(Map<String, Object?> corps, {int statut = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(corps)),
  statut,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _reponseConnexion({String portees = 'openid email profile $porteeDrive', bool avecActualisation = true}) =>
    <String, Object?>{
      'access_token': 'acces-1',
      'expires_in': 3599,
      if (avecActualisation) 'refresh_token': 'actualisation-1',
      'id_token': _jwt(<String, Object?>{'email': 'stef@exemple.fr', 'name': 'Stéphane'}),
      'scope': portees,
      'token_type': 'Bearer',
    };

/// Un « navigateur » de test : au lieu d'ouvrir une page, il fait ce que ferait Google (revenir sur l'adresse locale).
class _Navigateur {
  final List<Uri> ouvertes = <Uri>[];

  /// Ce que fait le navigateur quand l'application l'ouvre : par défaut, la personne accepte (retour avec le code).
  Future<void> Function(Uri adresse)? comportement;

  Future<void> ouvrir(Uri adresse) async {
    ouvertes.add(adresse);
    final Future<void> Function(Uri)? autre = comportement;
    if (autre != null) return autre(adresse);
    await retourner(adresse, <String, String>{'code': 'code-de-google'});
  }

  /// Visite l'adresse de retour avec [parametres] (plus l'état de la connexion si [avecEtat]).
  static Future<int> retourner(Uri adresse, Map<String, String> parametres, {bool avecEtat = true, String? etat}) async {
    final Uri redirection = Uri.parse(adresse.queryParameters['redirect_uri']!);
    final Uri visite = redirection.replace(
      queryParameters: <String, String>{...parametres, if (avecEtat) 'state': etat ?? adresse.queryParameters['state']!},
    );
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse reponse = await (await client.getUrl(visite)).close();
      await reponse.drain<void>();
      return reponse.statusCode;
    } finally {
      client.close(force: true);
    }
  }
}

void main() {
  group('PKCE et adresse de connexion', () {
    test('le défi PKCE suit l’exemple de la RFC 7636', () {
      expect(defiPkce('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('la chaîne aléatoire fait 64 caractères sûrs et change à chaque fois', () {
      final Random hasard = Random(1);
      final String a = chaineAleatoireSure(hasard);
      final String b = chaineAleatoireSure(hasard);
      expect(a, hasLength(64));
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{64}$')));
      expect(a, isNot(b));
    });

    test('l’adresse demande le seul droit Drive (drive.file), l’identité, une autorisation durable et PKCE', () {
      final Uri adresse = adresseDeConnexion(
        clientId: 'id-client',
        redirection: 'http://127.0.0.1:5000',
        defi: 'le-defi',
        etat: 'l-etat',
      );
      expect(adresse.origin, 'https://accounts.google.com');
      final Map<String, String> q = adresse.queryParameters;
      expect(q['client_id'], 'id-client');
      expect(q['redirect_uri'], 'http://127.0.0.1:5000');
      expect(q['response_type'], 'code');
      expect(q['code_challenge'], 'le-defi');
      expect(q['code_challenge_method'], 'S256');
      expect(q['state'], 'l-etat');
      expect(q['access_type'], 'offline');
      expect(q['prompt'], 'consent');
      final List<String> portees = q['scope']!.split(' ');
      expect(portees, containsAll(<String>['openid', 'email', 'profile', porteeDrive]));
      // Aucun autre droit Drive que drive.file.
      expect(portees.where((String p) => p.contains('drive')), <String>[porteeDrive]);
    });

    test('identiteDuJeton lit l’adresse e-mail et le nom, et reste vide si le jeton est absent ou illisible', () {
      final ({String email, String? nom}) identite = identiteDuJeton(_jwt(<String, Object?>{'email': 'a@b.fr', 'name': 'Stéphane'}));
      expect(identite.email, 'a@b.fr');
      expect(identite.nom, 'Stéphane');
      expect(identiteDuJeton(null).email, '');
      expect(identiteDuJeton('pas-un-jeton').email, '');
      expect(identiteDuJeton('a.%%%.c').email, '');
      expect(identiteDuJeton(_jwt(<String, Object?>{'sub': '1'})).nom, isNull);
    });
  });

  group('ClientOAuthBureau.autoriser', () {
    late _Navigateur navigateur;
    late List<http.Request> requetes;
    late http.Response Function(http.Request) reponseGoogle;

    ClientOAuthBureau client({Duration delaiAttente = const Duration(seconds: 10)}) => ClientOAuthBureau(
      clientHttp: MockClient((http.Request r) async {
        requetes.add(r);
        return reponseGoogle(r);
      }),
      ouvreur: navigateur.ouvrir,
      hasard: Random(7),
      delaiAttente: delaiAttente,
      horloge: () => DateTime(2026, 11, 20, 8),
    );

    setUp(() {
      navigateur = _Navigateur();
      requetes = <http.Request>[];
      reponseGoogle = (http.Request r) => _json(_reponseConnexion());
    });

    test('ouvre le navigateur, reçoit le code et l’échange contre les jetons (avec la preuve PKCE)', () async {
      final JetonsGoogle jetons = await client().autoriser(clientId: 'mon-id', codeSecret: 'GOCSPX-secret-123456');

      expect(jetons.jetonAcces, 'acces-1');
      expect(jetons.jetonActualisation, 'actualisation-1');
      expect(identiteDuJeton(jetons.jetonIdentite).email, 'stef@exemple.fr');
      // 3599 s moins une minute de marge.
      expect(jetons.expireLe, DateTime(2026, 11, 20, 8).add(const Duration(seconds: 3599 - 60)));

      expect(navigateur.ouvertes, hasLength(1));
      expect(requetes, hasLength(1));
      expect(requetes.single.url.toString(), adresseJetonGoogle);
      final Map<String, String> envoye = requetes.single.bodyFields;
      expect(envoye['grant_type'], 'authorization_code');
      expect(envoye['code'], 'code-de-google');
      expect(envoye['client_id'], 'mon-id');
      expect(envoye['client_secret'], 'GOCSPX-secret-123456');
      expect(envoye['redirect_uri'], navigateur.ouvertes.single.queryParameters['redirect_uri']);
      expect(envoye['redirect_uri'], startsWith('http://127.0.0.1:'));
      // Google a reçu le défi ; l'échange envoie la preuve qui lui correspond.
      expect(defiPkce(envoye['code_verifier']!), navigateur.ouvertes.single.queryParameters['code_challenge']);
    });

    test('une requête sans le bon état (ce n’est pas Google) est ignorée, puis le vrai retour est pris', () async {
      navigateur.comportement = (Uri adresse) async {
        expect(await _Navigateur.retourner(adresse, <String, String>{'code': 'pirate'}, etat: 'mauvais'), HttpStatus.notFound);
        expect(await _Navigateur.retourner(adresse, <String, String>{'code': 'pirate'}, avecEtat: false), HttpStatus.notFound);
        await _Navigateur.retourner(adresse, <String, String>{'code': 'vrai-code'});
      };
      await client().autoriser(clientId: 'id', codeSecret: 'secret-123456789');

      expect(requetes.single.bodyFields['code'], 'vrai-code');
    });

    test('la personne refuse : connexion annulée, sans rien demander à Google', () async {
      navigateur.comportement = (Uri adresse) => _Navigateur.retourner(adresse, <String, String>{'error': 'access_denied'});

      await expectLater(
        client().autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.annulee, 'annulee', isTrue)),
      );
      expect(requetes, isEmpty);
    });

    test('une autre erreur de Google est dite telle quelle', () async {
      navigateur.comportement = (Uri adresse) => _Navigateur.retourner(adresse, <String, String>{'error': 'invalid_scope'});

      await expectLater(
        client().autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('invalid_scope'))),
      );
    });

    test('le droit Drive décoché dans la fenêtre de Google : refusé avec une explication', () async {
      reponseGoogle = (http.Request r) => _json(_reponseConnexion(portees: 'openid email profile'));

      await expectLater(
        client().autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('droit d’accès à Google Drive'))),
      );
    });

    test('pas de jeton d’actualisation : refusé (la connexion ne durerait qu’une heure)', () async {
      reponseGoogle = (http.Request r) => _json(_reponseConnexion(avecActualisation: false));

      await expectLater(
        client().autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('autorisation durable'))),
      );
    });

    test('Google refuse l’ID ou le code secret : le message dit quoi vérifier', () async {
      reponseGoogle = (http.Request r) =>
          _json(<String, Object?>{'error': 'invalid_client', 'error_description': 'Unauthorized'}, statut: 401);

      await expectLater(
        client().autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('application de bureau'))),
      );
    });

    test('Internet absent pendant l’échange : message clair, ce n’est pas une autorisation expirée', () async {
      final ClientOAuthBureau sansReseau = ClientOAuthBureau(
        clientHttp: MockClient((http.Request r) async => throw const SocketException('pas de réseau')),
        ouvreur: navigateur.ouvrir,
        hasard: Random(7),
      );

      await expectLater(
        sansReseau.autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(
          isA<ErreurDrive>()
              .having((ErreurDrive e) => e.message, 'message', contains('injoignable'))
              .having((ErreurDrive e) => e.autorisationAExpire, 'expire', isFalse),
        ),
      );
    });

    test('la personne ne termine pas : au bout du délai, la connexion échoue proprement', () async {
      navigateur.comportement = (Uri adresse) async {};

      await expectLater(
        client(delaiAttente: const Duration(milliseconds: 150)).autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('temps imparti'))),
      );
      expect(requetes, isEmpty);
    });

    test('le navigateur ne s’ouvre pas : message clair, et rien ne reste en attente', () async {
      navigateur.comportement = (Uri adresse) async => throw const ProcessException('rundll32', <String>[]);

      await expectLater(
        client(delaiAttente: const Duration(milliseconds: 150)).autoriser(clientId: 'id', codeSecret: 'secret-123456789'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('navigateur'))),
      );
      // Laisse passer le délai d'attente : aucune erreur ne doit remonter toute seule.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    test('relancer la connexion abandonne la précédente', () async {
      final Completer<void> premiereOuverte = Completer<void>();
      navigateur.comportement = (Uri adresse) async {
        if (!premiereOuverte.isCompleted) {
          premiereOuverte.complete();
          return; // La première fenêtre reste sans réponse.
        }
        await _Navigateur.retourner(adresse, <String, String>{'code': 'code-de-la-seconde'});
      };
      final ClientOAuthBureau oauth = client();

      final Future<JetonsGoogle> premiere = oauth.autoriser(clientId: 'id', codeSecret: 'secret-123456789');
      final Future<ErreurDrive?> echecPremiere = premiere.then<ErreurDrive?>((_) => null, onError: (Object e) => e as ErreurDrive);
      await premiereOuverte.future;
      final JetonsGoogle seconde = await oauth.autoriser(clientId: 'id', codeSecret: 'secret-123456789');

      expect(seconde.jetonAcces, 'acces-1');
      expect((await echecPremiere)?.annulee, isTrue);
      expect(requetes.single.bodyFields['code'], 'code-de-la-seconde');
    });

    test('annulerConnexionEnCours arrête l’attente', () async {
      final Completer<void> ouverte = Completer<void>();
      navigateur.comportement = (Uri adresse) async => ouverte.complete();
      final ClientOAuthBureau oauth = client();

      final Future<JetonsGoogle> attente = oauth.autoriser(clientId: 'id', codeSecret: 'secret-123456789');
      final Future<ErreurDrive?> echec = attente.then<ErreurDrive?>((_) => null, onError: (Object e) => e as ErreurDrive);
      await ouverte.future;
      oauth.annulerConnexionEnCours();

      expect((await echec)?.annulee, isTrue);
    });
  });

  group('ClientOAuthBureau.actualiser et revoquer', () {
    late List<http.Request> requetes;

    ClientOAuthBureau client(http.Response Function(http.Request) reponse) => ClientOAuthBureau(
      clientHttp: MockClient((http.Request r) async {
        requetes.add(r);
        return reponse(r);
      }),
      horloge: () => DateTime(2026, 11, 20, 8),
    );

    setUp(() => requetes = <http.Request>[]);

    test('renouvelle le jeton d’accès et garde le jeton d’actualisation', () async {
      final ClientOAuthBureau oauth = client(
        (http.Request r) => _json(<String, Object?>{'access_token': 'acces-2', 'expires_in': 3600, 'scope': porteeDrive}),
      );

      final JetonsGoogle jetons = await oauth.actualiser(
        clientId: 'mon-id',
        codeSecret: 'secret-123456789',
        jetonActualisation: 'actualisation-1',
      );

      expect(jetons.jetonAcces, 'acces-2');
      expect(jetons.jetonActualisation, 'actualisation-1');
      final Map<String, String> envoye = requetes.single.bodyFields;
      expect(envoye['grant_type'], 'refresh_token');
      expect(envoye['refresh_token'], 'actualisation-1');
      expect(envoye['client_id'], 'mon-id');
      expect(envoye['client_secret'], 'secret-123456789');
    });

    test('autorisation retirée ou expirée (invalid_grant) : il faut se reconnecter', () async {
      final ClientOAuthBureau oauth = client(
        (http.Request r) => _json(<String, Object?>{'error': 'invalid_grant', 'error_description': 'Token has been expired or revoked.'}, statut: 400),
      );

      await expectLater(
        oauth.actualiser(clientId: 'id', codeSecret: 'secret-123456789', jetonActualisation: 'x'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'expire', isTrue)),
      );
    });

    test('Google ne répond pas : ce n’est pas une autorisation expirée, on pourra réessayer', () async {
      final ClientOAuthBureau oauth = ClientOAuthBureau(
        clientHttp: MockClient((http.Request r) async => throw TimeoutException('trop long')),
      );

      await expectLater(
        oauth.actualiser(clientId: 'id', codeSecret: 'secret-123456789', jetonActualisation: 'x'),
        throwsA(
          isA<ErreurDrive>()
              .having((ErreurDrive e) => e.message, 'message', contains('ne répond pas'))
              .having((ErreurDrive e) => e.autorisationAExpire, 'expire', isFalse),
        ),
      );
    });

    test('une réponse sans jeton d’accès est refusée', () async {
      final ClientOAuthBureau oauth = client((http.Request r) => _json(<String, Object?>{'expires_in': 3600}));

      await expectLater(
        oauth.actualiser(clientId: 'id', codeSecret: 'secret-123456789', jetonActualisation: 'x'),
        throwsA(isA<ErreurDrive>()),
      );
    });

    test('revoquer demande à Google d’oublier le jeton, et ne lève jamais d’erreur', () async {
      await client((http.Request r) => http.Response('', 200)).revoquer('actualisation-1');
      expect(requetes.single.url.toString(), adresseRevocationGoogle);
      expect(requetes.single.bodyFields['token'], 'actualisation-1');

      final ClientOAuthBureau enPanne = ClientOAuthBureau(
        clientHttp: MockClient((http.Request r) async => throw const SocketException('pas de réseau')),
      );
      await enPanne.revoquer('x');
    });
  });
}
