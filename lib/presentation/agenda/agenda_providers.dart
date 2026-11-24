import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/parametres_repository.dart';
import '../../domain/agenda.dart';

/// Un mois du calendrier : l'année et le mois (1 à 12).
typedef MoisAgenda = ({int annee, int mois});

/// Tout ce qui est prévu dans la grille d'un mois (avec les jours des semaines voisines qu'elle montre), tous types
/// confondus : l'écran masque ceux que les filtres écartent. Mis à jour automatiquement.
final entreesAgendaProvider = StreamProvider.autoDispose.family<List<EntreeAgenda>, MoisAgenda>((ref, MoisAgenda mois) {
  final List<DateTime> jours = joursAffiches(mois.annee, mois.mois);
  final DateTime debut = jours.first;
  final DateTime fin = DateTime(jours.last.year, jours.last.month, jours.last.day + 1);
  return ref.watch(agendaRepositoryProvider).observerEntrees(debut, fin, horloge: ref.watch(horlogeProvider));
});

/// Les types d'entrées que montre le calendrier (le choix de l'utilisatrice, mémorisé dans les réglages).
final filtresAgendaProvider = StreamProvider.autoDispose<FiltresAgenda>(
  (ref) => ref.watch(parametresRepositoryProvider).observer().map(ParametresRepository.filtresAgendaDe),
);
