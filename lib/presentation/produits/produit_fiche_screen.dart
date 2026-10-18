import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/duree.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/produit_repository.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/calculs/stock.dart';
import '../../domain/enums.dart';
import '../shell/nav_provider.dart';
import 'produit_widgets.dart';
import 'produits_providers.dart';
import 'stock_dialog.dart';
import 'variante_form_sheet.dart';

enum _ActionMenu { dupliquer, archiver, restaurer }

/// Fiche d'un produit : photos, informations, stock, variantes et historique des ventes (écran 4).
class ProduitFicheScreen extends ConsumerStatefulWidget {
  const ProduitFicheScreen({super.key, required this.produitId});

  final int produitId;

  @override
  ConsumerState<ProduitFicheScreen> createState() => _ProduitFicheScreenState();
}

class _ProduitFicheScreenState extends ConsumerState<ProduitFicheScreen> {
  ProduitRepository get _repo => ref.read(produitRepositoryProvider);

  /// Exécute une action et affiche l'erreur éventuelle en français.
  Future<void> _executer(Future<void> Function() action) async {
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Action sur le produit impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    }
  }

  void _modifier() {
    Navigator.of(context).pushNamed(AppRoutes.produitModifier, arguments: widget.produitId);
  }

  Future<void> _dupliquer() => _executer(() async {
    final Produit copie = await _repo.dupliquer(widget.produitId);
    if (!mounted) return;
    // On ouvre la copie en modification : le plus souvent, on veut la renommer.
    await Navigator.of(context).pushReplacementNamed(AppRoutes.produitModifier, arguments: copie.id);
  });

  Future<void> _archiver(Produit produit) async {
    final bool ok = await confirmer(
      context,
      titre: 'Archiver ce produit ?',
      message:
          '« ${produit.nom} » disparaîtra du catalogue, mais restera dans l’historique des ventes. '
          'Vous pourrez le restaurer à tout moment.',
      libelleConfirmer: 'Archiver',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await _repo.archiver(produit.id);
      if (mounted) afficherMessage(context, 'Produit archivé.');
    });
  }

  Future<void> _restaurer(Produit produit) => _executer(() async {
    await _repo.restaurer(produit.id);
    if (mounted) afficherMessage(context, 'Produit restauré dans le catalogue.');
  });

  Future<void> _ajusterStock(Produit produit, {VarianteProduit? variante}) async {
    final int? quantite = await demanderQuantiteStock(
      context,
      designation: variante == null ? produit.nom : '${produit.nom} – ${variante.libelle}',
      quantiteActuelle: variante?.quantiteStock ?? produit.quantiteStock,
    );
    if (quantite == null || !mounted) return;
    await _executer(() async {
      final int nouveau = await _repo.definirStock(
        produitId: produit.id,
        varianteId: variante?.id,
        quantite: quantite,
      );
      if (mounted) afficherMessage(context, 'Stock mis à jour : $nouveau.');
    });
  }

  Future<void> _ajouterVariante(Produit produit) async {
    final DonneesVariante? donnees = await afficherFormulaireVariante(context);
    if (donnees == null || !mounted) return;
    await _executer(() async {
      await _repo.ajouterVariante(produit.id, donnees);
      if (mounted) afficherMessage(context, 'Variante ajoutée.');
    });
  }

  Future<void> _modifierVariante(VarianteProduit variante) async {
    final DonneesVariante? donnees = await afficherFormulaireVariante(context, variante: variante);
    if (donnees == null || !mounted) return;
    await _executer(() async {
      await _repo.modifierVariante(variante.id, donnees);
      if (mounted) afficherMessage(context, 'Variante modifiée.');
    });
  }

  Future<void> _archiverVariante(VarianteProduit variante) async {
    final bool ok = await confirmer(
      context,
      titre: 'Archiver cette variante ?',
      message:
          '« ${variante.libelle} » ne sera plus proposée à la vente. '
          'Vous pourrez la restaurer à tout moment.',
      libelleConfirmer: 'Archiver',
    );
    if (!ok || !mounted) return;
    await _executer(() => _repo.archiverVariante(variante.id));
  }

  Future<void> _restaurerVariante(VarianteProduit variante) =>
      _executer(() => _repo.restaurerVariante(variante.id));

  /// Les écrans de vente arrivent à l'étape 5 : en attendant, on ouvre l'onglet « Vente ».
  void _versLaVente() {
    ref.read(navIndexProvider.notifier).aller(OngletsNav.vente);
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ProduitDetail?> detail = ref.watch(produitDetailProvider(widget.produitId));
    final ProduitDetail? donnees = detail.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(donnees?.produit.nom ?? 'Produit', overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (donnees != null) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifier',
              onPressed: _modifier,
            ),
            PopupMenuButton<_ActionMenu>(
              tooltip: 'Plus d’actions',
              onSelected: (_ActionMenu action) {
                switch (action) {
                  case _ActionMenu.dupliquer:
                    _dupliquer();
                  case _ActionMenu.archiver:
                    _archiver(donnees.produit);
                  case _ActionMenu.restaurer:
                    _restaurer(donnees.produit);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<_ActionMenu>>[
                const PopupMenuItem<_ActionMenu>(
                  value: _ActionMenu.dupliquer,
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Dupliquer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (donnees.produit.archiveLe == null)
                  const PopupMenuItem<_ActionMenu>(
                    value: _ActionMenu.archiver,
                    child: ListTile(
                      leading: Icon(Icons.archive_outlined),
                      title: Text('Archiver'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else
                  const PopupMenuItem<_ActionMenu>(
                    value: _ActionMenu.restaurer,
                    child: ListTile(
                      leading: Icon(Icons.unarchive_outlined),
                      title: Text('Restaurer'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger ce produit.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(produitDetailProvider(widget.produitId)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (ProduitDetail? d) {
          if (d == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Ce produit n’existe plus.', textAlign: TextAlign.center),
              ),
            );
          }
          return _Contenu(
            detail: d,
            onAjusterStock: ({VarianteProduit? variante}) => _ajusterStock(d.produit, variante: variante),
            onAjouterVariante: () => _ajouterVariante(d.produit),
            onModifierVariante: _modifierVariante,
            onArchiverVariante: _archiverVariante,
            onRestaurerVariante: _restaurerVariante,
            onRestaurerProduit: () => _restaurer(d.produit),
          );
        },
      ),
      bottomNavigationBar: donnees == null
          ? null
          : _BarreVente(
              resume: donnees.resume,
              onVendre: _versLaVente,
              onAjouterAuPanier: _versLaVente,
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Barre d'actions du bas
// -----------------------------------------------------------------------------

class _BarreVente extends StatelessWidget {
  const _BarreVente({required this.resume, required this.onVendre, required this.onAjouterAuPanier});

  final ProduitResume resume;
  final VoidCallback onVendre;
  final VoidCallback onAjouterAuPanier;

  String? get _raison {
    if (resume.produit.archiveLe != null) return 'Produit archivé : restaurez-le pour le vendre.';
    if (resume.produit.statut == StatutProduit.epuise) return 'Ce produit est marqué « épuisé ».';
    if (!resume.vendable) return 'Il n’en reste plus en stock : ajustez le stock pour le vendre.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool vendable = resume.vendable;
    final String? raison = _raison;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (raison != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    raison,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: vendable ? onAjouterAuPanier : null,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Ajouter au panier'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: vendable ? onVendre : null,
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Vendre'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Contenu
// -----------------------------------------------------------------------------

typedef _AjusterStock = void Function({VarianteProduit? variante});

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.detail,
    required this.onAjusterStock,
    required this.onAjouterVariante,
    required this.onModifierVariante,
    required this.onArchiverVariante,
    required this.onRestaurerVariante,
    required this.onRestaurerProduit,
  });

  final ProduitDetail detail;
  final _AjusterStock onAjusterStock;
  final VoidCallback onAjouterVariante;
  final ValueChanged<VarianteProduit> onModifierVariante;
  final ValueChanged<VarianteProduit> onArchiverVariante;
  final ValueChanged<VarianteProduit> onRestaurerVariante;
  final VoidCallback onRestaurerProduit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ProduitResume resume = detail.resume;
    final Produit produit = detail.produit;
    final List<Widget> etiquettes = etiquettesProduit(context, resume);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _Galerie(
          chemins: detail.cheminsPhotos,
          categorie: produit.categorie,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (produit.archiveLe != null) ...<Widget>[
                _BandeauArchive(onRestaurer: onRestaurerProduit),
                const SizedBox(height: 12),
              ],
              Text(produit.nom, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${produit.reference} · ${produit.categorie.libelle}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                textePrix(resume),
                style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary),
              ),
              if (etiquettes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: etiquettes),
              ],
              const SizedBox(height: 16),
              _CarteDetails(produit: produit),
              const SizedBox(height: 12),
              _CarteStock(detail: detail, onAjuster: () => onAjusterStock()),
              const SizedBox(height: 12),
              _CarteVariantes(
                detail: detail,
                onAjouter: onAjouterVariante,
                onAjusterStock: (VarianteProduit v) => onAjusterStock(variante: v),
                onModifier: onModifierVariante,
                onArchiver: onArchiverVariante,
                onRestaurer: onRestaurerVariante,
              ),
              const SizedBox(height: 12),
              _CarteHistorique(produitId: produit.id),
            ],
          ),
        ),
      ],
    );
  }
}

class _BandeauArchive extends StatelessWidget {
  const _BandeauArchive({required this.onRestaurer});

  final VoidCallback onRestaurer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.archive_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Produit archivé : il n’apparaît plus dans le catalogue.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onRestaurer, child: const Text('Restaurer')),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Photos
// -----------------------------------------------------------------------------

class _Galerie extends StatefulWidget {
  const _Galerie({required this.chemins, required this.categorie});

  final List<String> chemins;
  final CategorieProduit categorie;

  @override
  State<_Galerie> createState() => _GalerieState();
}

class _GalerieState extends State<_Galerie> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int nombre = widget.chemins.isEmpty ? 1 : widget.chemins.length;

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            itemCount: nombre,
            onPageChanged: (int page) => setState(() => _page = page),
            itemBuilder: (BuildContext context, int index) => ImageProduit(
              chemin: widget.chemins.isEmpty ? null : widget.chemins[index],
              categorie: widget.categorie,
              rayon: 0,
              largeur: double.infinity,
              hauteur: double.infinity,
            ),
          ),
          if (nombre > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < nombre; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page ? scheme.primary : scheme.surface.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cartes d'informations
// -----------------------------------------------------------------------------

class _CarteSection extends StatelessWidget {
  const _CarteSection({required this.titre, required this.child, this.action});

  final String titre;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(titre, style: Theme.of(context).textTheme.titleMedium)),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  const _LigneInfo(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              libelle,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(valeur, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _CarteDetails extends StatelessWidget {
  const _CarteDetails({required this.produit});

  final Produit produit;

  @override
  Widget build(BuildContext context) {
    final int? minutes = produit.tempsFabricationMinutes;

    return _CarteSection(
      titre: 'Informations',
      child: Column(
        children: <Widget>[
          _LigneInfo('Statut', produit.statut.libelle),
          if (produit.description != null) _LigneInfo('Description', produit.description!),
          if (produit.matieres != null) _LigneInfo('Matières', produit.matieres!),
          if (produit.couleur != null) _LigneInfo('Couleur', produit.couleur!),
          if (produit.dimensions != null) _LigneInfo('Taille / dimensions', produit.dimensions!),
          if (minutes != null) _LigneInfo('Temps de fabrication', formatDuree(minutes)),
          _LigneInfo('Coût des matières', formatEuros(produit.coutMatiereCentimes)),
          _LigneInfo('Personnalisable', produit.personnalisable ? 'Oui' : 'Non'),
        ],
      ),
    );
  }
}

class _CarteStock extends StatelessWidget {
  const _CarteStock({required this.detail, required this.onAjuster});

  final ProduitDetail detail;
  final VoidCallback onAjuster;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final ProduitResume resume = detail.resume;
    final Produit produit = detail.produit;

    if (!suitLeStock(produit.statut)) {
      return _CarteSection(
        titre: 'Stock',
        child: Text(
          'Produit sur commande : il est fabriqué à la demande, son stock n’est pas suivi.',
          style: theme.textTheme.bodyMedium?.copyWith(color: discret),
        ),
      );
    }

    final String seuil = produit.seuilAlerteStock > 0
        ? 'Alerte quand il en reste ${produit.seuilAlerteStock} ou moins.'
        : 'Alerte seulement quand il n’en reste plus.';

    return _CarteSection(
      titre: 'Stock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            texteStock(resume),
            style: theme.textTheme.headlineSmall,
            key: const ValueKey<String>('stock-total'),
          ),
          const SizedBox(height: 4),
          Text(seuil, style: theme.textTheme.bodyMedium?.copyWith(color: discret)),
          if (resume.aDesVariantes) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Total de ${resume.variantes.length} variantes : le stock se règle variante par variante.',
              style: theme.textTheme.bodyMedium?.copyWith(color: discret),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAjuster,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Ajuster le stock'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CarteVariantes extends StatelessWidget {
  const _CarteVariantes({
    required this.detail,
    required this.onAjouter,
    required this.onAjusterStock,
    required this.onModifier,
    required this.onArchiver,
    required this.onRestaurer,
  });

  final ProduitDetail detail;
  final VoidCallback onAjouter;
  final ValueChanged<VarianteProduit> onAjusterStock;
  final ValueChanged<VarianteProduit> onModifier;
  final ValueChanged<VarianteProduit> onArchiver;
  final ValueChanged<VarianteProduit> onRestaurer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final List<VarianteProduit> actives = detail.variantesActives;
    final List<VarianteProduit> archivees = detail.variantesArchivees;

    return _CarteSection(
      titre: 'Variantes',
      action: TextButton.icon(
        onPressed: onAjouter,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (actives.isEmpty)
            Text(
              'Aucune variante. Ajoutez-en pour suivre le stock par couleur ou par taille '
              '(le stock du produit est alors remplacé par celui de ses variantes).',
              style: theme.textTheme.bodyMedium?.copyWith(color: discret),
            ),
          for (final VarianteProduit v in actives)
            _TuileVariante(
              variante: v,
              produit: detail.produit,
              suivreStock: suitLeStock(detail.produit.statut),
              onAjusterStock: () => onAjusterStock(v),
              onModifier: () => onModifier(v),
              onArchiver: () => onArchiver(v),
            ),
          if (archivees.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Variantes archivées (${archivees.length})'),
              children: <Widget>[
                for (final VarianteProduit v in archivees)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.libelle),
                    trailing: TextButton(
                      onPressed: () => onRestaurer(v),
                      child: const Text('Restaurer'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _ActionVariante { stock, modifier, archiver }

class _TuileVariante extends StatelessWidget {
  const _TuileVariante({
    required this.variante,
    required this.produit,
    required this.suivreStock,
    required this.onAjusterStock,
    required this.onModifier,
    required this.onArchiver,
  });

  final VarianteProduit variante;
  final Produit produit;
  final bool suivreStock;
  final VoidCallback onAjusterStock;
  final VoidCallback onModifier;
  final VoidCallback onArchiver;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final EtatStock etat = etatStock(
      quantite: variante.quantiteStock,
      seuilAlerte: variante.seuilAlerteStock ?? produit.seuilAlerteStock,
    );
    final String details = <String>[
      if (variante.couleur != null) variante.couleur!,
      if (variante.taille != null) variante.taille!,
      formatEuros(variante.prixCentimes ?? produit.prixVenteCentimes),
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(variante.libelle),
      subtitle: Text(details),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (suivreStock)
            Etiquette(
              '${variante.quantiteStock}',
              fond: switch (etat) {
                EtatStock.epuise => scheme.errorContainer,
                EtatStock.faible => scheme.tertiaryContainer,
                EtatStock.suffisant => scheme.secondaryContainer,
              },
              couleurTexte: switch (etat) {
                EtatStock.epuise => scheme.onErrorContainer,
                EtatStock.faible => scheme.onTertiaryContainer,
                EtatStock.suffisant => scheme.onSecondaryContainer,
              },
            ),
          PopupMenuButton<_ActionVariante>(
            tooltip: 'Actions sur la variante ${variante.libelle}',
            onSelected: (_ActionVariante action) {
              switch (action) {
                case _ActionVariante.stock:
                  onAjusterStock();
                case _ActionVariante.modifier:
                  onModifier();
                case _ActionVariante.archiver:
                  onArchiver();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<_ActionVariante>>[
              if (suivreStock)
                const PopupMenuItem<_ActionVariante>(
                  value: _ActionVariante.stock,
                  child: Text('Ajuster le stock'),
                ),
              const PopupMenuItem<_ActionVariante>(
                value: _ActionVariante.modifier,
                child: Text('Modifier'),
              ),
              const PopupMenuItem<_ActionVariante>(
                value: _ActionVariante.archiver,
                child: Text('Archiver'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Historique des ventes
// -----------------------------------------------------------------------------

class _CarteHistorique extends ConsumerStatefulWidget {
  const _CarteHistorique({required this.produitId});

  final int produitId;

  @override
  ConsumerState<_CarteHistorique> createState() => _CarteHistoriqueState();
}

class _CarteHistoriqueState extends ConsumerState<_CarteHistorique> {
  static const int _apercu = 5;
  bool _toutVoir = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final AsyncValue<List<LigneHistoriqueVente>> historique = ref.watch(
      historiqueProduitProvider(widget.produitId),
    );

    return _CarteSection(
      titre: 'Historique des ventes',
      child: historique.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (Object erreur, StackTrace pile) =>
            const Text('Impossible de charger l’historique des ventes.'),
        data: (List<LigneHistoriqueVente> lignes) {
          if (lignes.isEmpty) {
            return Text(
              'Aucune vente pour ce produit pour l’instant.',
              style: theme.textTheme.bodyMedium?.copyWith(color: discret),
            );
          }
          final List<LigneHistoriqueVente> visibles = _toutVoir
              ? lignes
              : lignes.take(_apercu).toList();
          final int quantiteTotale = lignes.fold(0, (int s, LigneHistoriqueVente l) => s + l.quantite);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$quantiteTotale vendu${quantiteTotale > 1 ? 's' : ''} '
                'en ${lignes.length} vente${lignes.length > 1 ? 's' : ''}',
                style: theme.textTheme.bodyMedium?.copyWith(color: discret),
              ),
              for (final LigneHistoriqueVente l in visibles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.designation),
                  subtitle: Text(
                    '${formatDateCourte(l.dateVente)} · ${l.quantite} × ${formatEuros(l.prixUnitaireCentimes)}'
                    '${l.clientNom == null ? '' : ' · ${l.clientNom}'}',
                  ),
                  trailing: Text(
                    formatEuros(l.totalLigneCentimes),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              if (lignes.length > _apercu)
                TextButton(
                  onPressed: () => setState(() => _toutVoir = !_toutVoir),
                  child: Text(_toutVoir ? 'Voir moins' : 'Voir les ${lignes.length} ventes'),
                ),
            ],
          );
        },
      ),
    );
  }
}
