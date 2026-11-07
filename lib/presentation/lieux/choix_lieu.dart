import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/lieux_vente.dart';
import 'lieu_dialogues.dart';
import 'lieux_providers.dart';

/// Résultat de la feuille de choix : un lieu, ou `null` pour « Non renseigné ».
/// (Fermer la feuille sans choisir ne retourne rien du tout : la différence compte.)
class ChoixLieu {
  const ChoixLieu(this.lieuId);

  final int? lieuId;
}

/// Ouvre la feuille « Lieu de vente » : « Non renseigné », les lieux, et « Nouveau lieu de vente ».
/// [lieuIdActuel] est coché. Retourne `null` si on referme la feuille sans rien choisir.
Future<ChoixLieu?> choisirLieu(BuildContext context, {required int? lieuIdActuel}) {
  return showModalBottomSheet<ChoixLieu>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext contexteFeuille) => FeuilleChoixLieu(lieuIdActuel: lieuIdActuel),
  );
}

/// Carte « lieu de vente » : le lieu de la vente (ou « Non renseigné »), un appui ouvre la feuille de choix.
/// Sert au panier (choix avant de valider) et au détail d'une vente (correction après coup).
class LigneChoixLieu extends StatelessWidget {
  const LigneChoixLieu({super.key, required this.lieu, required this.onChoisi, this.charge = true});

  /// `null` = « Non renseigné ».
  final LieuVente? lieu;

  /// Appelé avec l'identifiant du lieu choisi, ou `null` pour « Non renseigné ».
  final void Function(int? lieuId) onChoisi;

  /// Faux tant que la liste des lieux se charge : on n'affiche pas « Non renseigné » pour un lieu qu'on ne connaît pas encore.
  final bool charge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LieuVente? choisi = lieu;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: Icon(choisi == null ? Icons.place_outlined : Icons.storefront_outlined),
        ),
        title: Text(choisi?.nom ?? (charge ? libelleLieuNonRenseigne : '…')),
        subtitle: const Text('Lieu de vente'),
        trailing: const Icon(Icons.unfold_more),
        onTap: () async {
          final ChoixLieu? choix = await choisirLieu(context, lieuIdActuel: choisi?.id);
          if (choix != null && context.mounted) onChoisi(choix.lieuId);
        },
      ),
    );
  }
}

/// Feuille du bas : « Non renseigné », puis les lieux, puis « Nouveau lieu de vente » (le lieu créé est choisi aussitôt).
class FeuilleChoixLieu extends ConsumerWidget {
  const FeuilleChoixLieu({super.key, this.lieuIdActuel});

  final int? lieuIdActuel;

  Future<void> _creer(BuildContext context, WidgetRef ref) async {
    final LieuVente? cree = await demanderNomLieu<LieuVente>(
      context,
      titre: 'Nouveau lieu de vente',
      libelleValider: 'Créer',
      enregistrer: (String nom) => ref.read(lieuVenteRepositoryProvider).creer(nom),
    );
    if (cree != null && context.mounted) Navigator.of(context).pop(ChoixLieu(cree.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LieuVente>> lieux = ref.watch(lieuxVenteProvider);
    final double hauteurMax = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: hauteurMax),
        child: lieux.when(
          loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (Object erreur, StackTrace pile) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Impossible de charger les lieux de vente. ${messageErreur(erreur)}'),
          ),
          data: (List<LieuVente> liste) => ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.place_outlined)),
                title: const Text(libelleLieuNonRenseigne),
                subtitle: const Text('Aucun lieu choisi'),
                selected: lieuIdActuel == null,
                trailing: lieuIdActuel == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(const ChoixLieu(null)),
              ),
              const Divider(height: 1),
              for (final LieuVente l in liste)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)),
                  title: Text(l.nom),
                  selected: lieuIdActuel == l.id,
                  trailing: lieuIdActuel == l.id ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(context).pop(ChoixLieu(l.id)),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: const Text('Nouveau lieu de vente'),
                onTap: () => _creer(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
