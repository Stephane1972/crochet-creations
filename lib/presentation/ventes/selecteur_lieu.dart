import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../lieux/choix_lieu.dart';
import '../lieux/lieux_providers.dart';
import 'panier_provider.dart';

/// Ligne « Lieu de vente : … » de la vente en cours ; un appui ouvre la liste des lieux.
class SelecteurLieu extends ConsumerWidget {
  const SelecteurLieu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? lieuId = ref.watch(venteEnCoursProvider.select((VenteEnCours v) => v.lieuId));
    final AsyncValue<List<LieuVente>> lieux = ref.watch(lieuxVenteProvider);
    return LigneChoixLieu(
      lieu: lieuParId(lieux.valueOrNull ?? const <LieuVente>[], lieuId),
      charge: lieux.hasValue,
      onChoisi: (int? choisi) => ref.read(venteEnCoursProvider.notifier).choisirLieu(choisi),
    );
  }
}
