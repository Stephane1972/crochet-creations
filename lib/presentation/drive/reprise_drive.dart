import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plateforme.dart';
import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../data/drive/service_sauvegarde_drive.dart';
import '../../data/providers.dart';
import '../../domain/drive_sauvegardes.dart';
import '../../domain/drive_synchro.dart';
import 'drive_providers.dart';
import 'drive_widgets.dart';

// Reprise d'un appareil à l'autre (le téléphone et l'ordinateur), côté écrans. Les règles sont dans `drive_synchro.dart`.

/// Ce que la personne répond à la proposition.
enum ReponseReprise { reprendre, garderCetAppareil }

String _dateHeure(DateTime date) => '${formatDateLongue(date)} à ${formatHeure(date)}';

/// Le titre de la proposition.
String titreReprise(ConstatSynchro constat) =>
    constat.situation == SituationSynchro.aReprendre ? 'Reprendre la version de Drive ?' : 'Deux versions différentes';

/// Ce qu'on dit à la personne : quelle version est sur Drive, et ce que chaque choix donne.
String texteReprise(ConstatSynchro constat) {
  final SauvegardeDrive? distante = constat.distante;
  final String quand = distante == null ? '' : ' (envoyée le ${_dateHeure(distante.date)})';
  if (constat.situation == SituationSynchro.aReprendre) {
    return 'Une version plus récente de vos données est sur Drive$quand, envoyée depuis un autre appareil. Rien n’a '
        'changé ici depuis la dernière synchronisation : vous pouvez la reprendre. Avant de remplacer quoi que ce soit, '
        'l’application vous demande confirmation et fait une copie de sécurité.';
  }
  return 'Une version plus récente de vos données est sur Drive$quand, mais les données de cet appareil ont aussi changé '
      'depuis la dernière synchronisation (ou on ne peut pas le dire). Les deux ne peuvent pas être fusionnées : choisissez '
      'celle que vous gardez.\n\n'
      '• Reprendre la version de Drive : les données de cet appareil sont remplacées (après confirmation et copie de '
      'sécurité).\n'
      '• Garder cet appareil : la version de Drive reste sur Drive mais n’est pas reprise ici ; le prochain envoi ajoutera '
      'celle de cet appareil comme version la plus récente. L’autre version restera restaurable depuis Réglages › Google '
      'Drive › Restaurer.\n\n'
      'Tant que vous n’avez pas choisi, rien n’est envoyé automatiquement.';
}

/// Montre la proposition (une fenêtre) et fait ce que la personne choisit. « Plus tard » ne change rien : la proposition reste
/// sur l'écran Google Drive.
Future<void> proposerReprise(BuildContext context, WidgetRef ref) async {
  final ConstatSynchro? constat = ref.read(repriseDriveProvider);
  final SauvegardeDrive? distante = constat?.distante;
  if (constat == null || distante == null) return;
  ref.read(repriseDriveProvider.notifier).dejaProposee = true;

  final bool aChoisir = constat.situation == SituationSynchro.aChoisir;
  final ReponseReprise? reponse = await showDialog<ReponseReprise>(
    context: context,
    builder: (BuildContext contexte) => AlertDialog(
      key: const Key('reprise-dialogue'),
      title: Text(titreReprise(constat)),
      content: SingleChildScrollView(child: Text(texteReprise(constat))),
      actions: <Widget>[
        TextButton(
          key: const Key('reprise-plus-tard'),
          onPressed: () => Navigator.of(contexte).pop(),
          child: const Text('Plus tard'),
        ),
        if (aChoisir)
          TextButton(
            key: const Key('reprise-garder'),
            onPressed: () => Navigator.of(contexte).pop(ReponseReprise.garderCetAppareil),
            child: const Text('Garder cet appareil'),
          ),
        FilledButton(
          key: const Key('reprise-reprendre'),
          onPressed: () => Navigator.of(contexte).pop(ReponseReprise.reprendre),
          child: Text(aChoisir ? 'Reprendre la version de Drive' : 'Reprendre'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (reponse) {
    case ReponseReprise.reprendre:
      // L'écran de restauration télécharge cette sauvegarde, dit ce qu'elle contient et demande confirmation.
      unawaited(Navigator.of(context).pushNamed(AppRoutes.driveRestauration, arguments: distante));
    case ReponseReprise.garderCetAppareil:
      await ref.read(repriseDriveProvider.notifier).garderCetAppareil();
    case null:
      break;
  }
}

/// Sur l'écran Google Drive : la proposition en attente (rien si aucune).
class CarteRepriseDrive extends ConsumerWidget {
  const CarteRepriseDrive({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ConstatSynchro? constat = ref.watch(repriseDriveProvider);
    if (constat == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CarteDrive(
        titre: 'Une version plus récente est sur Drive',
        enfants: <Widget>[
          Text(texteReprise(constat), key: const Key('drive-reprise-texte')),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('drive-reprise-decider'),
            onPressed: () => proposerReprise(context, ref),
            icon: const Icon(Icons.cloud_sync_outlined),
            label: const Text('Décider'),
          ),
        ],
      ),
    );
  }
}

/// Entoure l'écran principal et s'occupe de la synchronisation entre appareils :
/// - à l'ouverture, montre la proposition de reprise quand Drive a une version plus récente ;
/// - sous Windows, envoie ce qui a changé quand on ferme la fenêtre (avec un message, et la possibilité de fermer sans attendre) ;
/// - sous Android, envoie ce qui a changé quand l'application passe en arrière-plan (au plus toutes les 10 minutes).
/// Tout cela seulement si l'envoi automatique est activé et que Google est connecté (le notifier le vérifie).
class SynchroDriveObservateur extends ConsumerStatefulWidget {
  const SynchroDriveObservateur({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SynchroDriveObservateur> createState() => SynchroDriveObservateurState();
}

class SynchroDriveObservateurState extends ConsumerState<SynchroDriveObservateur> {
  /// Après ce délai sans avoir fini, la fermeture montre un message (sinon la fenêtre se ferme sans rien montrer).
  static const Duration delaiAvantMessage = Duration(milliseconds: 700);

  late final AppLifecycleListener _ecoute;
  late final ProviderSubscription<ConstatSynchro?> _abonnement;
  DateTime? _dernierEnvoiEnArrierePlan;
  bool _sortieEnCours = false;

  @override
  void initState() {
    super.initState();
    final bool bureau = ref.read(plateformeProvider).fenetreDeBureau;
    _ecoute = AppLifecycleListener(
      onPause: bureau ? null : aLArrierePlan,
      onExitRequested: bureau ? demandeDeSortie : null,
    );
    // Une proposition peut être déjà là (l'envoi d'ouverture a fini avant l'affichage de l'écran) ou arriver ensuite.
    _abonnement = ref.listenManual<ConstatSynchro?>(repriseDriveProvider, (ConstatSynchro? avant, ConstatSynchro? apres) {
      if (apres == null || ref.read(repriseDriveProvider.notifier).dejaProposee) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(repriseDriveProvider) == null) return;
        if (ref.read(repriseDriveProvider.notifier).dejaProposee) return;
        unawaited(proposerReprise(context, ref));
      });
      // Un écran au repos ne dessine rien tout seul : on demande une image pour que la fenêtre apparaisse.
      WidgetsBinding.instance.ensureVisualUpdate();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _abonnement.close();
    _ecoute.dispose();
    super.dispose();
  }

  /// L'application passe en arrière-plan (Android) : envoi discret, espacé. (Publique pour les tests.)
  void aLArrierePlan() {
    final DateTime maintenant = ref.read(horlogeProvider)();
    if (!envoiEnArrierePlanPermis(_dernierEnvoiEnArrierePlan, maintenant)) return;
    _dernierEnvoiEnArrierePlan = maintenant;
    unawaited(ref.read(sauvegardeDriveProvider.notifier).envoyerEnArrierePlan());
  }

  /// La fenêtre se ferme (Windows) : on envoie ce qui a changé, puis on laisse fermer. Ne bloque jamais la fermeture : le
  /// bouton « Fermer sans attendre » la laisse faire à tout moment. (Publique pour les tests.)
  Future<AppExitResponse> demandeDeSortie() async {
    if (_sortieEnCours) return AppExitResponse.exit;
    _sortieEnCours = true;
    try {
      final Future<void> travail = ref.read(sauvegardeDriveProvider.notifier).envoyerEnQuittant();
      // Fini avant le délai : on ferme sans rien montrer (et sans laisser de minuteur derrière soi).
      final Completer<bool> premier = Completer<bool>();
      final Timer minuteur = Timer(delaiAvantMessage, () {
        if (!premier.isCompleted) premier.complete(false);
      });
      unawaited(
        travail.whenComplete(() {
          if (!premier.isCompleted) premier.complete(true);
        }),
      );
      final bool fini = await premier.future;
      minuteur.cancel();
      if (!fini && mounted) {
        final Completer<void> sansAttendre = Completer<void>();
        bool dialogueOuvert = true;
        unawaited(
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext contexte) => _DialogueEnvoiAvantFermeture(
              onSansAttendre: () {
                dialogueOuvert = false;
                Navigator.of(contexte).pop();
                ref.read(sauvegardeDriveProvider.notifier).arreter();
                if (!sansAttendre.isCompleted) sansAttendre.complete();
              },
            ),
          ),
        );
        await Future.any<void>(<Future<void>>[travail, sansAttendre.future]);
        if (dialogueOuvert && mounted) Navigator.of(context).pop();
      }
    } finally {
      _sortieEnCours = false;
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DialogueEnvoiAvantFermeture extends ConsumerWidget {
  const _DialogueEnvoiAvantFermeture({required this.onSansAttendre});

  final VoidCallback onSansAttendre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SuiviSauvegardeDrive suivi = ref.watch(sauvegardeDriveProvider);
    final ProgressionSauvegardeDrive? progression = suivi.progression;
    final double? valeur = suivi.occupe && progression != null
        ? ((progression.numeroEtape - 1) +
                  (progression.etape == EtapeSauvegardeDrive.fichiers ? (progression.fichiers?.fraction ?? 0) : 0)) /
              3
        : null;
    final String etape = !suivi.occupe || progression == null
        ? 'Vérification de Drive…'
        : switch (progression.etape) {
            EtapeSauvegardeDrive.fichiers => 'Étape 1 sur 3 : envoi des photos et documents…',
            EtapeSauvegardeDrive.donnees => 'Étape 2 sur 3 : préparation de la sauvegarde…',
            EtapeSauvegardeDrive.envoi => 'Étape 3 sur 3 : envoi de la sauvegarde, puis vérification…',
          };
    return AlertDialog(
      key: const Key('fermeture-dialogue'),
      title: const Text('Envoi vers Drive avant de fermer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: valeur?.clamp(0.0, 1.0).toDouble()),
          const SizedBox(height: 12),
          Text(etape, key: const Key('fermeture-etape')),
          const SizedBox(height: 8),
          texteDiscretDrive(
            context,
            'Vos données partent sur Drive pour les retrouver sur l’autre appareil. Si vous fermez sans attendre, elles '
            'seront envoyées à la prochaine ouverture.',
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('fermeture-sans-attendre'),
          onPressed: onSansAttendre,
          child: const Text('Fermer sans attendre'),
        ),
      ],
    );
  }
}
