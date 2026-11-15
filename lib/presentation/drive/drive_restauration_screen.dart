import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/date_fr.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/drive/compte_google.dart';
import '../../data/drive/service_sauvegarde_drive.dart';
import '../../data/providers.dart';
import '../../data/sauvegarde/format_sauvegarde.dart';
import '../../data/sauvegarde/service_sauvegarde.dart';
import '../../domain/drive_sauvegardes.dart';
import '../../domain/erreurs.dart';
import '../../domain/pieces_jointes.dart';
import '../sauvegarde/sauvegarde_providers.dart';
import '../ventes/panier_provider.dart';
import 'drive_providers.dart';

/// Réglages › Google Drive › Restaurer depuis Drive (étape 7 de l'évolution) : liste les sauvegardes qui sont sur Drive, et
/// restaure celle qu'on choisit, après confirmation. Sert aussi à **changer de téléphone** : on se connecte au même compte
/// Google, puis on restaure.
///
/// La restauration remplace toutes les données ; une copie de sécurité est faite juste avant (elle reste dans la liste de
/// Réglages › Sauvegarde et export). Les photos et documents sont retéléchargés depuis leurs dossiers Drive et contrôlés
/// avant que quoi que ce soit ne soit touché.
class DriveRestaurationScreen extends ConsumerStatefulWidget {
  const DriveRestaurationScreen({super.key});

  @override
  ConsumerState<DriveRestaurationScreen> createState() => _DriveRestaurationScreenState();
}

class _DriveRestaurationScreenState extends ConsumerState<DriveRestaurationScreen> {
  /// Une opération est en cours : on ne quitte pas l'écran et on ne lance pas une autre restauration.
  bool _occupe = false;

  /// Ce qu'on fait en ce moment (`null` : rien), pour le dire.
  String? _activite;

  /// Où en est la restauration (`null` : pas encore de chiffres à montrer).
  ProgressionRestaurationDrive? _progression;

  /// Message d'échec de la dernière tentative.
  String? _erreur;

  /// Pour ne pas redessiner l'écran à chaque morceau reçu : au plus un changement tous les 150 ms (sauf changement d'étape ou
  /// de fichier).
  final Stopwatch _chrono = Stopwatch();

  void _surProgression(ProgressionRestaurationDrive progression) {
    if (!mounted) return;
    final ProgressionRestaurationDrive? avant = _progression;
    final bool nouveau =
        avant == null ||
        avant.etape != progression.etape ||
        avant.fichierEnCours != progression.fichierEnCours ||
        avant.fichiersFaits != progression.fichiersFaits ||
        !_chrono.isRunning ||
        _chrono.elapsedMilliseconds >= 150;
    if (!nouveau) return;
    _chrono
      ..reset()
      ..start();
    setState(() => _progression = progression);
  }

  String _dateHeure(DateTime date) => '${formatDateLongue(date)} à ${formatHeure(date)}';

  String _nombre(int n, String singulier, String pluriel) => '$n ${n > 1 ? pluriel : singulier}';

  /// Télécharge la sauvegarde choisie, la lit, demande confirmation en disant ce qu'elle contient, puis restaure.
  Future<void> _choisir(SauvegardeDrive choisie) async {
    if (_occupe) return;
    setState(() {
      _occupe = true;
      _activite = 'Téléchargement de la sauvegarde du ${_dateHeure(choisie.date)}…';
      _progression = null;
      _erreur = null;
    });

    final ServiceSauvegardeDrive service = ref.read(serviceSauvegardeDriveProvider);
    final PreparationRestaurationDrive preparation;
    try {
      preparation = await service.preparerRestauration(choisie);
    } on ErreurDrive catch (erreur) {
      _echec(erreur.message, autorisationAExpire: erreur.autorisationAExpire);
      return;
    } on ErreurMetier catch (erreur) {
      _echec(erreur.message);
      return;
    } catch (erreur, pile) {
      debugPrint('Restauration Drive : $erreur\n$pile');
      _echec('Téléchargement impossible : $erreur');
      return;
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _activite = null;
    });

    final ManifesteSauvegarde manifeste = preparation.examen.manifeste;
    final int lignes = manifeste.lignes.values.fold<int>(0, (int somme, int n) => somme + n);
    final int nombreFichiers = preparation.examen.fichiers.length;
    final bool ok = await confirmer(
      context,
      titre: 'Restaurer cette sauvegarde ?',
      message:
          'Sauvegarde du ${_dateHeure(choisie.date)} : ${_nombre(lignes, 'enregistrement', 'enregistrements')} '
          '(produits, clients, ventes, factures...) et ${_nombre(nombreFichiers, 'fichier', 'fichiers')} '
          '(photos, PDF, pièces jointes) à télécharger depuis votre Drive '
          '(${formaterTailleFichier(preparation.examen.octetsFichiers)}).\n\n'
          '${manifeste.complete ? '' : '${_phraseIncomplete(manifeste.fichiersAbsents.length)}\n\n'}'
          'TOUTES vos données actuelles (produits, clients, ventes, factures, photos...) seront remplacées par '
          'celles de cette sauvegarde.\n\n'
          'Une copie de sécurité de vos données actuelles est faite juste avant : vous la retrouverez dans '
          'Réglages › Sauvegarde et export.',
      libelleConfirmer: 'Restaurer',
    );
    if (!ok || !mounted) {
      await service.abandonnerRestauration();
      return;
    }

    setState(() {
      _occupe = true;
      _activite = 'Restauration en cours…';
      _progression = null;
    });
    final ResultatRestauration terminee;
    try {
      terminee = await service.restaurer(preparation, progression: _surProgression);

      // Ce que l'application garde en mémoire doit refléter les données restaurées : le mode jour / nuit (enregistré dans les
      // réglages) et la vente en cours (ses produits n'existent peut-être plus).
      final ThemeMode mode = await ref.read(parametresRepositoryProvider).lireModeTheme();
      ref.read(themeModeProvider.notifier).definir(mode);
      ref.invalidate(venteEnCoursProvider);
      ref.invalidate(sauvegardesLocalesProvider);
    } on ErreurDrive catch (erreur) {
      _echec(erreur.message, autorisationAExpire: erreur.autorisationAExpire);
      return;
    } on ErreurMetier catch (erreur) {
      _echec(erreur.message);
      return;
    } catch (erreur, pile) {
      debugPrint('Restauration Drive : $erreur\n$pile');
      _echec('Restauration impossible : $erreur');
      return;
    }
    _chrono.stop();
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _activite = null;
      _progression = null;
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext contexteDialogue) => AlertDialog(
        title: const Text('Restauration terminée'),
        content: Text(
          '${_nombre(terminee.lignes, 'enregistrement', 'enregistrements')} et '
          '${_nombre(terminee.fichiers, 'fichier', 'fichiers')} (photos, PDF, pièces jointes) remis en place.'
          '${terminee.fichiersAbsents.isEmpty ? '' : '\n\n${_phraseAbsents(terminee.fichiersAbsents)}'}',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(),
            child: const Text('Retour à l’accueil'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Pas de « await » : ce futur ne se termine que lorsque la page d'accueil est quittée.
    unawaited(Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.accueil, (Route<dynamic> route) => false));
  }

  void _echec(String message, {bool autorisationAExpire = false}) {
    _chrono.stop();
    if (autorisationAExpire) ref.read(profilGoogleProvider.notifier).connexionPerdue();
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _activite = null;
      _progression = null;
      _erreur = message;
    });
  }

  String _phraseIncomplete(int n) => n > 1
      ? '$n photos citées par les données ne sont pas dans cette sauvegarde (elles n’avaient pas pu être envoyées sur '
            'Drive) : elles ne pourront pas être remises.'
      : 'Une photo citée par les données n’est pas dans cette sauvegarde (elle n’avait pas pu être envoyée sur Drive) : '
            'elle ne pourra pas être remise.';

  String _phraseAbsents(List<String> absents) {
    final String noms = absents.take(5).map((String chemin) => chemin.split('/').last).join(', ');
    final String suite = absents.length > 5 ? ' et ${absents.length - 5} autres' : '';
    return absents.length > 1
        ? '${absents.length} photos n’ont pas pu être remises (absentes de Drive ou abîmées) : $noms$suite.'
        : 'Une photo n’a pas pu être remise (absente de Drive ou abîmée) : $noms.';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AsyncValue<List<SauvegardeDrive>> sauvegardes = ref.watch(sauvegardesDriveProvider);

    return PopScope(
      // Pendant une restauration, on ne quitte pas l'écran : elle ne s'arrêterait pas pour autant.
      canPop: !_occupe,
      child: Scaffold(
        appBar: AppBar(title: const Text('Restaurer depuis Drive')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Restaurer une sauvegarde', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Choisissez une sauvegarde faite sur votre Drive. La restauration remplace toutes les données de '
                      'l’application, après une copie de sécurité. Les photos et les documents sont retéléchargés depuis '
                      'vos dossiers Drive et contrôlés : prévoyez le Wi‑Fi si vous en avez beaucoup.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pour changer de téléphone : installez l’application, connectez-vous au même compte Google, puis '
                      'restaurez ici la sauvegarde la plus récente.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            if (_occupe) ...<Widget>[const SizedBox(height: 12), _CarteActivite(activite: _activite, progression: _progression)],
            if (_erreur != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _erreur!,
                key: const Key('drive-restauration-erreur'),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: sauvegardes.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Recherche des sauvegardes sur Drive…', key: Key('drive-restauration-chargement')),
                ),
                error: (Object erreur, StackTrace pile) {
                  final bool expiree = erreur is ErreurDrive && erreur.autorisationAExpire;
                  if (expiree) {
                    // La connexion est perdue : l'écran Google Drive repassera à « Non connecté ».
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) ref.read(profilGoogleProvider.notifier).connexionPerdue();
                    });
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          erreur is ErreurDrive ? erreur.message : 'Impossible de lire la liste des sauvegardes : $erreur',
                          key: const Key('drive-restauration-liste-erreur'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                        ),
                        if (expiree) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            'Reconnectez-vous à Google (écran Google Drive), puis réessayez.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton(
                          key: const Key('drive-restauration-reessayer'),
                          onPressed: () => ref.invalidate(sauvegardesDriveProvider),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  );
                },
                data: (List<SauvegardeDrive> liste) {
                  if (liste.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Aucune sauvegarde trouvée sur ce Drive. Faites d’abord « Sauvegarder maintenant sur Drive » sur '
                        'le téléphone d’origine, avec le même compte Google.',
                        key: const Key('drive-restauration-aucune'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return Column(
                    children: <Widget>[
                      for (int i = 0; i < liste.length; i++)
                        ListTile(
                          key: Key('drive-sauvegarde-$i'),
                          leading: const Icon(Icons.cloud_done_outlined),
                          title: Text(_dateHeure(liste[i].date)),
                          subtitle: Text(
                            <String>[
                              if (i == 0) 'La plus récente',
                              if (liste[i].octets != null) formaterTailleFichier(liste[i].octets!),
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: !_occupe,
                          onTap: _occupe ? null : () => _choisir(liste[i]),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ce que fait la restauration en ce moment, avec sa barre de progression.
class _CarteActivite extends StatelessWidget {
  const _CarteActivite({required this.activite, required this.progression});

  final String? activite;
  final ProgressionRestaurationDrive? progression;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ProgressionRestaurationDrive? p = progression;
    final String? libelle = p == null
        ? activite
        : switch (p.etape) {
            EtapeRestaurationDrive.telechargement =>
              'Étape ${p.numeroEtape} sur 3 : téléchargement des fichiers depuis Drive '
                  '(${p.fichiersFaits} sur ${p.fichiersTotal} · '
                  '${formaterTailleFichier(p.octetsFaits)} sur ${formaterTailleFichier(p.octetsTotal)})',
            EtapeRestaurationDrive.copieDeSecurite =>
              'Étape ${p.numeroEtape} sur 3 : copie de sécurité de vos données actuelles',
            EtapeRestaurationDrive.remplacement => 'Étape ${p.numeroEtape} sur 3 : remplacement des données',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LinearProgressIndicator(key: const Key('drive-restauration-progression'), value: p?.fraction),
            const SizedBox(height: 8),
            Text(libelle ?? 'Un instant…', key: const Key('drive-restauration-etape'), style: theme.textTheme.titleSmall),
            if (p?.fichierEnCours != null)
              Text(
                p!.fichierEnCours!,
                key: const Key('drive-restauration-fichier'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            Text(
              'Gardez l’application ouverte et l’écran allumé jusqu’à la fin.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
