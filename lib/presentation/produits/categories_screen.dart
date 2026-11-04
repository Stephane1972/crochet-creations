import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/categorie_repository.dart';
import 'categorie_dialogues.dart';
import 'categories_providers.dart';
import 'filtres_produits.dart';
import 'produit_widgets.dart';

/// Réglages › Catégories : ajouter, renommer et supprimer les catégories de produits.
///
/// Supprimer une catégorie qui contient des produits demande où les déplacer : aucun produit n'est jamais perdu
/// ni laissé sans catégorie.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategorieProduit>> categories = ref.watch(categoriesProduitProvider);
    final Map<String, int> comptes = ref.watch(nombreProduitsParCategorieProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Catégories')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'bouton-ajouter-categorie',
        onPressed: () => _ajouter(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle catégorie'),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Les catégories n’ont pas pu être chargées. Quittez cet écran et rouvrez-le.'),
          ),
        ),
        data: (List<CategorieProduit> liste) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            Text(
              'Les catégories classent vos produits (liste, filtres, statistiques). Renommer une catégorie change '
              'son nom partout ; en supprimer une déplace ses produits dans une autre.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (liste.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Aucune catégorie. Créez-en une avec « Nouvelle catégorie ».')),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < liste.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _LigneCategorie(
                        categorie: liste[i],
                        nombreProduits: comptes[liste[i].cle] ?? 0,
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
    final CategorieProduit? creee = await demanderNomCategorie<CategorieProduit>(
      context,
      titre: 'Nouvelle catégorie',
      libelleValider: 'Créer',
      enregistrer: (String nom) => ref.read(categorieRepositoryProvider).creer(nom),
    );
    if (creee != null && context.mounted) afficherMessage(context, 'Catégorie « ${creee.nom} » créée.');
  }

  Future<void> _renommer(BuildContext context, WidgetRef ref, CategorieProduit categorie) async {
    final CategorieProduit? renommee = await demanderNomCategorie<CategorieProduit>(
      context,
      titre: 'Renommer la catégorie',
      libelleValider: 'Enregistrer',
      nomInitial: categorie.nom,
      enregistrer: (String nom) => ref.read(categorieRepositoryProvider).renommer(categorie.id, nom),
    );
    if (renommee != null && context.mounted) afficherMessage(context, 'Catégorie renommée « ${renommee.nom} ».');
  }

  Future<void> _supprimer(
    BuildContext context,
    WidgetRef ref,
    CategorieProduit categorie,
    List<CategorieProduit> toutes,
  ) async {
    final CategorieRepository repo = ref.read(categorieRepositoryProvider);
    try {
      // Le nombre exact se lit en base au moment de supprimer (la liste affichée peut avoir une seconde de retard).
      final int nombre = await repo.nombreProduits(categorie.cle);
      if (!context.mounted) return;

      String? destination;
      if (nombre == 0) {
        final bool ok = await confirmer(
          context,
          titre: 'Supprimer cette catégorie ?',
          message: 'La catégorie « ${categorie.nom} » ne contient aucun produit. Elle sera supprimée.',
          libelleConfirmer: 'Supprimer',
        );
        if (!ok) return;
      } else {
        final List<CategorieProduit> autres = toutes.where((CategorieProduit c) => c.id != categorie.id).toList();
        if (autres.isEmpty) {
          await informer(
            context,
            titre: 'Suppression impossible',
            message:
                'La catégorie « ${categorie.nom} » contient ${_produits(nombre)} et c’est la seule catégorie. '
                'Créez d’abord une autre catégorie : ${nombre > 1 ? 'les produits y seront déplacés' : 'le produit y sera déplacé'}.',
          );
          return;
        }
        destination = await showDialog<String>(
          context: context,
          builder: (BuildContext contexteDialogue) =>
              _DialogueDeplacement(categorie: categorie, nombreProduits: nombre, destinations: autres),
        );
        if (destination == null) return;
      }

      final int deplaces = await repo.supprimer(categorie.id, deplacerVersCle: destination);

      // Le filtre de la liste des produits ne doit pas rester sur une catégorie qui n'existe plus.
      final FiltresProduitsNotifier filtres = ref.read(filtresProduitsProvider.notifier);
      if (ref.read(filtresProduitsProvider).categorie == categorie.cle) filtres.choisirCategorie(null);

      if (!context.mounted) return;
      if (deplaces > 0) {
        final String nomDestination = toutes.firstWhere((CategorieProduit c) => c.cle == destination).nom;
        afficherMessage(
          context,
          'Catégorie « ${categorie.nom} » supprimée. ${_produits(deplaces)} '
          '${deplaces > 1 ? 'déplacés' : 'déplacé'} vers « $nomDestination ».',
        );
      } else {
        afficherMessage(context, 'Catégorie « ${categorie.nom} » supprimée.');
      }
    } catch (erreur) {
      if (context.mounted) afficherMessage(context, messageErreur(erreur));
    }
  }
}

String _produits(int n) => n > 1 ? '$n produits' : '1 produit';

class _LigneCategorie extends StatelessWidget {
  const _LigneCategorie({
    required this.categorie,
    required this.nombreProduits,
    required this.onRenommer,
    required this.onSupprimer,
  });

  final CategorieProduit categorie;
  final int nombreProduits;
  final VoidCallback onRenommer;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(iconeCategorie(categorie.cle), color: scheme.primary),
      title: Text(categorie.nom),
      subtitle: Text(nombreProduits == 0 ? 'Aucun produit' : _produits(nombreProduits)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Renommer ${categorie.nom}',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onRenommer,
          ),
          IconButton(
            tooltip: 'Supprimer ${categorie.nom}',
            icon: const Icon(Icons.delete_outline),
            onPressed: onSupprimer,
          ),
        ],
      ),
    );
  }
}

/// Où déplacer les produits d'une catégorie qu'on supprime. Aucune destination n'est présélectionnée : il faut
/// choisir, pour ne pas déplacer des produits par mégarde.
class _DialogueDeplacement extends StatefulWidget {
  const _DialogueDeplacement({required this.categorie, required this.nombreProduits, required this.destinations});

  final CategorieProduit categorie;
  final int nombreProduits;
  final List<CategorieProduit> destinations;

  @override
  State<_DialogueDeplacement> createState() => _DialogueDeplacementState();
}

class _DialogueDeplacementState extends State<_DialogueDeplacement> {
  String? _choix;

  @override
  Widget build(BuildContext context) {
    final int n = widget.nombreProduits;
    return AlertDialog(
      title: const Text('Supprimer cette catégorie ?'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'La catégorie « ${widget.categorie.nom} » contient ${_produits(n)}. '
              'Choisissez la catégorie où ${n > 1 ? 'les' : 'le'} déplacer.',
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (final CategorieProduit c in widget.destinations)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: _choix == c.cle,
                        leading: Icon(_choix == c.cle ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        title: Text(c.nom),
                        onTap: () => setState(() => _choix = c.cle),
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
