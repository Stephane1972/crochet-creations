import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
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

/// Identifie un PDF de devis : le devis et une « version » de ce qui s'imprime (voir [versionPdfDevis]).
typedef ClePdfDevis = ({int id, int version});

/// Le PDF d'un devis, fabriqué à partir de son état actuel.
final devisPdfProvider = FutureProvider.autoDispose.family<Uint8List, ClePdfDevis>(
  (ref, ClePdfDevis cle) => ref.watch(devisRepositoryProvider).obtenirPdf(cle.id),
);

/// Résumé de tout ce qui s'imprime sur le devis (contenu, conditions, client) : le PDF est refabriqué quand
/// elle change, mais pas pour un simple changement de statut.
int versionPdfDevis(DevisDetail detail) {
  final DevisFiche d = detail.devis;
  return Object.hash(
    d.numero,
    d.dateEmission,
    d.dateValidite,
    d.delaiRealisation,
    d.acompteCentimes,
    d.sousTotalCentimes,
    d.remiseType,
    d.remiseValeur,
    d.remiseCentimes,
    d.fraisPortCentimes,
    d.totalCentimes,
    Object.hashAll(detail.lignes),
    detail.client,
  );
}
