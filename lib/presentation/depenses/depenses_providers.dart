import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/depense_vues.dart';

/// Les dépenses d'un mois (éventuellement d'une catégorie, ou archivées), mises à jour automatiquement.
final depensesListeProvider = StreamProvider.autoDispose.family<ListeDepenses, FiltreDepenses>(
  (ref, FiltreDepenses filtre) => ref
      .watch(depenseRepositoryProvider)
      .observerListe(
        annee: filtre.annee,
        mois: filtre.mois,
        categorie: filtre.categorie,
        archivees: filtre.archivees,
      ),
);
