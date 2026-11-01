import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/sauvegarde/format_sauvegarde.dart';

/// Les sauvegardes rangées sur le téléphone, de la plus récente à la plus ancienne. Relue (`ref.invalidate`)
/// après chaque sauvegarde, suppression ou restauration.
final sauvegardesLocalesProvider = FutureProvider.autoDispose<List<SauvegardeLocale>>(
  (ref) => ref.watch(serviceSauvegardeProvider).lister(),
);
