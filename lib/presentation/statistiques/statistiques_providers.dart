import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/statistiques_vues.dart';
import '../../domain/calculs/statistiques.dart';

/// Les chiffres de l'activité (jour, semaine, mois, année, factures impayées, franchise de TVA), mis à jour
/// automatiquement à chaque vente, paiement, dépense ou facture. Partagés par l'accueil et l'écran Statistiques.
final statistiquesProvider = StreamProvider.autoDispose<Statistiques>(
  (ref) => ref.watch(statistiquesRepositoryProvider).observer(horloge: ref.watch(horlogeProvider)),
);

/// Toutes les ventes avec leurs paiements, de tout temps, mises à jour automatiquement : la matière de l'écran
/// Analyse détaillée, qui regroupe et filtre ensuite en mémoire.
final ventesAnalyseProvider = StreamProvider.autoDispose<List<VenteCompta>>(
  (ref) => ref.watch(statistiquesRepositoryProvider).observerToutesLesVentes(),
);
