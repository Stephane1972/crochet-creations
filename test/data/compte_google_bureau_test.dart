import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/compte_google_bureau.dart';
import 'package:crochet_creations/data/drive/oauth_bureau.dart';
import 'package:crochet_creations/data/drive/stockage_google_bureau.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/id_client_google.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _id = '123456789012-abcdefghijklmnopqrstuvwxyz012345$suffixeIdClientGoogle';
const String _secret = '${debutCodeSecretGoogle}AbCdEfGhIjKlMnOpQrStUvWxYz12';

String _jwt(Map<String, Object?> contenu) {
  String b64(String texte) => base64Url.encode(utf8.encode(texte)).replaceAll('=', '');
  return '${b64('{"alg":"RS256"}')}.${b64(jsonEncode(contenu))}.signature';
}

http.Response _json(Map<String, Object?> corps, {int statut = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(corps)),
  statut,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// Tout ce qu'il faut pour essayer un [CompteGoogleBureau] sans réseau ni navigateur : un faux Google (jetons), un faux
/// navigateur (la personne accepte) et une horloge qu'on avance à la main.
class _Banc {
  _Banc(this.dossier) : stockage = StockageGoogleBureau(File('${dossier.path}${Platform.pathSeparator}google_bureau.json'));

  final Directory dossier;
  final StockageGoogleBureau stockage;

  DateTime maintenant = DateTime(2026, 11, 20, 8);
  final List<http.Request> requetes = <http.Request>[];
  int renouvellements = 0;
  int numeroJeton = 0;

  /// Ce que Google répond à un renouvellement (par défaut : un nouveau jeton d'accès).
  http.Response Function(http.Request)? reponseRenouvellement;

  http.Response _repondre(http.Request r) {
    requetes.add(r);
    if (r.url.toString() == adresseRevocationGoogle) return http.Response('', 200);
    final String type = r.bodyFields['grant_type'] ?? '';
    if (type == 'authorization_code') {
      return _json(<String, Object?>{
        'access_token': 'acces-0',
        'expires_in': 3600,
        'refresh_token': 'actualisation-1',
        'id_token': _jwt(<String, Object?>{'email': 'stef@exemple.fr', 'name': 'Stéphane'}),
        'scope': 'openid email profile $porteeDrive',
      });
    }
    renouvellements++;
    final http.Response Function(http.Request)? autre = reponseRenouvellement;
    if (autre != null) return autre(r);
    numeroJeton++;
    return _json(<String, Object?>{'access_token': 'acces-$numeroJeton', 'expires_in': 3600, 'scope': porteeDrive});
  }

  Future<void> _navigateur(Uri adresse) async {
    final Uri redirection = Uri.parse(adresse.queryParameters['redirect_uri']!);
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse reponse = await (await client.getUrl(
        redirection.replace(queryParameters: <String, String>{'code': 'le-code', 'state': adresse.queryParameters['state']!}),
      )).close();
      await reponse.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  Future<CompteGoogleBureau> compte() async => CompteGoogleBureau(
    stockage: stockage,
    reglages: await stockage.lire(),
    oauth: ClientOAuthBureau(
      clientHttp: MockClient((http.Request r) async => _repondre(r)),
      ouvreur: _navigateur,
      hasard: Random(3),
      horloge: () => maintenant,
    ),
    horloge: () => maintenant,
  );

  Future<CompteGoogleBureau> compteConnecte() async {
    final CompteGoogleBureau compte = await this.compte();
    await compte.enregistrerClientWeb(_id);
    await compte.enregistrerCodeSecret(_secret);
    await compte.seConnecter();
    return compte;
  }
}

void main() {
  late Directory dossier;
  late _Banc banc;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('compte_bureau_test');
    banc = _Banc(dossier);
  });

  tearDown(() => dossier.deleteSync(recursive: true));

  group('configuration', () {
    test('au départ rien n’est configuré', () async {
      final CompteGoogleBureau compte = await banc.compte();

      expect(compte.configure, isFalse);
      expect(compte.clientWebEnregistre, isFalse);
      expect(compte.codeSecretEnregistre, isFalse);
      expect(compte.redemarrageNecessaire, isFalse);
      expect(await compte.restaurer(), isNull);
    });

    test('il faut l’ID ET le code secret ; ils sont vérifiés et gardés pour le prochain lancement', () async {
      final CompteGoogleBureau compte = await banc.compte();

      await compte.enregistrerClientWeb('  $_id \n');
      expect(compte.clientWeb, _id);
      expect(compte.configure, isFalse, reason: 'sans le code secret, la connexion est impossible');

      await compte.enregistrerCodeSecret(' "$_secret" ');
      expect(compte.configure, isTrue);

      final CompteGoogleBureau relance = await banc.compte();
      expect(relance.clientWeb, _id);
      expect(relance.codeSecretEnregistre, isTrue);
      expect(relance.configure, isTrue);
    });

    test('un ID ou un code secret impossible est refusé avec un message, sans rien enregistrer', () async {
      final CompteGoogleBureau compte = await banc.compte();

      await expectLater(
        compte.enregistrerClientWeb('bonjour'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('doit se terminer par'))),
      );
      await expectLater(
        compte.enregistrerClientWeb(_secret),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('code secret'))),
      );
      await expectLater(
        compte.enregistrerCodeSecret(_id),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('ID client, pas le code secret'))),
      );
      await expectLater(compte.enregistrerCodeSecret('court'), throwsA(isA<ErreurDrive>()));
      expect(compte.clientWebEnregistre, isFalse);
      expect(compte.codeSecretEnregistre, isFalse);
      expect(await banc.stockage.lire(), isA<ReglagesGoogleBureau>().having((ReglagesGoogleBureau r) => r.clientId, 'id', isEmpty));
    });

    test('se connecter sans accès configuré : message clair, sans toucher au navigateur', () async {
      final CompteGoogleBureau compte = await banc.compte();

      await expectLater(
        compte.seConnecter(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Renseignez d’abord'))),
      );
      expect(banc.requetes, isEmpty);
    });
  });

  group('connexion', () {
    test('se connecter donne le compte et garde l’autorisation pour le lancement suivant, sans nouvelle connexion', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();

      final CompteGoogleBureau relance = await banc.compte();
      final ProfilGoogle? profil = await relance.restaurer();
      expect(profil?.email, 'stef@exemple.fr');
      expect(profil?.nom, 'Stéphane');
      // Aucune demande à Google pour retrouver le compte : pas besoin d'Internet au lancement.
      final int avant = banc.requetes.length;
      await relance.restaurer();
      expect(banc.requetes.length, avant);
      expect(compte.configure, isTrue);
    });

    test('le jeton d’accès est gardé tant qu’il est valable, puis renouvelé sans redemander la connexion', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();

      expect(await compte.jetonAcces(), 'acces-0');
      expect(await compte.jetonAcces(), 'acces-0');
      expect(banc.renouvellements, 0);

      banc.maintenant = banc.maintenant.add(const Duration(hours: 2));
      expect(await compte.jetonAcces(), 'acces-1');
      expect(await compte.jetonAcces(), 'acces-1');
      expect(banc.renouvellements, 1);
    });

    test('deux demandes en même temps ne font qu’un seul renouvellement', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();
      banc.maintenant = banc.maintenant.add(const Duration(hours: 2));

      final List<String> jetons = await Future.wait(<Future<String>>[compte.jetonAcces(), compte.jetonAcces()]);

      expect(jetons, <String>['acces-1', 'acces-1']);
      expect(banc.renouvellements, 1);
    });

    test('invaliderJeton force un renouvellement', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();
      expect(await compte.jetonAcces(), 'acces-0');

      compte.invaliderJeton();

      expect(await compte.jetonAcces(), 'acces-1');
    });

    test('autorisation retirée chez Google : on le dit, et le compte repasse à « non connecté » (l’accès saisi reste)', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();
      banc.maintenant = banc.maintenant.add(const Duration(hours: 2));
      banc.reponseRenouvellement = (http.Request r) => _json(<String, Object?>{'error': 'invalid_grant'}, statut: 400);

      await expectLater(
        compte.jetonAcces(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'expire', isTrue)),
      );

      expect(await compte.restaurer(), isNull);
      expect((await banc.compte()).configure, isTrue, reason: 'l’ID et le code secret sont gardés pour se reconnecter');
      expect(await (await banc.compte()).restaurer(), isNull);
    });

    test('Internet coupé au renouvellement : l’erreur est passagère, l’autorisation est conservée', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();
      banc.maintenant = banc.maintenant.add(const Duration(hours: 2));
      banc.reponseRenouvellement = (http.Request r) => throw const SocketException('pas de réseau');

      await expectLater(compte.jetonAcces(), throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'expire', isFalse)));

      expect((await compte.restaurer())?.email, 'stef@exemple.fr');
    });

    test('sans autorisation, demander un jeton dit de se reconnecter', () async {
      final CompteGoogleBureau compte = await banc.compte();
      await compte.enregistrerClientWeb(_id);
      await compte.enregistrerCodeSecret(_secret);

      await expectLater(
        compte.jetonAcces(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'expire', isTrue)),
      );
    });
  });

  group('déconnexion et oubli', () {
    test('se déconnecter oublie l’autorisation, la fait retirer chez Google, et garde l’accès saisi', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();

      await compte.seDeconnecter();

      expect(await compte.restaurer(), isNull);
      expect(compte.configure, isTrue);
      final http.Request revocation = banc.requetes.last;
      expect(revocation.url.toString(), adresseRevocationGoogle);
      expect(revocation.bodyFields['token'], 'actualisation-1');
      expect(await (await banc.compte()).restaurer(), isNull);
      await expectLater(compte.jetonAcces(), throwsA(isA<ErreurDrive>()));
    });

    test('changer d’ID client oublie l’autorisation donnée à l’ancien', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();

      await compte.enregistrerClientWeb('987654321098-zyxwvutsrqponmlkjihgfedcba012345$suffixeIdClientGoogle');

      expect(await compte.restaurer(), isNull);
    });

    test('ré-enregistrer le même ID garde l’autorisation', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();

      await compte.enregistrerClientWeb(_id);

      expect((await compte.restaurer())?.email, 'stef@exemple.fr');
    });

    test('oublier l’accès efface tout (ID, code secret, autorisation) et le fichier', () async {
      final CompteGoogleBureau compte = await banc.compteConnecte();

      await compte.oublierClientWeb();

      expect(compte.configure, isFalse);
      expect(compte.clientWebEnregistre, isFalse);
      expect(compte.codeSecretEnregistre, isFalse);
      expect(await compte.restaurer(), isNull);
      expect(banc.stockage.fichier.existsSync(), isFalse);
    });
  });
}
