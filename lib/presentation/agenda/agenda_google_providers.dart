import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/agenda/service_agenda_google.dart';
import '../../data/providers.dart';
import '../../data/repositories/parametres_repository.dart';
import '../drive/drive_providers.dart';

/// Le réglage de la synchronisation vers Google Agenda : activée ou non, et l'agenda créé dans le compte Google (`null` : aucun).
typedef ReglageAgendaGoogle = ({bool actif, String? calendrier});

/// Le réglage, mis à jour en direct (c'est le choix de la personne, mémorisé dans la base).
final reglageAgendaGoogleProvider = StreamProvider.autoDispose<ReglageAgendaGoogle>(
  (ref) => ref.watch(parametresRepositoryProvider).observer().map(
    (e) => (actif: ParametresRepository.agendaGoogleActifDe(e), calendrier: ParametresRepository.agendaGoogleCalendrierDe(e)),
  ),
);

/// Le droit « Google Agenda » est-il accordé ? Relu quand la connexion à Google change et, à la main, avec `ref.invalidate`
/// après une demande d'autorisation.
final droitAgendaGoogleProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(profilGoogleProvider);
  return ref.watch(serviceAgendaGoogleProvider).droitAccorde();
});

/// Combien de temps après une modification (cours, devis, événement...) le calendrier est renvoyé vers Google Agenda : on
/// attend que les modifications cessent, pour n'envoyer qu'une fois. Les tests le raccourcissent.
final delaiSynchroAgendaGoogleProvider = Provider<Duration>((ref) => const Duration(seconds: 30));

/// Où en est la synchronisation, pour l'écran : en cours ou non, et le bilan de la dernière.
class EtatSynchroAgendaGoogle {
  const EtatSynchroAgendaGoogle({this.enCours = false, this.bilan, this.quand});

  final bool enCours;

  /// Le bilan de la dernière synchronisation (`null` : aucune depuis l'ouverture de l'application).
  final BilanSynchro? bilan;

  /// Quand elle a eu lieu.
  final DateTime? quand;
}

/// La synchronisation vers Google Agenda, déclenchée :
/// - à l'ouverture de l'application (voir `main.dart`) ;
/// - quelques secondes après une modification de ce qui alimente le calendrier (cours, devis, clients, événements) ;
/// - à la demande, avec « Synchroniser maintenant ».
///
/// Sans effet tant que la synchronisation n'est pas activée. Ne lance jamais d'erreur : tout est dans l'état.
class SynchroAgendaGoogleNotifier extends Notifier<EtatSynchroAgendaGoogle> {
  Timer? _minuteur;
  bool _vivant = true;
  bool _premierSignal = true;

  @override
  EtatSynchroAgendaGoogle build() {
    _vivant = true;
    _premierSignal = true;
    final StreamSubscription<int> abonnement = ref
        .watch(agendaRepositoryProvider)
        .observerChangements()
        .listen(
          (int _) {
            // Le premier signal est la lecture de départ, pas une modification.
            if (_premierSignal) {
              _premierSignal = false;
              return;
            }
            _programmer();
          },
          onError: (Object _) {},
        );
    ref.onDispose(() {
      _vivant = false;
      _minuteur?.cancel();
      abonnement.cancel();
    });
    return const EtatSynchroAgendaGoogle();
  }

  void _programmer() {
    _minuteur?.cancel();
    _minuteur = Timer(ref.read(delaiSynchroAgendaGoogleProvider), () {
      if (_vivant) unawaited(synchroniser());
    });
  }

  /// Envoie le calendrier vers Google Agenda (sans effet si la synchronisation n'est pas activée).
  Future<BilanSynchro> synchroniser() => _lancer(() => ref.read(serviceAgendaGoogleProvider).synchroniser());

  /// Active la synchronisation (demande le droit à Google si besoin) puis envoie le calendrier.
  Future<BilanSynchro> activer() => _lancer(() => ref.read(serviceAgendaGoogleProvider).activer());

  /// Crée un nouvel agenda dans Google Agenda (l'ancien n'existe plus) et y envoie le calendrier.
  Future<BilanSynchro> recreerAgenda() => _lancer(() => ref.read(serviceAgendaGoogleProvider).recreerAgenda());

  /// Désactive la synchronisation (ce qui est déjà dans Google Agenda y reste).
  Future<void> desactiver() async {
    _minuteur?.cancel();
    await ref.read(serviceAgendaGoogleProvider).desactiver();
  }

  Future<BilanSynchro> _lancer(Future<BilanSynchro> Function() action) async {
    if (_vivant) state = EtatSynchroAgendaGoogle(enCours: true, bilan: state.bilan, quand: state.quand);
    final BilanSynchro bilan = await action();
    if (_vivant) {
      // « Désactivée » et « indisponible » ne sont pas des résultats : on garde ce qui était affiché.
      final bool aGarder = bilan.issue == IssueSynchro.desactivee || bilan.issue == IssueSynchro.indisponible;
      state = aGarder
          ? EtatSynchroAgendaGoogle(bilan: state.bilan, quand: state.quand)
          : EtatSynchroAgendaGoogle(bilan: bilan, quand: ref.read(horlogeProvider)());
    }
    return bilan;
  }
}

final synchroAgendaGoogleProvider = NotifierProvider<SynchroAgendaGoogleNotifier, EtatSynchroAgendaGoogle>(
  SynchroAgendaGoogleNotifier.new,
);
