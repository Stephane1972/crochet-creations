import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/enums.dart';
import 'filtres_produits.dart';
import 'produit_widgets.dart';
import 'produits_providers.dart';

/// Onglet « Produits » : catalogue avec recherche, filtres et alertes de stock (écran 3).
class ProduitsScreen extends ConsumerStatefulWidget {
  const ProduitsScreen({super.key});

  @override
  ConsumerState<ProduitsScreen> createState() => _ProduitsScreenState();
}

class _ProduitsScreenState extends ConsumerState<ProduitsScreen> {
  final TextEditingController _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _reinitialiser() {
    _recherche.clear();
    ref.read(filtresProduitsProvider.notifier).reinitialiser();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ProduitResume>> produits = ref.watch(produitsResumesProvider);
    final FiltresProduits filtres = ref.watch(filtresProduitsProvider);

    // Un filtre posé ailleurs (raccourci de l'accueil) doit aussi vider ou remplir le champ de recherche.
    ref.listen<FiltresProduits>(filtresProduitsProvider, (FiltresProduits? avant, FiltresProduits apres) {
      if (_recherche.text != apres.recherche) _recherche.text = apres.recherche;
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Produits'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(
        // Un nom propre à cet onglet : plusieurs onglets pourront avoir leur bouton (étapes suivantes).
        heroTag: 'bouton-ajouter-produit',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.produitNouveau),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _recherche,
              textInputAction: TextInputAction.search,
              onChanged: ref.read(filtresProduitsProvider.notifier).rechercher,
              decoration: InputDecoration(
                hintText: 'Rechercher un produit',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filtres.recherche.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Effacer la recherche',
                        onPressed: () {
                          _recherche.clear();
                          ref.read(filtresProduitsProvider.notifier).rechercher('');
                        },
                      ),
              ),
            ),
          ),
          _BarreFiltres(filtres: filtres, nombreAReapprovisionner: ref.watch(nombreAReapprovisionnerProvider)),
          Expanded(
            child: produits.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object erreur, StackTrace pile) => _Erreur(
                onRetry: () => ref.invalidate(produitsResumesProvider),
              ),
              data: (List<ProduitResume> tous) {
                final List<ProduitResume> visibles = filtrerProduits(tous, filtres);
                if (visibles.isEmpty) {
                  return _ListeVide(
                    catalogueVide: tous.where((ProduitResume r) => r.produit.archiveLe == null).isEmpty &&
                        !filtres.limiteLaListe,
                    onReinitialiser: _reinitialiser,
                  );
                }
                return _Liste(produits: visibles);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BarreFiltres extends ConsumerWidget {
  const _BarreFiltres({required this.filtres, required this.nombreAReapprovisionner});

  final FiltresProduits filtres;
  final int? nombreAReapprovisionner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FiltresProduitsNotifier actions = ref.read(filtresProduitsProvider.notifier);
    final int alertes = nombreAReapprovisionner ?? 0;

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: <Widget>[
          FilterChip(
            label: Text(alertes > 0 ? 'À réapprovisionner ($alertes)' : 'À réapprovisionner'),
            avatar: const Icon(Icons.warning_amber_rounded, size: 18),
            selected: filtres.aReapprovisionner,
            onSelected: (bool _) => actions.basculerReapprovisionner(),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Tous'),
            selected: filtres.categorie == null,
            onSelected: (bool _) => actions.choisirCategorie(null),
          ),
          for (final CategorieProduit c in CategorieProduit.values) ...<Widget>[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(c.libelle),
              selected: filtres.categorie == c,
              onSelected: (bool selectionne) => actions.choisirCategorie(selectionne ? c : null),
            ),
          ],
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Archivés'),
            avatar: const Icon(Icons.archive_outlined, size: 18),
            selected: filtres.archives,
            onSelected: (bool _) => actions.basculerArchives(),
          ),
        ],
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.produits});

  final List<ProduitResume> produits;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Marge en bas : le bouton « Ajouter » ne doit pas cacher le dernier produit.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: produits.length,
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CarteProduit(resume: produits[index]),
        );
      },
    );
  }
}

class _CarteProduit extends StatelessWidget {
  const _CarteProduit({required this.resume});

  final ProduitResume resume;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final Produit produit = resume.produit;
    final List<Widget> etiquettes = etiquettesProduit(context, resume);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.produitFiche, arguments: produit.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ImageProduit(
                chemin: produit.photoPrincipaleChemin,
                categorie: produit.categorie,
                largeur: 72,
                hauteur: 72,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      produit.nom,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${produit.reference} · ${produit.categorie.libelle}',
                      style: theme.textTheme.bodySmall?.copyWith(color: discret),
                    ),
                    if (etiquettes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: etiquettes),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(textePrix(resume), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(texteStock(resume), style: theme.textTheme.bodySmall?.copyWith(color: discret)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeVide extends StatelessWidget {
  const _ListeVide({required this.catalogueVide, required this.onReinitialiser});

  /// Vrai si aucun produit n'existe encore (sinon, c'est la recherche ou un filtre qui ne trouve rien).
  final bool catalogueVide;
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
                catalogueVide ? Icons.inventory_2_outlined : Icons.search_off,
                size: 40,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              catalogueVide ? 'Aucun produit pour le moment' : 'Aucun produit trouvé',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              catalogueVide
                  ? 'Ajoutez votre premier produit avec le bouton « Ajouter ».'
                  : 'Essayez un autre mot, ou retirez les filtres.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (!catalogueVide) ...<Widget>[
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
            const Text('Impossible de charger les produits.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
