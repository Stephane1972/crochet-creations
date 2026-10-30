import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/depense_vues.dart';
import '../../domain/enums.dart';
import 'depenses_providers.dart';
import 'depenses_widgets.dart';

/// Liste des dépenses (écran 19) : un mois à la fois, avec son total, filtrable par catégorie.
/// Un appui sur une dépense l'ouvre pour la modifier (ou l'archiver). Les dépenses archivées ont leur filtre.
class DepensesScreen extends ConsumerStatefulWidget {
  const DepensesScreen({super.key});

  @override
  ConsumerState<DepensesScreen> createState() => _DepensesScreenState();
}

class _DepensesScreenState extends ConsumerState<DepensesScreen> {
  late int _annee;
  late int _mois;
  CategorieDepense? _categorie;
  bool _archivees = false;

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = DateTime.now();
    _annee = maintenant.year;
    _mois = maintenant.month;
  }

  bool get _moisCourant {
    final DateTime maintenant = DateTime.now();
    return _annee == maintenant.year && _mois == maintenant.month;
  }

  void _changerMois(int decalage) {
    final DateTime nouveau = DateTime(_annee, _mois + decalage);
    setState(() {
      _annee = nouveau.year;
      _mois = nouveau.month;
    });
  }

  FiltreDepenses get _filtre => (annee: _annee, mois: _mois, categorie: _categorie, archivees: _archivees);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ListeDepenses> liste = ref.watch(depensesListeProvider(_filtre));

    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.depenseNouvelle),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle dépense'),
      ),
      body: Column(
        children: <Widget>[
          _SelecteurMois(
            annee: _annee,
            mois: _mois,
            peutAvancer: !_moisCourant,
            onPrecedent: () => _changerMois(-1),
            onSuivant: () => _changerMois(1),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Toutes'),
                  selected: !_archivees && _categorie == null,
                  onSelected: (bool _) => setState(() {
                    _categorie = null;
                    _archivees = false;
                  }),
                ),
                for (final CategorieDepense c in CategorieDepense.values) ...<Widget>[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(c.libelle),
                    selected: !_archivees && _categorie == c,
                    onSelected: (bool _) => setState(() {
                      _categorie = c;
                      _archivees = false;
                    }),
                  ),
                ],
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Archivées'),
                  selected: _archivees,
                  onSelected: (bool _) => setState(() {
                    _categorie = null;
                    _archivees = true;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: liste.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object erreur, StackTrace pile) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('Impossible de charger les dépenses.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(depensesListeProvider(_filtre)),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (ListeDepenses donnees) {
                if (donnees.vide) {
                  return _AucuneDepense(annee: _annee, mois: _mois, categorie: _categorie, archivees: _archivees);
                }
                return ListView.separated(
                  // De la place sous la dernière ligne pour que le bouton « Nouvelle dépense » ne la masque pas.
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: donnees.lignes.length + 1,
                  separatorBuilder: (BuildContext context, int index) =>
                      index == 0 ? const SizedBox(height: 8) : const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return _CarteTotal(donnees: donnees, categorie: _categorie, archivees: _archivees);
                    }
                    return _LigneDepense(ligne: donnees.lignes[index - 1]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// « ‹  octobre 2026  › » : on passe d'un mois à l'autre ; pas de mois à venir (on ne note pas une dépense à l'avance).
class _SelecteurMois extends StatelessWidget {
  const _SelecteurMois({
    required this.annee,
    required this.mois,
    required this.peutAvancer,
    required this.onPrecedent,
    required this.onSuivant,
  });

  final int annee;
  final int mois;
  final bool peutAvancer;
  final VoidCallback onPrecedent;
  final VoidCallback onSuivant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(tooltip: 'Mois précédent', icon: const Icon(Icons.chevron_left), onPressed: onPrecedent),
          Expanded(
            child: Text(
              formatMois(annee, mois),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Mois suivant',
            icon: const Icon(Icons.chevron_right),
            onPressed: peutAvancer ? onSuivant : null,
          ),
        ],
      ),
    );
  }
}

/// Total des dépenses affichées : « Total du mois », ou celui de la catégorie choisie ; pour les archivées, leur nombre.
class _CarteTotal extends StatelessWidget {
  const _CarteTotal({required this.donnees, required this.categorie, required this.archivees});

  final ListeDepenses donnees;
  final CategorieDepense? categorie;
  final bool archivees;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int nombre = donnees.lignes.length;
    final String pluriel = nombre > 1 ? 'dépenses' : 'dépense';

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: archivees
            ? Text(
                nombre > 1 ? '$nombre dépenses archivées ce mois-ci' : '$nombre dépense archivée ce mois-ci',
                style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSecondaryContainer),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    categorie == null ? 'Total du mois' : 'Total · ${categorie!.libelle}',
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatEuros(donnees.totalCentimes),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$nombre $pluriel',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LigneDepense extends StatelessWidget {
  const _LigneDepense({required this.ligne});

  final DepenseLigne ligne;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Depense depense = ligne.depense;
    final String titre = depense.fournisseur ?? depense.categorie.libelle;
    final TextStyle? discret = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(iconeCategorieDepense(depense.categorie)),
      ),
      title: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${formatDateCourte(depense.dateDepense)} · ${depense.categorie.libelle}', style: discret),
          if (depense.description != null)
            Text(depense.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: discret),
          if (ligne.produit != null)
            Text('Produit : ${ligne.produit!.nom}', maxLines: 1, overflow: TextOverflow.ellipsis, style: discret),
          if (depense.photoTicketChemin != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.receipt_long_outlined, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Ticket joint', style: discret),
                ],
              ),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: Text(formatEuros(depense.montantCentimes), style: theme.textTheme.titleSmall),
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.depenseModifier, arguments: depense.id),
    );
  }
}

class _AucuneDepense extends StatelessWidget {
  const _AucuneDepense({
    required this.annee,
    required this.mois,
    required this.categorie,
    required this.archivees,
  });

  final int annee;
  final int mois;
  final CategorieDepense? categorie;
  final bool archivees;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String quand = formatMois(annee, mois);
    final (String titre, String? conseil) = archivees
        ? ('Aucune dépense archivée en $quand.', 'Une dépense archivée depuis sa fiche apparaît ici.')
        : categorie != null
        ? ('Aucune dépense « ${categorie!.libelle} » en $quand.', null)
        : ('Aucune dépense en $quand.', 'Appuyez sur « Nouvelle dépense » pour en ajouter une.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.payments_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(titre, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (conseil != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                conseil,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
