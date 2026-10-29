import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/cours_vues.dart';

/// Les cours du filtre choisi (à venir, passés, archivés), mis à jour automatiquement.
final coursListeProvider = StreamProvider.autoDispose.family<List<CoursResume>, FiltreCours>(
  (ref, FiltreCours filtre) => ref.watch(coursRepositoryProvider).observerListe(filtre: filtre),
);

/// La fiche d'un cours avec ses inscrits (`null` s'il n'existe pas), mise à jour automatiquement.
final coursDetailProvider = StreamProvider.autoDispose.family<CoursDetail?, int>(
  (ref, int id) => ref.watch(coursRepositoryProvider).observerDetail(id),
);
