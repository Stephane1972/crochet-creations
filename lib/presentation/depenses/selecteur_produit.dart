import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/recherche.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/produit_vues.dart';
import '../produits/produit_widgets.dart';
import '../produits/produits_providers.dart';

/// Résultat de la feuille de choix : un produit, ou `null` pour « aucun produit ».
/// (Fermer la feuille sans choisir ne retourne rien du tout : la différence compte.)
class ChoixProduit {
  const ChoixProduit(this.produit);

  final Produit? produit;
}

/// Ligne « Produit concerné » d'une dépense ; un appui ouvre la liste des produits.
class LigneChoixProduit extends StatelessWidget {
  const LigneChoixProduit({super.key, required this.produit, required this.onChoisi});

  final Produit? produit;
  final void Function(Produit? produit) onChoisi;

  @override
  Widget build(BuildContext context) {
    final Produit? choisi = produit;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: choisi == null
            ? const CircleAvatar(child: Icon(Icons.inventory_2_outlined))
            : ImageProduit(
                chemin: choisi.photoPrincipaleChemin,
                categorie: choisi.categorie,
                largeur: 40,
                hauteur: 40,
              ),
        title: const Text('Produit concerné'),
        subtitle: Text(choisi == null ? 'Aucun produit' : choisi.nom),
        trailing: const Icon(Icons.unfold_more),
        onTap: () async {
          final ChoixProduit? choix = await showModalBottomSheet<ChoixProduit>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (BuildContext contexteFeuille) => FeuilleChoixProduit(produitActuel: choisi),
          );
          if (choix != null && context.mounted) onChoisi(choix.produit);
        },
      ),
    );
  }
}

/// Feuille du bas : « Aucun produit », puis le catalogue (recherche par nom ou référence).
class FeuilleChoixProduit extends ConsumerStatefulWidget {
  const FeuilleChoixProduit({super.key, this.produitActuel});

  final Produit? produitActuel;

  @override
  ConsumerState<FeuilleChoixProduit> createState() => _FeuilleChoixProduitState();
}

class _FeuilleChoixProduitState extends ConsumerState<FeuilleChoixProduit> {
  String _recherche = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ProduitResume>> produits = ref.watch(produitsResumesProvider);
    final double hauteur = MediaQuery.sizeOf(context).height * 0.75;
    final int? idActuel = widget.produitActuel?.id;

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
                decoration: const InputDecoration(hintText: 'Rechercher un produit', prefixIcon: Icon(Icons.search)),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.block)),
              title: const Text('Aucun produit'),
              subtitle: const Text('Dépense générale, sans produit précis'),
              selected: idActuel == null,
              trailing: idActuel == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(const ChoixProduit(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: produits.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object erreur, StackTrace pile) =>
                    const Center(child: Text('Impossible de charger les produits.')),
                data: (List<ProduitResume> tous) {
                  // Les produits archivés ne sont plus proposés, sauf celui déjà lié à la dépense.
                  final List<Produit> visibles = <Produit>[
                    for (final ProduitResume r in tous)
                      if ((r.produit.archiveLe == null || r.produit.id == idActuel) &&
                          correspondALaRecherche(_recherche, <String?>[r.produit.nom, r.produit.reference]))
                        r.produit,
                  ];
                  if (visibles.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _recherche.trim().isEmpty ? 'Aucun produit pour le moment.' : 'Aucun produit trouvé.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: visibles.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Produit p = visibles[index];
                      final bool choisi = p.id == idActuel;
                      return ListTile(
                        leading: ImageProduit(
                          chemin: p.photoPrincipaleChemin,
                          categorie: p.categorie,
                          largeur: 40,
                          hauteur: 40,
                        ),
                        title: Text(p.nom),
                        subtitle: Text(p.reference),
                        selected: choisi,
                        trailing: choisi ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.of(context).pop(ChoixProduit(p)),
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
