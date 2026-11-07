import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/lieu_vente_repository.dart';
import '../../domain/lieux_vente.dart';
import 'lieu_dialogues.dart';
import 'lieux_providers.dart';

/// Réglages › Lieux de vente : ajouter, renommer et supprimer les lieux où l'on vend (marché, salon, boutique...).
///
/// Supprimer un lieu qui a des ventes demande où les déplacer (un autre lieu, ou « Non renseigné ») : aucune vente
/// n'est jamais supprimée ni perdue.
class LieuxScreen extends ConsumerWidget {
  const LieuxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LieuVente>> lieux = ref.watch(lieuxVenteProvider);
    final Map<int, int> comptes = ref.watch(nombreVentesParLieuProvider).valueOrNull ?? const <int, int>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Lieux de vente')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'bouton-ajouter-lieu',
        onPressed: () => _ajouter(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau lieu'),
      ),
      body: lieux.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Les lieux de vente n’ont pas pu être chargés. Quittez cet écran et rouvrez-le.'),
          ),
        ),
        data: (List<LieuVente> liste) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            Text(
              'Chaque vente peut porter un lieu (marché, salon, boutique, vente en ligne...). Renommer un lieu '
              'change son nom partout ; en supprimer un déplace ses ventes dans un autre lieu, ou dans '
              '« $libelleLieuNonRenseigne ». Aucune vente n’est jamais supprimée.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (liste.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Aucun lieu de vente. Créez-en un avec « Nouveau lieu ».')),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < liste.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _LigneLieu(
                        lieu: liste[i],
                        nombreVentes: comptes[liste[i].id] ?? 0,
                        onRenommer: () => _renommer(context, ref, liste[i]),
                        onSupprimer: () => _supprimer(context, ref, liste[i], liste),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _ajouter(BuildContext context, WidgetRef ref) async {
    final LieuVente? cree = await demanderNomLieu<LieuVente>(
      context,
      titre: 'Nouveau lieu de vente',
      libelleValider: 'Créer',
      enregistrer: (String nom) => ref.read(lieuVenteRepositoryProvider).creer(nom),
    );
    if (cree != null && context.mounted) afficherMessage(context, 'Lieu « ${cree.nom} » créé.');
  }

  Future<void> _renommer(BuildContext context, WidgetRef ref, LieuVente lieu) async {
    final LieuVente? renomme = await demanderNomLieu<LieuVente>(
      context,
      titre: 'Renommer le lieu',
      libelleValider: 'Enregistrer',
      nomInitial: lieu.nom,
      enregistrer: (String nom) => ref.read(lieuVenteRepositoryProvider).renommer(lieu.id, nom),
    );
    if (renomme != null && context.mounted) afficherMessage(context, 'Lieu renommé « ${renomme.nom} ».');
  }

  Future<void> _supprimer(BuildContext context, WidgetRef ref, LieuVente lieu, List<LieuVente> tous) async {
    final LieuVenteRepository repo = ref.read(lieuVenteRepositoryProvider);
    try {
      // Le nombre exact se lit en base au moment de supprimer (la liste affichée peut avoir une seconde de retard).
      final int nombre = await repo.nombreVentes(lieu.id);
      if (!context.mounted) return;

      DestinationVentes? destination;
      if (nombre == 0) {
        final bool ok = await confirmer(
          context,
          titre: 'Supprimer ce lieu ?',
          message: 'Le lieu « ${lieu.nom} » n’a aucune vente. Il sera supprimé.',
          libelleConfirmer: 'Supprimer',
        );
        if (!ok) return;
      } else {
        final List<LieuVente> autres = tous.where((LieuVente l) => l.id != lieu.id).toList();
        destination = await showDialog<DestinationVentes>(
          context: context,
          builder: (BuildContext contexteDialogue) =>
              _DialogueDeplacement(lieu: lieu, nombreVentes: nombre, destinations: autres),
        );
        if (destination == null) return;
      }

      final int deplacees = await repo.supprimer(lieu.id, deplacerVers: destination);

      if (!context.mounted) return;
      if (deplacees > 0) {
        final int? versId = destination?.lieuId;
        final String nomDestination = versId == null
            ? libelleLieuNonRenseigne
            : tous.firstWhere((LieuVente l) => l.id == versId).nom;
        afficherMessage(
          context,
          'Lieu « ${lieu.nom} » supprimé. ${_ventes(deplacees)} '
          '${deplacees > 1 ? 'déplacées' : 'déplacée'} vers « $nomDestination ».',
        );
      } else {
        afficherMessage(context, 'Lieu « ${lieu.nom} » supprimé.');
      }
    } catch (erreur) {
      if (context.mounted) afficherMessage(context, messageErreur(erreur));
    }
  }
}

String _ventes(int n) => n > 1 ? '$n ventes' : '1 vente';

class _LigneLieu extends StatelessWidget {
  const _LigneLieu({
    required this.lieu,
    required this.nombreVentes,
    required this.onRenommer,
    required this.onSupprimer,
  });

  final LieuVente lieu;
  final int nombreVentes;
  final VoidCallback onRenommer;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.storefront_outlined, color: scheme.primary),
      title: Text(lieu.nom),
      subtitle: Text(nombreVentes == 0 ? 'Aucune vente' : _ventes(nombreVentes)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Renommer ${lieu.nom}',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onRenommer,
          ),
          IconButton(
            tooltip: 'Supprimer ${lieu.nom}',
            icon: const Icon(Icons.delete_outline),
            onPressed: onSupprimer,
          ),
        ],
      ),
    );
  }
}

/// Où déplacer les ventes d'un lieu qu'on supprime : un autre lieu, ou « Non renseigné ». Aucune destination n'est
/// présélectionnée : il faut choisir, pour ne pas déplacer des ventes par mégarde.
class _DialogueDeplacement extends StatefulWidget {
  const _DialogueDeplacement({required this.lieu, required this.nombreVentes, required this.destinations});

  final LieuVente lieu;
  final int nombreVentes;
  final List<LieuVente> destinations;

  @override
  State<_DialogueDeplacement> createState() => _DialogueDeplacementState();
}

class _DialogueDeplacementState extends State<_DialogueDeplacement> {
  /// `null` = pas encore choisi ; sinon la destination retenue.
  DestinationVentes? _choix;

  bool _estChoisi(int? lieuId) => _choix != null && _choix!.lieuId == lieuId;

  @override
  Widget build(BuildContext context) {
    final int n = widget.nombreVentes;
    return AlertDialog(
      title: const Text('Supprimer ce lieu ?'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Le lieu « ${widget.lieu.nom} » contient ${_ventes(n)}. '
              'Choisissez où ${n > 1 ? 'les' : 'la'} déplacer : aucune vente n’est supprimée.',
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (final LieuVente l in widget.destinations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: _estChoisi(l.id),
                        leading: Icon(_estChoisi(l.id) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        title: Text(l.nom),
                        onTap: () => setState(() => _choix = DestinationVentes.lieu(l.id)),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: _estChoisi(null),
                      leading: Icon(_estChoisi(null) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      title: const Text(libelleLieuNonRenseigne),
                      subtitle: const Text('Les ventes n’auront plus de lieu'),
                      onTap: () => setState(() => _choix = const DestinationVentes.nonRenseigne()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _choix == null ? null : () => Navigator.of(context).pop(_choix),
          child: const Text('Déplacer et supprimer'),
        ),
      ],
    );
  }
}
