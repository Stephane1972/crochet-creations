import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_vues.dart';

/// Tous les clients (archivés compris), mis à jour automatiquement.
/// Les filtres s'appliquent ensuite côté écran (voir `filtrerClients`).
final clientsProvider = StreamProvider.autoDispose<List<Client>>(
  (ref) => ref.watch(clientRepositoryProvider).observerClients(inclureArchives: true),
);

/// Fiche d'un client (`null` s'il n'existe pas ou plus).
final clientProvider = StreamProvider.autoDispose.family<Client?, int>(
  (ref, int id) => ref.watch(clientRepositoryProvider).observerClient(id),
);

/// Devis, ventes, factures, paiements et cours d'un client.
final historiqueClientProvider = StreamProvider.autoDispose.family<HistoriqueClient, int>(
  (ref, int id) => ref.watch(clientRepositoryProvider).observerHistorique(id),
);
