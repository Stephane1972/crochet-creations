import 'dart:convert';
import 'dart:io';

import 'package:crochet_creations/data/drive/client_drive.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_partage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'aide_drive.dart';

/// Une réponse que Google ferait à un test.
class _Cas {
  const _Cas(this.statut, this.corps, this.attendu);

  final int statut;
  final String corps;

  /// Un morceau du message lisible attendu.
  final String attendu;
}

String _erreurJson(int code, String message) => jsonEncode(<String, Object?>{
  'error': <String, Object?>{'code': code, 'message': message},
});

/// Une réponse JSON (ou HTML si [corps] en est, comme le ferait un serveur en panne).
http.Response _json(String corps, [int statut = 200]) => http.Response(
  corps,
  statut,
  headers: <String, String>{
    'content-type': corps.startsWith('<') ? 'text/html; charset=utf-8' : 'application/json; charset=utf-8',
  },
);

void main() {
  group('typeMimeDrive', () {
    test('donne le type d’après l’extension, sans tenir compte des majuscules', () {
      expect(typeMimeDrive('photo.jpg'), 'image/jpeg');
      expect(typeMimeDrive('PHOTO.JPEG'), 'image/jpeg');
      expect(typeMimeDrive('logo.png'), 'image/png');
      expect(typeMimeDrive('FACT-2026-0001.pdf'), 'application/pdf');
      expect(typeMimeDrive('video.mp4'), 'video/mp4');
      expect(typeMimeDrive('notes.docx'), contains('wordprocessingml'));
    });

    test('type générique si l’extension est inconnue ou absente', () {
      expect(typeMimeDrive('fichier.xyz'), 'application/octet-stream');
      expect(typeMimeDrive('sans_extension'), 'application/octet-stream');
      expect(typeMimeDrive('.cache'), 'application/octet-stream');
    });
  });

  group('protegerPourRequeteDrive', () {
    test('protège les apostrophes et les antislashs', () {
      expect(protegerPourRequeteDrive('simple'), 'simple');
      expect(protegerPourRequeteDrive("L'atelier"), r"L\'atelier");
      expect(protegerPourRequeteDrive(r'a\b'), r'a\\b');
      expect(protegerPourRequeteDrive(r"\'"), r"\\\'");
    });
  });

  group('ClientDriveGoogle', () {
    late FauxCompteGoogle compte;
    late List<http.Request> appels;
    late Directory temp;

    setUp(() {
      compte = FauxCompteGoogle();
      appels = <http.Request>[];
      temp = Directory.systemTemp.createTempSync('crochet_client_drive_');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    /// Un client dont Google répond avec [repondre] ; les requêtes reçues sont gardées dans [appels].
    ClientDriveGoogle creer(Future<http.Response> Function(http.Request requete) repondre) {
      return ClientDriveGoogle(
        compte,
        base: MockClient((http.Request requete) async {
          appels.add(requete);
          return repondre(requete);
        }),
      );
    }

    group('dossiers', () {
      test('trouverDossier : retrouve le dossier, avec le jeton du compte et une requête protégée', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"files":[{"id":"d42"}]}'));
        expect(await client.trouverDossier("L'atelier"), 'd42');

        expect(appels, hasLength(1));
        final http.Request requete = appels.single;
        expect(requete.method, 'GET');
        expect(requete.headers['authorization'], 'Bearer jeton-de-test');
        final String q = requete.url.queryParameters['q']!;
        expect(q, contains(r"name = 'L\'atelier'"));
        expect(q, contains("'root' in parents"));
        expect(q, contains('trashed = false'));
        expect(q, contains("mimeType = 'application/vnd.google-apps.folder'"));
      });

      test('trouverDossier : cherche dans le dossier parent donné', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"files":[]}'));
        expect(await client.trouverDossier('Factures', parentId: 'racine-1'), isNull);
        expect(appels.single.url.queryParameters['q'], contains("'racine-1' in parents"));
      });

      test('trouverDossier : null si Google ne répond aucun dossier', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{}'));
        expect(await client.trouverDossier('Devis'), isNull);
      });

      test('creerDossier : crée un dossier à la racine, avec le bon type', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"id":"nouveau-dossier"}'));
        expect(await client.creerDossier('Un p’tit crochet dans les stocks'), 'nouveau-dossier');

        final http.Request requete = appels.single;
        expect(requete.method, 'POST');
        final Map<String, dynamic> corps = jsonDecode(requete.body) as Map<String, dynamic>;
        expect(corps['name'], 'Un p’tit crochet dans les stocks');
        expect(corps['mimeType'], 'application/vnd.google-apps.folder');
        expect(corps['parents'], <String>['root']);
      });

      test('creerDossier : crée un sous-dossier dans le dossier parent', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"id":"d2"}'));
        await client.creerDossier('Photos des produits', parentId: 'racine-1');
        final Map<String, dynamic> corps = jsonDecode(appels.single.body) as Map<String, dynamic>;
        expect(corps['parents'], <String>['racine-1']);
      });

      test('creerDossier : erreur lisible si Google ne donne pas d’identifiant', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{}'));
        await expectLater(
          client.creerDossier('Devis'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('n’a pas créé le dossier'))),
        );
      });
    });

    group('lister', () {
      test('lit toutes les pages, avec la taille et l’empreinte notées sur Drive', () async {
        final ClientDriveGoogle client = creer((http.Request requete) async {
          if (requete.url.queryParameters['pageToken'] == 'page-2') {
            return _json('{"files":[{"id":"c","name":"c.jpg","size":"7"}]}');
          }
          return _json(
            jsonEncode(<String, Object?>{
              'nextPageToken': 'page-2',
              'files': <Object?>[
                <String, Object?>{
                  'id': 'a',
                  'name': 'a.pdf',
                  'size': '1234',
                  'appProperties': <String, String>{proprieteEmpreinteDrive: 'abc123'},
                },
                <String, Object?>{'id': 'b', 'name': 'b.jpg', 'size': '56'},
                // Sans identifiant ni nom : ignoré.
                <String, Object?>{'size': '9'},
              ],
            }),
          );
        });

        final List<FichierDistant> fichiers = await client.lister('d1');

        expect(appels, hasLength(2));
        expect(appels.first.url.queryParameters['q'], contains("'d1' in parents"));
        expect(appels.first.url.queryParameters['q'], contains('trashed = false'));
        expect(appels.first.url.queryParameters['q'], contains("mimeType != 'application/vnd.google-apps.folder'"));
        expect(appels.last.url.queryParameters['pageToken'], 'page-2');

        expect(fichiers.map((FichierDistant f) => f.nom), <String>['a.pdf', 'b.jpg', 'c.jpg']);
        expect(fichiers[0].id, 'a');
        expect(fichiers[0].octets, 1234);
        expect(fichiers[0].empreinte, 'abc123');
        expect(fichiers[1].octets, 56);
        expect(fichiers[1].empreinte, isNull);
        expect(fichiers[2].octets, 7);
      });

      test('dossier vide : liste vide', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{}'));
        expect(await client.lister('d1'), isEmpty);
      });
    });

    group('autorisation', () {
      test('un refus 401 est retenté une fois avec un jeton neuf', () async {
        int n = 0;
        final ClientDriveGoogle client = creer((_) async {
          n++;
          return n == 1 ? _json(_erreurJson(401, 'Invalid Credentials'), 401) : _json('{"files":[{"id":"d1"}]}');
        });

        expect(await client.trouverDossier('Factures'), 'd1');
        expect(appels, hasLength(2));
        expect(compte.jetonsInvalides, 1);
      });

      test('deux refus 401 de suite : la connexion est à refaire', () async {
        final ClientDriveGoogle client = creer((_) async => _json(_erreurJson(401, 'Invalid Credentials'), 401));

        await expectLater(
          client.trouverDossier('Factures'),
          throwsA(
            isA<ErreurDrive>()
                .having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)
                .having((ErreurDrive e) => e.message, 'message', contains('Reconnectez-vous')),
          ),
        );
        expect(appels, hasLength(2));
        expect(compte.jetonsInvalides, 1);
      });

      test('connexion perdue côté téléphone : l’erreur du compte sort telle quelle, sans appeler Google', () async {
        compte.erreurDeJeton = const ErreurDrive('La connexion à Google est perdue. Reconnectez-vous.', autorisationAExpire: true);
        final ClientDriveGoogle client = creer((_) async => _json('{}'));

        await expectLater(
          client.lister('d1'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
        );
        expect(appels, isEmpty);
      });
    });

    group('erreurs traduites', () {
      final List<_Cas> cas = <_Cas>[
        _Cas(403, _erreurJson(403, 'Rate Limit Exceeded'), 'ralentir'),
        _Cas(403, _erreurJson(403, 'The user\'s Drive storage quota has been exceeded.'), 'Drive est plein'),
        _Cas(403, _erreurJson(403, 'Access Not Configured. Drive API has not been used in project 1234.'), 'API Google Drive est activée'),
        _Cas(404, _erreurJson(404, 'File not found'), 'introuvable'),
        _Cas(429, _erreurJson(429, 'Too Many Requests'), 'ralentir'),
        _Cas(503, _erreurJson(503, 'Backend Error'), 'momentanément indisponible'),
        const _Cas(500, '<html>Erreur</html>', 'momentanément indisponible'),
        _Cas(400, _erreurJson(400, 'Invalid query'), 'erreur (400)'),
      ];

      for (final _Cas c in cas) {
        test('${c.statut} → « ${c.attendu} »', () async {
          final ClientDriveGoogle client = creer((_) async => _json(c.corps, c.statut));
          await expectLater(
            client.lister('d1'),
            throwsA(
              isA<ErreurDrive>()
                  .having((ErreurDrive e) => e.message, 'message', contains(c.attendu))
                  .having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isFalse),
            ),
          );
        });
      }

      test('pas d’Internet : message clair', () async {
        final ClientDriveGoogle client = creer((_) async => throw const SocketException('injoignable'));
        await expectLater(
          client.lister('d1'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Pas de connexion à Internet'))),
        );
      });

      test('erreur du client HTTP : message clair', () async {
        final ClientDriveGoogle client = creer((_) async => throw http.ClientException('coupé'));
        await expectLater(
          client.lister('d1'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Pas de connexion à Internet'))),
        );
      });
    });

    group('envoyer', () {
      /// Google, côté envoi « reprenable » : la requête de départ reçoit l'adresse d'envoi (en-tête `location`), puis
      /// l'envoi du contenu reçoit l'identifiant du fichier.
      Future<http.Response> repondreEnvoi(http.Request requete) async {
        if (requete.url.host == 'envoi.exemple.test') return _json('{"id":"fichier-1"}');
        return http.Response(
          '',
          200,
          headers: <String, String>{'location': 'https://envoi.exemple.test/session-1', 'content-type': 'application/json'},
        );
      }

      test('crée le fichier dans le dossier, avec l’empreinte, et suit la progression', () async {
        final File fichier = File('${temp.path}/FACT-2026-0001.pdf')..writeAsStringSync('%PDF contenu de la facture');
        final int longueur = fichier.lengthSync();
        final List<int> progres = <int>[];
        final ClientDriveGoogle client = creer(repondreEnvoi);

        await client.envoyer(
          fichier: fichier,
          nom: 'FACT-2026-0001.pdf',
          dossierId: 'dossier-factures',
          empreinte: 'empreinte-sha256',
          progression: progres.add,
        );

        final http.Request depart = appels.first;
        expect(depart.method, 'POST');
        expect(depart.url.queryParameters['uploadType'], 'resumable');
        expect(depart.headers['authorization'], 'Bearer jeton-de-test');
        final Map<String, dynamic> metadonnees = jsonDecode(depart.body) as Map<String, dynamic>;
        expect(metadonnees['name'], 'FACT-2026-0001.pdf');
        expect(metadonnees['parents'], <String>['dossier-factures']);
        expect((metadonnees['appProperties'] as Map<String, dynamic>)[proprieteEmpreinteDrive], 'empreinte-sha256');

        // Le contenu part vers l'adresse donnée par Google, et tout a été lu.
        expect(appels.any((http.Request r) => r.url.host == 'envoi.exemple.test'), isTrue);
        expect(progres, isNotEmpty);
        expect(progres.last, longueur);
      });

      test('sans empreinte : aucune propriété notée', () async {
        final File fichier = File('${temp.path}/photo.jpg')..writeAsStringSync('image');
        final ClientDriveGoogle client = creer(repondreEnvoi);

        await client.envoyer(fichier: fichier, nom: 'photo.jpg', dossierId: 'd1');

        final Map<String, dynamic> metadonnees = jsonDecode(appels.first.body) as Map<String, dynamic>;
        expect(metadonnees.containsKey('appProperties'), isFalse);
      });

      test('avec un fichier existant : remplace son contenu sans le recréer', () async {
        final File fichier = File('${temp.path}/FACT-2026-0001.pdf')..writeAsStringSync('%PDF nouvelle version');
        final ClientDriveGoogle client = creer(repondreEnvoi);

        await client.envoyer(
          fichier: fichier,
          nom: 'FACT-2026-0001.pdf',
          dossierId: 'dossier-factures',
          empreinte: 'nouvelle-empreinte',
          idExistant: 'fichier-existant',
        );

        final http.Request depart = appels.first;
        expect(depart.method, 'PATCH');
        expect(depart.url.path, contains('fichier-existant'));
        final Map<String, dynamic> metadonnees = jsonDecode(depart.body) as Map<String, dynamic>;
        expect(metadonnees.containsKey('parents'), isFalse); // le fichier ne change pas de dossier
        expect((metadonnees['appProperties'] as Map<String, dynamic>)[proprieteEmpreinteDrive], 'nouvelle-empreinte');
      });

      test('fichier introuvable sur le téléphone : message clair, rien n’est envoyé', () async {
        final ClientDriveGoogle client = creer(repondreEnvoi);
        await expectLater(
          client.envoyer(fichier: File('${temp.path}/absent.pdf'), nom: 'absent.pdf', dossierId: 'd1'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Fichier illisible'))),
        );
        expect(appels, isEmpty);
      });
    });

    group('telecharger', () {
      /// Le contenu d'un fichier, comme Drive le renvoie (type et longueur annoncés).
      Future<http.Response> contenu(String corps) async => http.Response(
        corps,
        200,
        headers: <String, String>{'content-type': 'application/octet-stream', 'content-length': '${utf8.encode(corps).length}'},
      );

      test('écrit le contenu dans le fichier demandé, avec le jeton du compte, et suit la progression', () async {
        final ClientDriveGoogle client = creer((_) => contenu('contenu du fichier'));
        final File destination = File('${temp.path}/sous-dossier/photo_1.jpg');
        final List<int> progres = <int>[];

        await client.telecharger(id: 'fichier-1', destination: destination, progression: progres.add);

        expect(destination.readAsStringSync(), 'contenu du fichier');
        expect(File('${destination.path}.tmp').existsSync(), isFalse);
        final http.Request requete = appels.single;
        expect(requete.method, 'GET');
        expect(requete.url.path, contains('fichier-1'));
        expect(requete.url.queryParameters['alt'], 'media'); // le contenu, pas les informations du fichier
        expect(requete.headers['authorization'], 'Bearer jeton-de-test');
        expect(progres, isNotEmpty);
        expect(progres.last, 'contenu du fichier'.length);
      });

      test('un fichier déjà là est remplacé', () async {
        final ClientDriveGoogle client = creer((_) => contenu('version de Drive'));
        final File destination = File('${temp.path}/FACT-2026-0001.pdf')..writeAsStringSync('ancienne version');

        await client.telecharger(id: 'fichier-1', destination: destination);

        expect(destination.readAsStringSync(), 'version de Drive');
        expect(File('${destination.path}.tmp').existsSync(), isFalse);
      });

      test('un téléchargement coupé : message clair, le fichier d’avant est gardé, rien ne reste', () async {
        final ClientDriveGoogle client = ClientDriveGoogle(
          compte,
          base: MockClient.streaming(
            (http.BaseRequest requete, http.ByteStream corps) async => http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode('0123456789')),
              200,
              headers: <String, String>{'content-type': 'application/octet-stream', 'content-length': '100'},
            ),
          ),
        );
        final File destination = File('${temp.path}/photo_1.jpg')..writeAsStringSync('ancienne version');

        await expectLater(
          client.telecharger(id: 'fichier-1', destination: destination),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('s’est arrêté avant la fin'))),
        );

        expect(destination.readAsStringSync(), 'ancienne version');
        expect(File('${destination.path}.tmp').existsSync(), isFalse);
      });

      test('fichier introuvable sur Drive : message clair, rien n’est écrit', () async {
        final ClientDriveGoogle client = creer((_) async => _json(_erreurJson(404, 'File not found'), 404));
        final File destination = File('${temp.path}/absent.jpg');

        await expectLater(
          client.telecharger(id: 'fichier-1', destination: destination),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('introuvable'))),
        );

        expect(destination.existsSync(), isFalse);
        expect(File('${destination.path}.tmp').existsSync(), isFalse);
      });

      test('pas d’Internet : message clair, rien n’est écrit', () async {
        final ClientDriveGoogle client = creer((_) async => throw const SocketException('injoignable'));
        final File destination = File('${temp.path}/photo_1.jpg');

        await expectLater(
          client.telecharger(id: 'fichier-1', destination: destination),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Pas de connexion à Internet'))),
        );

        expect(destination.existsSync(), isFalse);
        expect(File('${destination.path}.tmp').existsSync(), isFalse);
      });
    });

    group('partage', () {
      test('listerAcces : le propriétaire, les personnes, le lien public et les autres accès', () async {
        final ClientDriveGoogle client = creer(
          (_) async => _json(
            '{"permissions":['
            '{"id":"p0","type":"user","role":"owner","emailAddress":"stef@exemple.fr","displayName":"Stéphane"},'
            '{"id":"p1","type":"user","role":"reader","emailAddress":"marie@exemple.fr"},'
            '{"id":"p2","type":"anyone","role":"reader"},'
            '{"id":"p3","type":"user","role":"writer","emailAddress":"paul@exemple.fr"},'
            '{"id":"p4","type":"group","role":"reader","emailAddress":"equipe@exemple.fr"},'
            '{"type":"user","role":"reader"}'
            ']}',
          ),
        );

        final List<AccesDrive> acces = await client.listerAcces('f1');

        expect(acces.map((AccesDrive a) => a.id), <String>['p0', 'p1', 'p2', 'p3', 'p4']); // sans identifiant : ignoré
        expect(acces.map((AccesDrive a) => a.type), <TypeAcces>[
          TypeAcces.proprietaire,
          TypeAcces.personne,
          TypeAcces.lienPublic,
          TypeAcces.personne,
          TypeAcces.autre,
        ]);
        expect(acces[0].nom, 'Stéphane');
        expect(acces[1].email, 'marie@exemple.fr');
        expect(acces.map((AccesDrive a) => a.peutModifier), <bool>[false, false, false, true, false]);

        final http.Request requete = appels.single;
        expect(requete.method, 'GET');
        expect(requete.url.path, endsWith('/files/f1/permissions'));
        expect(requete.url.queryParameters['fields'], 'permissions(id,type,role,emailAddress,displayName)');
        expect(requete.headers['authorization'], 'Bearer jeton-de-test');
      });

      test('listerAcces : aucun accès si Google ne répond rien', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{}'));
        expect(await client.listerAcces('f1'), isEmpty);
      });

      test('partagerAvec : une personne, en lecture seule, prévenue par e-mail', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"id":"p9"}'));
        await client.partagerAvec(fichierId: 'f1', email: 'marie@exemple.fr');

        final http.Request requete = appels.single;
        expect(requete.method, 'POST');
        expect(requete.url.path, endsWith('/files/f1/permissions'));
        expect(requete.url.queryParameters['sendNotificationEmail'], 'true');
        final Map<String, dynamic> corps = jsonDecode(requete.body) as Map<String, dynamic>;
        expect(corps['type'], 'user');
        expect(corps['role'], 'reader');
        expect(corps['emailAddress'], 'marie@exemple.fr');
      });

      test('activerLienPublic : toute personne ayant le lien, en lecture seule, sans apparaître dans les recherches', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"id":"p9"}'));
        await client.activerLienPublic('f1');

        final http.Request requete = appels.single;
        expect(requete.method, 'POST');
        expect(requete.url.path, endsWith('/files/f1/permissions'));
        final Map<String, dynamic> corps = jsonDecode(requete.body) as Map<String, dynamic>;
        expect(corps['type'], 'anyone');
        expect(corps['role'], 'reader');
        expect(corps['allowFileDiscovery'], false);
        expect(corps.containsKey('emailAddress'), isFalse);
      });

      test('retirerAcces : retire seulement le droit, jamais le fichier', () async {
        final ClientDriveGoogle client = creer((_) async => http.Response('', 204));
        await client.retirerAcces(fichierId: 'f1', accesId: 'p1');

        final http.Request requete = appels.single;
        expect(requete.method, 'DELETE');
        expect(requete.url.path, endsWith('/files/f1/permissions/p1'));
      });

      test('aucun appel de l’application ne supprime un fichier : tout DELETE vise un droit', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"id":"p9"}'));
        await client.partagerAvec(fichierId: 'f1', email: 'marie@exemple.fr');
        await client.activerLienPublic('f1');
        await client.listerAcces('f1');
        expect(appels.where((http.Request r) => r.method == 'DELETE'), isEmpty);
      });

      test('lienDuFichier : l’adresse du fichier dans Drive', () async {
        final ClientDriveGoogle client = creer(
          (_) async => _json('{"webViewLink":"https://drive.google.com/file/d/f1/view"}'),
        );
        expect(await client.lienDuFichier('f1'), 'https://drive.google.com/file/d/f1/view');

        final http.Request requete = appels.single;
        expect(requete.method, 'GET');
        expect(requete.url.path, endsWith('/files/f1'));
        expect(requete.url.queryParameters['fields'], 'webViewLink');
      });

      test('lienDuFichier : null si Google ne donne pas d’adresse', () async {
        final ClientDriveGoogle client = creer((_) async => _json('{"id":"f1"}'));
        expect(await client.lienDuFichier('f1'), isNull);
      });

      test('lister demande aussi si le fichier est partagé, et son adresse', () async {
        final ClientDriveGoogle client = creer(
          (_) async => _json(
            '{"files":['
            '{"id":"a","name":"a.pdf","size":"3","shared":true,"webViewLink":"https://drive.google.com/file/d/a/view"},'
            '{"id":"b","name":"b.pdf","size":"4"}'
            ']}',
          ),
        );
        final List<FichierDistant> fichiers = await client.lister('d1');

        expect(appels.single.url.queryParameters['fields'], contains('shared'));
        expect(appels.single.url.queryParameters['fields'], contains('webViewLink'));
        expect(fichiers[0].partage, isTrue);
        expect(fichiers[0].lien, 'https://drive.google.com/file/d/a/view');
        expect(fichiers[1].partage, isFalse);
        expect(fichiers[1].lien, isNull);
      });

      test('une adresse que Google refuse (400) : message qui parle de l’adresse', () async {
        final ClientDriveGoogle client = creer((_) async => _json(_erreurJson(400, 'Invalid sharing request.'), 400));
        await expectLater(
          client.partagerAvec(fichierId: 'f1', email: 'inconnue@exemple.fr'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('n’a pas accepté de partager'))),
        );
      });

      test('droits insuffisants (403) : message qui parle du partage, pas de l’API', () async {
        final ClientDriveGoogle client = creer(
          (_) async => _json(_erreurJson(403, 'The user does not have sufficient permissions for this file.'), 403),
        );
        await expectLater(
          client.activerLienPublic('f1'),
          throwsA(
            isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', allOf(contains('changer le partage'), isNot(contains('API')))),
          ),
        );
      });

      test('connexion expirée (401) pendant un partage : la connexion est à refaire', () async {
        final ClientDriveGoogle client = creer((_) async => _json(_erreurJson(401, 'Invalid Credentials'), 401));
        await expectLater(
          client.listerAcces('f1'),
          throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
        );
      });
    });
  });

  group('CompteGoogleReel sans ID client Web', () {
    test('n’est pas configuré, et n’appelle jamais Google', () async {
      final CompteGoogleReel compte = CompteGoogleReel(clientWeb: '');
      expect(compte.configure, isFalse);
      expect(await compte.restaurer(), isNull);
      await compte.seDeconnecter(); // ne lève rien
      compte.invaliderJeton(); // ne lève rien
    });

    test('seConnecter : erreur lisible qui explique que Google n’est pas configuré', () async {
      final CompteGoogleReel compte = CompteGoogleReel(clientWeb: '');
      await expectLater(
        compte.seConnecter(),
        throwsA(
          isA<ErreurDrive>()
              .having((ErreurDrive e) => e.message, 'message', contains('pas encore configuré'))
              .having((ErreurDrive e) => e.annulee, 'annulee', isFalse),
        ),
      );
    });

    test('jetonAcces sans connexion : la connexion est à refaire', () async {
      final CompteGoogleReel compte = CompteGoogleReel(clientWeb: '');
      await expectLater(
        compte.jetonAcces(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
      );
    });

    test('avec un ID client Web, il est configuré', () {
      expect(CompteGoogleReel(clientWeb: '123-abc.apps.googleusercontent.com').configure, isTrue);
    });
  });
}
