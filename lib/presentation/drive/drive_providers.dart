import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drive/compte_google.dart';
import '../../data/drive/service_drive.dart';
import '../../data/providers.dart';
import '../../domain/drive_envoi.dart';

/// Le compte Google connecté (`null` : personne n'est connecté). Au premier affichage de l'écran Google Drive, retrouve le
/// compte déjà connecté, sans rien demander.
final profilGoogleProvider = AsyncNotifierProvider<ProfilGoogleNotifier, ProfilGoogle?>(ProfilGoogleNotifier.new);

class ProfilGoogleNotifier extends AsyncNotifier<ProfilGoogle?> {
  @override
  Future<ProfilGoogle?> build() => ref.read(compteGoogleProvider).restaurer();

  /// Ouvre la connexion Google. Retourne `null` si le compte est connecté, sinon l'erreur à montrer (voir
  /// [ErreurDrive.annulee] : fermer la fenêtre n'est pas une panne).
  Future<ErreurDrive?> seConnecter() async {
    state = const AsyncLoading<ProfilGoogle?>();
    try {
      final ProfilGoogle profil = await ref.read(compteGoogleProvider).seConnecter();
      state = AsyncData<ProfilGoogle?>(profil);
      return null;
    } on ErreurDrive catch (erreur) {
      state = const AsyncData<ProfilGoogle?>(null);
      return erreur;
    } catch (erreur) {
      state = const AsyncData<ProfilGoogle?>(null);
      return ErreurDrive('Connexion à Google impossible : $erreur');
    }
  }

  /// Oublie le compte sur ce téléphone (les fichiers déjà envoyés restent sur Drive).
  Future<void> seDeconnecter() async {
    await ref.read(compteGoogleProvider).seDeconnecter();
    state = const AsyncData<ProfilGoogle?>(null);
    ref.read(envoiDriveProvider.notifier).reinitialiser();
  }

  /// La connexion est perdue (droit retiré, jeton refusé) : l'écran repasse à « Non connecté ».
  void connexionPerdue() => state = const AsyncData<ProfilGoogle?>(null);
}

/// Le bilan du dernier envoi (`null` : aucun envoi pour l'instant).
final dernierBilanDriveProvider = FutureProvider.autoDispose<RapportEnvoi?>(
  (ref) => ref.watch(serviceDriveProvider).dernierBilan(),
);

/// Où en est la vérification ou l'envoi.
enum PhaseEnvoi {
  /// Rien en cours.
  repos,

  /// Comparaison du téléphone et de Drive, sans rien envoyer.
  verification,

  /// Comparaison faite : on sait ce qu'il reste à envoyer.
  verifie,

  /// Envoi en cours.
  envoi,

  /// Envoi terminé (ou arrêté) : le bilan est dans [EtatEnvoi.resultat].
  termine,

  /// Échec avant d'avoir pu commencer (Google injoignable, connexion perdue).
  erreur,
}

class EtatEnvoi {
  const EtatEnvoi._(
    this.phase, {
    this.verification,
    this.progression,
    this.resultat,
    this.erreur,
    this.autorisationAExpire = false,
    this.arretDemande = false,
  });

  const EtatEnvoi.repos() : this._(PhaseEnvoi.repos);

  const EtatEnvoi.enVerification() : this._(PhaseEnvoi.verification);

  const EtatEnvoi.verifie(VerificationDrive verification) : this._(PhaseEnvoi.verifie, verification: verification);

  const EtatEnvoi.enEnvoi(ProgressionEnvoi progression, {bool arretDemande = false})
    : this._(PhaseEnvoi.envoi, progression: progression, arretDemande: arretDemande);

  const EtatEnvoi.termine(ResultatEnvoi resultat) : this._(PhaseEnvoi.termine, resultat: resultat);

  const EtatEnvoi.enErreur(String message, {bool autorisationAExpire = false})
    : this._(PhaseEnvoi.erreur, erreur: message, autorisationAExpire: autorisationAExpire);

  final PhaseEnvoi phase;
  final VerificationDrive? verification;
  final ProgressionEnvoi? progression;
  final ResultatEnvoi? resultat;
  final String? erreur;

  /// Vrai si la connexion à Google doit être refaite.
  final bool autorisationAExpire;

  /// Vrai si la personne a demandé l'arrêt : il a lieu à la fin du fichier en cours.
  final bool arretDemande;

  /// Une vérification ou un envoi est en cours.
  bool get occupe => phase == PhaseEnvoi.verification || phase == PhaseEnvoi.envoi;
}

/// La vérification et l'envoi vers Drive. L'envoi continue si l'on quitte l'écran (tant que l'application reste ouverte).
final envoiDriveProvider = NotifierProvider<EnvoiDriveNotifier, EtatEnvoi>(EnvoiDriveNotifier.new);

class EnvoiDriveNotifier extends Notifier<EtatEnvoi> {
  AnnulationEnvoi? _annulation;

  @override
  EtatEnvoi build() => const EtatEnvoi.repos();

  /// Compare le téléphone et Drive, sans rien envoyer.
  Future<void> verifier() async {
    if (state.occupe) return;
    state = const EtatEnvoi.enVerification();
    try {
      state = EtatEnvoi.verifie(await ref.read(serviceDriveProvider).verifier());
    } on ErreurDrive catch (erreur) {
      _echec(erreur);
    } catch (erreur) {
      state = EtatEnvoi.enErreur('Vérification impossible : $erreur');
    }
  }

  /// Envoie ce qui n'est pas encore sur Drive.
  Future<void> envoyer() async {
    if (state.occupe) return;
    final AnnulationEnvoi annulation = AnnulationEnvoi();
    _annulation = annulation;
    state = const EtatEnvoi.enEnvoi(ProgressionEnvoi.preparation());

    // La progression arrive à chaque morceau lu : on ne rafraîchit l'écran que s'il y a du nouveau (autre fichier, autre
    // nombre de fichiers) ou au plus tous les 150 ms.
    ProgressionEnvoi? derniere;
    DateTime? dernierRafraichissement;
    void suivre(ProgressionEnvoi progression) {
      final DateTime maintenant = DateTime.now();
      final ProgressionEnvoi? avant = derniere;
      final bool nouveau =
          avant == null ||
          avant.fichierEnCours != progression.fichierEnCours ||
          avant.fichiersFaits != progression.fichiersFaits ||
          dernierRafraichissement == null ||
          maintenant.difference(dernierRafraichissement!) >= const Duration(milliseconds: 150);
      if (!nouveau) return;
      derniere = progression;
      dernierRafraichissement = maintenant;
      state = EtatEnvoi.enEnvoi(progression, arretDemande: annulation.demandee);
    }

    try {
      final ResultatEnvoi resultat = await ref.read(serviceDriveProvider).envoyer(
        progression: suivre,
        annulation: annulation,
      );
      state = EtatEnvoi.termine(resultat);
      ref.invalidate(dernierBilanDriveProvider);
      if (resultat.arret?.autorisationAExpire ?? false) ref.read(profilGoogleProvider.notifier).connexionPerdue();
    } on ErreurDrive catch (erreur) {
      _echec(erreur);
    } catch (erreur) {
      state = EtatEnvoi.enErreur('Envoi impossible : $erreur');
    } finally {
      _annulation = null;
    }
  }

  /// Demande l'arrêt de l'envoi : il s'arrête à la fin du fichier en cours.
  void arreter() {
    final AnnulationEnvoi? annulation = _annulation;
    final ProgressionEnvoi? progression = state.progression;
    if (annulation == null || state.phase != PhaseEnvoi.envoi || progression == null) return;
    annulation.demander();
    state = EtatEnvoi.enEnvoi(progression, arretDemande: true);
  }

  /// Revient à « rien en cours » (après une déconnexion, par exemple). Sans effet pendant un envoi.
  void reinitialiser() {
    if (!state.occupe) state = const EtatEnvoi.repos();
  }

  void _echec(ErreurDrive erreur) {
    state = EtatEnvoi.enErreur(erreur.message, autorisationAExpire: erreur.autorisationAExpire);
    if (erreur.autorisationAExpire) ref.read(profilGoogleProvider.notifier).connexionPerdue();
  }
}
