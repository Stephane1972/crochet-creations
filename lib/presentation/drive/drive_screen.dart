import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_fr.dart';
import '../../data/drive/compte_google.dart';
import '../../data/drive/service_drive.dart';
import '../../data/providers.dart';
import '../../domain/drive_envoi.dart';
import '../../domain/pieces_jointes.dart';
import 'drive_providers.dart';

/// Réglages › Google Drive (étape 6 de l'évolution) : se connecter à Google, vérifier ce qui est déjà sur Drive, envoyer à la
/// demande les photos des produits, les factures, les devis et les pièces jointes des notes, et voir le bilan du dernier envoi.
///
/// L'envoi ne fait que **copier** : l'application ne supprime ni ne partage rien sur Drive. Rien ne part tout seul.
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool connecte = ref.watch(profilGoogleProvider).valueOrNull != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const _CarteConnexion(),
          if (connecte) ...<Widget>[const SizedBox(height: 12), const _CarteEnvoi()],
          const SizedBox(height: 12),
          const _CarteDernierEnvoi(),
        ],
      ),
    );
  }
}

String _pluriel(int n, String singulier, [String? pluriel]) => '$n ${n > 1 ? (pluriel ?? '${singulier}s') : singulier}';

class _Carte extends StatelessWidget {
  const _Carte({required this.titre, required this.enfants});

  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...enfants,
          ],
        ),
      ),
    );
  }
}

Text _texteDiscret(BuildContext context, String texte, {Key? key}) {
  final ThemeData theme = Theme.of(context);
  return Text(
    texte,
    key: key,
    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  );
}

Text _texteErreur(BuildContext context, String texte, {Key? key}) {
  final ThemeData theme = Theme.of(context);
  return Text(texte, key: key, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error));
}

// -----------------------------------------------------------------------------
// Connexion
// -----------------------------------------------------------------------------

class _CarteConnexion extends ConsumerStatefulWidget {
  const _CarteConnexion();

  @override
  ConsumerState<_CarteConnexion> createState() => _CarteConnexionState();
}

class _CarteConnexionState extends ConsumerState<_CarteConnexion> {
  String? _erreur;

  Future<void> _seConnecter() async {
    setState(() => _erreur = null);
    final ErreurDrive? erreur = await ref.read(profilGoogleProvider.notifier).seConnecter();
    if (!mounted) return;
    // Fermer la fenêtre de connexion n'est pas une panne : rien à dire.
    if (erreur != null && !erreur.annulee) setState(() => _erreur = erreur.message);
  }

  @override
  Widget build(BuildContext context) {
    final bool configure = ref.watch(compteGoogleProvider).configure;
    final AsyncValue<ProfilGoogle?> profil = ref.watch(profilGoogleProvider);
    final bool occupe = ref.watch(envoiDriveProvider).occupe;

    if (!configure) {
      return _Carte(
        titre: 'Connexion à Google',
        enfants: <Widget>[
          Text(
            'La connexion à Google n’est pas encore configurée dans cette version de l’application.',
            key: const Key('drive-non-configure'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          _texteDiscret(
            context,
            'Il s’agit d’une configuration unique et gratuite sur Google Cloud (environ 15 minutes) : elle est expliquée '
            'pas à pas dans le guide « Google Drive » du fichier README du projet. L’application fonctionne normalement '
            'sans.',
          ),
        ],
      );
    }

    final ProfilGoogle? connecte = profil.valueOrNull;
    if (profil.isLoading) {
      return const _Carte(
        titre: 'Connexion à Google',
        enfants: <Widget>[
          Row(
            key: Key('drive-chargement'),
            children: <Widget>[
              SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('Connexion en cours…')),
            ],
          ),
        ],
      );
    }

    if (connecte == null) {
      return _Carte(
        titre: 'Connexion à Google',
        enfants: <Widget>[
          const Text('Aucun compte Google n’est connecté.', key: Key('drive-non-connecte')),
          const SizedBox(height: 8),
          _texteDiscret(
            context,
            'Votre Drive reste privé : l’application ne demande que le droit de voir et de gérer les fichiers qu’elle '
            'crée elle-même, jamais le reste de votre Drive. Elle ne supprime rien et ne partage rien.',
          ),
          if (_erreur != null) ...<Widget>[
            const SizedBox(height: 8),
            _texteErreur(context, _erreur!, key: const Key('drive-erreur-connexion')),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('drive-connecter'),
            onPressed: _seConnecter,
            icon: const Icon(Icons.login),
            label: const Text('Se connecter à Google'),
          ),
        ],
      );
    }

    return _Carte(
      titre: 'Connexion à Google',
      enfants: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                connecte.email,
                key: const Key('drive-compte'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _texteDiscret(context, 'Connecté. Les fichiers déjà envoyés restent sur Drive, même après une déconnexion.'),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('drive-deconnecter'),
          onPressed: occupe ? null : () => ref.read(profilGoogleProvider.notifier).seDeconnecter(),
          child: const Text('Se déconnecter'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Envoi
// -----------------------------------------------------------------------------

class _CarteEnvoi extends ConsumerWidget {
  const _CarteEnvoi();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EtatEnvoi etat = ref.watch(envoiDriveProvider);
    final EnvoiDriveNotifier controle = ref.read(envoiDriveProvider.notifier);

    final Widget boutons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('drive-envoyer'),
          onPressed: controle.envoyer,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Envoyer maintenant'),
        ),
        OutlinedButton.icon(
          key: const Key('drive-verifier'),
          onPressed: controle.verifier,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Vérifier'),
        ),
      ],
    );

    final List<Widget> contenu = <Widget>[
      Text(
        'Envoie sur votre Drive, dans le dossier « $nomDossierRacineDrive », les photos des produits, les factures, les '
        'devis et les pièces jointes des notes. Ce qui est déjà sur Drive n’est pas renvoyé. Rien n’est supprimé ni '
        'partagé sur Drive, et rien ne part tout seul.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
    ];

    switch (etat.phase) {
      case PhaseEnvoi.repos:
        contenu.add(boutons);
      case PhaseEnvoi.verification:
        contenu.addAll(<Widget>[
          const LinearProgressIndicator(key: Key('drive-verification-en-cours')),
          const SizedBox(height: 8),
          _texteDiscret(context, 'Comparaison du téléphone et de Drive…'),
        ]);
      case PhaseEnvoi.verifie:
        contenu.addAll(<Widget>[_ResumeVerification(verification: etat.verification!), const SizedBox(height: 12), boutons]);
      case PhaseEnvoi.envoi:
        contenu.add(_Progression(etat: etat, onArreter: controle.arreter));
      case PhaseEnvoi.termine:
        final ResultatEnvoi resultat = etat.resultat!;
        final ErreurDrive? arret = resultat.arret;
        contenu.addAll(<Widget>[
          Text(
            resultat.rapport.complet
                ? 'Envoi terminé : tout est sur Drive.'
                : resultat.rapport.erreurs.isEmpty
                ? 'Envoi arrêté avant la fin.'
                : 'Envoi terminé, mais certains fichiers n’ont pas pu partir (voir le bilan plus bas).',
            key: const Key('drive-fin-envoi'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (arret != null) ...<Widget>[
            const SizedBox(height: 4),
            _texteErreur(context, arret.message, key: const Key('drive-arret')),
          ],
          const SizedBox(height: 12),
          boutons,
        ]);
      case PhaseEnvoi.erreur:
        contenu.addAll(<Widget>[
          _texteErreur(context, etat.erreur ?? 'Une erreur est survenue.', key: const Key('drive-erreur')),
          if (etat.autorisationAExpire) ...<Widget>[
            const SizedBox(height: 4),
            _texteDiscret(context, 'Reconnectez-vous à Google (carte « Connexion à Google »), puis réessayez.'),
          ],
          const SizedBox(height: 12),
          boutons,
        ]);
    }

    return _Carte(titre: 'Envoyer sur Drive', enfants: contenu);
  }
}

class _ResumeVerification extends StatelessWidget {
  const _ResumeVerification({required this.verification});

  final VerificationDrive verification;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          verification.toutEstSurDrive
              ? 'Tout est déjà sur Drive.'
              : '${_pluriel(verification.fichiersAEnvoyer, 'fichier')} à envoyer '
                    '(${formaterTailleFichier(verification.octetsAEnvoyer)}).',
          key: const Key('drive-verification-resume'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        for (final PlanDossier plan in verification.plans)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${plan.dossier.nomDrive} : ${_pluriel(plan.nombreLocaux, 'fichier')} sur le téléphone · '
              '${plan.dejaSurDrive} déjà sur Drive · ${plan.aEnvoyer.length} à envoyer',
              key: Key('drive-plan-${plan.dossier.name}'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _Progression extends StatelessWidget {
  const _Progression({required this.etat, required this.onArreter});

  final EtatEnvoi etat;
  final VoidCallback onArreter;

  @override
  Widget build(BuildContext context) {
    final ProgressionEnvoi progression = etat.progression ?? const ProgressionEnvoi.preparation();
    final bool prepare = progression.fichiersTotal == 0 && progression.fichierEnCours == null;
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Sans fichier à envoyer connu (préparation), la barre reste vide : une barre qui tourne sans fin gênerait les tests
        // et n'apprend rien de plus.
        LinearProgressIndicator(key: const Key('drive-progression'), value: progression.fraction),
        const SizedBox(height: 8),
        Text(
          prepare
              ? 'Préparation : recherche des dossiers sur Drive…'
              : '${progression.fichiersFaits} sur ${_pluriel(progression.fichiersTotal, 'fichier')} · '
                    '${formaterTailleFichier(progression.octetsFaits)} sur ${formaterTailleFichier(progression.octetsTotal)}',
          key: const Key('drive-progression-texte'),
          style: theme.textTheme.titleSmall,
        ),
        if (progression.fichierEnCours != null)
          Text(
            progression.fichierEnCours!,
            key: const Key('drive-fichier-en-cours'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        const SizedBox(height: 8),
        _texteDiscret(context, 'Gardez l’application ouverte et l’écran allumé jusqu’à la fin.'),
        const SizedBox(height: 8),
        if (etat.arretDemande)
          _texteDiscret(context, 'Arrêt demandé : l’envoi s’arrête à la fin du fichier en cours…', key: const Key('drive-arret-demande'))
        else
          OutlinedButton.icon(
            key: const Key('drive-arreter'),
            onPressed: onArreter,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Arrêter'),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dernier envoi
// -----------------------------------------------------------------------------

class _CarteDernierEnvoi extends ConsumerWidget {
  const _CarteDernierEnvoi();

  /// Combien d'échecs on détaille (les autres sont comptés).
  static const int _erreursMontrees = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RapportEnvoi?> bilan = ref.watch(dernierBilanDriveProvider);
    final ThemeData theme = Theme.of(context);

    final RapportEnvoi? rapport = bilan.valueOrNull;
    if (rapport == null) {
      return _Carte(
        titre: 'Dernier envoi',
        enfants: <Widget>[
          _texteDiscret(
            context,
            bilan.isLoading ? 'Lecture du bilan…' : 'Aucun envoi pour l’instant.',
            key: const Key('drive-aucun-bilan'),
          ),
        ],
      );
    }

    return _Carte(
      titre: 'Dernier envoi',
      enfants: <Widget>[
        Text(
          '${formatDateLongue(rapport.date)} à ${formatHeure(rapport.date)}',
          key: const Key('drive-bilan-date'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${_pluriel(rapport.envoyes, 'fichier envoyé', 'fichiers envoyés')} '
          '(${formaterTailleFichier(rapport.octetsEnvoyes)}) · ${rapport.dejaSurDrive} déjà sur Drive',
          key: const Key('drive-bilan-resume'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        if (rapport.complet)
          const Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline, size: 18),
              SizedBox(width: 6),
              Expanded(child: Text('Tout est sur Drive.', key: Key('drive-bilan-etat'))),
            ],
          )
        else
          _texteErreur(
            context,
            rapport.interrompu
                ? 'Envoi incomplet : il s’est arrêté avant la fin. Relancez « Envoyer maintenant » : seul ce qui manque repart.'
                : 'Envoi incomplet : certains fichiers n’ont pas pu partir. Relancez « Envoyer maintenant » pour réessayer.',
            key: const Key('drive-bilan-etat'),
          ),
        for (int i = 0; i < rapport.erreurs.length && i < _erreursMontrees; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${rapport.erreurs[i].dossier.nomDrive} · ${rapport.erreurs[i].nom} : ${rapport.erreurs[i].message}',
              key: Key('drive-bilan-erreur-$i'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (rapport.erreurs.length > _erreursMontrees)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'et ${_pluriel(rapport.erreurs.length - _erreursMontrees, 'autre fichier', 'autres fichiers')} en échec.',
              key: const Key('drive-bilan-autres-erreurs'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
