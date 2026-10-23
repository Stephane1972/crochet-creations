import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/calculs/panier.dart';
import '../produits/filtres_produits.dart';
import '../produits/produit_widgets.dart';
import '../produits/produits_providers.dart';
import 'ajout_panier.dart';
import 'panier_provider.dart';
import 'selecteur_client.dart';

/// Nouvelle vente (écran 8, onglet « Vente ») : choix du client, puis des articles à mettre
/// dans le panier. Le récapitulatif, le paiement et la validation sont dans le panier.
class VenteScreen extends ConsumerStatefulWidget {
  const VenteScreen({super.key});

  @override
  ConsumerState<VenteScreen> createState() => _VenteScreenState();
}

class _VenteScreenState extends ConsumerState<VenteScreen> {
  final TextEditingController _recherche = TextEditingController();
  String _texte = '';

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _ajouterProduit(ProduitResume resume) async {
    final bool ajoute = await ajouterAuPanier(context, ref, resume);
    if (ajoute && mounted) afficherMessage(context, '« ${resume.produit.nom} » ajouté au panier.');
  }

  Future<void> _ajouterLigneLibre() async {
    final bool ajoute = await ajouterLigneLibre(context, ref);
    if (ajoute && mounted) afficherMessage(context, 'Article ajouté au panier.');
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ProduitResume>> produits = ref.watch(produitsResumesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle vente')),
      body: Column(
        children: <Widget>[
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: SelecteurClient()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _recherche,
              onChanged: (String valeur) => setState(() => _texte = valeur),
              decoration: InputDecoration(
                hintText: 'Rechercher un produit à vendre',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _texte.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Effacer la recherche',
                        onPressed: () {
                          _recherche.clear();
                          setState(() => _texte = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: produits.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object erreur, StackTrace pile) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Impossible de charger les produits.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => ref.invalidate(produitsResumesProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (List<ProduitResume> tous) {
                final List<ProduitResume> visibles = filtrerProduits(
                  tous,
                  const FiltresProduits().avecRecherche(_texte),
                );
                return _Liste(
                  produits: visibles,
                  catalogueVide: tous.where((ProduitResume r) => r.produit.archiveLe == null).isEmpty,
                  onAjouter: _ajouterProduit,
                  onLigneLibre: _ajouterLigneLibre,
                );
              },
            ),
          ),
          const _BarrePanier(),
        ],
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({
    required this.produits,
    required this.catalogueVide,
    required this.onAjouter,
    required this.onLigneLibre,
  });

  final List<ProduitResume> produits;
  final bool catalogueVide;
  final void Function(ProduitResume resume) onAjouter;
  final VoidCallback onLigneLibre;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      // La première ligne est « Article ou prestation libre » ; ensuite les produits, ou un message.
      itemCount: 1 + (produits.isEmpty ? 1 : produits.length),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Article ou prestation libre'),
                subtitle: const Text('Création sur mesure, cours, frais...'),
                trailing: const Icon(Icons.add),
                onTap: onLigneLibre,
              ),
            ),
          );
        }
        if (produits.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              catalogueVide
                  ? 'Aucun produit au catalogue. Ajoutez-en dans l’onglet Produits, ou utilisez '
                        '« Article ou prestation libre ».'
                  : 'Aucun produit trouvé.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        final ProduitResume resume = produits[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CarteProduitVente(resume: resume, onAjouter: () => onAjouter(resume)),
        );
      },
    );
  }
}

class _CarteProduitVente extends ConsumerWidget {
  const _CarteProduitVente({required this.resume, required this.onAjouter});

  final ProduitResume resume;
  final VoidCallback onAjouter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Produit produit = resume.produit;
    final bool vendable = resume.vendable;

    // Quantité déjà au panier, toutes variantes confondues.
    final int auPanier = ref.watch(
      venteEnCoursProvider.select(
        (VenteEnCours v) => v.panier.lignes
            .where((LignePanier l) => l.produitId == produit.id)
            .fold(0, (int somme, LignePanier l) => somme + l.quantite),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: vendable ? onAjouter : null,
        child: Opacity(
          opacity: vendable ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                ImageProduit(
                  chemin: produit.photoPrincipaleChemin,
                  categorie: produit.categorie,
                  largeur: 56,
                  hauteur: 56,
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
                        '${textePrix(resume)} · ${texteStock(resume)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (auPanier > 0) ...<Widget>[
                        const SizedBox(height: 4),
                        Etiquette(
                          '$auPanier au panier',
                          fond: scheme.primaryContainer,
                          couleurTexte: scheme.onPrimaryContainer,
                          icone: Icons.shopping_basket_outlined,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add_shopping_cart),
                  tooltip: 'Ajouter « ${produit.nom} » au panier',
                  onPressed: vendable ? onAjouter : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre du bas : nombre d'articles, sous-total et accès au panier.
class _BarrePanier extends ConsumerWidget {
  const _BarrePanier();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Panier panier = ref.watch(venteEnCoursProvider.select((VenteEnCours v) => v.panier));
    final ThemeData theme = Theme.of(context);
    final int articles = panier.nombreArticles;
    final int sousTotal = panier.lignes.fold(0, (int somme, LignePanier l) => somme + l.totalCentimes);

    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    articles == 0
                        ? 'Panier vide'
                        : (articles == 1 ? '1 article' : '$articles articles'),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (articles > 0)
                    Text(
                      'Sous-total ${formatEuros(sousTotal)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: articles == 0 ? null : () => Navigator.of(context).pushNamed(AppRoutes.panier),
              icon: const Icon(Icons.shopping_basket_outlined),
              label: const Text('Voir le panier'),
            ),
          ],
        ),
      ),
    );
  }
}
