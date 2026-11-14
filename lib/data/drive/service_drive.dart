import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import '../../domain/drive_envoi.dart';
import 'client_drive.dart';
import 'compte_google.dart';

/// Ce que la vérification a trouvé : pour chaque dossier, ce qui est déjà sur Drive et ce qu'il reste à envoyer.
class VerificationDrive {
  const VerificationDrive(this.plans);

  final List<PlanDossier> plans;

  /// Fichiers du téléphone dans les quatre dossiers.
  int get fichiersLocaux => plans.fold(0, (int s, PlanDossier p) => s + p.nombreLocaux);

  int get dejaSurDrive => plans.fold(0, (int s, PlanDossier p) => s + p.dejaSurDrive);

  int get fichiersAEnvoyer => plans.fold(0, (int s, PlanDossier p) => s + p.aEnvoyer.length);

  int get octetsAEnvoyer => plans.fold(0, (int s, PlanDossier p) => s + p.octetsAEnvoyer);

  bool get toutEstSurDrive => fichiersAEnvoyer == 0;
}

/// Où en est un envoi.
class ProgressionEnvoi {
  const ProgressionEnvoi({
    this.fichiersFaits = 0,
    this.fichiersTotal = 0,
    this.octetsFaits = 0,
    this.octetsTotal = 0,
    this.fichierEnCours,
  });

  /// L'envoi démarre : le plan n'est pas encore connu.
  const ProgressionEnvoi.preparation() : this();

  final int fichiersFaits;
  final int fichiersTotal;
  final int octetsFaits;
  final int octetsTotal;

  /// Nom du fichier en cours d'envoi (`null` pendant la préparation).
  final String? fichierEnCours;

  /// Avancement de 0 à 1 (0 tant que le plan n'est pas connu).
  double get fraction {
    if (octetsTotal > 0) return (octetsFaits / octetsTotal).clamp(0.0, 1.0).toDouble();
    if (fichiersTotal > 0) return (fichiersFaits / fichiersTotal).clamp(0.0, 1.0).toDouble();
    return 0;
  }
}

/// Demande d'arrêt d'un envoi : il s'arrête à la fin du fichier en cours (un fichier à moitié envoyé n'est jamais créé :
/// l'envoi se fait en une seule opération côté Drive).
class AnnulationEnvoi {
  bool _demandee = false;

  bool get demandee => _demandee;

  void demander() => _demandee = true;
}

/// Ce qu'un envoi a donné : le bilan, et pourquoi il s'est arrêté avant la fin (`null` : il est allé jusqu'au bout, ou
/// la personne l'a arrêté).
class ResultatEnvoi {
  const ResultatEnvoi({required this.rapport, this.arret});

  final RapportEnvoi rapport;
  final ErreurDrive? arret;
}

/// Envoi des fichiers de l'application vers Google Drive, à la demande.
///
/// Trois principes :
/// - **Copier, jamais supprimer** : le service ne sait ni supprimer ni partager (voir [ClientDrive]) ;
/// - **Drive est la mémoire** : ce qui est déjà parti se reconnaît en comparant avec le dossier Drive (`planifierEnvoi`),
///   donc rien à synchroniser sur le téléphone, et un téléphone neuf ou réinstallé repart sans rien renvoyer pour rien ;
/// - **un fichier qui échoue n'empêche pas les autres** (sauf si la connexion à Google est perdue, ou après trois échecs
///   d'affilée : inutile d'insister), et chaque échec est dit dans le bilan.
///
/// Le dernier bilan est gardé dans un petit fichier du téléphone ([fichierBilan]), hors de la base : il n'entre ni dans la
/// sauvegarde ni dans le schéma.
class ServiceDrive {
  ServiceDrive({
    required ClientDrive client,
    required Map<DossierDrive, Directory> dossiers,
    required File fichierBilan,
    DateTime Function()? horloge,
  }) : _client = client,
       _dossiers = dossiers,
       _fichierBilan = fichierBilan,
       _horloge = horloge ?? DateTime.now;

  final ClientDrive _client;
  final Map<DossierDrive, Directory> _dossiers;
  final File _fichierBilan;
  final DateTime Function() _horloge;

  /// Échecs d'affilée au bout desquels l'envoi s'arrête.
  static const int echecsAvantArret = 3;

  // --- Dernier bilan -----------------------------------------------------------

  /// Le bilan du dernier envoi, `null` s'il n'y en a pas encore (ou si le fichier est illisible).
  Future<RapportEnvoi?> dernierBilan() async {
    try {
      if (!await _fichierBilan.exists()) return null;
      return RapportEnvoi.depuisJson(jsonDecode(await _fichierBilan.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _enregistrerBilan(RapportEnvoi rapport) async {
    try {
      await _fichierBilan.parent.create(recursive: true);
      // Écrit dans un fichier provisoire renommé à la fin : jamais un bilan à moitié écrit.
      final File provisoire = File('${_fichierBilan.path}.tmp');
      await provisoire.writeAsString(jsonEncode(rapport.versJson()), flush: true);
      await provisoire.rename(_fichierBilan.path);
    } catch (_) {
      // Le bilan est une commodité : ne pas pouvoir l'écrire ne doit rien casser.
    }
  }

  // --- Fichiers du téléphone ---------------------------------------------------

  Directory? _dossierLocal(DossierDrive dossier) => _dossiers[dossier];

  File _fichierLocal(DossierDrive dossier, String nom) =>
      File('${_dossierLocal(dossier)!.path}${Platform.pathSeparator}$nom');

  /// Les fichiers du dossier sur le téléphone. Les fichiers provisoires (`.tmp`) et cachés sont ignorés : ce sont des
  /// copies en cours, jamais un fichier de la personne.
  Future<List<FichierLocal>> _lireLocaux(DossierDrive dossier) async {
    final Directory? dossierLocal = _dossierLocal(dossier);
    if (dossierLocal == null || !await dossierLocal.exists()) return const <FichierLocal>[];
    final List<FichierLocal> locaux = <FichierLocal>[];
    await for (final FileSystemEntity entite in dossierLocal.list(followLinks: false)) {
      if (entite is! File) continue;
      final String nom = entite.path.split(Platform.pathSeparator).last;
      if (nom.endsWith('.tmp') || nom.startsWith('.')) continue;
      locaux.add(
        FichierLocal(
          nom: nom,
          octets: await entite.length(),
          empreinte: dossier.compareContenu ? await _empreinte(entite) : null,
        ),
      );
    }
    return locaux;
  }

  Future<String> _empreinte(File fichier) async => (await sha256.bind(fichier.openRead()).first).toString();

  // --- Dossiers sur Drive ------------------------------------------------------

  /// Retrouve (ou crée, si [creer]) le dossier principal puis ses sous-dossiers. Un dossier absent (et non créé) n'a pas
  /// d'entrée dans le résultat.
  Future<Map<DossierDrive, String>> _dossiersDrive({required bool creer}) async {
    String? racine = await _client.trouverDossier(nomDossierRacineDrive);
    if (racine == null) {
      if (!creer) return const <DossierDrive, String>{};
      racine = await _client.creerDossier(nomDossierRacineDrive);
    }
    final Map<DossierDrive, String> ids = <DossierDrive, String>{};
    for (final DossierDrive dossier in DossierDrive.values) {
      String? id = await _client.trouverDossier(dossier.nomDrive, parentId: racine);
      if (id == null && creer) id = await _client.creerDossier(dossier.nomDrive, parentId: racine);
      if (id != null) ids[dossier] = id;
    }
    return ids;
  }

  // --- Vérifier et envoyer -----------------------------------------------------

  /// Compare le téléphone et Drive, **sans rien envoyer ni créer**. Lève une [ErreurDrive] si Drive est injoignable.
  Future<VerificationDrive> verifier() async {
    final Map<DossierDrive, String> ids = await _dossiersDrive(creer: false);
    final List<PlanDossier> plans = <PlanDossier>[];
    for (final DossierDrive dossier in DossierDrive.values) {
      final String? id = ids[dossier];
      final List<FichierDistant> distants = id == null ? const <FichierDistant>[] : await _client.lister(id);
      plans.add(planifierEnvoi(dossier: dossier, locaux: await _lireLocaux(dossier), distants: distants));
    }
    return VerificationDrive(plans);
  }

  /// Envoie ce qui n'est pas encore sur Drive, un fichier après l'autre. [progression] est appelée à chaque étape.
  /// Lève une [ErreurDrive] si la préparation échoue (Google injoignable, droit retiré) : rien n'est alors parti et le
  /// dernier bilan reste celui d'avant. Ensuite, tout se passe dans le bilan.
  Future<ResultatEnvoi> envoyer({void Function(ProgressionEnvoi progression)? progression, AnnulationEnvoi? annulation}) async {
    progression?.call(const ProgressionEnvoi.preparation());
    final Map<DossierDrive, String> ids = await _dossiersDrive(creer: true);
    final List<PlanDossier> plans = <PlanDossier>[];
    for (final DossierDrive dossier in DossierDrive.values) {
      final List<FichierDistant> distants = await _client.lister(ids[dossier]!);
      plans.add(planifierEnvoi(dossier: dossier, locaux: await _lireLocaux(dossier), distants: distants));
    }

    final int fichiersTotal = plans.fold(0, (int s, PlanDossier p) => s + p.aEnvoyer.length);
    final int octetsTotal = plans.fold(0, (int s, PlanDossier p) => s + p.octetsAEnvoyer);
    final int dejaSurDrive = plans.fold(0, (int s, PlanDossier p) => s + p.dejaSurDrive);

    final List<ErreurEnvoi> erreurs = <ErreurEnvoi>[];
    int envoyes = 0;
    int octetsEnvoyes = 0;
    int echecsDAffilee = 0;
    bool interrompu = false;
    ErreurDrive? arret;

    void signaler(String? nom, int octetsEnCours) => progression?.call(
      ProgressionEnvoi(
        fichiersFaits: envoyes + erreurs.length,
        fichiersTotal: fichiersTotal,
        octetsFaits: octetsEnvoyes + octetsEnCours,
        octetsTotal: octetsTotal,
        fichierEnCours: nom,
      ),
    );

    envoi:
    for (final PlanDossier plan in plans) {
      for (final EnvoiPrevu prevu in plan.aEnvoyer) {
        if (annulation?.demandee ?? false) {
          interrompu = true;
          break envoi;
        }
        signaler(prevu.fichier.nom, 0);
        try {
          await _client.envoyer(
            fichier: _fichierLocal(plan.dossier, prevu.fichier.nom),
            nom: prevu.fichier.nom,
            dossierId: ids[plan.dossier]!,
            empreinte: prevu.fichier.empreinte,
            idExistant: prevu.idDistant,
            progression: (int lus) => signaler(prevu.fichier.nom, lus),
          );
          envoyes++;
          octetsEnvoyes += prevu.fichier.octets;
          echecsDAffilee = 0;
        } on ErreurDrive catch (erreur) {
          erreurs.add(ErreurEnvoi(dossier: plan.dossier, nom: prevu.fichier.nom, message: erreur.message));
          echecsDAffilee++;
          if (erreur.autorisationAExpire || echecsDAffilee >= echecsAvantArret) {
            arret = erreur;
            interrompu = true;
            break envoi;
          }
        } catch (erreur) {
          erreurs.add(
            ErreurEnvoi(dossier: plan.dossier, nom: prevu.fichier.nom, message: 'Envoi impossible : $erreur'),
          );
          echecsDAffilee++;
          if (echecsDAffilee >= echecsAvantArret) {
            interrompu = true;
            break envoi;
          }
        }
      }
    }
    signaler(null, 0);

    final RapportEnvoi rapport = RapportEnvoi(
      date: _horloge(),
      envoyes: envoyes,
      dejaSurDrive: dejaSurDrive,
      octetsEnvoyes: octetsEnvoyes,
      erreurs: erreurs,
      interrompu: interrompu,
    );
    await _enregistrerBilan(rapport);
    return ResultatEnvoi(rapport: rapport, arret: arret);
  }
}
