import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../core/widgets/etiquette.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/enums.dart';
import 'factures_providers.dart';

/// Aperçu et détail d'une facture (écran 12) : le PDF tel qu'il sera envoyé, avec les boutons pour le
/// partager, l'imprimer, ouvrir la vente ou annuler la facture.
class FactureDetailScreen extends ConsumerStatefulWidget {
  const FactureDetailScreen({super.key, required this.factureId});

  final int factureId;

  @override
  ConsumerState<FactureDetailScreen> createState() => _FactureDetailScreenState();
}

class _FactureDetailScreenState extends ConsumerState<FactureDetailScreen> {
  /// Une action est en cours (fabrication du PDF, feuille de partage...) : les boutons sont bloqués.
  bool _occupe = false;

  /// Exécute une action en affichant l'erreur éventuelle en français.
  Future<void> _executer(Future<void> Function() action) async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Action sur la facture impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _partager(Facture facture) {
    return _executer(() async {
      final String chemin = await ref.read(factureRepositoryProvider).cheminPdf(facture.id);
      await ref
          .read(serviceDocumentsProvider)
          .partager(cheminFichier: chemin, nomFichier: '${facture.numero}.pdf', sujet: 'Facture ${facture.numero}');
    });
  }

  Future<void> _imprimer(Facture facture) {
    return _executer(() async {
      final Uint8List octets = await ref.read(factureRepositoryProvider).obtenirPdf(facture.id);
      await ref.read(serviceDocumentsProvider).imprimer(octets: octets, nomDocument: facture.numero);
    });
  }

  Future<void> _annuler(Facture facture) async {
    final bool ok = await confirmer(
      context,
      titre: 'Annuler la facture ${facture.numero} ?',
      message:
          'La facture reste dans la liste, marquée « annulée », et son numéro ne sera pas réutilisé. '
          'La vente n’est pas annulée : vous pourrez établir une nouvelle facture depuis la vente. '
          'Cette action est définitive.',
      libelleConfirmer: 'Annuler la facture',
      libelleAnnuler: 'Garder la facture',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await ref.read(factureRepositoryProvider).annuler(facture.id);
      if (mounted) afficherMessage(context, 'Facture ${facture.numero} annulée.');
    });
  }

  void _ouvrirVente(Facture facture) {
    Navigator.of(context).pushNamed(AppRoutes.venteConfirmation, arguments: facture.venteId);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Facture?> facture = ref.watch(factureProvider(widget.factureId));

    return Scaffold(
      appBar: AppBar(title: Text(facture.valueOrNull?.numero ?? 'Facture')),
      body: facture.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger cette facture.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(factureProvider(widget.factureId)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (Facture? f) {
          if (f == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Cette facture n’existe plus.', textAlign: TextAlign.center),
              ),
            );
          }
          return Column(
            children: <Widget>[
              _EnTete(facture: f),
              Expanded(child: _Apercu(facture: f)),
              _Actions(
                facture: f,
                occupe: _occupe,
                onPartager: () => _partager(f),
                onImprimer: () => _imprimer(f),
                onAnnuler: () => _annuler(f),
                onOuvrirVente: () => _ouvrirVente(f),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Client, dates, total et statut de la facture.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.facture});

  final Facture facture;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool annulee = facture.statut == StatutFacture.annulee;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      facture.clientNom ?? 'Client de passage',
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Émise le ${formatDateCourte(facture.dateEmission)} · '
                      'vente du ${formatDateCourte(facture.dateVentePrestation)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(formatEuros(facture.totalCentimes), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (annulee)
                    Etiquette(
                      'Annulée',
                      fond: scheme.surfaceContainerHighest,
                      couleurTexte: scheme.onSurfaceVariant,
                      icone: Icons.cancel_outlined,
                    )
                  else
                    Etiquette(
                      'Émise',
                      fond: scheme.primaryContainer,
                      couleurTexte: scheme.onPrimaryContainer,
                      icone: Icons.check,
                    ),
                ],
              ),
            ],
          ),
          if (annulee) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Cette facture est annulée. Son numéro reste utilisé et la vente n’est pas modifiée : '
                'vous pouvez établir une nouvelle facture depuis la vente.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le PDF, tel qu'il sera partagé ou imprimé.
class _Apercu extends ConsumerWidget {
  const _Apercu({required this.facture});

  final Facture facture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List> pdf = ref.watch(facturePdfProvider(facture.id));
    return pdf.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object erreur, StackTrace pile) {
        debugPrint('PDF de la facture impossible : $erreur\n$pile');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de fabriquer le PDF de cette facture.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(facturePdfProvider(facture.id)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );
      },
      data: (Uint8List octets) =>
          ref.watch(constructeurApercuPdfProvider)(context, octets, '${facture.numero}.pdf'),
    );
  }
}

/// Partager et imprimer (factures émises), ouvrir la vente, annuler la facture.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.facture,
    required this.occupe,
    required this.onPartager,
    required this.onImprimer,
    required this.onAnnuler,
    required this.onOuvrirVente,
  });

  final Facture facture;
  final bool occupe;
  final VoidCallback onPartager;
  final VoidCallback onImprimer;
  final VoidCallback onAnnuler;
  final VoidCallback onOuvrirVente;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool emise = facture.statut == StatutFacture.emise;

    return Material(
      color: scheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (emise)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: occupe ? null : onPartager,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Partager'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: occupe ? null : onImprimer,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimer'),
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: onOuvrirVente,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Voir la vente'),
                  ),
                  if (emise)
                    TextButton.icon(
                      onPressed: occupe ? null : onAnnuler,
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Annuler la facture'),
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
