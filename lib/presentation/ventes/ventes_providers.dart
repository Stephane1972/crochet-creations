import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/vente_vues.dart';

/// Détail d'une vente (`null` si elle n'existe pas), mis à jour automatiquement
/// (encaissement, annulation...).
final venteDetailProvider = StreamProvider.autoDispose.family<VenteDetail?, int>(
  (ref, int id) => ref.watch(venteRepositoryProvider).observerDetail(id),
);
