import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/parametres_repository.dart';
import '../../data/repositories/statistiques_repository.dart';

/// Le rappel de la déclaration des recettes est-il activé ? (Le choix de l'utilisatrice, mémorisé dans les réglages.)
final rappelDeclarationProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(parametresRepositoryProvider).observer().map(ParametresRepository.rappelDeclarationDe),
);

/// Les notifications sont-elles autorisées sur cet appareil en ce moment ? Relu avec `ref.invalidate` après une demande
/// d'autorisation, et à chaque ouverture de l'écran.
final notificationsAutoriseesProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(serviceRappelsDeclarationProvider).notificationsAutorisees(),
);

/// L'argent encaissé ce mois-ci et le mois dernier, mis à jour automatiquement à chaque vente ou paiement.
final recettesDeclarationProvider = StreamProvider.autoDispose<RecettesDeclaration>(
  (ref) => ref.watch(statistiquesRepositoryProvider).observerRecettesDeclaration(horloge: ref.watch(horlogeProvider)),
);
