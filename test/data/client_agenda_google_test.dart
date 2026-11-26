import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crochet_creations/data/agenda/client_agenda_google.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/domain/agenda_google.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _reponse(Object? corps, [int statut = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(corps)),
  statut,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

http.Response _erreurGoogle(int statut, {String? raison, String message = 'Une erreur'}) => _reponse(<String, Object?>{
  'error': <String, Object?>{
    'code': statut,
    'message': message,
    if (raison != null)
      'errors': <Object?>[
        <String, Object?>{'reason': raison, 'message': message},
      ],
  },
}, statut);

EvenementGoogle _journee() => EvenementGoogle(
  id: 'ptite4',
  titre: 'Marché de Noël',
  debut: DateTime.utc(2026, 12, 12),
  fin: DateTime.utc(2026, 12, 13),
  journeeEntiere: true,
  description: 'Stand n° 3',
  lieu: 'Mairie',
  type: TypeEntreeAgenda.evenement,
);

EvenementGoogle _heure() => EvenementGoogle(
  id: 'ptitc12',
  titre: 'Atelier crochet',
  debut: DateTime.utc(2026, 12, 5, 13, 30),
  fin: DateTime.utc(2026, 12, 5, 15, 30),
  journeeEntiere: false,
  type: TypeEntreeAgenda.cours,
);

Map<String, Object?> _evenementJson(
  String id, {
  String titre = 'Atelier crochet',
  Map<String, Object?>? privees = const <String, Object?>{'crochet': '1', 'type': 'cours'},
  Map<String, Object?>? debut,
  Map<String, Object?>? fin,
  String? statut,
}) => <String, Object?>{
  'id': id,
  'summary': titre,
  'start': debut ?? <String, Object?>{'dateTime': '2026-12-05T14:30:00+01:00'},
  'end': fin ?? <String, Object?>{'dateTime': '2026-12-05T16:30:00+01:00'},
  if (statut != null) 'status': statut,
  if (privees != null) 'extendedProperties': <String, Object?>{'private': privees},
};

/// Un faux Google Agenda : il note les requêtes et répond ce que [repondre] décide.
class _Banc {
  _Banc(this.repondre, {Duration delai = const Duration(seconds: 5)}) {
    client = ClientAgendaGoogleReel(
      jeton: () async => 'jeton-${++jetonsDemandes}',
      invaliderJeton: () => invalidations++,
      base: MockClient((http.Request r) async {
        requetes.add(r);
        return repondre(r);
      }),
      pause: (Duration d) async => pauses.add(d),
      delaiReseau: delai,
    );
  }

  final http.Response Function(http.Request) repondre;
  late final ClientAgendaGoogleReel client;
  final List<http.Request> requetes = <http.Request>[];
  final List<Duration> pauses = <Duration>[];
  int jetonsDemandes = 0;
  int invalidations = 0;

  Map<String, Object?> corps(int i) => jsonDecode(requetes[i].body) as Map<String, Object?>;
}

void main() {
  group('le corps d’un événement', () {
    test('toute la journée : des dates, la fin est le lendemain ; opaque ; propriétés privées', () {
      final Map<String, Object?> c = corpsEvenementGoogle(_journee());

      expect(c['id'], 'ptite4');
      expect(c['status'], 'confirmed');
      expect(c['summary'], 'Marché de Noël');
      expect(c['description'], 'Stand n° 3');
      expect(c['location'], 'Mairie');
      expect(c['start'], <String, Object?>{'date': '2026-12-12'});
      expect(c['end'], <String, Object?>{'date': '2026-12-13'});
      expect(c['transparency'], 'opaque');
      expect(c['extendedProperties'], <String, Object?>{
        'private': <String, Object?>{'crochet': '1', 'type': 'evenement'},
      });
    });

    test('à heure fixe : l’instant exact en UTC ; sans description ni lieu, ces champs sont omis', () {
      final Map<String, Object?> c = corpsEvenementGoogle(_heure());

      expect(c['start'], <String, Object?>{'dateTime': '2026-12-05T13:30:00.000Z'});
      expect(c['end'], <String, Object?>{'dateTime': '2026-12-05T15:30:00.000Z'});
      expect(c.containsKey('description'), isFalse);
      expect(c.containsKey('location'), isFalse);
    });

    test('un événement « [Annulé] » est « disponible » (transparent), pas « occupé »', () {
      expect(corpsEvenementGoogle(_heure().annule())['transparency'], 'transparent');
      expect(corpsEvenementGoogle(_heure().annule())['summary'], '[Annulé] Atelier crochet');
    });

    test('sans type connu, la propriété « type » est omise', () {
      final EvenementGoogle e = EvenementGoogle(
        id: 'ptitc1',
        titre: 'x',
        debut: DateTime.utc(2026, 12, 5, 9),
        fin: DateTime.utc(2026, 12, 5, 10),
        journeeEntiere: false,
      );

      expect(corpsEvenementGoogle(e)['extendedProperties'], <String, Object?>{
        'private': <String, Object?>{'crochet': '1'},
      });
    });
  });

  group('lire un événement de Google', () {
    test('à heure fixe, avec un décalage horaire : converti en UTC', () {
      final EvenementGoogle e = evenementDepuisJsonGoogle(_evenementJson('ptitc12'))!;

      expect(e.id, 'ptitc12');
      expect(e.titre, 'Atelier crochet');
      expect(e.journeeEntiere, isFalse);
      expect(e.debut, DateTime.utc(2026, 12, 5, 13, 30));
      expect(e.fin, DateTime.utc(2026, 12, 5, 15, 30));
      expect(e.type, TypeEntreeAgenda.cours);
    });

    test('toute la journée : la date, fin exclue', () {
      final EvenementGoogle e = evenementDepuisJsonGoogle(
        _evenementJson(
          'ptite4',
          privees: <String, Object?>{'crochet': '1', 'type': 'evenement'},
          debut: <String, Object?>{'date': '2026-12-12'},
          fin: <String, Object?>{'date': '2026-12-13'},
        ),
      )!;

      expect(e.journeeEntiere, isTrue);
      expect(e.debut, DateTime.utc(2026, 12, 12));
      expect(e.fin, DateTime.utc(2026, 12, 13));
      expect(e.type, TypeEntreeAgenda.evenement);
    });

    test('sans titre, description ni lieu : des textes vides ; type inconnu : null', () {
      final Map<String, Object?> json = _evenementJson('ptitc1', privees: <String, Object?>{'crochet': '1', 'type': 'inconnu'})..remove('summary');
      final EvenementGoogle e = evenementDepuisJsonGoogle(json)!;

      expect(e.titre, '');
      expect(e.description, '');
      expect(e.lieu, '');
      expect(e.type, isNull);
    });

    test('un événement supprimé, sans la marque de l’application, sans date lisible ou sans identifiant : ignoré', () {
      expect(evenementDepuisJsonGoogle(_evenementJson('ptitc1', statut: 'cancelled')), isNull);
      expect(evenementDepuisJsonGoogle(_evenementJson('ptitc1', privees: null)), isNull);
      expect(evenementDepuisJsonGoogle(_evenementJson('ptitc1', privees: <String, Object?>{'type': 'cours'})), isNull);
      expect(evenementDepuisJsonGoogle(_evenementJson('ptitc1', debut: <String, Object?>{'dateTime': 'pas une date'})), isNull);
      expect(evenementDepuisJsonGoogle(_evenementJson('ptitc1', fin: <String, Object?>{})), isNull);
      expect(evenementDepuisJsonGoogle(_evenementJson('')), isNull);
      expect(evenementDepuisJsonGoogle('texte'), isNull);
      expect(evenementDepuisJsonGoogle(null), isNull);
    });

    test('ce qu’on envoie, relu tel que Google le renvoie, est reconnu comme identique (pas de réécriture inutile)', () {
      for (final EvenementGoogle e in <EvenementGoogle>[_journee(), _heure(), _heure().annule()]) {
        final EvenementGoogle relu = evenementDepuisJsonGoogle(jsonDecode(jsonEncode(corpsEvenementGoogle(e))))!;

        expect(relu.memeContenu(e), isTrue, reason: e.titre);
        expect(relu.type, e.type, reason: e.titre);
        expect(relu.estAnnule, e.estAnnule, reason: e.titre);
      }
    });
  });

  group('créer l’agenda', () {
    test('POST /calendars avec le nom et le fuseau ; rend l’identifiant', () async {
      final _Banc banc = _Banc((http.Request r) => _reponse(<String, Object?>{'id': 'abc@group.calendar.google.com'}));

      final String id = await banc.client.creerCalendrier(nom: nomAgendaGoogle, fuseau: fuseauAgendaGoogle);

      expect(id, 'abc@group.calendar.google.com');
      expect(banc.requetes, hasLength(1));
      expect(banc.requetes.single.method, 'POST');
      expect(banc.requetes.single.url.host, 'www.googleapis.com');
      expect(banc.requetes.single.url.pathSegments, <String>['calendar', 'v3', 'calendars']);
      expect(banc.requetes.single.headers['Authorization'], 'Bearer jeton-1');
      expect(banc.requetes.single.headers['Content-Type'], contains('application/json'));
      expect(banc.corps(0), <String, Object?>{'summary': 'Un p’tit crochet dans les stocks', 'timeZone': 'Europe/Paris'});
    });

    test('une réponse sans identifiant, ou illisible : une erreur claire', () async {
      final _Banc sansId = _Banc((http.Request r) => _reponse(<String, Object?>{}));
      await expectLater(
        sansId.client.creerCalendrier(nom: 'x', fuseau: 'Europe/Paris'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('n’a pas créé'))),
      );

      final _Banc illisible = _Banc((http.Request r) => http.Response('pas du json', 200));
      await expectLater(
        illisible.client.creerCalendrier(nom: 'x', fuseau: 'Europe/Paris'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('inattendue'))),
      );
    });

    test('une panne de Google (503) n’est pas retentée : on n’aurait pas deux agendas', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(503));

      await expectLater(
        banc.client.creerCalendrier(nom: 'x', fuseau: 'Europe/Paris'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('momentanément indisponible'))),
      );
      expect(banc.requetes, hasLength(1));
      expect(banc.pauses, isEmpty);
    });
  });

  group('lister les événements', () {
    test('GET des événements de l’application seuls, dans la période, sans les supprimés', () async {
      final _Banc banc = _Banc(
        (http.Request r) => _reponse(<String, Object?>{
          'items': <Object?>[
            _evenementJson('ptitc12'),
            _evenementJson('autre', privees: null), // pas de l'application : ignoré
          ],
        }),
      );
      final DateTime debut = DateTime.utc(2026, 10, 1);
      final DateTime fin = DateTime.utc(2027, 12, 1);

      final List<EvenementGoogle> liste = await banc.client.lister('abc@group.calendar.google.com', debut: debut, fin: fin);

      expect(liste.map((EvenementGoogle e) => e.id), <String>['ptitc12']);
      final Uri url = banc.requetes.single.url;
      expect(banc.requetes.single.method, 'GET');
      expect(url.pathSegments, <String>['calendar', 'v3', 'calendars', 'abc@group.calendar.google.com', 'events']);
      expect(url.queryParameters['privateExtendedProperty'], 'crochet=1');
      expect(url.queryParameters['singleEvents'], 'true');
      expect(url.queryParameters['showDeleted'], 'false');
      expect(url.queryParameters['timeMin'], debut.toIso8601String());
      expect(url.queryParameters['timeMax'], fin.toIso8601String());
    });

    test('sans bornes, aucune date n’est envoyée', () async {
      final _Banc banc = _Banc((http.Request r) => _reponse(<String, Object?>{'items': <Object?>[]}));

      await banc.client.lister('cal');

      expect(banc.requetes.single.url.queryParameters.containsKey('timeMin'), isFalse);
      expect(banc.requetes.single.url.queryParameters.containsKey('timeMax'), isFalse);
    });

    test('plusieurs pages : toutes sont lues', () async {
      final _Banc banc = _Banc((http.Request r) {
        if (r.url.queryParameters['pageToken'] == null) {
          return _reponse(<String, Object?>{
            'items': <Object?>[_evenementJson('ptitc1'), _evenementJson('ptitc2')],
            'nextPageToken': 'page-2',
          });
        }
        expect(r.url.queryParameters['pageToken'], 'page-2');
        return _reponse(<String, Object?>{
          'items': <Object?>[_evenementJson('ptitc3')],
        });
      });

      final List<EvenementGoogle> liste = await banc.client.lister('cal');

      expect(liste.map((EvenementGoogle e) => e.id), <String>['ptitc1', 'ptitc2', 'ptitc3']);
      expect(banc.requetes, hasLength(2));
    });

    test('un agenda qui n’existe plus (404) : CalendrierIntrouvable', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(404, raison: 'notFound', message: 'Not Found'));

      await expectLater(banc.client.lister('cal'), throwsA(isA<CalendrierIntrouvable>()));
    });
  });

  group('créer, remplacer, supprimer un événement', () {
    test('créer : POST sur les événements, sans prévenir personne (sendUpdates=none)', () async {
      final _Banc banc = _Banc((http.Request r) => _reponse(<String, Object?>{'id': 'ptite4'}));

      await banc.client.creer('cal', _journee());

      expect(banc.requetes, hasLength(1));
      expect(banc.requetes.single.method, 'POST');
      expect(banc.requetes.single.url.pathSegments, <String>['calendar', 'v3', 'calendars', 'cal', 'events']);
      expect(banc.requetes.single.url.queryParameters['sendUpdates'], 'none');
      expect(banc.corps(0)['id'], 'ptite4');
      expect(banc.corps(0)['summary'], 'Marché de Noël');
    });

    test('créer un événement dont l’identifiant existe déjà (409) : il est rétabli par un remplacement', () async {
      final _Banc banc = _Banc((http.Request r) {
        if (r.method == 'POST') return _erreurGoogle(409, raison: 'duplicate', message: 'The requested identifier already exists.');
        return _reponse(<String, Object?>{'id': 'ptite4'});
      });

      await banc.client.creer('cal', _journee());

      expect(banc.requetes.map((http.Request r) => r.method), <String>['POST', 'PUT']);
      expect(banc.requetes[1].url.pathSegments, <String>['calendar', 'v3', 'calendars', 'cal', 'events', 'ptite4']);
      expect(banc.corps(1)['status'], 'confirmed');
    });

    test('remplacer : PUT sur l’événement, avec le contenu complet', () async {
      final _Banc banc = _Banc((http.Request r) => _reponse(<String, Object?>{'id': 'ptitc12'}));

      await banc.client.remplacer('cal', _heure().annule());

      expect(banc.requetes, hasLength(1));
      expect(banc.requetes.single.method, 'PUT');
      expect(banc.requetes.single.url.pathSegments.last, 'ptitc12');
      expect(banc.requetes.single.url.queryParameters['sendUpdates'], 'none');
      expect(banc.corps(0)['summary'], '[Annulé] Atelier crochet');
      expect(banc.corps(0)['transparency'], 'transparent');
    });

    test('remplacer un événement qui n’existe plus (404) : il est créé ; si l’agenda a disparu, CalendrierIntrouvable', () async {
      final _Banc banc = _Banc((http.Request r) => r.method == 'PUT' ? _erreurGoogle(404) : _reponse(<String, Object?>{'id': 'ptitc12'}));
      await banc.client.remplacer('cal', _heure());
      expect(banc.requetes.map((http.Request r) => r.method), <String>['PUT', 'POST']);

      final _Banc sansAgenda = _Banc((http.Request r) => _erreurGoogle(404));
      await expectLater(sansAgenda.client.remplacer('cal', _heure()), throwsA(isA<CalendrierIntrouvable>()));
    });

    test('supprimer : DELETE ; un événement déjà supprimé (404 ou 410) est ignoré', () async {
      final _Banc banc = _Banc((http.Request r) => http.Response('', 204));
      await banc.client.supprimer('cal', 'ptitc12');
      expect(banc.requetes.single.method, 'DELETE');
      expect(banc.requetes.single.url.pathSegments, <String>['calendar', 'v3', 'calendars', 'cal', 'events', 'ptitc12']);

      for (final int statut in <int>[404, 410]) {
        final _Banc dejaFait = _Banc((http.Request r) => _erreurGoogle(statut));
        await dejaFait.client.supprimer('cal', 'ptitc12');
      }
    });

    test('supprimer, refusé (403) : une erreur lisible', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(403, raison: 'forbidden', message: 'Interdit'));

      await expectLater(
        banc.client.supprimer('cal', 'ptitc12'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Interdit'))),
      );
    });

    test('les accents passent intacts dans ce qui est envoyé', () async {
      final _Banc banc = _Banc((http.Request r) => _reponse(<String, Object?>{'id': 'x'}));
      final EvenementGoogle e = EvenementGoogle(
        id: 'ptite1',
        titre: 'Réunion « été » — œuvres',
        debut: DateTime.utc(2026, 12, 5),
        fin: DateTime.utc(2026, 12, 6),
        journeeEntiere: true,
      );

      await banc.client.creer('cal', e);

      expect(banc.corps(0)['summary'], 'Réunion « été » — œuvres');
    });
  });

  group('autorisation et limites de Google', () {
    test('un jeton refusé (401) est renouvelé une fois, puis la requête repart avec le nouveau', () async {
      int appels = 0;
      final _Banc banc = _Banc((http.Request r) => ++appels == 1 ? _erreurGoogle(401) : _reponse(<String, Object?>{'items': <Object?>[]}));

      await banc.client.lister('cal');

      expect(banc.requetes, hasLength(2));
      expect(banc.invalidations, 1);
      expect(banc.requetes[0].headers['Authorization'], 'Bearer jeton-1');
      expect(banc.requetes[1].headers['Authorization'], 'Bearer jeton-2');
    });

    test('un 401 qui persiste : l’autorisation a expiré, il faut se reconnecter', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(401));

      await expectLater(
        banc.client.lister('cal'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
      );
      expect(banc.requetes, hasLength(2));
    });

    test('un jeton impossible à obtenir : l’erreur remonte telle quelle, sans requête', () async {
      final MockClient base = MockClient((http.Request r) async => throw StateError('aucune requête attendue'));
      final ClientAgendaGoogleReel client = ClientAgendaGoogleReel(
        jeton: () async => throw const ErreurDrive('La connexion à Google est perdue.', autorisationAExpire: true),
        invaliderJeton: () {},
        base: base,
      );

      await expectLater(
        client.lister('cal'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
      );
    });

    test('limite de débit (403 rateLimitExceeded) : deux pauses, puis ça passe', () async {
      int appels = 0;
      final _Banc banc = _Banc(
        (http.Request r) => ++appels <= 2 ? _erreurGoogle(403, raison: 'rateLimitExceeded', message: 'Rate Limit Exceeded') : _reponse(<String, Object?>{'id': 'x'}),
      );

      await banc.client.creer('cal', _heure());

      expect(banc.requetes, hasLength(3));
      expect(banc.pauses, <Duration>[const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('limite de débit qui dure (429) : trois pauses, puis un message qui dit de patienter', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(429));

      await expectLater(
        banc.client.creer('cal', _heure()),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('ralentir'))),
      );
      expect(banc.requetes, hasLength(4));
      expect(banc.pauses, ClientAgendaGoogleReel.pausesRetentative);
    });

    test('une panne passagère de Google (503) lors d’une lecture est retentée', () async {
      int appels = 0;
      final _Banc banc = _Banc((http.Request r) => ++appels == 1 ? _erreurGoogle(503) : _reponse(<String, Object?>{'items': <Object?>[]}));

      await banc.client.lister('cal');

      expect(banc.requetes, hasLength(2));
      expect(banc.pauses, hasLength(1));
    });

    test('l’API Google Calendar pas activée dans le projet : le message dit quoi faire', () async {
      final _Banc banc = _Banc(
        (http.Request r) => _erreurGoogle(
          403,
          raison: 'accessNotConfigured',
          message: 'Google Calendar API has not been used in project 123 before or it is disabled.',
        ),
      );

      await expectLater(
        banc.client.creerCalendrier(nom: 'x', fuseau: 'Europe/Paris'),
        throwsA(
          isA<ErreurDrive>()
              .having((ErreurDrive e) => e.message, 'message', allOf(contains('Google Calendar API'), contains('Activez')))
              .having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isFalse),
        ),
      );
      expect(banc.requetes, hasLength(1)); // pas de nouvelle tentative : ce n'est pas passager
    });

    test('le droit « agenda » absent du jeton : il faut autoriser de nouveau', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(403, raison: 'insufficientPermissions', message: 'Request had insufficient authentication scopes.'));

      await expectLater(
        banc.client.lister('cal'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
      );
    });

    test('une demande refusée (400) : le message de Google est repris', () async {
      final _Banc banc = _Banc((http.Request r) => _erreurGoogle(400, raison: 'invalid', message: 'Invalid value for: start'));

      await expectLater(
        banc.client.creer('cal', _heure()),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Invalid value for: start'))),
      );
    });

    test('pas de réseau : « Pas de connexion à Internet. »', () async {
      final ClientAgendaGoogleReel client = ClientAgendaGoogleReel(
        jeton: () async => 'jeton',
        invaliderJeton: () {},
        base: MockClient((http.Request r) async => throw const SocketException('pas de réseau')),
      );

      await expectLater(
        client.lister('cal'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', 'Pas de connexion à Internet.')),
      );
    });

    test('Google qui ne répond pas : « trop lente », sans rester bloqué', () async {
      final ClientAgendaGoogleReel client = ClientAgendaGoogleReel(
        jeton: () async => 'jeton',
        invaliderJeton: () {},
        base: MockClient((http.Request r) => Completer<http.Response>().future),
        delaiReseau: const Duration(milliseconds: 50),
      );

      await expectLater(
        client.lister('cal'),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('trop lente'))),
      );
    });
  });
}
