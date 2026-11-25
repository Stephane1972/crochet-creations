import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_fr.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/notifications/service_rappels_declaration.dart';
import '../../data/providers.dart';
import '../../data/repositories/statistiques_repository.dart';
import '../../domain/calculs/statistiques.dart';
import '../../domain/declaration.dart';
import 'declaration_providers.dart';

/// Plus › Déclaration des recettes : le rappel de fin de mois (activer, désactiver, tester) et ce qui a été encaissé
/// ce mois-ci et le mois dernier, pour le reporter sur le site de l'organisme. L'application n'envoie rien à l'organisme.
class DeclarationScreen extends ConsumerStatefulWidget {
  const DeclarationScreen({super.key});

  @override
  ConsumerState<DeclarationScreen> createState() => _DeclarationScreenState();
}

class _DeclarationScreenState extends ConsumerState<DeclarationScreen> {
  bool _enCours = false;

  Future<void> _changerRappel(bool actif) async {
    setState(() => _enCours = true);
    try {
      final ServiceRappelsDeclaration service = ref.read(serviceRappelsDeclarationProvider);
      if (actif) {
        final ResultatRappel resultat = await service.activer();
        if (!mounted) return;
        _expliquerRefus(resultat, 'Le rappel n’est pas activé.');
      } else {
        await service.desactiver();
      }
      ref.invalidate(notificationsAutoriseesProvider);
    } catch (erreur) {
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _tester() async {
    setState(() => _enCours = true);
    try {
      final ResultatRappel resultat = await ref.read(serviceRappelsDeclarationProvider).tester();
      if (!mounted) return;
      if (resultat == ResultatRappel.reussi) {
        afficherMessage(
          context,
          'Notification envoyée. Si vous ne la voyez pas, vérifiez les réglages de notifications de l’appareil.',
        );
      } else {
        _expliquerRefus(resultat, 'Aucune notification n’a été envoyée.');
      }
      ref.invalidate(notificationsAutoriseesProvider);
    } catch (erreur) {
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _expliquerRefus(ResultatRappel resultat, String consequence) {
    switch (resultat) {
      case ResultatRappel.reussi:
        break;
      case ResultatRappel.autorisationRefusee:
        afficherMessage(
          context,
          '$consequence Les notifications sont refusées : autorisez-les pour l’application dans les réglages de l’appareil.',
        );
      case ResultatRappel.indisponible:
        afficherMessage(context, '$consequence Les notifications ne sont pas disponibles sur cet appareil.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ServiceRappelsDeclaration service = ref.watch(serviceRappelsDeclarationProvider);
    final bool actif = ref.watch(rappelDeclarationProvider).valueOrNull ?? false;
    final bool autorise = ref.watch(notificationsAutoriseesProvider).valueOrNull ?? true;
    final AsyncValue<RecettesDeclaration> recettes = ref.watch(recettesDeclarationProvider);
    final DateTime maintenant = ref.watch(horlogeProvider)();
    final List<RappelDeclaration> prochains = prochainsRappelsDeclaration(maintenant, mois: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Déclaration des recettes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          _CarteRappel(
            disponible: service.disponible,
            actif: actif,
            autorise: autorise,
            enCours: _enCours,
            prochain: prochains.isEmpty ? null : prochains.first,
            onChanger: _changerRappel,
            onTester: _tester,
          ),
          const SizedBox(height: 12),
          if (recettes.hasError && !recettes.hasValue)
            const _Message('Impossible de calculer les recettes pour le moment.')
          else if (!recettes.hasValue)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else ...<Widget>[
            _CarteRecettes(titre: 'Ce mois-ci', periode: recettes.requireValue.courant),
            const SizedBox(height: 12),
            _CarteRecettes(titre: 'Le mois dernier', periode: recettes.requireValue.precedent),
            const SizedBox(height: 12),
            const _Message(
              'Argent réellement encaissé, remboursements déduits : le chiffre d’affaires des Statistiques. '
              'L’application n’envoie rien à l’organisme : reportez ces montants sur son site.',
            ),
          ],
        ],
      ),
    );
  }
}

class _CarteRappel extends StatelessWidget {
  const _CarteRappel({
    required this.disponible,
    required this.actif,
    required this.autorise,
    required this.enCours,
    required this.prochain,
    required this.onChanger,
    required this.onTester,
  });

  final bool disponible;
  final bool actif;
  final bool autorise;
  final bool enCours;
  final RappelDeclaration? prochain;
  final ValueChanged<bool> onChanger;
  final VoidCallback onTester;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme couleurs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Rappel de fin de mois', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (!disponible)
              Text(
                'Les rappels ne sont pas disponibles sur cet appareil.',
                style: theme.textTheme.bodyMedium?.copyWith(color: couleurs.onSurfaceVariant),
              )
            else ...<Widget>[
              SwitchListTile(
                key: const ValueKey<String>('rappel-declaration'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Me rappeler la déclaration'),
                subtitle: Text(
                  'Une notification $joursAvantDeclaration jours avant la fin du mois, puis le dernier jour, à '
                  '$heureRappelDeclaration h. Elle apparaît même si l’application est fermée.',
                ),
                value: actif,
                onChanged: enCours ? null : onChanger,
              ),
              if (actif && prochain != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Prochain rappel : ${formatDateLongue(prochain!.quand)} à ${formatHeure(prochain!.quand)}.',
                    key: const ValueKey<String>('prochain-rappel'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (actif && !autorise)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Les notifications sont bloquées pour l’application : aucun rappel n’apparaîtra tant que vous ne les '
                    'autorisez pas dans les réglages de l’appareil.',
                    key: const ValueKey<String>('rappel-bloque'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: couleurs.error),
                  ),
                ),
              OutlinedButton.icon(
                key: const ValueKey<String>('rappel-tester'),
                onPressed: enCours ? null : onTester,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Tester la notification'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CarteRecettes extends StatelessWidget {
  const _CarteRecettes({required this.titre, required this.periode});

  final String titre;
  final StatsPeriode periode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String mois = formatMois(periode.debut.year, periode.debut.month);

    Widget ligne(String libelle, int centimes, {bool fort = false, String? cle}) {
      final TextStyle? style = fort ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(libelle, style: style)),
            Text(formatEuros(centimes), key: cle == null ? null : ValueKey<String>(cle), style: style),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('$titre : $mois', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ligne('Ventes d’objets', periode.encaisseObjetsCentimes),
            ligne('Prestations et cours', periode.encaissePrestationsCentimes),
            const Divider(height: 16),
            ligne('Total encaissé', periode.encaisseTotalCentimes, fort: true, cle: 'total-${periode.debut.year}-${periode.debut.month}'),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(texte, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
