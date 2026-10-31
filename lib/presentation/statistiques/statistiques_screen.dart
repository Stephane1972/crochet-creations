import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../data/repositories/produit_vues.dart';
import '../../data/repositories/statistiques_vues.dart';
import '../../domain/calculs/statistiques.dart';
import '../../domain/calculs/stock.dart';
import '../depenses/depenses_widgets.dart';
import '../produits/produits_providers.dart';
import 'franchise_tva_carte.dart';
import 'statistiques_providers.dart';

/// Statistiques (écran 20) : ce que rapporte l'activité sur le jour, la semaine, le mois ou l'année en cours.
///
/// Le chiffre d'affaires est l'**argent réellement encaissé** (remboursements déduits) ; la marge estimée est cet
/// argent moins le coût de la matière des articles vendus. Les dépenses sont présentées à part.
class StatistiquesScreen extends ConsumerStatefulWidget {
  const StatistiquesScreen({super.key});

  @override
  ConsumerState<StatistiquesScreen> createState() => _StatistiquesScreenState();
}

class _StatistiquesScreenState extends ConsumerState<StatistiquesScreen> {
  PeriodeStats _periode = PeriodeStats.mois;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Statistiques> stats = ref.watch(statistiquesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de calculer les statistiques.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(statistiquesProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (Statistiques donnees) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            SegmentedButton<PeriodeStats>(
              segments: <ButtonSegment<PeriodeStats>>[
                for (final PeriodeStats p in PeriodeStats.values)
                  ButtonSegment<PeriodeStats>(value: p, label: Text(p.libelle)),
              ],
              selected: <PeriodeStats>{_periode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<PeriodeStats> choix) => setState(() => _periode = choix.first),
            ),
            const SizedBox(height: 12),
            _Periode(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            _ChiffreAffaires(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            _Marge(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            _PanierEtCours(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            _MeilleuresVentes(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            _CategoriesRentables(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            _Depenses(stats: donnees.periode(_periode)),
            const SizedBox(height: 12),
            const _StockFaible(),
            const SizedBox(height: 12),
            _FacturesImpayees(stats: donnees),
            const SizedBox(height: 12),
            const FranchiseTvaCarte(),
          ],
        ),
      ),
    );
  }
}

/// « Ce mois-ci · octobre 2026 ».
class _Periode extends StatelessWidget {
  const _Periode({required this.stats});

  final StatsPeriode stats;

  String get _libelle {
    switch (stats.periode) {
      case PeriodeStats.jour:
        return formatDateLongue(stats.debut);
      case PeriodeStats.semaine:
        final DateTime dernierJour = DateTime(stats.fin.year, stats.fin.month, stats.fin.day - 1);
        return 'du ${formatDateCourte(stats.debut)} au ${formatDateCourte(dernierJour)}';
      case PeriodeStats.mois:
        return formatMois(stats.debut.year, stats.debut.month);
      case PeriodeStats.annee:
        return '${stats.debut.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '${stats.periode.libelleCourant} · $_libelle',
        key: const Key('stat-periode'),
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Briques communes
// -----------------------------------------------------------------------------

/// Une carte avec un titre et, en dessous, son contenu.
class _Section extends StatelessWidget {
  const _Section({required this.titre, required this.enfants, this.legende, this.onTap});

  final String titre;
  final List<Widget> enfants;

  /// Précision discrète sous le titre.
  final String? legende;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(titre, style: theme.textTheme.titleMedium),
              if (legende != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  legende!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              ...enfants,
            ],
          ),
        ),
      ),
    );
  }
}

/// Un libellé et son montant, sur une ligne.
class _LigneMontant extends StatelessWidget {
  const _LigneMontant({required this.libelle, required this.centimes, this.cle, this.discret = false});

  final String libelle;
  final int centimes;
  final String? cle;
  final bool discret;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = discret
        ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: EdgeInsets.fromLTRB(discret ? 16 : 0, 3, 0, 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(libelle, style: style)),
          Text(formatEuros(centimes), key: cle == null ? null : Key(cle!), style: style),
        ],
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(texte, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }
}

/// Un grand chiffre.
class _GrosChiffre extends StatelessWidget {
  const _GrosChiffre(this.texte, {required this.cle});

  final String texte;
  final String cle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      texte,
      key: Key(cle),
      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

// -----------------------------------------------------------------------------
// Chiffre d'affaires et marge
// -----------------------------------------------------------------------------

class _ChiffreAffaires extends StatelessWidget {
  const _ChiffreAffaires({required this.stats});

  final StatsPeriode stats;

  @override
  Widget build(BuildContext context) {
    return _Section(
      titre: 'Chiffre d’affaires',
      legende: 'Argent encaissé, remboursements déduits.',
      enfants: <Widget>[
        _GrosChiffre(formatEuros(stats.encaisseTotalCentimes), cle: 'stat-ca'),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _LigneMontant(libelle: 'Objets', centimes: stats.encaisseObjetsCentimes, cle: 'stat-objets'),
        _LigneMontant(
          libelle: 'Cours et prestations',
          centimes: stats.encaissePrestationsCentimes,
          cle: 'stat-prestations',
        ),
        _LigneMontant(libelle: 'dont cours', centimes: stats.encaisseCoursCentimes, discret: true),
      ],
    );
  }
}

class _Marge extends StatelessWidget {
  const _Marge({required this.stats});

  final StatsPeriode stats;

  @override
  Widget build(BuildContext context) {
    return _Section(
      titre: 'Marge estimée',
      legende: 'Argent encaissé moins le coût de la matière des articles vendus. Les dépenses ne sont pas déduites.',
      enfants: <Widget>[
        _GrosChiffre(formatEuros(stats.margeCentimes), cle: 'stat-marge'),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _LigneMontant(libelle: 'Argent encaissé', centimes: stats.encaisseTotalCentimes),
        _LigneMontant(libelle: 'Coût de la matière', centimes: stats.coutCentimes, cle: 'stat-cout'),
      ],
    );
  }
}

/// Deux petites cartes côte à côte : le panier moyen et les revenus des cours.
class _PanierEtCours extends StatelessWidget {
  const _PanierEtCours({required this.stats});

  final StatsPeriode stats;

  @override
  Widget build(BuildContext context) {
    final int nombre = stats.nombreVentes;
    final int? panier = stats.panierMoyenCentimes;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _Tuile(
              titre: 'Panier moyen',
              valeur: panier == null ? '—' : formatEuros(panier),
              cle: 'stat-panier',
              detail: nombre == 0
                  ? 'Aucune vente'
                  : nombre == 1
                  ? '1 vente'
                  : '$nombre ventes',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Tuile(
              titre: 'Revenus des cours',
              valeur: formatEuros(stats.encaisseCoursCentimes),
              cle: 'stat-cours',
              detail: 'Inscriptions encaissées',
            ),
          ),
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({required this.titre, required this.valeur, required this.cle, required this.detail});

  final String titre;
  final String valeur;
  final String cle;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(titre, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(valeur, key: Key(cle), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Classements
// -----------------------------------------------------------------------------

class _MeilleuresVentes extends StatelessWidget {
  const _MeilleuresVentes({required this.stats});

  final StatsPeriode stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _Section(
      titre: 'Meilleures ventes',
      legende: 'Articles les plus vendus (hors cours), d’après les ventes faites sur la période.',
      enfants: stats.meilleuresVentes.isEmpty
          ? const <Widget>[_Vide('Aucune vente sur cette période.')]
          : <Widget>[
              for (int i = 0; i < stats.meilleuresVentes.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: 28, child: Text('${i + 1}.', style: theme.textTheme.bodyLarge)),
                      Expanded(
                        child: Text(
                          stats.meilleuresVentes[i].designation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('× ${stats.meilleuresVentes[i].quantite}', style: theme.textTheme.bodyMedium),
                      const SizedBox(width: 12),
                      Text(formatEuros(stats.meilleuresVentes[i].totalCentimes), style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
            ],
    );
  }
}

class _CategoriesRentables extends StatelessWidget {
  const _CategoriesRentables({required this.stats});

  final StatsPeriode stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return _Section(
      titre: 'Catégories les plus rentables',
      legende: 'Marge estimée des produits du catalogue, hors lignes libres et cours.',
      enfants: stats.categories.isEmpty
          ? const <Widget>[_Vide('Aucun produit du catalogue encaissé sur cette période.')]
          : <Widget>[
              for (final CategorieRentable c in stats.categories)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(c.categorie.libelle, style: theme.textTheme.bodyLarge),
                            Text(
                              'Encaissé ${formatEuros(c.encaisseCentimes)} · matière ${formatEuros(c.coutCentimes)}',
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatEuros(c.margeCentimes),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
            ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dépenses
// -----------------------------------------------------------------------------

class _Depenses extends StatelessWidget {
  const _Depenses({required this.stats});

  final StatsPeriode stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return _Section(
      titre: 'Dépenses par catégorie',
      enfants: stats.depenses.isEmpty
          ? const <Widget>[_Vide('Aucune dépense sur cette période.')]
          : <Widget>[
              _LigneMontant(libelle: 'Total des dépenses', centimes: stats.depensesTotalCentimes, cle: 'stat-depenses'),
              const SizedBox(height: 4),
              const Divider(height: 1),
              const SizedBox(height: 4),
              for (final DepenseParCategorie d in stats.depenses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(iconeCategorieDepense(d.categorie), size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(child: Text(d.categorie.libelle, style: theme.textTheme.bodyLarge)),
                      Text(formatEuros(d.totalCentimes), style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
            ],
    );
  }
}

// -----------------------------------------------------------------------------
// Stock faible et factures impayées (à l'instant présent, quelle que soit la période)
// -----------------------------------------------------------------------------

/// Les produits dont le stock est faible ou épuisé.
class _StockFaible extends ConsumerWidget {
  const _StockFaible();

  /// Au-delà, on indique seulement combien d'autres produits sont concernés.
  static const int _maxAffiches = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<ProduitResume>? produits = ref.watch(produitsResumesProvider).valueOrNull;
    final List<ProduitResume> alertes = <ProduitResume>[
      for (final ProduitResume r in produits ?? const <ProduitResume>[])
        if (r.produit.archiveLe == null && r.aReapprovisionner) r,
    ];

    return _Section(
      titre: 'Stock faible',
      legende: 'Produits à réapprovisionner, à l’instant présent.',
      enfants: produits == null
          ? const <Widget>[_Vide('Chargement…')]
          : alertes.isEmpty
          ? const <Widget>[_Vide('Aucun produit à réapprovisionner.')]
          : <Widget>[
              Text(
                alertes.length == 1 ? '1 produit à réapprovisionner' : '${alertes.length} produits à réapprovisionner',
                key: const Key('stat-stock-faible'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              for (final ProduitResume r in alertes.take(_maxAffiches))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(r.produit.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.alerte == EtatStock.epuise ? 'Épuisé' : 'Reste ${r.stockTotal}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: r.alerte == EtatStock.epuise ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (alertes.length > _maxAffiches)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    alertes.length - _maxAffiches == 1
                        ? 'et 1 autre produit'
                        : 'et ${alertes.length - _maxAffiches} autres produits',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
    );
  }
}

/// Les factures émises dont la vente n'est pas encore entièrement payée.
class _FacturesImpayees extends StatelessWidget {
  const _FacturesImpayees({required this.stats});

  final Statistiques stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int nombre = stats.facturesImpayeesNombre;
    return _Section(
      titre: 'Factures impayées',
      legende: 'Factures émises pas encore entièrement payées, toutes périodes confondues.',
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.factures),
      enfants: nombre == 0
          ? const <Widget>[_Vide('Aucune facture impayée.')]
          : <Widget>[
              Text(
                nombre == 1 ? '1 facture impayée' : '$nombre factures impayées',
                key: const Key('stat-impayees'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatEuros(stats.facturesImpayeesCentimes)} à encaisser',
                key: const Key('stat-impayees-montant'),
                style: theme.textTheme.titleMedium,
              ),
            ],
    );
  }
}
