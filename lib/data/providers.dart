import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'repositories/client_repository.dart';
import 'repositories/numerotation_repository.dart';
import 'repositories/parametres_repository.dart';
import 'repositories/produit_repository.dart';

/// Base de données ouverte par `main()` au démarrage (voir `lib/main.dart`).
/// Les tests la remplacent par une base en mémoire.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

final parametresRepositoryProvider = Provider<ParametresRepository>(
  (ref) => ParametresRepository(ref.watch(appDatabaseProvider)),
);

final numerotationRepositoryProvider = Provider<NumerotationRepository>(
  (ref) => NumerotationRepository(ref.watch(appDatabaseProvider)),
);

final produitRepositoryProvider = Provider<ProduitRepository>(
  (ref) => ProduitRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(numerotationRepositoryProvider),
  ),
);

final clientRepositoryProvider = Provider<ClientRepository>(
  (ref) => ClientRepository(ref.watch(appDatabaseProvider)),
);
