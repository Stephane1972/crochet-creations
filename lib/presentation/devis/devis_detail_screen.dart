import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_vues.dart';
import '../../data/repositories/devis_vues.dart';
import '../../domain/enums.dart';
import '../factures/factures_providers.dart';
import 'devis_providers.dart';
import 'devis_widgets.dart';

/// Aperçu et détail d'un devis : le PDF tel qu'il sera envoyé, avec les boutons pour le partager, l'imprimer,
/// le modifier, changer son statut ou le convertir en commande.
class DevisDetailScreen extends ConsumerStatefulWidget {
  const DevisDetailScreen({super.key, required this.devisId});

  final int devisId;

  @override
  ConsumerState<DevisDetailScreen> createState() => _DevisDetailScreenState();
}

class _DevisDetailScreenState extends ConsumerState<DevisDetailScreen> {
  /// Une action est en cours (fabrication du PDF, feuille de partage...) : les boutons sont bloqués.
  bool _occupe = false;

  /// Exécute une action en affichant l'erreur éventuelle en français.
  Future<void> _executer(Future<void> Function() action) async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Action sur le devis impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _partager(DevisFiche devis) {
    return _executer(() async {
      final String chemin = await ref.read(devisRepositoryProvider).cheminPdf(devis.id);
      await ref
          .read(serviceDocumentsProvider)
          .partager(cheminFichier: chemin, nomFichier: '${devis.numero}.pdf', sujet: 'Devis ${devis.numero}');
    });
  }

  Future<void> _imprimer(DevisFiche devis) {
    return _executer(() async {
      final Uint8List octets = await ref.read(devisRepositoryProvider).obtenirPdf(devis.id);
      await ref.read(serviceDocumentsProvider).imprimer(octets: octets, nomDocument: devis.numero);
    });
  }

  Future<void> _changerStatut(DevisFiche devis, StatutDevis nouveau) async {
    if (nouveau == StatutDevis.refuse) {
      final bool ok = await confirmer(
        context,
        titre: 'Marquer ${devis.numero} comme refusé ?',
        message: 'Un devis refusé ne change plus de statut et ne peut plus être modifié ni converti.',
        libelleConfirmer: 'Marquer comme refusé',
        libelleAnnuler: 'Garder le devis',
      );
      if (!ok || !mounted) return;
    }
    await _executer(() async {
      await ref.read(devisRepositoryProvider).changerStatut(devis.id, nouveau);
      if (mounted) afficherMessage(context, 'Devis ${devis.numero} : ${nouveau.libelle.toLowerCase()}.');
    });
  }

  void _modifier(DevisFiche devis) {
    Navigator.of(context).pushNamed(AppRoutes.devisModifier, arguments: devis.id);
  }

  void _convertir(DevisFiche devis) {
    Navigator.of(context).pushNamed(AppRoutes.devisConversion, arguments: devis.id);
  }

  void _ouvrirCommande(int venteId) {
    Navigator.of(context).pushNamed(AppRoutes.venteConfirmation, arguments: venteId);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DevisDetail?> detail = ref.watch(devisDetailProvider(widget.devisId));
    final DateTime maintenant = DateTime.now();
    final DevisDetail? fiche = detail.valueOrNull;
    final Set<StatutDevis> changements =
        fiche == null ? const <StatutDevis>{} : fiche.statutsProposes(maintenant);

    return Scaffold(
      appBar: AppBar(
        title: Text(fiche?.devis.numero ?? 'Devis'),
        actions: <Widget>[
          if (fiche != null && changements.isNotEmpty)
            PopupMenuButton<StatutDevis>(
              tooltip: 'Changer le statut',
              icon: const Icon(Icons.more_vert),
              enabled: !_occupe,
              onSelected: (StatutDevis nouveau) => _changerStatut(fiche.devis, nouveau),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<StatutDevis>>[
                for (final StatutDevis s in StatutDevis.values)
                  if (changements.contains(s))
                    PopupMenuItem<StatutDevis>(value: s, child: Text('Marquer comme ${s.libelle.toLowerCase()}')),
              ],
            ),
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
                const Text('Impossible de charger ce devis.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(devisDetailProvider(widget.devisId)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (DevisDetail? d) {
          if (d == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Ce devis n’existe plus.', textAlign: TextAlign.center),
              ),
            );
          }
          return Column(
            children: <Widget>[
              _EnTete(detail: d, maintenant: maintenant, onOuvrirCommande: _ouvrirCommande),
              Expanded(child: _Apercu(detail: d)),
              _Actions(
                detail: d,
                maintenant: maintenant,
                occupe: _occupe,
                onPartager: () => _partager(d.devis),
                onImprimer: () => _imprimer(d.devis),
                onModifier: () => _modifier(d.devis),
                onConvertir: () => _convertir(d.devis),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Client, dates, total et statut du devis, avec une explication quand il ne peut plus être utilisé.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.detail, required this.maintenant, required this.onOuvrirCommande});

  final DevisDetail detail;
  final DateTime maintenant;
  final void Function(int venteId) onOuvrirCommande;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DevisFiche devis = detail.devis;
    final Client? client = detail.client;
    final StatutDevis statut = detail.statut(maintenant);
    final DateTime? validite = devis.dateValidite;
    final int? venteId = devis.venteId;

    String? information;
    Color fond = scheme.surfaceContainerHighest;
    Color texte = scheme.onSurfaceVariant;
    if (statut == StatutDevis.expire) {
      information =
          'Ce devis est expiré${validite == null ? '' : ' depuis le ${formatDateCourte(validite)}'}. '
          'Appuyez sur « Modifier » pour prolonger sa validité.';
      fond = scheme.tertiaryContainer;
      texte = scheme.onTertiaryContainer;
    } else if (statut == StatutDevis.refuse) {
      information = 'Ce devis a été refusé : il ne peut plus être modifié ni converti.';
    }

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
                      client == null ? 'Sans client' : libelleClient(client),
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Établi le ${formatDateCourte(devis.dateEmission)}'
                      '${validite == null ? '' : ' · valable jusqu’au ${formatDateCourte(validite)}'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(formatEuros(devis.totalCentimes), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  EtiquetteStatutDevis(statut),
                ],
              ),
            ],
          ),
          if (venteId != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Ce devis a été converti en commande.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ),
                  TextButton(onPressed: () => onOuvrirCommande(venteId), child: const Text('Voir la commande')),
                ],
              ),
            )
          else if (information != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
              child: Text(information, style: theme.textTheme.bodySmall?.copyWith(color: texte)),
            ),
        ],
      ),
    );
  }
}

/// Le PDF, tel qu'il sera partagé ou imprimé.
class _Apercu extends ConsumerWidget {
  const _Apercu({required this.detail});

  final DevisDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DevisFiche devis = detail.devis;
    final ClePdfDevis cle = (id: devis.id, version: versionPdfDevis(detail));
    final AsyncValue<Uint8List> pdf = ref.watch(devisPdfProvider(cle));
    return pdf.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object erreur, StackTrace pile) {
        debugPrint('PDF du devis impossible : $erreur\n$pile');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de fabriquer le PDF de ce devis.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(devisPdfProvider(cle)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );
      },
      data: (Uint8List octets) => ref.watch(constructeurApercuPdfProvider)(context, octets, '${devis.numero}.pdf'),
    );
  }
}

/// Partager et imprimer, puis modifier et convertir en commande selon le statut.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.detail,
    required this.maintenant,
    required this.occupe,
    required this.onPartager,
    required this.onImprimer,
    required this.onModifier,
    required this.onConvertir,
  });

  final DevisDetail detail;
  final DateTime maintenant;
  final bool occupe;
  final VoidCallback onPartager;
  final VoidCallback onImprimer;
  final VoidCallback onModifier;
  final VoidCallback onConvertir;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool modifiable = detail.peutModifier(maintenant);
    final bool convertible = detail.peutConvertir(maintenant);

    return Material(
      color: scheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonalIcon(
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
              if (modifiable || convertible) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    if (modifiable)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: occupe ? null : onModifier,
                          child: const Text('Modifier'),
                        ),
                      ),
                    if (modifiable && convertible) const SizedBox(width: 12),
                    if (convertible)
                      Expanded(
                        child: FilledButton(
                          onPressed: occupe ? null : onConvertir,
                          child: const Text('Convertir en commande'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
