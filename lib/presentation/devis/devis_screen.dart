import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/client_vues.dart';
import '../../data/repositories/devis_vues.dart';
import '../../domain/enums.dart';
import 'devis_providers.dart';
import 'devis_widgets.dart';

/// Liste des devis (écran 13) : le plus récent d'abord, avec son statut. Un appui ouvre l'aperçu du devis.
class DevisScreen extends ConsumerWidget {
  const DevisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DevisResume>> devis = ref.watch(devisListeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Devis')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.devisNouveau),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau devis'),
      ),
      body: devis.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger les devis.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(devisListeProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (List<DevisResume> liste) {
          if (liste.isEmpty) return const _AucunDevis();
          final DateTime maintenant = DateTime.now();
          return ListView.separated(
            // De la place sous la dernière ligne pour que le bouton « Nouveau devis » ne la masque pas.
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: liste.length,
            separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) =>
                _LigneDevis(resume: liste[index], maintenant: maintenant),
          );
        },
      ),
    );
  }
}

class _LigneDevis extends StatelessWidget {
  const _LigneDevis({required this.resume, required this.maintenant});

  final DevisResume resume;
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DevisFiche devis = resume.devis;
    final Client? client = resume.client;
    final StatutDevis statut = resume.statut(maintenant);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Icon(Icons.request_quote_outlined, color: theme.colorScheme.primary),
      title: Text(devis.numero, style: theme.textTheme.titleSmall),
      subtitle: Text(
        '${client == null ? 'Sans client' : libelleClient(client)} · ${formatDateCourte(devis.dateEmission)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(formatEuros(devis.totalCentimes), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          EtiquetteStatutDevis(statut),
        ],
      ),
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.devisDetail, arguments: devis.id),
    );
  }
}

class _AucunDevis extends StatelessWidget {
  const _AucunDevis();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.request_quote_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Aucun devis pour le moment.', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Appuyez sur « Nouveau devis » pour en établir un.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
