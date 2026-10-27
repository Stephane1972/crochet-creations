import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/devis_repository.dart';
import '../../data/repositories/devis_vues.dart';

/// Tous les devis, le plus récent d'abord, mis à jour automatiquement. À l'ouverture, les devis dont la
/// date de validité est dépassée passent en « Expiré ».
final devisListeProvider = StreamProvider.autoDispose<List<DevisResume>>((ref) async* {
  final DevisRepository depot = ref.watch(devisRepositoryProvider);
  await depot.actualiserExpirations();
  yield* depot.observerListe();
});

/// Détail d'un devis (`null` s'il n'existe pas), mis à jour automatiquement.
final devisDetailProvider = StreamProvider.autoDispose.family<DevisDetail?, int>((ref, int id) async* {
  final DevisRepository depot = ref.watch(devisRepositoryProvider);
  await depot.actualiserExpirations();
  yield* depot.observerDetail(id);
});

/// Identifie un PDF de devis : le devis et sa dernière modification (le PDF est refabriqué quand le devis change).
typedef ClePdfDevis = ({int id, int version});

/// Le PDF d'un devis, fabriqué à partir de son état actuel.
final devisPdfProvider = FutureProvider.autoDispose.family<Uint8List, ClePdfDevis>(
  (ref, ClePdfDevis cle) => ref.watch(devisRepositoryProvider).obtenirPdf(cle.id),
);
