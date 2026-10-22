import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/client_vues.dart';
import '../../domain/enums.dart';
import 'client_widgets.dart';
import 'clients_providers.dart';
import 'filtres_clients.dart';

/// Onglet « Clients » : liste et recherche des fiches clients (écran 6).
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final TextEditingController _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _reinitialiser() {
    _recherche.clear();
    ref.read(filtresClientsProvider.notifier).reinitialiser();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Client>> clients = ref.watch(clientsProvider);
    final FiltresClients filtres = ref.watch(filtresClientsProvider);
    final FiltresClientsNotifier actions = ref.read(filtresClientsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Clients'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(
        // Un nom propre à cet onglet : tous les onglets restent construits.
        heroTag: 'bouton-ajouter-client',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.clientNouveau),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Ajouter'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _recherche,
              textInputAction: TextInputAction.search,
              onChanged: actions.rechercher,
              decoration: InputDecoration(
                hintText: 'Rechercher un client',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filtres.recherche.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Effacer la recherche',
                        onPressed: () {
                          _recherche.clear();
                          actions.rechercher('');
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 0,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: filtres.type == null,
                  onSelected: (bool _) => actions.choisirType(null),
                ),
                for (final TypeClient t in TypeClient.values)
                  ChoiceChip(
                    label: Text('${t.libelle}s'),
                    selected: filtres.type == t,
                    onSelected: (bool selectionne) => actions.choisirType(selectionne ? t : null),
                  ),
                FilterChip(
                  label: const Text('Archivés'),
                  avatar: const Icon(Icons.archive_outlined, size: 18),
                  selected: filtres.archives,
                  onSelected: (bool _) => actions.basculerArchives(),
                ),
              ],
            ),
          ),
          Expanded(
            child: clients.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object erreur, StackTrace pile) =>
                  _Erreur(onRetry: () => ref.invalidate(clientsProvider)),
              data: (List<Client> tous) {
                final List<Client> visibles = filtrerClients(tous, filtres);
                if (visibles.isEmpty) {
                  return _ListeVide(
                    annuaireVide:
                        tous.where((Client c) => c.archiveLe == null).isEmpty && !filtres.limiteLaListe,
                    onReinitialiser: _reinitialiser,
                  );
                }
                return _Liste(clients: visibles);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.clients});

  final List<Client> clients;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Marge en bas : le bouton « Ajouter » ne doit pas cacher le dernier client.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: clients.length,
      itemBuilder: (BuildContext context, int index) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _CarteClient(client: clients[index]),
      ),
    );
  }
}

class _CarteClient extends StatelessWidget {
  const _CarteClient({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final String? contact = contactClient(client);
    final String coordonnees = resumeCoordonnees(client);
    final List<Widget> etiquettes = etiquettesClient(context, client);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.clientFiche, arguments: client.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PastilleClient(client: client),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      libelleClient(client),
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contact != null)
                      Text(contact, style: theme.textTheme.bodySmall?.copyWith(color: discret)),
                    if (coordonnees.isNotEmpty)
                      Text(coordonnees, style: theme.textTheme.bodySmall?.copyWith(color: discret)),
                    if (etiquettes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: etiquettes),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: discret),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeVide extends StatelessWidget {
  const _ListeVide({required this.annuaireVide, required this.onReinitialiser});

  /// Vrai si aucun client n'existe encore (sinon, c'est la recherche ou un filtre qui ne trouve rien).
  final bool annuaireVide;
  final VoidCallback onReinitialiser;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(
                annuaireVide ? Icons.people_outline : Icons.search_off,
                size: 40,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              annuaireVide ? 'Aucun client pour le moment' : 'Aucun client trouvé',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              annuaireVide
                  ? 'Ajoutez votre premier client avec le bouton « Ajouter ». '
                        'Pour une vente rapide, vous pourrez aussi choisir « client de passage », sans fiche.'
                  : 'Essayez un autre mot, ou retirez les filtres.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (!annuaireVide) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onReinitialiser, child: const Text('Retirer les filtres')),
            ],
          ],
        ),
      ),
    );
  }
}

class _Erreur extends StatelessWidget {
  const _Erreur({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Impossible de charger les clients.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
