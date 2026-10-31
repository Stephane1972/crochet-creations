import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/repositories/statistiques_vues.dart';
import '../../domain/calculs/statistiques.dart';
import 'statistiques_providers.dart';

/// Suivi des seuils de la franchise en base de TVA : l'argent encaissé depuis le 1er janvier, objets d'un côté,
/// cours et prestations de l'autre, avec une alerte quand un seuil approche (80 %) ou est dépassé.
/// Affichée sur l'accueil et sur l'écran Statistiques.
class FranchiseTvaCarte extends ConsumerWidget {
  const FranchiseTvaCarte({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Statistiques? stats = ref.watch(statistiquesProvider).valueOrNull;

    final int annee = (stats?.maintenant ?? DateTime.now()).year;
    final int objets = stats?.franchiseObjetsCentimes ?? 0;
    final int prestations = stats?.franchisePrestationsCentimes ?? 0;
    final NiveauFranchise niveauObjets = niveauFranchise(objets, AppConstants.seuilTvaVentesCentimes);
    final NiveauFranchise niveauPrestations = niveauFranchise(prestations, AppConstants.seuilTvaServicesCentimes);
    final NiveauFranchise pire = niveauObjets.index >= niveauPrestations.index ? niveauObjets : niveauPrestations;

    final String message = switch (pire) {
      NiveauFranchise.ok =>
        'Une alerte s’affichera ici quand votre chiffre d’affaires approchera des seuils.',
      NiveauFranchise.approche =>
        'Attention : vous approchez d’un seuil de la franchise en base de TVA. '
            'Parlez-en à votre comptable ou au service des impôts.',
      NiveauFranchise.depasse =>
        'Un seuil de la franchise en base de TVA est dépassé. '
            'Parlez-en sans attendre à votre comptable ou au service des impôts.',
    };
    final Color couleurMessage = switch (pire) {
      NiveauFranchise.ok => scheme.onSurfaceVariant,
      NiveauFranchise.approche => scheme.tertiary,
      NiveauFranchise.depasse => scheme.error,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  pire == NiveauFranchise.ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: pire == NiveauFranchise.ok ? scheme.primary : couleurMessage,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Franchise de TVA', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              key: const Key('franchise-message'),
              style: theme.textTheme.bodyMedium?.copyWith(color: couleurMessage),
            ),
            const SizedBox(height: 18),
            _Seuil(
              cle: 'objets',
              libelle: 'Ventes d’objets',
              atteintCentimes: objets,
              seuilCentimes: AppConstants.seuilTvaVentesCentimes,
              niveau: niveauObjets,
            ),
            const SizedBox(height: 18),
            _Seuil(
              cle: 'prestations',
              libelle: 'Cours et prestations',
              atteintCentimes: prestations,
              seuilCentimes: AppConstants.seuilTvaServicesCentimes,
              niveau: niveauPrestations,
            ),
            const SizedBox(height: 14),
            Text(
              'Argent encaissé depuis le 1er janvier $annee, remboursements déduits.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Seuil extends StatelessWidget {
  const _Seuil({
    required this.cle,
    required this.libelle,
    required this.atteintCentimes,
    required this.seuilCentimes,
    required this.niveau,
  });

  final String cle;
  final String libelle;
  final int atteintCentimes;
  final int seuilCentimes;
  final NiveauFranchise niveau;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int atteint = atteintCentimes < 0 ? 0 : atteintCentimes;
    final int pourcent = seuilCentimes <= 0 ? 0 : atteint * 100 ~/ seuilCentimes;

    final Color couleurBarre = switch (niveau) {
      NiveauFranchise.ok => scheme.primary,
      NiveauFranchise.approche => scheme.tertiary,
      NiveauFranchise.depasse => scheme.error,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(libelle, style: theme.textTheme.bodyLarge)),
            Text(
              '${formatEuros(atteint, avecCentimes: false)} / ${formatEuros(seuilCentimes, avecCentimes: false)}',
              key: Key('franchise-montant-$cle'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: partDuSeuil(atteint, seuilCentimes),
          minHeight: 10,
          borderRadius: BorderRadius.circular(8),
          color: couleurBarre,
          backgroundColor: scheme.surfaceContainerHighest,
          // Pas de semanticsValue : Flutter annonce déjà le pourcentage (et exige un nombre).
          semanticsLabel: libelle,
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$pourcent % du seuil',
                key: Key('franchise-part-$cle'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (niveau == NiveauFranchise.approche)
              Etiquette(
                'Seuil approché',
                key: Key('franchise-etiquette-$cle'),
                fond: scheme.tertiaryContainer,
                couleurTexte: scheme.onTertiaryContainer,
                icone: Icons.warning_amber_rounded,
              ),
            if (niveau == NiveauFranchise.depasse)
              Etiquette(
                'Seuil dépassé',
                key: Key('franchise-etiquette-$cle'),
                fond: scheme.errorContainer,
                couleurTexte: scheme.onErrorContainer,
                icone: Icons.error_outline,
              ),
          ],
        ),
      ],
    );
  }
}
