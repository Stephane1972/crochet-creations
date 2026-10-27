import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/client_vues.dart';
import '../clients/client_widgets.dart';
import '../clients/clients_providers.dart';
import '../clients/filtres_clients.dart';
import 'panier_provider.dart';

/// Résultat de la feuille de choix : un client, ou `null` pour « client de passage ».
/// (Fermer la feuille sans choisir ne retourne rien du tout : la différence compte.)
class ChoixClient {
  const ChoixClient(this.client);

  final Client? client;
}

/// Ligne « Client : … » de la vente en cours ; un appui ouvre la liste des clients.
class SelecteurClient extends ConsumerWidget {
  const SelecteurClient({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Client? client = ref.watch(venteEnCoursProvider.select((VenteEnCours v) => v.client));
    return LigneChoixClient(
      client: client,
      onChoisi: (Client? choisi) => ref.read(venteEnCoursProvider.notifier).choisirClient(choisi),
    );
  }
}

/// Carte « client » : le client choisi (ou « aucun client »), un appui ouvre la feuille de choix.
/// Sert à la vente (« Client de passage ») et au devis (« Aucun client »).
class LigneChoixClient extends StatelessWidget {
  const LigneChoixClient({
    super.key,
    required this.client,
    required this.onChoisi,
    this.titreAucun = 'Client de passage',
    this.sousTitreAucun = 'Vente rapide, sans fiche client',
  });

  final Client? client;
  final void Function(Client? client) onChoisi;
  final String titreAucun;
  final String sousTitreAucun;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Client? choisi = client;
    final String? coordonnees = choisi == null ? null : resumeCoordonnees(choisi);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: choisi == null
            ? CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
                child: const Icon(Icons.person_outline),
              )
            : PastilleClient(client: choisi, taille: 40),
        title: Text(choisi == null ? titreAucun : libelleClient(choisi)),
        subtitle: Text(
          choisi == null
              ? sousTitreAucun
              : (coordonnees == null || coordonnees.isEmpty ? 'Fiche client' : coordonnees),
        ),
        trailing: const Icon(Icons.unfold_more),
        onTap: () async {
          final ChoixClient? choix = await showModalBottomSheet<ChoixClient>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (BuildContext contexteFeuille) => FeuilleChoixClient(
              clientActuel: choisi,
              titreAucun: titreAucun,
              sousTitreAucun: sousTitreAucun,
            ),
          );
          if (choix != null && context.mounted) onChoisi(choix.client);
        },
      ),
    );
  }
}

/// Feuille du bas : « Client de passage » (ou « Aucun client »), puis les clients (recherche par nom, téléphone...).
class FeuilleChoixClient extends ConsumerStatefulWidget {
  const FeuilleChoixClient({
    super.key,
    this.clientActuel,
    this.titreAucun = 'Client de passage',
    this.sousTitreAucun = 'Vente rapide, sans fiche client',
  });

  final Client? clientActuel;

  /// Première ligne de la liste : choisir « personne » (client de passage, ou devis sans client).
  final String titreAucun;
  final String sousTitreAucun;

  @override
  ConsumerState<FeuilleChoixClient> createState() => _FeuilleChoixClientState();
}

class _FeuilleChoixClientState extends ConsumerState<FeuilleChoixClient> {
  String _recherche = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Client>> clients = ref.watch(clientsProvider);
    final double hauteur = MediaQuery.sizeOf(context).height * 0.75;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: hauteur,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (String valeur) => setState(() => _recherche = valeur),
                decoration: const InputDecoration(
                  hintText: 'Rechercher un client',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(widget.titreAucun),
              subtitle: Text(widget.sousTitreAucun),
              selected: widget.clientActuel == null,
              trailing: widget.clientActuel == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(const ChoixClient(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: clients.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object erreur, StackTrace pile) => const Center(
                  child: Text('Impossible de charger les clients.'),
                ),
                data: (List<Client> tous) {
                  final List<Client> visibles = filtrerClients(
                    tous,
                    const FiltresClients().avecRecherche(_recherche),
                  );
                  if (visibles.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _recherche.trim().isEmpty
                              ? 'Aucune fiche client pour le moment.'
                              : 'Aucun client trouvé.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: visibles.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Client c = visibles[index];
                      final bool choisi = widget.clientActuel?.id == c.id;
                      final String coordonnees = resumeCoordonnees(c);
                      return ListTile(
                        leading: PastilleClient(client: c, taille: 40),
                        title: Text(libelleClient(c)),
                        subtitle: coordonnees.isEmpty ? null : Text(coordonnees),
                        selected: choisi,
                        trailing: choisi ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.of(context).pop(ChoixClient(c)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
