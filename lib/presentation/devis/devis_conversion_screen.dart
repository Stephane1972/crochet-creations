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
import '../../domain/erreurs.dart';
import '../entreprise/profil_incomplet.dart';
import '../ventes/recap_widgets.dart';
import 'devis_providers.dart';

/// Conversion d'un devis en commande, et en facture si on le souhaite (écran 15).
///
/// Deux choix : « Créer la commande » (la facture se fera plus tard depuis la vente) ou « Créer la commande et
/// la facture ». Si le devis demande un acompte, on peut l'enregistrer comme premier paiement de la commande.
class DevisConversionScreen extends ConsumerStatefulWidget {
  const DevisConversionScreen({super.key, required this.devisId});

  final int devisId;

  @override
  ConsumerState<DevisConversionScreen> createState() => _DevisConversionScreenState();
}

class _DevisConversionScreenState extends ConsumerState<DevisConversionScreen> {
  bool _acompteRecu = false;
  ModePaiement _mode = ModePaiement.especes;
  bool _enCours = false;

  /// La commande est créée : en attendant que son écran s'affiche, celui-ci ne montre plus le devis.
  bool _converti = false;

  Future<void> _convertir(DevisDetail detail, {required bool avecFacture}) async {
    if (_enCours) return;
    setState(() => _enCours = true);
    try {
      final ResultatConversion resultat = await ref
          .read(devisRepositoryProvider)
          .convertir(
            detail.devis.id,
            avecFacture: avecFacture,
            modeAcompte: _acompteRecu && detail.devis.acompteCentimes > 0 ? _mode : null,
          );
      if (!mounted) return;
      setState(() => _converti = true);
      final String? probleme = resultat.problemeFacture;
      if (probleme != null) {
        afficherMessage(
          context,
          'La commande est créée, mais pas sa facture : $probleme Vous pourrez la créer depuis la commande.',
        );
      } else if (resultat.facture != null) {
        afficherMessage(context, 'Commande et facture ${resultat.facture!.numero} créées.');
      } else {
        afficherMessage(context, 'Commande créée.');
      }
      await Navigator.of(context).pushReplacementNamed(AppRoutes.venteConfirmation, arguments: resultat.vente.id);
    } on ProfilIncomplet catch (manque) {
      if (!mounted) return;
      setState(() => _enCours = false);
      await proposerProfilComplet(context, manque);
    } catch (erreur, pile) {
      debugPrint('Conversion du devis impossible : $erreur\n$pile');
      if (mounted) {
        afficherMessage(context, messageErreur(erreur));
        setState(() => _enCours = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DevisDetail?> detail = ref.watch(devisDetailProvider(widget.devisId));

    return Scaffold(
      appBar: AppBar(title: const Text('Convertir le devis')),
      body: _converti
          ? const SizedBox.shrink()
          : detail.when(
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
                if (d == null) return const _Message('Ce devis n’existe plus.');
                if (!d.peutConvertir(DateTime.now())) {
                  return _Message(
                    d.estConverti
                        ? 'Ce devis a déjà été converti en commande.'
                        : 'Ce devis ne peut pas être converti : il est ${d.statut(DateTime.now()).libelle.toLowerCase()}.',
                  );
                }
                return _corps(context, d);
              },
            ),
    );
  }

  Widget _corps(BuildContext context, DevisDetail detail) {
    final ThemeData theme = Theme.of(context);
    final Color discret = theme.colorScheme.onSurfaceVariant;
    final DevisFiche devis = detail.devis;
    final Client? client = detail.client;
    final bool acompte = devis.acompteCentimes > 0;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              CarteRubrique(
                titre: 'Devis ${devis.numero}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${client == null ? 'Sans client' : libelleClient(client)} · '
                      'établi le ${formatDateCourte(devis.dateEmission)}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: discret),
                    ),
                    const SizedBox(height: 8),
                    for (final LigneDevis l in detail.lignes)
                      LigneMontant(libelle: '${l.quantite} × ${l.designation}', montant: formatEuros(l.totalLigneCentimes)),
                    if (devis.remiseCentimes > 0)
                      LigneMontant(libelle: 'Remise', montant: '−${formatEuros(devis.remiseCentimes)}'),
                    if (devis.fraisPortCentimes > 0)
                      LigneMontant(libelle: 'Frais de port', montant: formatEuros(devis.fraisPortCentimes)),
                    const Divider(),
                    LigneMontant(libelle: 'Total', montant: formatEuros(devis.totalCentimes), fort: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (acompte)
                CarteRubrique(
                  titre: 'Acompte',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _acompteRecu,
                        onChanged: _enCours ? null : (bool? valeur) => setState(() => _acompteRecu = valeur ?? false),
                        title: const Text('Acompte reçu'),
                        subtitle: Text('${formatEuros(devis.acompteCentimes)} demandés par le devis'),
                      ),
                      if (_acompteRecu) ...<Widget>[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<ModePaiement>(
                          initialValue: _mode,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Mode de paiement'),
                          items: <DropdownMenuItem<ModePaiement>>[
                            for (final ModePaiement m in ModePaiement.values)
                              DropdownMenuItem<ModePaiement>(value: m, child: Text(m.libelle)),
                          ],
                          onChanged: _enCours
                              ? null
                              : (ModePaiement? valeur) {
                                  if (valeur != null) setState(() => _mode = valeur);
                                },
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _acompteRecu
                            ? 'L’acompte est enregistré comme premier paiement : la commande est « partiellement payée ».'
                            : 'Sans cela, la commande reste impayée : vous pourrez encaisser l’acompte plus tard.',
                        style: theme.textTheme.bodySmall?.copyWith(color: discret),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'La commande reprend les lignes, la remise et les frais de port du devis. '
                'Elle n’a aucun effet sur le stock. Le devis passe à « Accepté ».',
                style: theme.textTheme.bodySmall?.copyWith(color: discret),
              ),
            ],
          ),
        ),
        Material(
          elevation: 6,
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _enCours ? null : () => _convertir(detail, avecFacture: true),
                      child: const Text('Créer la commande et la facture'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _enCours ? null : () => _convertir(detail, avecFacture: false),
                      child: const Text('Créer la commande'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(texte, textAlign: TextAlign.center),
      ),
    );
  }
}
