import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/utils/date_fr.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/agenda/service_agenda_google.dart';
import '../../data/drive/compte_google.dart';
import '../../data/providers.dart';
import '../../domain/agenda.dart';
import '../../domain/agenda_google.dart';
import '../drive/drive_providers.dart';
import '../drive/drive_widgets.dart';
import 'agenda_google_providers.dart';

/// Calendrier › Google Agenda : envoyer le calendrier de l'application vers un agenda Google, créé pour elle dans le compte de la
/// personne. Un seul sens (de l'application vers Google), rien n'est supprimé sans demande, aucun autre agenda n'est lu.
class AgendaGoogleScreen extends ConsumerStatefulWidget {
  const AgendaGoogleScreen({super.key});

  @override
  ConsumerState<AgendaGoogleScreen> createState() => _AgendaGoogleScreenState();
}

class _AgendaGoogleScreenState extends ConsumerState<AgendaGoogleScreen> {
  /// Une action de cet écran (nettoyage) est en cours.
  bool _occupe = false;

  Future<void> _activer() async {
    final BilanSynchro bilan = await ref.read(synchroAgendaGoogleProvider.notifier).activer();
    ref.invalidate(droitAgendaGoogleProvider);
    if (!mounted) return;
    switch (bilan.issue) {
      case IssueSynchro.annulee:
        afficherMessage(context, 'Autorisation annulée : la synchronisation n’est pas activée.');
      case IssueSynchro.nonConnecte:
        afficherMessage(context, 'Connectez-vous d’abord à Google (Réglages › Google Drive).');
      case IssueSynchro.indisponible:
        afficherMessage(context, 'Google Agenda n’est pas disponible sur cet appareil.');
      default:
        break;
    }
  }

  Future<void> _changer(bool actif) async {
    if (actif) {
      await _activer();
      return;
    }
    try {
      await ref.read(synchroAgendaGoogleProvider.notifier).desactiver();
    } catch (erreur) {
      if (mounted) afficherMessage(context, messageErreur(erreur));
    }
  }

  Future<void> _synchroniser() async {
    await ref.read(synchroAgendaGoogleProvider.notifier).synchroniser();
    ref.invalidate(droitAgendaGoogleProvider);
  }

  Future<void> _recreer() async {
    await ref.read(synchroAgendaGoogleProvider.notifier).recreerAgenda();
    ref.invalidate(droitAgendaGoogleProvider);
  }

  Future<void> _ouvrirGoogleAgenda(String? compte) async {
    final bool ouverte = await ref.read(ouvreurAdresseProvider).ouvrir(lienOuvrirGoogleAgenda(compte: compte));
    if (!ouverte && mounted) {
      afficherMessage(
        context,
        'Impossible d’ouvrir Google Agenda. Vérifiez qu’un navigateur est installé et que l’appareil est connecté à Internet.',
      );
    }
  }

  Future<void> _nettoyer() async {
    setState(() => _occupe = true);
    try {
      final ServiceAgendaGoogle service = ref.read(serviceAgendaGoogleProvider);
      final List<EvenementGoogle> annules = await service.evenementsAnnules();
      if (!mounted) return;
      if (annules.isEmpty) {
        afficherMessage(context, 'Aucun événement « [Annulé] » dans Google Agenda : il n’y a rien à nettoyer.');
        return;
      }
      final int n = annules.length;
      final bool confirme = await confirmer(
        context,
        titre: 'Nettoyer l’agenda Google ?',
        message:
            '${n > 1 ? '$n événements marqués' : '1 événement marqué'} « [Annulé] » ${n > 1 ? 'seront supprimés' : 'sera supprimé'} '
            'définitivement de Google Agenda. Rien n’est supprimé dans l’application.',
        libelleConfirmer: 'Supprimer',
      );
      if (!confirme || !mounted) return;
      final ({int supprimes, int echecs}) resultat = await service.nettoyer();
      if (!mounted) return;
      final String fait = resultat.supprimes > 1
          ? '${resultat.supprimes} événements supprimés de Google Agenda.'
          : '${resultat.supprimes} événement supprimé de Google Agenda.';
      afficherMessage(
        context,
        resultat.echecs == 0 ? fait : '$fait ${resultat.echecs} n’ont pas pu l’être : réessayez plus tard.',
      );
    } on ErreurDrive catch (erreur) {
      if (mounted) afficherMessage(context, erreur.message);
    } catch (erreur) {
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ServiceAgendaGoogle service = ref.watch(serviceAgendaGoogleProvider);
    final AsyncValue<ProfilGoogle?> profil = ref.watch(profilGoogleProvider);
    final ReglageAgendaGoogle reglage = ref.watch(reglageAgendaGoogleProvider).valueOrNull ?? (actif: false, calendrier: null);
    final bool? droit = ref.watch(droitAgendaGoogleProvider).valueOrNull;
    final EtatSynchroAgendaGoogle etat = ref.watch(synchroAgendaGoogleProvider);
    final String? email = profil.valueOrNull?.email;
    final bool occupe = _occupe || etat.enCours;

    return Scaffold(
      appBar: AppBar(title: const Text('Google Agenda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          CarteDrive(
            titre: 'Envoyer mon calendrier vers Google Agenda',
            enfants: <Widget>[
              texteDiscretDrive(
                context,
                'L’application crée son propre agenda « $nomAgendaGoogle » dans votre compte Google et y envoie vos cours, '
                'la fin de validité de vos devis, les jours de déclaration et vos événements, du mois dernier jusqu’à '
                '$moisFutursSynchronises mois plus tard. Ils apparaissent alors dans Google Agenda sur tous vos appareils.',
              ),
              const SizedBox(height: 12),
              if (!service.disponible)
                texteErreurDrive(
                  context,
                  'Google Agenda n’est pas disponible sur cet appareil.',
                  key: const ValueKey<String>('agenda-google-indisponible'),
                )
              else if (profil.isLoading && !profil.hasValue)
                const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
              else if (email == null) ...<Widget>[
                texteErreurDrive(
                  context,
                  'Vous n’êtes pas connecté à Google. Connectez-vous d’abord (c’est le même compte que pour Google Drive).',
                  key: const ValueKey<String>('agenda-google-non-connecte'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey<String>('agenda-google-connexion'),
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.drive),
                  icon: const Icon(Icons.login),
                  label: const Text('Me connecter à Google'),
                ),
              ] else ...<Widget>[
                SwitchListTile(
                  key: const ValueKey<String>('agenda-google-actif'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Synchroniser avec Google Agenda'),
                  subtitle: Text('Compte Google : $email'),
                  value: reglage.actif,
                  onChanged: occupe ? null : _changer,
                ),
                if (reglage.actif && droit == false) ...<Widget>[
                  texteErreurDrive(
                    context,
                    'Le droit « Google Agenda » n’est pas accordé (ou a été retiré) : l’agenda n’est pas mis à jour.',
                    key: const ValueKey<String>('agenda-google-droit-absent'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey<String>('agenda-google-autoriser'),
                    onPressed: occupe ? null : _activer,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Autoriser Google Agenda'),
                  ),
                ],
              ],
            ],
          ),
          if (service.disponible && email != null && reglage.actif) ...<Widget>[
            const SizedBox(height: 12),
            CarteDrive(
              titre: 'Synchronisation',
              enfants: <Widget>[
                _Bilan(etat: etat),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const ValueKey<String>('agenda-google-synchroniser'),
                      onPressed: occupe ? null : _synchroniser,
                      icon: const Icon(Icons.sync),
                      label: const Text('Synchroniser maintenant'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('agenda-google-ouvrir'),
                      onPressed: () => _ouvrirGoogleAgenda(email),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Ouvrir Google Agenda'),
                    ),
                    if (etat.bilan?.issue == IssueSynchro.agendaIntrouvable)
                      FilledButton.tonalIcon(
                        key: const ValueKey<String>('agenda-google-recreer'),
                        onPressed: occupe ? null : _recreer,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Créer un nouvel agenda'),
                      ),
                  ],
                ),
              ],
            ),
          ],
          if (service.disponible && email != null && reglage.calendrier != null) ...<Widget>[
            const SizedBox(height: 12),
            CarteDrive(
              titre: 'Nettoyer l’agenda Google',
              enfants: <Widget>[
                texteDiscretDrive(
                  context,
                  'Quand un élément disparaît de l’application (événement supprimé, cours annulé, devis accepté ou expiré), '
                  'son événement reste dans Google Agenda, marqué « [Annulé] ». Vous pouvez les supprimer de Google Agenda '
                  'quand vous le voulez : une confirmation vous est demandée, et rien n’est supprimé dans l’application.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey<String>('agenda-google-nettoyer'),
                  onPressed: occupe ? null : _nettoyer,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Nettoyer l’agenda Google'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          CarteDrive(
            titre: 'Ce qu’il faut savoir',
            enfants: <Widget>[
              texteDiscretDrive(
                context,
                '• Un seul sens : l’application écrit dans Google Agenda, elle n’y lit rien d’autre que ses propres '
                'événements, et ne voit aucun autre de vos agendas.\n'
                '• Rien n’est supprimé de Google Agenda sans votre demande : un élément qui disparaît de l’application y reste, '
                'marqué « [Annulé] ».\n'
                '• Une modification faite à la main dans Google Agenda est remplacée à la prochaine synchronisation : '
                'modifiez toujours dans l’application.\n'
                '• Les types d’éléments masqués dans le calendrier ne sont pas envoyés.\n'
                '• La synchronisation part à l’ouverture de l’application, une trentaine de secondes après une modification, '
                'et quand vous touchez « Synchroniser maintenant ». Elle demande Internet.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Le bilan de la dernière synchronisation, en une ou deux phrases.
class _Bilan extends StatelessWidget {
  const _Bilan({required this.etat});

  final EtatSynchroAgendaGoogle etat;

  @override
  Widget build(BuildContext context) {
    if (etat.enCours) {
      return const Row(
        key: ValueKey<String>('agenda-google-en-cours'),
        children: <Widget>[
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Expanded(child: Text('Synchronisation en cours…')),
        ],
      );
    }
    final BilanSynchro? bilan = etat.bilan;
    final DateTime? quand = etat.quand;
    if (bilan == null || quand == null) {
      return texteDiscretDrive(
        context,
        'Aucune synchronisation depuis l’ouverture de l’application.',
        key: const ValueKey<String>('agenda-google-bilan'),
      );
    }
    final String horodatage = '${formatDateCourte(quand)} à ${formatHeure(quand)}';
    final String texte = textePourLeBilan(bilan);
    final bool probleme = !bilan.reussie;
    final Text phrase = probleme
        ? texteErreurDrive(context, texte, key: const ValueKey<String>('agenda-google-bilan'))
        : texteDiscretDrive(context, texte, key: const ValueKey<String>('agenda-google-bilan'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Dernière synchronisation : $horodatage', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        phrase,
      ],
    );
  }
}

/// Ce que dit l'écran d'un bilan de synchronisation.
String textePourLeBilan(BilanSynchro bilan) {
  final ResultatSynchro? resultat = bilan.resultat;
  switch (bilan.issue) {
    case IssueSynchro.reussie:
      return resultat == null ? 'Tout est à jour.' : resumeSynchro(resultat);
    case IssueSynchro.partielle:
      final String motif = bilan.message == null ? '' : ' Motif : ${bilan.message}';
      return '${resultat == null ? 'Une partie seulement a été envoyée.' : resumeSynchro(resultat)}$motif Le reste sera retenté '
          'à la prochaine synchronisation.';
    case IssueSynchro.desactivee:
      return 'La synchronisation n’est pas activée.';
    case IssueSynchro.indisponible:
      return 'Google Agenda n’est pas disponible sur cet appareil.';
    case IssueSynchro.nonConnecte:
      return 'Vous n’êtes pas connecté à Google : connectez-vous dans Réglages › Google Drive.';
    case IssueSynchro.droitAbsent:
      return bilan.message ?? 'Le droit « Google Agenda » n’est pas (ou plus) accordé : autorisez-le de nouveau.';
    case IssueSynchro.annulee:
      return 'Autorisation annulée : la synchronisation n’est pas activée.';
    case IssueSynchro.agendaIntrouvable:
      return 'L’agenda Google mémorisé est introuvable : il a peut-être été supprimé dans Google Agenda, ou n’est pas '
          'accessible depuis cet appareil. Vous pouvez en créer un nouveau (il sera rempli de nouveau, l’ancien n’est pas touché).';
    case IssueSynchro.erreur:
      return bilan.message ?? 'La synchronisation a échoué. Réessayez dans un instant.';
  }
}
