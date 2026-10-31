import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/statistiques_vues.dart';

/// Les chiffres de l'activité (jour, semaine, mois, année, factures impayées, franchise de TVA), mis à jour
/// automatiquement à chaque vente, paiement, dépense ou facture. Partagés par l'accueil et l'écran Statistiques.
final statistiquesProvider = StreamProvider.autoDispose<Statistiques>(
  (ref) => ref.watch(statistiquesRepositoryProvider).observer(horloge: ref.watch(horlogeProvider)),
);
