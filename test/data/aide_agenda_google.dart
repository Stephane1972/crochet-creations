import 'package:crochet_creations/data/agenda/client_agenda_google.dart';
import 'package:crochet_creations/domain/agenda_google.dart';

/// Faux Google Agenda en mémoire, pour les tests : les mêmes opérations que [ClientAgendaGoogle], aucun réseau.
///
/// Il garde tout ce que l'application écrit (par agenda, par identifiant) et un [journal] de tous les appels, pour vérifier
/// ce qui a été fait — et surtout ce qui ne l'a pas été (aucune suppression sans demande).
class FauxClientAgendaGoogle implements ClientAgendaGoogle {
  /// Les événements de chaque agenda créé, par identifiant d'événement.
  final Map<String, Map<String, EvenementGoogle>> calendriers = <String, Map<String, EvenementGoogle>>{};

  /// Tous les appels, dans l'ordre, y compris ceux qui échouent : `creerCalendrier`, `lister`, `creer:<id>`,
  /// `remplacer:<id>`, `supprimer:<id>`.
  final List<String> journal = <String>[];

  /// Si défini, est appelé au début de chaque opération (`creerCalendrier`, `lister`, `creer`, `remplacer`, `supprimer`) avec
  /// l'identifiant de l'événement concerné (`null` pour les deux premières) : ce qu'il rend (non `null`) est lancé à la place
  /// de l'opération.
  Object? Function(String operation, String? evenementId)? panne;

  int _suite = 0;

  /// Les écritures (création, remplacement, suppression) demandées, dans l'ordre.
  List<String> get ecritures =>
      journal.where((String a) => a.startsWith('creer:') || a.startsWith('remplacer:') || a.startsWith('supprimer:')).toList();

  /// Le nombre d'appels de ce type (`creer`, `remplacer`, `supprimer`, `lister`, `creerCalendrier`).
  int appels(String operation) => journal.where((String a) => a == operation || a.startsWith('$operation:')).length;

  void _entrer(String operation, [String? evenementId]) {
    journal.add(evenementId == null ? operation : '$operation:$evenementId');
    final Object? erreur = panne?.call(operation, evenementId);
    if (erreur != null) throw erreur;
  }

  Map<String, EvenementGoogle> _agenda(String calendrierId) {
    final Map<String, EvenementGoogle>? agenda = calendriers[calendrierId];
    if (agenda == null) throw const CalendrierIntrouvable();
    return agenda;
  }

  /// L'événement [id] de l'agenda [calendrierId] tel qu'il est dans Google (`null` : absent).
  EvenementGoogle? evenement(String calendrierId, String id) => calendriers[calendrierId]?[id];

  /// Ce que ferait la personne dans Google Agenda : supprimer l'événement à la main (sans passer par l'application).
  void retirerDansGoogle(String calendrierId, String id) => calendriers[calendrierId]?.remove(id);

  /// Ce que ferait la personne dans Google Agenda : supprimer tout l'agenda.
  void supprimerAgendaDansGoogle(String calendrierId) => calendriers.remove(calendrierId);

  /// Pose directement un événement dans Google (sans journal), comme s'il y était déjà.
  void poser(String calendrierId, EvenementGoogle evenement) => _agenda(calendrierId)[evenement.id] = evenement;

  @override
  Future<String> creerCalendrier({required String nom, required String fuseau}) async {
    _entrer('creerCalendrier');
    final String id = 'agenda-test-${++_suite}';
    calendriers[id] = <String, EvenementGoogle>{};
    return id;
  }

  @override
  Future<List<EvenementGoogle>> lister(String calendrierId, {DateTime? debut, DateTime? fin}) async {
    _entrer('lister');
    final DateTime? depuis = debut?.toUtc();
    final DateTime? jusqua = fin?.toUtc();
    // Comme Google : un événement est dans la période s'il finit après son début et commence avant sa fin.
    return _agenda(calendrierId).values
        .where((EvenementGoogle e) => (depuis == null || e.fin.isAfter(depuis)) && (jusqua == null || e.debut.isBefore(jusqua)))
        .toList();
  }

  @override
  Future<void> creer(String calendrierId, EvenementGoogle evenement) async {
    _entrer('creer', evenement.id);
    // L'identifiant d'un événement supprimé reste réservé : le vrai client le rétablit, ici on l'écrit par-dessus.
    _agenda(calendrierId)[evenement.id] = evenement;
  }

  @override
  Future<void> remplacer(String calendrierId, EvenementGoogle evenement) async {
    _entrer('remplacer', evenement.id);
    _agenda(calendrierId)[evenement.id] = evenement;
  }

  @override
  Future<void> supprimer(String calendrierId, String evenementId) async {
    _entrer('supprimer', evenementId);
    _agenda(calendrierId).remove(evenementId);
  }
}
