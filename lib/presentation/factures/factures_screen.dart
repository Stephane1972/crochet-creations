import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../domain/enums.dart';
import 'factures_providers.dart';

/// Liste des factures (écran 11) : la plus récente d'abord. Un appui ouvre l'aperçu et le détail.
class FacturesScreen extends ConsumerWidget {
  const FacturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Facture>> factures = ref.watch(facturesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Factures')),
      body: factures.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger les factures.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(facturesProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (List<Facture> liste) {
          if (liste.isEmpty) return const _AucuneFacture();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: liste.length,
            separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) => _LigneFacture(facture: liste[index]),
          );
        },
      ),
    );
  }
}

class _LigneFacture extends StatelessWidget {
  const _LigneFacture({required this.facture});

  final Facture facture;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool annulee = facture.statut == StatutFacture.annulee;
    final Color? couleurTexte = annulee ? scheme.onSurfaceVariant : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Icon(annulee ? Icons.receipt_long : Icons.receipt_long_outlined, color: couleurTexte ?? scheme.primary),
      title: Text(
        facture.numero,
        style: theme.textTheme.titleSmall?.copyWith(
          color: couleurTexte,
          decoration: annulee ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${facture.clientNom ?? 'Client de passage'} · ${formatDateCourte(facture.dateEmission)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(formatEuros(facture.totalCentimes), style: theme.textTheme.titleSmall?.copyWith(color: couleurTexte)),
          if (annulee) ...<Widget>[
            const SizedBox(height: 4),
            Etiquette(
              'Annulée',
              fond: scheme.surfaceContainerHighest,
              couleurTexte: scheme.onSurfaceVariant,
              icone: Icons.cancel_outlined,
            ),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.factureDetail, arguments: facture.id),
    );
  }
}

class _AucuneFacture extends StatelessWidget {
  const _AucuneFacture();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.receipt_long_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Aucune facture pour le moment.', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Ouvrez une vente, puis appuyez sur « Créer la facture ».',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
