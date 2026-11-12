import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/calculs/analyse_ventes.dart';
import '../../domain/calculs/statistiques.dart';
import '../../domain/lieux_vente.dart';
import '../lieux/lieux_providers.dart';
import '../produits/categories_providers.dart';
import 'statistiques_providers.dart';

/// Libellé d'une catégorie qui regroupe les articles sans catégorie de produit.
const String libelleSansCategorie = 'Sans catégorie';

/// Analyse détaillée (étape 5 de l'évolution) : l'argent encaissé regroupé par année, par mois, par lieu de vente ou
/// par catégorie, avec des filtres qui se croisent (année, mois, lieu, catégorie), en graphique et en tableau.
///
/// Même base que l'écran Statistiques : argent réellement encaissé à la date du paiement, remboursements déduits ;
/// la marge estimée est cet argent moins le coût de la matière des articles vendus.
class AnalyseScreen extends ConsumerStatefulWidget {
  const AnalyseScreen({super.key});

  @override
  ConsumerState<AnalyseScreen> createState() => _AnalyseScreenState();
}

class _AnalyseScreenState extends ConsumerState<AnalyseScreen> {
  DimensionAnalyse _dimension = DimensionAnalyse.mois;

  /// 0 = toutes les années (une année n'est jamais 0). Au départ : l'année en cours.
  int _annee = 0;

  /// 0 = tous les mois.
  int _mois = 0;
  ChoixFiltre<int> _lieu = const ChoixFiltre<int>.tous();
  ChoixFiltre<String> _categorie = const ChoixFiltre<String>.tous();

  @override
  void initState() {
    super.initState();
    _annee = ref.read(horlogeProvider)().year;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<VenteCompta>> ventes = ref.watch(ventesAnalyseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analyse détaillée')),
      body: ventes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de calculer l’analyse.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(ventesAnalyseProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: _contenu,
      ),
    );
  }

  Widget _contenu(List<VenteCompta> ventes) {
    final List<LieuVente> lieux = ref.watch(lieuxVenteProvider).valueOrNull ?? const <LieuVente>[];
    final List<CategorieProduit> categories =
        ref.watch(categoriesProduitProvider).valueOrNull ?? const <CategorieProduit>[];
    final Map<String, String> noms = ref.watch(nomsCategoriesProvider);
    final int anneeCourante = ref.read(horlogeProvider)().year;

    // Un lieu ou une catégorie supprimés entre-temps : on revient à « tous » plutôt que d'afficher un choix fantôme.
    final ChoixFiltre<int> lieu = _lieu.valeur == null || lieux.any((LieuVente l) => l.id == _lieu.valeur)
        ? _lieu
        : const ChoixFiltre<int>.tous();
    final ChoixFiltre<String> categorie =
        _categorie.valeur == null || categories.any((CategorieProduit c) => c.cle == _categorie.valeur)
        ? _categorie
        : const ChoixFiltre<String>.tous();

    final List<int> annees = <int>{
      ...anneesAvecEncaissements(ventes),
      anneeCourante,
      if (_annee != 0) _annee,
    }.toList()..sort((int a, int b) => b.compareTo(a));

    final AnalyseVentes analyse = calculerAnalyse(
      ventes: ventes,
      dimension: _dimension,
      filtre: FiltreAnalyse(
        annee: _annee == 0 ? null : _annee,
        mois: _mois == 0 ? null : _mois,
        lieu: lieu,
        categorie: categorie,
      ),
      ordreLieux: <int>[for (final LieuVente l in lieux) l.id],
      ordreCategories: <String>[for (final CategorieProduit c in categories) c.cle],
    );

    String libelleLieu(int? id) => lieuParId(lieux, id)?.nom ?? libelleLieuNonRenseigne;
    String libelleCategorie(String? cle) => cle == null ? libelleSansCategorie : nomCategorie(noms, cle);

    String libelleLigne(LigneAnalyse l) {
      switch (l.dimension) {
        case DimensionAnalyse.annee:
          return '${l.annee}';
        case DimensionAnalyse.mois:
          return formatMois(l.annee!, l.mois!);
        case DimensionAnalyse.lieu:
          return libelleLieu(l.lieuId);
        case DimensionAnalyse.categorie:
          return libelleCategorie(l.categorie);
      }
    }

    // « 2026 · octobre · Marché · Doudou » : ce qui est analysé, en quelques mots.
    final String resume = <String>[
      _annee == 0 ? 'Toutes les années' : '$_annee',
      if (_mois != 0) nomDuMois(_mois),
      if (!lieu.tous) lieu.valeur == null ? libelleLieuNonRenseigne : libelleLieu(lieu.valeur),
      if (!categorie.tous) libelleCategorie(categorie.valeur),
    ].join(' · ');

    final bool sansCategorie =
        _dimension == DimensionAnalyse.categorie && analyse.lignes.any((LigneAnalyse l) => l.categorie == null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        _Carte(
          titre: 'Regrouper par',
          enfants: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final DimensionAnalyse d in DimensionAnalyse.values)
                  ChoiceChip(
                    key: Key('analyse-par-${d.name}'),
                    label: Text(d.libelle),
                    selected: _dimension == d,
                    onSelected: (bool _) => setState(() => _dimension = d),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Carte(
          titre: 'Filtres',
          legende: 'Les filtres se croisent : par exemple un lieu et une catégorie sur une année.',
          enfants: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _Liste<int>(
                    cle: 'analyse-filtre-annee',
                    titre: 'Année',
                    valeur: _annee,
                    options: <_Option<int>>[
                      const _Option<int>(0, 'Toutes les années'),
                      for (final int a in annees) _Option<int>(a, '$a'),
                    ],
                    onChanged: (int v) => setState(() => _annee = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Liste<int>(
                    cle: 'analyse-filtre-mois',
                    titre: 'Mois',
                    valeur: _mois,
                    options: <_Option<int>>[
                      const _Option<int>(0, 'Tous les mois'),
                      for (int m = 1; m <= 12; m++) _Option<int>(m, nomDuMois(m)),
                    ],
                    onChanged: (int v) => setState(() => _mois = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Liste<ChoixFiltre<int>>(
                    cle: 'analyse-filtre-lieu',
                    titre: 'Lieu de vente',
                    valeur: lieu,
                    options: <_Option<ChoixFiltre<int>>>[
                      const _Option<ChoixFiltre<int>>(ChoixFiltre<int>.tous(), 'Tous les lieux'),
                      for (final LieuVente l in lieux) _Option<ChoixFiltre<int>>(ChoixFiltre<int>.valeur(l.id), l.nom),
                      const _Option<ChoixFiltre<int>>(ChoixFiltre<int>.sans(), libelleLieuNonRenseigne),
                    ],
                    onChanged: (ChoixFiltre<int> v) => setState(() => _lieu = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Liste<ChoixFiltre<String>>(
                    cle: 'analyse-filtre-categorie',
                    titre: 'Catégorie',
                    valeur: categorie,
                    options: <_Option<ChoixFiltre<String>>>[
                      const _Option<ChoixFiltre<String>>(ChoixFiltre<String>.tous(), 'Toutes les catégories'),
                      for (final CategorieProduit c in categories)
                        _Option<ChoixFiltre<String>>(ChoixFiltre<String>.valeur(c.cle), c.nom),
                      const _Option<ChoixFiltre<String>>(ChoixFiltre<String>.sans(), libelleSansCategorie),
                    ],
                    onChanged: (ChoixFiltre<String> v) => setState(() => _categorie = v),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (analyse.vide)
          const _Carte(
            titre: 'Argent encaissé',
            enfants: <Widget>[_Vide('Aucun encaissement ne correspond à ces critères.', cle: 'analyse-vide')],
          )
        else ...<Widget>[
          _Graphique(
            titre: 'Argent encaissé · ${_dimension.parLibelle}',
            resume: resume,
            analyse: analyse,
            libelle: libelleLigne,
          ),
          const SizedBox(height: 12),
          _Tableau(
            analyse: analyse,
            libelle: libelleLigne,
            legende: sansCategorie
                ? '« $libelleSansCategorie » regroupe les lignes libres, les cours et les frais de port.'
                : null,
          ),
        ],
      ],
    );
  }
}

extension on DimensionAnalyse {
  /// « par mois », « par lieu de vente »... : pour le titre du graphique.
  String get parLibelle {
    switch (this) {
      case DimensionAnalyse.annee:
        return 'par année';
      case DimensionAnalyse.mois:
        return 'par mois';
      case DimensionAnalyse.lieu:
        return 'par lieu de vente';
      case DimensionAnalyse.categorie:
        return 'par catégorie';
    }
  }
}

// -----------------------------------------------------------------------------
// Briques
// -----------------------------------------------------------------------------

/// Une carte avec un titre et, en dessous, son contenu.
class _Carte extends StatelessWidget {
  const _Carte({required this.titre, required this.enfants, this.legende});

  final String titre;
  final List<Widget> enfants;
  final String? legende;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
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
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide(this.texte, {this.cle});

  final String texte;
  final String? cle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      texte,
      key: cle == null ? null : Key(cle!),
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Un choix d'une liste déroulante.
class _Option<T> {
  const _Option(this.valeur, this.libelle);

  final T valeur;
  final String libelle;
}

/// Une liste déroulante avec son titre.
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required this.cle,
    required this.titre,
    required this.valeur,
    required this.options,
    required this.onChanged,
  });

  final String cle;
  final String titre;
  final T valeur;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: titre,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: Key(cle),
          isExpanded: true,
          value: valeur,
          items: <DropdownMenuItem<T>>[
            for (final _Option<T> o in options)
              DropdownMenuItem<T>(
                value: o.valeur,
                child: Text(o.libelle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (T? choix) {
            if (choix != null) onChanged(choix);
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Graphique
// -----------------------------------------------------------------------------

/// Les chiffres sous forme de barres : une barre par ligne, proportionnelle à l'argent encaissé.
class _Graphique extends StatelessWidget {
  const _Graphique({required this.titre, required this.resume, required this.analyse, required this.libelle});

  final String titre;
  final String resume;
  final AnalyseVentes analyse;
  final String Function(LigneAnalyse) libelle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int plusGrand = analyse.lignes.fold(
      0,
      (int m, LigneAnalyse l) => l.encaisseCentimes > m ? l.encaisseCentimes : m,
    );

    return _Carte(
      titre: titre,
      legende: 'Argent encaissé à la date du paiement, remboursements déduits.',
      enfants: <Widget>[
        Text(resume, key: const Key('analyse-resume'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          formatEuros(analyse.encaisseTotalCentimes),
          key: const Key('analyse-total'),
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < analyse.lignes.length; i++)
          _Barre(
            index: i,
            libelle: libelle(analyse.lignes[i]),
            ligne: analyse.lignes[i],
            part: analyse.partEnPourcent(analyse.lignes[i]),
            fraction: plusGrand <= 0 ? 0 : analyse.lignes[i].encaisseCentimes.clamp(0, plusGrand) / plusGrand,
            couleur: scheme.primary,
            fond: scheme.surfaceContainerHighest,
          ),
      ],
    );
  }
}

class _Barre extends StatelessWidget {
  const _Barre({
    required this.index,
    required this.libelle,
    required this.ligne,
    required this.part,
    required this.fraction,
    required this.couleur,
    required this.fond,
  });

  final int index;
  final String libelle;
  final LigneAnalyse ligne;
  final int? part;
  final double fraction;
  final Color couleur;
  final Color fond;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  libelle,
                  key: Key('graphique-libelle-$index'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatEuros(ligne.encaisseCentimes),
                key: Key('graphique-montant-$index'),
                style: theme.textTheme.bodyLarge,
              ),
              if (part != null) ...<Widget>[
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$part %',
                    key: Key('graphique-part-$index'),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ExcludeSemantics(
            child: Container(
              key: Key('graphique-piste-$index'),
              height: 10,
              decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(5)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: DecoratedBox(
                  key: Key('graphique-barre-$index'),
                  decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(5)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tableau
// -----------------------------------------------------------------------------

/// Les mêmes chiffres en tableau : argent encaissé, coût de la matière, marge estimée, et le total.
class _Tableau extends StatelessWidget {
  const _Tableau({required this.analyse, required this.libelle, this.legende});

  final AnalyseVentes analyse;
  final String Function(LigneAnalyse) libelle;
  final String? legende;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? petit = theme.textTheme.bodyMedium;
    final TextStyle? gras = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    final TextStyle? entete = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    Widget cellule(String texte, {String? cle, TextStyle? style, bool aDroite = true}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: aDroite
          ? Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(texte, key: cle == null ? null : Key(cle), style: style),
              ),
            )
          : Text(texte, key: cle == null ? null : Key(cle), style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
    );

    final BoxDecoration trait = BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant)));
    final BoxDecoration traitHaut = BoxDecoration(border: Border(top: BorderSide(color: scheme.outline)));

    return _Carte(
      titre: 'Tableau',
      legende: legende ?? 'Marge estimée : argent encaissé moins le coût de la matière des articles vendus.',
      enfants: <Widget>[
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(2.1),
            1: FlexColumnWidth(1.5),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.5),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: <TableRow>[
            TableRow(
              decoration: trait,
              children: <Widget>[
                cellule(analyse.dimension.libelle, style: entete, aDroite: false),
                cellule('Encaissé', style: entete),
                cellule('Matière', style: entete),
                cellule('Marge', style: entete),
              ],
            ),
            for (int i = 0; i < analyse.lignes.length; i++)
              TableRow(
                children: <Widget>[
                  cellule(libelle(analyse.lignes[i]), cle: 'tableau-libelle-$i', style: petit, aDroite: false),
                  cellule(formatEuros(analyse.lignes[i].encaisseCentimes), cle: 'tableau-encaisse-$i', style: petit),
                  cellule(formatEuros(analyse.lignes[i].coutCentimes), cle: 'tableau-cout-$i', style: petit),
                  cellule(formatEuros(analyse.lignes[i].margeCentimes), cle: 'tableau-marge-$i', style: petit),
                ],
              ),
            TableRow(
              decoration: traitHaut,
              children: <Widget>[
                cellule('Total', style: gras, aDroite: false),
                cellule(formatEuros(analyse.encaisseTotalCentimes), cle: 'tableau-total-encaisse', style: gras),
                cellule(formatEuros(analyse.coutTotalCentimes), cle: 'tableau-total-cout', style: gras),
                cellule(formatEuros(analyse.margeTotalCentimes), cle: 'tableau-total-marge', style: gras),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
