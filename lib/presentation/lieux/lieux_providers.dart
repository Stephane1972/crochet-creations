import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';

/// Les lieux de vente, dans l'ordre d'affichage, mis à jour automatiquement.
final lieuxVenteProvider = StreamProvider.autoDispose<List<LieuVente>>(
  (ref) => ref.watch(lieuVenteRepositoryProvider).observer(),
);

/// Nombre de ventes de chaque lieu (annulées comprises), par identifiant. Les lieux sans vente n'y figurent pas.
final nombreVentesParLieuProvider = StreamProvider.autoDispose<Map<int, int>>(
  (ref) => ref.watch(lieuVenteRepositoryProvider).observerNombreVentesParLieu(),
);

/// Le lieu d'identifiant [id] dans [lieux], ou `null` (« Non renseigné ») si [id] est vide ou n'existe plus.
LieuVente? lieuParId(List<LieuVente> lieux, int? id) {
  if (id == null) return null;
  for (final LieuVente l in lieux) {
    if (l.id == id) return l;
  }
  return null;
}
