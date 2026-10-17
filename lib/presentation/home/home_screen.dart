import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_logo.dart';
import '../shell/nav_provider.dart';

/// Accueil / tableau de bord.
///
/// Étape 1 : la mise en page est en place, mais aucun chiffre n'est encore
/// calculé (la base de données arrive à l'étape 2, les statistiques à l'étape 10).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DateTime maintenant = DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: <Widget>[
            _EnTete(maintenant: maintenant),
            const SizedBox(height: 28),
            const _TitreSection('Actions rapides'),
            const _ActionsRapides(),
            const SizedBox(height: 28),
            const _TitreSection('En un coup d’œil'),
            const _Chiffres(),
            const SizedBox(height: 28),
            const _FranchiseTvaCarte(),
          ],
        ),
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.maintenant});

  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        const AppLogo(taille: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${salutation(maintenant)} !', style: theme.textTheme.headlineSmall),
              Text(
                formatDateLongue(maintenant),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Réglages',
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.reglages),
        ),
      ],
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(texte, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

// -----------------------------------------------------------------------------
// Actions rapides
// -----------------------------------------------------------------------------

class _ActionsRapides extends ConsumerWidget {
  const _ActionsRapides();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void versOnglet(int index) => ref.read(navIndexProvider.notifier).aller(index);
    void ouvrir(String route) => Navigator.of(context).pushNamed(route);

    return Column(
      children: <Widget>[
        _RangeeDeuxCartes(
          gauche: _ActionTuile(
            icone: Icons.point_of_sale_outlined,
            libelle: 'Nouvelle vente',
            onTap: () => versOnglet(OngletsNav.vente),
          ),
          droite: _ActionTuile(
            icone: Icons.request_quote_outlined,
            libelle: 'Nouveau devis',
            onTap: () => ouvrir(AppRoutes.devisNouveau),
          ),
        ),
        const SizedBox(height: 12),
        _RangeeDeuxCartes(
          gauche: _ActionTuile(
            icone: Icons.add_circle_outline,
            libelle: 'Ajouter un produit',
            onTap: () => ouvrir(AppRoutes.produitNouveau),
          ),
          droite: _ActionTuile(
            icone: Icons.person_add_alt_outlined,
            libelle: 'Nouveau client',
            onTap: () => ouvrir(AppRoutes.clientNouveau),
          ),
        ),
      ],
    );
  }
}

/// Deux cartes côte à côte, de même hauteur.
class _RangeeDeuxCartes extends StatelessWidget {
  const _RangeeDeuxCartes({required this.gauche, required this.droite});

  final Widget gauche;
  final Widget droite;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: gauche),
          const SizedBox(width: 12),
          Expanded(child: droite),
        ],
      ),
    );
  }
}

class _ActionTuile extends StatelessWidget {
  const _ActionTuile({required this.icone, required this.libelle, required this.onTap});

  final IconData icone;
  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 12),
              Text(libelle, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Chiffres clés (valeurs branchées à l'étape 10)
// -----------------------------------------------------------------------------

class _Chiffres extends StatelessWidget {
  const _Chiffres();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _RangeeDeuxCartes(
          gauche: _ChiffreTuile(
            icone: Icons.shopping_bag_outlined,
            libelle: 'Ventes du mois',
            valeur: '—',
          ),
          droite: _ChiffreTuile(
            icone: Icons.school_outlined,
            libelle: 'Cours du mois',
            valeur: '—',
          ),
        ),
        const SizedBox(height: 12),
        const _RangeeDeuxCartes(
          gauche: _ChiffreTuile(
            icone: Icons.inventory_2_outlined,
            libelle: 'Stock faible',
            valeur: '—',
          ),
          droite: _ChiffreTuile(
            icone: Icons.hourglass_empty,
            libelle: 'Factures impayées',
            valeur: '—',
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Les chiffres apparaîtront dès les premières ventes.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ChiffreTuile extends StatelessWidget {
  const _ChiffreTuile({required this.icone, required this.libelle, required this.valeur});

  final IconData icone;
  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icone, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    libelle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(valeur, style: theme.textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Franchise de TVA : suivi des seuils (alertes branchées à l'étape 10)
// -----------------------------------------------------------------------------

class _FranchiseTvaCarte extends StatelessWidget {
  const _FranchiseTvaCarte();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.verified_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('Franchise de TVA', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Une alerte s’affichera ici quand votre chiffre d’affaires '
              'approchera des seuils.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            const _Seuil(
              libelle: 'Ventes d’objets',
              atteintCentimes: 0,
              seuilCentimes: AppConstants.seuilTvaVentesCentimes,
            ),
            const SizedBox(height: 18),
            const _Seuil(
              libelle: 'Cours et prestations',
              atteintCentimes: 0,
              seuilCentimes: AppConstants.seuilTvaServicesCentimes,
            ),
          ],
        ),
      ),
    );
  }
}

class _Seuil extends StatelessWidget {
  const _Seuil({
    required this.libelle,
    required this.atteintCentimes,
    required this.seuilCentimes,
  });

  final String libelle;
  final int atteintCentimes;
  final int seuilCentimes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double part = (atteintCentimes / seuilCentimes).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(libelle, style: theme.textTheme.bodyLarge)),
            Text(
              '${formatEuros(atteintCentimes, avecCentimes: false)} / '
              '${formatEuros(seuilCentimes, avecCentimes: false)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: part,
          minHeight: 10,
          borderRadius: BorderRadius.circular(8),
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
          semanticsLabel: libelle,
          semanticsValue: '${(part * 100).round()} pour cent du seuil',
        ),
      ],
    );
  }
}
