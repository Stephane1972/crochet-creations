import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/date_fr.dart';
import '../../core/widgets/dialogues.dart';
import '../../data/providers.dart';
import '../../data/sauvegarde/export_csv.dart';
import '../../data/sauvegarde/format_sauvegarde.dart';
import '../../data/sauvegarde/service_sauvegarde.dart';
import '../../domain/erreurs.dart';
import '../ventes/panier_provider.dart';
import 'sauvegarde_providers.dart';

/// Écran 23 : sauvegarde, export et restauration (étape 11).
///
/// - **Sauvegarder maintenant** : une archive .zip (données, photos, PDF) rangée sur le téléphone, avec une barre
///   de progression ; une copie automatique est aussi faite à l'ouverture de l'application si la dernière date
///   d'un jour ou plus. Une sauvegarde est dite « incomplète » si des photos manquaient sur le téléphone.
/// - **Partager** une sauvegarde : pour en garder une copie ailleurs que sur le téléphone.
/// - **Restaurer** (depuis la liste ou depuis un fichier) : remplace toutes les données, après confirmation
///   et copie de sécurité.
/// - **Exporter** en CSV (tableur) ou en JSON (toutes les données).
class SauvegardeScreen extends ConsumerStatefulWidget {
  const SauvegardeScreen({super.key});

  @override
  ConsumerState<SauvegardeScreen> createState() => _SauvegardeScreenState();
}

enum _Action { partager, restaurer, supprimer }

class _SauvegardeScreenState extends ConsumerState<SauvegardeScreen> {
  /// Une opération est en cours : les boutons sont désactivés (on ne lance pas deux sauvegardes à la fois).
  bool _occupe = false;

  /// Où en est la sauvegarde ou la restauration en cours (`null` : pas de progression à montrer).
  ProgressionSauvegarde? _progression;

  /// Pour ne pas redessiner l'écran à chaque photo : au plus un changement tous les 100 ms (sauf changement d'étape).
  final Stopwatch _chrono = Stopwatch();

  void _surProgression(ProgressionSauvegarde progression) {
    if (!mounted) return;
    final bool autreEtape = _progression?.etape != progression.etape;
    final bool terminee = progression.total > 0 && progression.fait >= progression.total;
    if (!autreEtape && !terminee && _chrono.isRunning && _chrono.elapsedMilliseconds < 100) return;
    _chrono
      ..reset()
      ..start();
    setState(() => _progression = progression);
  }

  /// Exécute une opération longue en désactivant les boutons ; une erreur est expliquée en bas de l'écran.
  Future<void> _executer(Future<void> Function() action) async {
    if (_occupe) return;
    setState(() {
      _occupe = true;
      _progression = null;
    });
    try {
      await action();
    } catch (erreur, pile) {
      debugPrint('Sauvegarde : $erreur\n$pile');
      if (mounted) afficherMessage(context, messageErreur(erreur));
    } finally {
      _chrono.stop();
      if (mounted) {
        setState(() {
          _occupe = false;
          _progression = null;
        });
      }
    }
  }

  Future<void> _sauvegarder() {
    return _executer(() async {
      final SauvegardeLocale sauvegarde = await ref
          .read(serviceSauvegardeProvider)
          .creer(TypeSauvegarde.manuelle, surProgression: _surProgression);
      ref.invalidate(sauvegardesLocalesProvider);
      if (!mounted) return;
      afficherMessage(
        context,
        sauvegarde.complete
            ? 'Sauvegarde créée. Partagez-la pour en garder une copie hors du téléphone.'
            : _phraseSauvegardeIncomplete(sauvegarde.fichiersAbsents.length),
      );
    });
  }

  Future<void> _partager(SauvegardeLocale sauvegarde) {
    return _executer(() async {
      await ref.read(servicePartageFichiersProvider).partager(
        cheminFichier: sauvegarde.fichier.path,
        nomFichier: sauvegarde.nom,
        typeMime: 'application/zip',
        sujet: 'Sauvegarde du ${formatDateCourte(sauvegarde.date)} – ${AppConstants.nomApplication}',
      );
    });
  }

  Future<void> _supprimer(SauvegardeLocale sauvegarde) async {
    final bool ok = await confirmer(
      context,
      titre: 'Supprimer cette sauvegarde ?',
      message:
          'La sauvegarde du ${_dateHeure(sauvegarde.date)} sera effacée du téléphone. '
          'Vos données actuelles ne changent pas.',
      libelleConfirmer: 'Supprimer',
    );
    if (!ok || !mounted) return;
    await _executer(() async {
      await ref.read(serviceSauvegardeProvider).supprimer(sauvegarde);
      ref.invalidate(sauvegardesLocalesProvider);
    });
  }

  Future<void> _restaurerDepuisListe(SauvegardeLocale sauvegarde) async {
    if (!await sauvegarde.fichier.exists()) {
      if (mounted) afficherMessage(context, 'Cette sauvegarde est introuvable sur le téléphone.');
      ref.invalidate(sauvegardesLocalesProvider);
      return;
    }
    if (!mounted) return;
    await _confirmerEtRestaurer(sauvegarde.fichier);
  }

  Future<void> _restaurerDepuisFichier() async {
    final File? copie;
    try {
      copie = await ref.read(selecteurFichierSauvegardeProvider).choisir();
    } catch (erreur, pile) {
      debugPrint('Choix du fichier : $erreur\n$pile');
      if (mounted) afficherMessage(context, 'Impossible d’ouvrir ce fichier.');
      return;
    }
    if (copie == null) return;
    try {
      if (mounted) await _confirmerEtRestaurer(copie);
    } finally {
      // Le sélecteur a donné une copie de travail : elle n'est plus utile.
      try {
        if (await copie.exists()) await copie.delete();
      } on FileSystemException {
        // Elle disparaîtra avec le dossier temporaire.
      }
    }
  }

  /// Vérifie l'archive (message clair si ce n'est pas une sauvegarde), demande confirmation en disant ce
  /// qu'elle contient, puis restaure.
  Future<void> _confirmerEtRestaurer(File archive) async {
    final ManifesteSauvegarde manifeste;
    try {
      manifeste = await ref.read(serviceSauvegardeProvider).examiner(archive);
    } on ErreurMetier catch (erreur) {
      if (mounted) afficherMessage(context, erreur.message);
      return;
    }
    if (!mounted) return;

    final String quand = manifeste.creeLe == null ? 'date inconnue' : _dateHeure(manifeste.creeLe!);
    final bool ok = await confirmer(
      context,
      titre: 'Restaurer cette sauvegarde ?',
      message:
          'Sauvegarde du $quand : ${_resume(manifeste)}.\n\n'
          '${manifeste.complete ? '' : '${_phraseArchiveIncomplete(manifeste.fichiersAbsents.length)}\n\n'}'
          'TOUTES vos données actuelles (produits, clients, ventes, factures, photos...) seront remplacées par '
          'celles de cette sauvegarde.\n\n'
          'Une copie de sécurité de vos données actuelles est faite juste avant : vous la retrouverez dans la liste.',
      libelleConfirmer: 'Restaurer',
    );
    if (!ok || !mounted) return;

    ResultatRestauration? restauration;
    await _executer(() async {
      restauration = await ref
          .read(serviceSauvegardeProvider)
          .restaurer(archive, surProgression: _surProgression);

      // Ce que l'application garde en mémoire doit refléter les données restaurées : le mode jour / nuit
      // (enregistré dans les réglages) et la vente en cours (ses produits n'existent peut-être plus).
      final ThemeMode mode = await ref.read(parametresRepositoryProvider).lireModeTheme();
      ref.read(themeModeProvider.notifier).definir(mode);
      ref.invalidate(venteEnCoursProvider);
      ref.invalidate(sauvegardesLocalesProvider);
    });

    // Une erreur a été expliquée par [_executer] : il n'y a alors rien à annoncer.
    final ResultatRestauration? resultat = restauration;
    if (resultat == null || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext contexteDialogue) => AlertDialog(
        title: const Text('Restauration terminée'),
        content: Text(
          '${_nombre(resultat.lignes, 'enregistrement', 'enregistrements')} et '
          '${_nombre(resultat.fichiers, 'fichier', 'fichiers')} (photos, PDF) remis en place.'
          '${resultat.fichiersAbsents.isEmpty ? '' : '\n\n${_phraseRestaurationIncomplete(resultat.fichiersAbsents.length)}'}',
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
    await Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.accueil, (Route<dynamic> route) => false);
  }

  Future<void> _exporterCsv() {
    return _executer(() async {
      final ServiceSauvegarde service = ref.read(serviceSauvegardeProvider);
      final ExportCsv export = ref.read(exportCsvProvider);
      final File fichier = await export.ecrireArchive(service.dossierExports);
      await ref.read(servicePartageFichiersProvider).partager(
        cheminFichier: fichier.path,
        nomFichier: fichier.uri.pathSegments.last,
        typeMime: 'application/zip',
        sujet: 'Export CSV – ${AppConstants.nomApplication}',
      );
    });
  }

  Future<void> _exporterJson() {
    return _executer(() async {
      final File fichier = await ref.read(serviceSauvegardeProvider).ecrireJson();
      await ref.read(servicePartageFichiersProvider).partager(
        cheminFichier: fichier.path,
        nomFichier: fichier.uri.pathSegments.last,
        typeMime: 'application/json',
        sujet: 'Export JSON – ${AppConstants.nomApplication}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AsyncValue<List<SauvegardeLocale>> sauvegardes = ref.watch(sauvegardesLocalesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde et export'),
        bottom: _occupe
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _progression?.fraction),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          if (_occupe && _progression != null) ...<Widget>[
            CarteProgressionSauvegarde(progression: _progression!),
            const SizedBox(height: 16),
          ],

          // --- Sauvegarder -------------------------------------------------------------------------------
          const _TitreSection('Sauvegarder'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _phraseDerniereSauvegarde(sauvegardes.asData?.value),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Une sauvegarde contient toutes vos données, vos photos et vos PDF ; elle est vérifiée avant d’être '
                    'rangée. L’application en fait une toute seule à l’ouverture, si la dernière date de plus d’un '
                    'jour (les 7 dernières sont gardées).',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _occupe ? null : _sauvegarder,
                      icon: const Icon(Icons.backup_outlined),
                      label: const Text('Sauvegarder maintenant'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Sauvegardes du téléphone ------------------------------------------------------------------
          const _TitreSection('Sauvegardes sur ce téléphone'),
          Card(
            child: sauvegardes.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Chargement…'),
              ),
              error: (Object erreur, StackTrace pile) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Impossible de lire la liste des sauvegardes.'),
              ),
              data: (List<SauvegardeLocale> liste) {
                if (liste.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Aucune sauvegarde pour l’instant.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: <Widget>[
                    for (int i = 0; i < liste.length; i++) ...<Widget>[
                      if (i > 0) const Divider(indent: 16),
                      _LigneSauvegarde(
                        sauvegarde: liste[i],
                        actif: !_occupe,
                        onAction: (_Action action) {
                          switch (action) {
                            case _Action.partager:
                              _partager(liste[i]);
                            case _Action.restaurer:
                              _restaurerDepuisListe(liste[i]);
                            case _Action.supprimer:
                              _supprimer(liste[i]);
                          }
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // --- Restaurer ---------------------------------------------------------------------------------
          const _TitreSection('Restaurer'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Pour retrouver vos données sur un nouveau téléphone, ou revenir à une ancienne sauvegarde. '
                    'Choisissez une sauvegarde dans la liste ci-dessus (menu ⋮), ou un fichier .zip reçu par '
                    'e-mail ou enregistré ailleurs. La restauration remplace tout, après une copie de sécurité.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _occupe ? null : _restaurerDepuisFichier,
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('Restaurer depuis un fichier'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Exporter ----------------------------------------------------------------------------------
          const _TitreSection('Exporter'),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(Icons.table_chart_outlined, color: scheme.primary),
                  title: Text('Exporter en CSV (tableur)', style: theme.textTheme.titleSmall),
                  subtitle: Text(
                    'Un fichier .zip avec un tableau par type : produits, clients, ventes, factures, devis, '
                    'cours, inscriptions, dépenses.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  enabled: !_occupe,
                  onTap: _exporterCsv,
                ),
                const Divider(indent: 56),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(Icons.data_object_outlined, color: scheme.primary),
                  title: Text('Exporter en JSON (toutes les données)', style: theme.textTheme.titleSmall),
                  subtitle: Text(
                    'Un seul fichier avec toutes les données, sans les photos ni les PDF. Pour les développeurs ; '
                    'pour une vraie sauvegarde, utilisez « Sauvegarder maintenant ».',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  enabled: !_occupe,
                  onTap: _exporterJson,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Textes
  // ---------------------------------------------------------------------------

  /// « Dernière sauvegarde : aujourd'hui à 13 h 49 », « Aucune sauvegarde pour l'instant. »
  String _phraseDerniereSauvegarde(List<SauvegardeLocale>? liste) {
    if (liste == null) return 'Dernière sauvegarde : …';
    final Iterable<SauvegardeLocale> utiles = liste.where(
      (SauvegardeLocale s) => s.type != TypeSauvegarde.avantRestauration,
    );
    if (utiles.isEmpty) return 'Aucune sauvegarde pour l’instant.';
    return 'Dernière sauvegarde : ${_jourHeure(utiles.first.date)}';
  }

  /// « aujourd'hui à 13 h 49 », « hier à 9 h 05 », sinon « 28/10/2026 à 18 h 30 ».
  String _jourHeure(DateTime date) {
    final DateTime maintenant = ref.read(horlogeProvider)();
    final DateTime aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime jour = DateTime(date.year, date.month, date.day);
    final int ecart = aujourdhui.difference(jour).inDays;
    final String heure = formatHeure(date);
    if (ecart == 0) return 'aujourd’hui à $heure';
    if (ecart == 1) return 'hier à $heure';
    return '${formatDateCourte(date)} à $heure';
  }

  String _dateHeure(DateTime date) => '${formatDateCourte(date)} à ${formatHeure(date)}';

  /// « 12 produits, 8 clients, 15 ventes, 3 factures, 24 photos et PDF ».
  String _resume(ManifesteSauvegarde m) {
    return <String>[
      _nombre(m.lignesDe('produits'), 'produit', 'produits'),
      _nombre(m.lignesDe('clients'), 'client', 'clients'),
      _nombre(m.lignesDe('ventes'), 'vente', 'ventes'),
      _nombre(m.lignesDe('factures'), 'facture', 'factures'),
      _nombre(m.nombreFichiers, 'photo ou PDF', 'photos et PDF'),
    ].join(', ');
  }

  String _nombre(int n, String singulier, String pluriel) => '$n ${n > 1 ? pluriel : singulier}';

  /// Annoncé juste après « Sauvegarder maintenant » quand des photos manquaient.
  String _phraseSauvegardeIncomplete(int n) => n > 1
      ? 'Sauvegarde créée, mais incomplète : $n photos citées par vos données sont introuvables sur le téléphone, '
            'elles ne sont donc pas dans la sauvegarde.'
      : 'Sauvegarde créée, mais incomplète : 1 photo citée par vos données est introuvable sur le téléphone, '
            'elle n’est donc pas dans la sauvegarde.';

  /// Dans la demande de confirmation d'une restauration.
  String _phraseArchiveIncomplete(int n) => n > 1
      ? 'ATTENTION, cette sauvegarde est incomplète : $n photos manquaient déjà quand elle a été faite, '
            'elles ne pourront pas être remises.'
      : 'ATTENTION, cette sauvegarde est incomplète : 1 photo manquait déjà quand elle a été faite, '
            'elle ne pourra pas être remise.';

  /// Dans le compte rendu d'une restauration.
  String _phraseRestaurationIncomplete(int n) => n > 1
      ? '$n photos manquaient dans la sauvegarde : elles n’ont pas pu être remises.'
      : '1 photo manquait dans la sauvegarde : elle n’a pas pu être remise.';
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(texte, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Où en est la sauvegarde ou la restauration : l'étape, et « n sur N » quand on compte des fichiers.
class CarteProgressionSauvegarde extends StatelessWidget {
  const CarteProgressionSauvegarde({super.key, required this.progression});

  final ProgressionSauvegarde progression;

  String get _libelle => switch (progression.etape) {
    EtapeSauvegarde.lectureDonnees => 'Lecture de vos données',
    EtapeSauvegarde.empreintes => 'Contrôle de vos photos et PDF',
    EtapeSauvegarde.ecritureFichiers => 'Copie des photos et PDF dans la sauvegarde',
    EtapeSauvegarde.verification => 'Vérification de la sauvegarde',
    EtapeSauvegarde.controleFichiers => 'Contrôle des fichiers de la sauvegarde',
    EtapeSauvegarde.copieDeSecurite => 'Copie de sécurité de vos données actuelles',
    EtapeSauvegarde.remplacement => 'Remplacement de vos données',
  };

  /// On compte des fichiers à ces étapes seulement.
  bool get _compteDesFichiers =>
      progression.total > 1 &&
      (progression.etape == EtapeSauvegarde.empreintes ||
          progression.etape == EtapeSauvegarde.ecritureFichiers ||
          progression.etape == EtapeSauvegarde.controleFichiers);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Étape ${progression.numeroEtape} sur ${progression.nombreEtapes} : $_libelle',
              style: theme.textTheme.titleSmall,
            ),
            if (_compteDesFichiers) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '${progression.fait} sur ${progression.total} fichiers',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Ne fermez pas l’application avant la fin.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneSauvegarde extends StatelessWidget {
  const _LigneSauvegarde({required this.sauvegarde, required this.actif, required this.onAction});

  final SauvegardeLocale sauvegarde;
  final bool actif;
  final void Function(_Action action) onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: Icon(
        sauvegarde.complete ? Icons.folder_zip_outlined : Icons.warning_amber_outlined,
        color: sauvegarde.complete ? scheme.primary : scheme.error,
      ),
      title: Text(
        '${formatDateCourte(sauvegarde.date)} à ${formatHeure(sauvegarde.date)}',
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${sauvegarde.type.libelle} · ${_taille(sauvegarde.octets)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (!sauvegarde.complete)
            Text(
              'Incomplète : des photos manquaient',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
        ],
      ),
      trailing: PopupMenuButton<_Action>(
        key: ValueKey<String>('menu-${sauvegarde.nom}'),
        tooltip: 'Actions',
        enabled: actif,
        onSelected: onAction,
        itemBuilder: (BuildContext context) => const <PopupMenuEntry<_Action>>[
          PopupMenuItem<_Action>(value: _Action.partager, child: Text('Partager')),
          PopupMenuItem<_Action>(value: _Action.restaurer, child: Text('Restaurer')),
          PopupMenuItem<_Action>(value: _Action.supprimer, child: Text('Supprimer')),
        ],
      ),
    );
  }

  /// « 850 o », « 12 Ko », « 1,4 Mo ».
  static String _taille(int octets) {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) return '${(octets / 1024).round()} Ko';
    return '${(octets / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
}
