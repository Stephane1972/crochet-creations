import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drive/compte_google.dart';
import '../../data/drive/service_drive.dart';
import '../../data/drive/service_partages_drive.dart';
import '../../data/drive/service_sauvegarde_drive.dart';
import '../../data/providers.dart';
import '../../domain/drive_envoi.dart';
import '../../domain/drive_sauvegardes.dart';
import '../../domain/erreurs.dart';

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
    ref.read(sauvegardeDriveProvider.notifier).reinitialiser();
  }

  /// La connexion est perdue (droit retiré, jeton refusé) : l'écran repasse à « Non connecté ».
  void connexionPerdue() => state = const AsyncData<ProfilGoogle?>(null);
}

/// L'ID client Web de Google Cloud utilisé par l'application (voir `google_config.dart`) : ce que la personne a saisi dans
/// l'écran Google Drive, sinon celui qui a été fourni avec l'application.
class EtatClientWeb {
  const EtatClientWeb({
    required this.id,
    required this.surLeTelephone,
    required this.redemarrageNecessaire,
    this.demandeCodeSecret = false,
    this.codeSecretEnregistre = false,
  });

  /// L'ID utilisé (vide : aucun, la connexion à Google est alors impossible).
  final String id;

  /// Vrai si cet ID a été saisi dans l'application.
  final bool surLeTelephone;

  /// Vrai si l'application doit être fermée complètement, puis rouverte, pour prendre en compte le nouvel ID.
  final bool redemarrageNecessaire;

  /// Vrai sous Windows : l'accès « application de bureau » demande, en plus de l'ID, un code secret.
  final bool demandeCodeSecret;

  /// Vrai si ce code secret est enregistré (sans objet quand il n'est pas demandé).
  final bool codeSecretEnregistre;

  /// Vrai si tout ce qu'il faut pour se connecter est renseigné.
  bool get configure => id.isNotEmpty && (!demandeCodeSecret || codeSecretEnregistre);
}

final clientWebProvider = NotifierProvider<ClientWebNotifier, EtatClientWeb>(ClientWebNotifier.new);

class ClientWebNotifier extends Notifier<EtatClientWeb> {
  @override
  EtatClientWeb build() => _lire();

  EtatClientWeb _lire() {
    final CompteGoogle compte = ref.read(compteGoogleProvider);
    // `CompteAvecCodeSecret` est une interface à part (Windows) : un simple test de type ne suffit pas à « promouvoir » le compte.
    final CompteAvecCodeSecret? avecCode = compte is CompteAvecCodeSecret ? compte as CompteAvecCodeSecret : null;
    return EtatClientWeb(
      id: compte.clientWeb,
      surLeTelephone: compte.clientWebEnregistre,
      redemarrageNecessaire: compte.redemarrageNecessaire,
      demandeCodeSecret: avecCode != null,
      codeSecretEnregistre: avecCode != null && avecCode.codeSecretEnregistre,
    );
  }

  /// Enregistre le code secret collé (sous Windows). Retourne `null` si c'est fait, sinon le message à montrer.
  Future<String?> enregistrerCodeSecret(String saisie) async {
    final CompteGoogle compte = ref.read(compteGoogleProvider);
    if (compte is! CompteAvecCodeSecret) return 'Ce compte Google ne demande pas de code secret.';
    final CompteAvecCodeSecret avecCode = compte as CompteAvecCodeSecret;
    try {
      await avecCode.enregistrerCodeSecret(saisie);
    } on ErreurDrive catch (erreur) {
      return erreur.message;
    } catch (erreur) {
      return 'Enregistrement impossible : $erreur';
    }
    state = _lire();
    return null;
  }

  /// Enregistre l'ID collé. Retourne `null` si c'est fait, sinon le message à montrer.
  Future<String?> enregistrer(String saisie) async {
    try {
      await ref.read(compteGoogleProvider).enregistrerClientWeb(saisie);
    } on ErreurDrive catch (erreur) {
      return erreur.message;
    } catch (erreur) {
      return 'Enregistrement impossible : $erreur';
    }
    state = _lire();
    return null;
  }

  /// Oublie l'ID enregistré sur le téléphone. Retourne `null` si c'est fait, sinon le message à montrer.
  Future<String?> oublier() async {
    try {
      await ref.read(compteGoogleProvider).oublierClientWeb();
    } catch (erreur) {
      return 'Impossible d’oublier l’ID : $erreur';
    }
    state = _lire();
    return null;
  }
}

/// Les fichiers de Drive que l'on peut partager (factures, devis, exports), par rubrique. Relus à chaque ouverture de l'écran
/// « Partages ». Rien n'est créé sur Drive par cette lecture.
final fichiersPartageablesProvider = FutureProvider.autoDispose<FichiersPartageables>(
  (ref) => ref.watch(servicePartagesDriveProvider).lister(),
);

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
    if (state.occupe || ref.read(sauvegardeDriveProvider).occupe) return;
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
    if (state.occupe || ref.read(sauvegardeDriveProvider).occupe) return;
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

// -----------------------------------------------------------------------------
// Sauvegarde des données sur Drive (étape 7)
// -----------------------------------------------------------------------------

/// Le réglage « envoi automatique » et le dernier bilan des sauvegardes Drive (gardés sur le téléphone).
final etatSauvegardesDriveProvider = FutureProvider.autoDispose<EtatSauvegardesDrive>(
  (ref) => ref.watch(serviceSauvegardeDriveProvider).lireEtat(),
);

/// Les sauvegardes qui sont sur Drive, de la plus récente à la plus ancienne (pour les restaurer).
final sauvegardesDriveProvider = FutureProvider.autoDispose<List<SauvegardeDrive>>(
  (ref) => ref.watch(serviceSauvegardeDriveProvider).listerSauvegardes(),
);

/// Où en est la sauvegarde sur Drive.
enum PhaseSauvegardeDrive {
  /// Rien en cours.
  repos,

  /// Sauvegarde en cours.
  enCours,

  /// Terminée (ou arrêtée) : le résultat est dans [SuiviSauvegardeDrive.resultat].
  termine,

  /// Échec (Google injoignable, connexion perdue, données illisibles).
  erreur,
}

class SuiviSauvegardeDrive {
  const SuiviSauvegardeDrive._(
    this.phase, {
    this.progression,
    this.resultat,
    this.erreur,
    this.autorisationAExpire = false,
    this.arretDemande = false,
    this.automatique = false,
  });

  const SuiviSauvegardeDrive.repos() : this._(PhaseSauvegardeDrive.repos);

  const SuiviSauvegardeDrive.enCours(ProgressionSauvegardeDrive progression, {bool arretDemande = false, bool automatique = false})
    : this._(PhaseSauvegardeDrive.enCours, progression: progression, arretDemande: arretDemande, automatique: automatique);

  const SuiviSauvegardeDrive.termine(ResultatSauvegardeDrive resultat, {bool automatique = false})
    : this._(PhaseSauvegardeDrive.termine, resultat: resultat, automatique: automatique);

  const SuiviSauvegardeDrive.enErreur(String message, {bool autorisationAExpire = false, bool automatique = false})
    : this._(PhaseSauvegardeDrive.erreur, erreur: message, autorisationAExpire: autorisationAExpire, automatique: automatique);

  final PhaseSauvegardeDrive phase;
  final ProgressionSauvegardeDrive? progression;
  final ResultatSauvegardeDrive? resultat;
  final String? erreur;

  /// Vrai si la connexion à Google doit être refaite.
  final bool autorisationAExpire;

  /// Vrai si la personne a demandé l'arrêt : il a lieu à la fin du fichier en cours.
  final bool arretDemande;

  /// Vrai si cette sauvegarde est celle de l'envoi automatique (lancée à l'ouverture de l'application).
  final bool automatique;

  bool get occupe => phase == PhaseSauvegardeDrive.enCours;
}

/// La sauvegarde des données sur Drive. Elle continue si l'on quitte l'écran (tant que l'application reste ouverte), et c'est
/// elle que l'envoi automatique lance à l'ouverture de l'application.
final sauvegardeDriveProvider = NotifierProvider<SauvegardeDriveNotifier, SuiviSauvegardeDrive>(SauvegardeDriveNotifier.new);

class SauvegardeDriveNotifier extends Notifier<SuiviSauvegardeDrive> {
  AnnulationEnvoi? _annulation;

  @override
  SuiviSauvegardeDrive build() => const SuiviSauvegardeDrive.repos();

  /// « Sauvegarder maintenant sur Drive ».
  Future<void> sauvegarder() => _lancer(automatique: false);

  /// À l'ouverture de l'application : sauvegarde si l'envoi automatique est activé, que Google est connecté et que rien n'est
  /// passé depuis un jour. Ne fait rien (et ne dit rien) sinon : un échec s'affiche sur l'écran Google Drive, jamais ailleurs.
  Future<void> lancerSiBesoin() async {
    if (state.occupe || ref.read(envoiDriveProvider).occupe) return;
    try {
      if (!await ref.read(serviceSauvegardeDriveProvider).automatiqueEstDu()) return;
      if (await ref.read(compteGoogleProvider).restaurer() == null) return;
    } catch (_) {
      return;
    }
    await _lancer(automatique: true);
  }

  Future<void> _lancer({required bool automatique}) async {
    if (state.occupe || ref.read(envoiDriveProvider).occupe) return;
    final AnnulationEnvoi annulation = AnnulationEnvoi();
    _annulation = annulation;
    state = SuiviSauvegardeDrive.enCours(const ProgressionSauvegardeDrive.preparation(), automatique: automatique);

    // La progression arrive à chaque morceau envoyé : on ne rafraîchit l'écran que s'il y a du nouveau (autre étape, autre
    // fichier, autre nombre de fichiers) ou au plus tous les 150 ms.
    ProgressionSauvegardeDrive? derniere;
    DateTime? dernierRafraichissement;
    void suivre(ProgressionSauvegardeDrive progression) {
      final DateTime maintenant = DateTime.now();
      final ProgressionSauvegardeDrive? avant = derniere;
      final bool nouveau =
          avant == null ||
          avant.etape != progression.etape ||
          avant.fichiers?.fichierEnCours != progression.fichiers?.fichierEnCours ||
          avant.fichiers?.fichiersFaits != progression.fichiers?.fichiersFaits ||
          dernierRafraichissement == null ||
          maintenant.difference(dernierRafraichissement!) >= const Duration(milliseconds: 150);
      if (!nouveau) return;
      derniere = progression;
      dernierRafraichissement = maintenant;
      state = SuiviSauvegardeDrive.enCours(progression, arretDemande: annulation.demandee, automatique: automatique);
    }

    try {
      final ResultatSauvegardeDrive resultat = await ref
          .read(serviceSauvegardeDriveProvider)
          .sauvegarder(progression: suivre, annulation: annulation);
      state = SuiviSauvegardeDrive.termine(resultat, automatique: automatique);
      ref.invalidate(etatSauvegardesDriveProvider);
      ref.invalidate(dernierBilanDriveProvider);
      ref.invalidate(sauvegardesDriveProvider);
      if (resultat.arret?.autorisationAExpire ?? false) ref.read(profilGoogleProvider.notifier).connexionPerdue();
    } on ErreurDrive catch (erreur) {
      state = SuiviSauvegardeDrive.enErreur(
        erreur.message,
        autorisationAExpire: erreur.autorisationAExpire,
        automatique: automatique,
      );
      if (erreur.autorisationAExpire) ref.read(profilGoogleProvider.notifier).connexionPerdue();
    } on ErreurMetier catch (erreur) {
      state = SuiviSauvegardeDrive.enErreur(erreur.message, automatique: automatique);
    } catch (erreur) {
      state = SuiviSauvegardeDrive.enErreur('Sauvegarde impossible : $erreur', automatique: automatique);
    } finally {
      _annulation = null;
    }
  }

  /// Demande l'arrêt de l'envoi des fichiers : il s'arrête à la fin du fichier en cours, et les données ne sont alors pas
  /// sauvegardées.
  void arreter() {
    final AnnulationEnvoi? annulation = _annulation;
    final ProgressionSauvegardeDrive? progression = state.progression;
    if (annulation == null || !state.occupe || progression == null) return;
    if (progression.etape != EtapeSauvegardeDrive.fichiers) return;
    annulation.demander();
    state = SuiviSauvegardeDrive.enCours(progression, arretDemande: true, automatique: state.automatique);
  }

  /// Revient à « rien en cours » (après une déconnexion, par exemple). Sans effet pendant une sauvegarde.
  void reinitialiser() {
    if (!state.occupe) state = const SuiviSauvegardeDrive.repos();
  }
}
