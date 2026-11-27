import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/agenda.dart';
import '../../domain/agenda_google.dart';
import '../drive/compte_google.dart';

/// L'agenda Google mémorisé n'existe plus (la personne l'a supprimé dans Google Agenda) : il faut en créer un autre.
class CalendrierIntrouvable implements Exception {
  const CalendrierIntrouvable();

  @override
  String toString() => 'L’agenda Google est introuvable.';
}

/// Les opérations sur Google Agenda dont l'application a besoin : créer son agenda, lister ses propres événements, en créer,
/// en remplacer, et (seulement quand la personne le demande) en supprimer. Les échecs sortent en [ErreurDrive] (message lisible
/// tel quel) ; un agenda disparu sort en [CalendrierIntrouvable].
abstract class ClientAgendaGoogle {
  /// Crée un agenda nommé [nom] dans le compte Google et retourne son identifiant.
  Future<String> creerCalendrier({required String nom, required String fuseau});

  /// Les événements de l'application déjà présents dans l'agenda [calendrierId] (et eux seuls), entre [debut] et [fin] ;
  /// sans bornes, tous. Les événements supprimés dans Google Agenda ne sont pas rendus.
  Future<List<EvenementGoogle>> lister(String calendrierId, {DateTime? debut, DateTime? fin});

  /// Crée [evenement]. Si Google dit que son identifiant existe déjà (événement supprimé dans Google Agenda, dont
  /// l'identifiant reste réservé), il est rétabli à la place.
  Future<void> creer(String calendrierId, EvenementGoogle evenement);

  /// Remplace l'événement de même identifiant par [evenement] (s'il n'existe plus, il est créé).
  Future<void> remplacer(String calendrierId, EvenementGoogle evenement);

  /// Supprime l'événement [evenementId]. Un événement déjà supprimé est ignoré. N'est appelé que sur demande de la personne.
  Future<void> supprimer(String calendrierId, String evenementId);
}

// -----------------------------------------------------------------------------
// Le format de Google
// -----------------------------------------------------------------------------

String _deux(int n) => n.toString().padLeft(2, '0');

/// `AAAA-MM-JJ` (le jour d'un événement « toute la journée »).
String _jourGoogle(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_deux(d.month)}-${_deux(d.day)}';

/// Le corps JSON d'un événement, tel que Google Agenda le reçoit (création et remplacement). Le lieu et la description
/// vides sont omis : un remplacement les retire alors de l'événement.
Map<String, Object?> corpsEvenementGoogle(EvenementGoogle e) {
  Map<String, Object?> moment(DateTime d) =>
      e.journeeEntiere ? <String, Object?>{'date': _jourGoogle(d)} : <String, Object?>{'dateTime': d.toUtc().toIso8601String()};
  final TypeEntreeAgenda? type = e.type;
  return <String, Object?>{
    'id': e.id,
    // « confirmed » rétablit aussi un événement supprimé dans Google Agenda.
    'status': 'confirmed',
    'summary': e.titre,
    if (e.description.trim().isNotEmpty) 'description': e.description,
    if (e.lieu.trim().isNotEmpty) 'location': e.lieu,
    'start': moment(e.debut),
    'end': moment(e.fin),
    // Un événement annulé ne bloque plus le créneau (il apparaît comme « disponible »).
    'transparency': e.estAnnule ? 'transparent' : 'opaque',
    'extendedProperties': <String, Object?>{
      'private': <String, Object?>{proprieteCrochet: '1', if (type != null) proprieteType: type.name},
    },
  };
}

({DateTime instant, bool journee})? _moment(Object? valeur) {
  if (valeur is! Map<String, Object?>) return null;
  final Object? date = valeur['date'];
  if (date is String) {
    final DateTime? d = DateTime.tryParse(date);
    return d == null ? null : (instant: DateTime.utc(d.year, d.month, d.day), journee: true);
  }
  final Object? heure = valeur['dateTime'];
  if (heure is String) {
    final DateTime? d = DateTime.tryParse(heure);
    return d == null ? null : (instant: d.toUtc(), journee: false);
  }
  return null;
}

/// L'événement de l'application décrit par [json] (un événement renvoyé par Google). `null` s'il est supprimé, illisible, ou
/// s'il n'a pas été créé par l'application (sans la propriété privée `crochet`).
EvenementGoogle? evenementDepuisJsonGoogle(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final Object? id = json['id'];
  if (id is! String || id.isEmpty) return null;
  if (json['status'] == 'cancelled') return null;

  final Object? etendues = json['extendedProperties'];
  final Object? privees = etendues is Map<String, Object?> ? etendues['private'] : null;
  final Map<String, Object?> proprietes = privees is Map<String, Object?> ? privees : const <String, Object?>{};
  if (proprietes[proprieteCrochet] != '1') return null;

  final ({DateTime instant, bool journee})? debut = _moment(json['start']);
  final ({DateTime instant, bool journee})? fin = _moment(json['end']);
  if (debut == null || fin == null) return null;

  final Object? titre = json['summary'];
  final Object? description = json['description'];
  final Object? lieu = json['location'];
  final Object? nomType = proprietes[proprieteType];
  return EvenementGoogle(
    id: id,
    titre: titre is String ? titre : '',
    description: description is String ? description : '',
    lieu: lieu is String ? lieu : '',
    journeeEntiere: debut.journee,
    debut: debut.instant,
    fin: fin.instant,
    type: TypeEntreeAgenda.values.where((TypeEntreeAgenda t) => t.name == nomType).firstOrNull,
  );
}

// -----------------------------------------------------------------------------
// Le client réel
// -----------------------------------------------------------------------------

/// [ClientAgendaGoogle] réel : l'API Google Calendar v3, en appels HTTP directs, avec le seul droit `calendar.app.created`
/// (l'agenda de l'application, rien d'autre).
///
/// [jeton] donne le jeton d'accès portant le droit « agenda » ; [invaliderJeton] l'oublie quand Google le refuse (401) : la
/// requête est alors retentée une fois avec un jeton neuf. Une limite de débit (429, ou 403 « rate limit ») est retentée
/// après quelques secondes ; [pause] est injectable pour les tests.
class ClientAgendaGoogleReel implements ClientAgendaGoogle {
  ClientAgendaGoogleReel({
    required Future<String> Function() jeton,
    required void Function() invaliderJeton,
    http.Client? base,
    this.delaiReseau = const Duration(seconds: 30),
    Future<void> Function(Duration)? pause,
  }) : _jeton = jeton,
       _invaliderJeton = invaliderJeton,
       _base = base ?? http.Client(),
       _pause = pause ?? _pauseReelle;

  final Future<String> Function() _jeton;
  final void Function() _invaliderJeton;
  final http.Client _base;
  final Future<void> Function(Duration) _pause;

  /// Délai maximal d'une réponse de Google.
  final Duration delaiReseau;

  static Future<void> _pauseReelle(Duration duree) => Future<void>.delayed(duree);

  /// Les attentes avant chaque nouvelle tentative, après une limite de débit ou une panne passagère de Google.
  static const List<Duration> pausesRetentative = <Duration>[Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)];

  Uri _url(List<String> chemin, [Map<String, String>? parametres]) => Uri(
    scheme: 'https',
    host: 'www.googleapis.com',
    pathSegments: <String>['calendar', 'v3', ...chemin],
    queryParameters: parametres,
  );

  Uri _urlEvenements(String calendrierId, {String? evenementId}) => _url(<String>[
    'calendars',
    calendrierId,
    'events',
    if (evenementId != null) evenementId,
  ], <String, String>{'sendUpdates': 'none'});

  Future<http.Response> _tenter(String methode, Uri adresse, Map<String, Object?>? corps) async {
    final http.Request requete = http.Request(methode, adresse);
    requete.headers['Authorization'] = 'Bearer ${await _jeton()}';
    requete.headers['Accept'] = 'application/json';
    if (corps != null) {
      requete.headers['Content-Type'] = 'application/json; charset=utf-8';
      requete.body = jsonEncode(corps);
    }
    final http.StreamedResponse flux = await _base.send(requete).timeout(delaiReseau);
    return http.Response.fromStream(flux).timeout(delaiReseau);
  }

  /// Un appel, avec un jeton neuf si Google refuse le premier (401) et les erreurs réseau en [ErreurDrive] lisibles.
  Future<http.Response> _unAppel(String methode, Uri adresse, Map<String, Object?>? corps) async {
    try {
      http.Response reponse = await _tenter(methode, adresse, corps);
      if (reponse.statusCode == 401) {
        _invaliderJeton();
        reponse = await _tenter(methode, adresse, corps);
      }
      return reponse;
    } on SocketException {
      throw const ErreurDrive('Pas de connexion à Internet.');
    } on http.ClientException {
      throw const ErreurDrive('Pas de connexion à Internet.');
    } on TimeoutException {
      throw const ErreurDrive('La connexion à Google est trop lente. Réessayez.');
    }
  }

  /// Un appel, retenté après une pause si Google demande de ralentir (ou, si [retenterPannes], s'il est momentanément en panne).
  Future<http.Response> _appeler(String methode, Uri adresse, {Map<String, Object?>? corps, bool retenterPannes = true}) async {
    int essai = 0;
    while (true) {
      final http.Response reponse = await _unAppel(methode, adresse, corps);
      final bool aRetenter = _limiteDeDebit(reponse) || (retenterPannes && reponse.statusCode >= 500);
      if (!aRetenter || essai >= pausesRetentative.length) return reponse;
      await _pause(pausesRetentative[essai++]);
    }
  }

  ({String? raison, String? message}) _detail(http.Response reponse) {
    try {
      final Object? lu = jsonDecode(utf8.decode(reponse.bodyBytes));
      final Object? erreur = lu is Map<String, Object?> ? lu['error'] : null;
      if (erreur is Map<String, Object?>) {
        final Object? details = erreur['errors'];
        final Object? premier = details is List && details.isNotEmpty ? details.first : null;
        final Object? raison = premier is Map<String, Object?> ? premier['reason'] : null;
        final Object? message = erreur['message'];
        return (raison: raison is String ? raison : null, message: message is String ? message : null);
      }
    } on FormatException {
      // Corps illisible : on s'en tient au code de réponse.
    }
    return (raison: null, message: null);
  }

  bool _limiteDeDebit(http.Response reponse) {
    if (reponse.statusCode == 429) return true;
    if (reponse.statusCode != 403) return false;
    final String? raison = _detail(reponse).raison;
    return raison == 'rateLimitExceeded' || raison == 'userRateLimitExceeded';
  }

  ErreurDrive _erreur(http.Response reponse) {
    final int statut = reponse.statusCode;
    final ({String? raison, String? message}) detail = _detail(reponse);
    final String raison = detail.raison ?? '';
    final String message = detail.message ?? '';
    final String bas = message.toLowerCase();
    if (statut == 401) {
      return const ErreurDrive('L’autorisation Google Agenda a expiré. Reconnectez-vous.', autorisationAExpire: true);
    }
    if (statut == 403) {
      if (raison == 'accessNotConfigured' || bas.contains('has not been used') || bas.contains('is disabled') || bas.contains('service_disabled')) {
        return const ErreurDrive(
          'Google Agenda est refusé : l’API « Google Calendar API » n’est pas activée dans votre projet Google Cloud. '
          'Activez-la (voir le guide du dépôt, « Google Agenda »), puis réessayez.',
        );
      }
      if (raison == 'insufficientPermissions' || bas.contains('insufficient') || bas.contains('scope')) {
        return const ErreurDrive(
          'Le droit « agenda » n’est pas accordé à l’application. Autorisez-le de nouveau.',
          autorisationAExpire: true,
        );
      }
      if (_limiteDeDebit(reponse) || raison == 'quotaExceeded' || raison == 'calendarUsageLimitsExceeded') {
        return const ErreurDrive('Google demande de ralentir. Réessayez dans quelques minutes.');
      }
      return ErreurDrive('Google Agenda a refusé l’accès (${message.isEmpty ? 'accès refusé' : message}).');
    }
    if (statut == 429) return const ErreurDrive('Google demande de ralentir. Réessayez dans quelques minutes.');
    if (statut == 400) {
      return ErreurDrive('Google Agenda a refusé cet envoi (${message.isEmpty ? 'demande invalide' : message}).');
    }
    if (statut >= 500) return const ErreurDrive('Google Agenda est momentanément indisponible. Réessayez plus tard.');
    return ErreurDrive('Google Agenda a répondu une erreur ($statut)${message.isEmpty ? '' : ' : $message'}.');
  }

  /// Ne fait rien si [reponse] est une réussite ; sinon lève [CalendrierIntrouvable] (404) ou une [ErreurDrive].
  void _verifier(http.Response reponse) {
    if (reponse.statusCode >= 200 && reponse.statusCode < 300) return;
    if (reponse.statusCode == 404) throw const CalendrierIntrouvable();
    throw _erreur(reponse);
  }

  Map<String, Object?> _json(http.Response reponse) {
    try {
      final Object? lu = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (lu is Map<String, Object?>) return lu;
    } on FormatException {
      // Traité ci-dessous comme une réponse inattendue.
    }
    throw const ErreurDrive('Réponse inattendue de Google Agenda : réessayez dans un instant.');
  }

  @override
  Future<String> creerCalendrier({required String nom, required String fuseau}) async {
    final http.Response reponse = await _appeler(
      'POST',
      _url(<String>['calendars']),
      corps: <String, Object?>{'summary': nom, 'timeZone': fuseau},
      // Un agenda créé deux fois serait un doublon : pas de nouvelle tentative sur une panne de Google.
      retenterPannes: false,
    );
    _verifier(reponse);
    final Object? id = _json(reponse)['id'];
    if (id is! String || id.isEmpty) throw const ErreurDrive('Google Agenda n’a pas créé l’agenda.');
    return id;
  }

  @override
  Future<List<EvenementGoogle>> lister(String calendrierId, {DateTime? debut, DateTime? fin}) async {
    final List<EvenementGoogle> resultat = <EvenementGoogle>[];
    String? page;
    do {
      final Map<String, String> parametres = <String, String>{
        'singleEvents': 'true',
        'showDeleted': 'false',
        'maxResults': '250',
        'privateExtendedProperty': '$proprieteCrochet=1',
        'fields': 'nextPageToken,items(id,status,summary,description,location,start,end,extendedProperties)',
        if (debut != null) 'timeMin': debut.toUtc().toIso8601String(),
        if (fin != null) 'timeMax': fin.toUtc().toIso8601String(),
        if (page != null) 'pageToken': page,
      };
      final http.Response reponse = await _appeler('GET', _url(<String>['calendars', calendrierId, 'events'], parametres));
      _verifier(reponse);
      final Map<String, Object?> corps = _json(reponse);
      final Object? elements = corps['items'];
      if (elements is List) {
        for (final Object? element in elements) {
          final EvenementGoogle? evenement = evenementDepuisJsonGoogle(element);
          if (evenement != null) resultat.add(evenement);
        }
      }
      final Object? suivante = corps['nextPageToken'];
      page = suivante is String && suivante.isNotEmpty ? suivante : null;
    } while (page != null);
    return resultat;
  }

  @override
  Future<void> creer(String calendrierId, EvenementGoogle evenement) async {
    final http.Response reponse = await _appeler(
      'POST',
      _urlEvenements(calendrierId),
      corps: corpsEvenementGoogle(evenement),
    );
    // 409 : l'identifiant existe déjà (un événement supprimé dans Google Agenda garde son identifiant) → on le rétablit.
    if (reponse.statusCode == 409) return remplacer(calendrierId, evenement);
    _verifier(reponse);
  }

  @override
  Future<void> remplacer(String calendrierId, EvenementGoogle evenement) async {
    final http.Response reponse = await _appeler(
      'PUT',
      _urlEvenements(calendrierId, evenementId: evenement.id),
      corps: corpsEvenementGoogle(evenement),
    );
    if (reponse.statusCode == 404) {
      // Soit l'événement n'existe plus, soit l'agenda a disparu : on tente de le créer, le 404 suivant dira lequel.
      final http.Response creation = await _appeler(
        'POST',
        _urlEvenements(calendrierId),
        corps: corpsEvenementGoogle(evenement),
      );
      _verifier(creation);
      return;
    }
    _verifier(reponse);
  }

  @override
  Future<void> supprimer(String calendrierId, String evenementId) async {
    final http.Response reponse = await _appeler('DELETE', _urlEvenements(calendrierId, evenementId: evenementId));
    // 404 et 410 : déjà supprimé, c'est ce qu'on voulait.
    if (reponse.statusCode == 404 || reponse.statusCode == 410) return;
    _verifier(reponse);
  }
}
