import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/client_repository.dart';
import '../../data/repositories/client_vues.dart';
import '../../domain/enums.dart';
import '../../domain/regles_devis.dart';
import 'client_widgets.dart';
import 'clients_providers.dart';

enum _ActionMenu { archiver, restaurer }

/// Fiche d'un client : coordonnées et historique des devis, ventes, factures, paiements et cours (écran 7).
class ClientFicheScreen extends ConsumerStatefulWidget {
  const ClientFicheScreen({super.key, required this.clientId});

  final int clientId;

  @override
  ConsumerState<ClientFicheScreen> createState() => _ClientFicheScreenState();
}

class _ClientFicheScreenState extends ConsumerState<ClientFicheScreen> {
  ClientRepository get _repo => ref.read(clientRepositoryProvider);

  /// Exécute une action et affiche l'erreur éventuelle en français.
  Future<void> _executer(Future<void> Function() action) async {
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Action sur le client impossible : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    }
  }

  void _modifier() {
    Navigator.of(context).pushNamed(AppRoutes.clientModifier, arguments: widget.clientId);
  }

  Future<void> _archiver(Client client) async {
    final bool ok = await confirmer(
      context,
      titre: 'Archiver ce client ?',
      message:
          '« ${libelleClient(client)} » disparaîtra de la liste des clients, mais ses ventes, '
          'factures et devis restent conservés. Vous pourrez le restaurer à tout moment.',
      libelleConfirmer: 'Archiver',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await _repo.archiver(client.id);
      if (mounted) afficherMessage(context, 'Client archivé.');
    });
  }

  Future<void> _restaurer(Client client) => _executer(() async {
    await _repo.restaurer(client.id);
    if (mounted) afficherMessage(context, 'Client restauré dans la liste.');
  });

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Client?> fiche = ref.watch(clientProvider(widget.clientId));
    final Client? client = fiche.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(client == null ? 'Client' : libelleClient(client), overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (client != null) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifier',
              onPressed: _modifier,
            ),
            PopupMenuButton<_ActionMenu>(
              tooltip: 'Plus d’actions',
              onSelected: (_ActionMenu action) {
                switch (action) {
                  case _ActionMenu.archiver:
                    _archiver(client);
                  case _ActionMenu.restaurer:
                    _restaurer(client);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<_ActionMenu>>[
                if (client.archiveLe == null)
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
      body: fiche.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object erreur, StackTrace pile) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Impossible de charger ce client.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(clientProvider(widget.clientId)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (Client? c) {
          if (c == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Ce client n’existe plus.', textAlign: TextAlign.center),
              ),
            );
          }
          return _Contenu(client: c, onRestaurer: () => _restaurer(c));
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Contenu
// -----------------------------------------------------------------------------

class _Contenu extends StatelessWidget {
  const _Contenu({required this.client, required this.onRestaurer});

  final Client client;
  final VoidCallback onRestaurer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final String? contact = contactClient(client);
    final List<Widget> etiquettes = etiquettesClient(context, client);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        if (client.archiveLe != null) ...<Widget>[
          _BandeauArchive(onRestaurer: onRestaurer),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            PastilleClient(client: client, taille: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(libelleClient(client), style: theme.textTheme.headlineSmall),
                  if (contact != null)
                    Text(contact, style: theme.textTheme.bodyMedium?.copyWith(color: discret)),
                  if (etiquettes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: etiquettes),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CarteCoordonnees(client: client),
        const SizedBox(height: 12),
        _CarteHistorique(clientId: client.id),
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
              'Client archivé : il n’apparaît plus dans la liste.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onRestaurer, child: const Text('Restaurer')),
        ],
      ),
    );
  }
}

class _CarteSection extends StatelessWidget {
  const _CarteSection({required this.titre, required this.child});

  final String titre;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
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
            width: 110,
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

class _CarteCoordonnees extends StatelessWidget {
  const _CarteCoordonnees({required this.client});

  final Client client;

  /// « 12 rue des Lilas » puis « 31000 Toulouse » sur deux lignes.
  String? get _adresse {
    final String villeComplete = <String?>[
      client.codePostal,
      client.ville,
    ].whereType<String>().where((String s) => s.trim().isNotEmpty).join(' ');
    final List<String> lignes = <String>[
      if (client.adresse != null) client.adresse!,
      if (villeComplete.isNotEmpty) villeComplete,
    ];
    return lignes.isEmpty ? null : lignes.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final Color discret = Theme.of(context).colorScheme.onSurfaceVariant;
    final String? adresse = _adresse;
    final bool pro = client.typeClient == TypeClient.professionnel;
    final List<Widget> lignes = <Widget>[
      _LigneInfo('Type', client.typeClient.libelle),
      if (client.civilite != null) _LigneInfo('Civilité', client.civilite!.libelle),
      if (client.telephone != null) _LigneInfo('Téléphone', client.telephone!),
      if (client.email != null) _LigneInfo('E-mail', client.email!),
      if (adresse != null) _LigneInfo('Adresse', adresse),
      if (pro && client.siret != null) _LigneInfo('SIREN / SIRET', client.siret!),
      if (client.notes != null) _LigneInfo('Notes', client.notes!),
    ];

    return _CarteSection(
      titre: 'Coordonnées',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ...lignes,
          if (lignes.length == 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Aucune coordonnée enregistrée. Utilisez « Modifier » pour en ajouter.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: discret),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Historique
// -----------------------------------------------------------------------------

class _CarteHistorique extends ConsumerWidget {
  const _CarteHistorique({required this.clientId});

  final int clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HistoriqueClient> historique = ref.watch(historiqueClientProvider(clientId));

    return _CarteSection(
      titre: 'Historique',
      child: historique.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (Object erreur, StackTrace pile) => const Text('Impossible de charger l’historique.'),
        data: (HistoriqueClient h) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHistorique<VenteClient>(
              titre: 'Ventes',
              resume: h.ventes.isEmpty
                  ? null
                  : '${h.nombreVentesValidees} vente${h.nombreVentesValidees > 1 ? 's' : ''} validée'
                        '${h.nombreVentesValidees > 1 ? 's' : ''} · ${formatEuros(h.totalAchatsCentimes)}',
              vide: 'Aucune vente.',
              elements: h.ventes,
              ligne: (BuildContext context, VenteClient v) => _LigneHistorique(
                titre: formatDateCourte(v.dateVente),
                detail: v.statut == StatutVente.annulee ? 'Annulée' : v.statutPaiement.libelle,
                montant: formatEuros(v.totalCentimes),
                onTap: () => _ouvrirVente(context, v.venteId),
              ),
            ),
            _SectionHistorique<PaiementClient>(
              titre: 'Paiements',
              vide: 'Aucun paiement.',
              elements: h.paiements,
              ligne: (BuildContext context, PaiementClient p) => _LigneHistorique(
                titre: formatDateCourte(p.datePaiement),
                detail: p.montantCentimes < 0 ? 'Remboursement · ${p.mode.libelle}' : p.mode.libelle,
                montant: formatEuros(p.montantCentimes),
                onTap: () => _ouvrirVente(context, p.venteId),
              ),
            ),
            _SectionHistorique<Facture>(
              titre: 'Factures',
              vide: 'Aucune facture.',
              elements: h.factures,
              ligne: (BuildContext context, Facture f) => _LigneHistorique(
                titre: f.numero,
                detail: '${formatDateCourte(f.dateEmission)} · ${f.statut.libelle}',
                montant: formatEuros(f.totalCentimes),
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.factureDetail, arguments: f.id),
              ),
            ),
            _SectionHistorique<DevisFiche>(
              titre: 'Devis',
              vide: 'Aucun devis.',
              elements: h.devis,
              ligne: (BuildContext context, DevisFiche d) => _LigneHistorique(
                titre: d.numero,
                detail:
                    '${formatDateCourte(d.dateEmission)} · '
                    '${statutAffiche(d.statut, d.dateValidite, DateTime.now()).libelle}',
                montant: formatEuros(d.totalCentimes),
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.devisDetail, arguments: d.id),
              ),
            ),
            _SectionHistorique<InscriptionClient>(
              titre: 'Cours',
              vide: 'Aucune inscription à un cours.',
              elements: h.inscriptions,
              dernier: true,
              ligne: (BuildContext context, InscriptionClient i) => _LigneHistorique(
                titre: i.titreCours,
                detail: '${formatDateCourte(i.debutCours)} · ${i.statut.libelle}',
                montant: formatEuros(i.prixCentimes),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ouvre une vente du client : détail, encaissement du solde, annulation.
void _ouvrirVente(BuildContext context, int venteId) {
  Navigator.of(context).pushNamed(AppRoutes.venteConfirmation, arguments: venteId);
}

/// Une ligne de l'historique : titre, détail et montant à droite.
class _LigneHistorique extends StatelessWidget {
  const _LigneHistorique({required this.titre, required this.detail, required this.montant, this.onTap});

  final String titre;
  final String detail;
  final String montant;

  /// Ouvre l'élément (une vente, par exemple) ; `null` = ligne non cliquable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(titre),
      subtitle: Text(detail),
      trailing: Text(montant, style: theme.textTheme.titleSmall),
      onTap: onTap,
    );
  }
}

/// Une rubrique de l'historique (ventes, paiements...) : les 5 plus récentes, puis « Voir tout ».
class _SectionHistorique<T> extends StatefulWidget {
  const _SectionHistorique({
    required this.titre,
    required this.vide,
    required this.elements,
    required this.ligne,
    this.resume,
    this.dernier = false,
  });

  final String titre;
  final String vide;
  final List<T> elements;
  final Widget Function(BuildContext context, T element) ligne;

  /// Phrase de synthèse sous le titre (« 3 ventes validées · 85 € »).
  final String? resume;
  final bool dernier;

  @override
  State<_SectionHistorique<T>> createState() => _SectionHistoriqueState<T>();
}

class _SectionHistoriqueState<T> extends State<_SectionHistorique<T>> {
  static const int _apercu = 5;
  bool _toutVoir = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final List<T> tous = widget.elements;
    final List<T> visibles = _toutVoir ? tous : tous.take(_apercu).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: widget.dernier ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.titre, style: theme.textTheme.titleSmall),
          if (widget.resume != null)
            Text(widget.resume!, style: theme.textTheme.bodySmall?.copyWith(color: discret)),
          if (tous.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(widget.vide, style: theme.textTheme.bodyMedium?.copyWith(color: discret)),
            ),
          for (final T element in visibles) widget.ligne(context, element),
          if (tous.length > _apercu)
            TextButton(
              onPressed: () => setState(() => _toutVoir = !_toutVoir),
              child: Text(_toutVoir ? 'Voir moins' : 'Voir les ${tous.length}'),
            ),
        ],
      ),
    );
  }
}
