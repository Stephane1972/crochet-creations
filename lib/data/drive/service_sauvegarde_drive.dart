import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';

import '../../domain/drive_envoi.dart';
import '../../domain/drive_sauvegardes.dart';
import '../../domain/drive_synchro.dart';
import '../sauvegarde/format_sauvegarde.dart';
import '../sauvegarde/service_sauvegarde.dart';
import 'client_drive.dart';
import 'compte_google.dart';
import 'service_drive.dart';

/// Les étapes d'une sauvegarde sur Drive.
enum EtapeSauvegardeDrive {
  /// Envoi des fichiers (photos, factures, devis, pièces jointes) qui ne sont pas encore sur Drive.
  fichiers,

  /// Lecture des données et préparation de la sauvegarde.
  donnees,

  /// Envoi de la sauvegarde, puis vérification qu'elle est bien sur Drive.
  envoi,
}

/// Où en est une sauvegarde sur Drive.
class ProgressionSauvegardeDrive {
  const ProgressionSauvegardeDrive(this.etape, {this.fichiers});

  /// La sauvegarde démarre.
  const ProgressionSauvegardeDrive.preparation() : this(EtapeSauvegardeDrive.fichiers);

  final EtapeSauvegardeDrive etape;

  /// Avancement de l'envoi des fichiers (à l'étape [EtapeSauvegardeDrive.fichiers]).
  final ProgressionEnvoi? fichiers;

  /// Numéro de l'étape (à partir de 1) sur 3.
  int get numeroEtape => etape.index + 1;
}

/// Comment s'est terminée une sauvegarde sur Drive.
enum IssueSauvegardeDrive {
  /// Une nouvelle sauvegarde des données est sur Drive.
  faite,

  /// Rien n'a changé depuis la dernière sauvegarde : aucune nouvelle sauvegarde n'a été ajoutée.
  dejaAJour,

  /// L'envoi des fichiers s'est arrêté avant la fin : les données n'ont pas été sauvegardées.
  interrompue,
}

/// Ce qu'une sauvegarde sur Drive a donné.
class ResultatSauvegardeDrive {
  const ResultatSauvegardeDrive({
    required this.issue,
    required this.envoi,
    this.sauvegarde,
    this.fichiersNonEnvoyes = const <String>[],
    this.arret,
  });

  final IssueSauvegardeDrive issue;

  /// Le bilan de l'envoi des fichiers qui précède la sauvegarde des données.
  final RapportEnvoi envoi;

  /// La sauvegarde des données qui est sur Drive (la nouvelle, ou la dernière si rien n'a changé) ; `null` si interrompue.
  final BilanSauvegardeDrive? sauvegarde;

  /// Les fichiers (`photos_produits/photo_1.jpg`) qui n'ont pas pu partir : la sauvegarde ne les liste pas.
  final List<String> fichiersNonEnvoyes;

  /// Pourquoi l'envoi s'est arrêté (connexion perdue, échecs répétés), si c'est le cas.
  final ErreurDrive? arret;
}

/// Les étapes d'une restauration depuis Drive.
enum EtapeRestaurationDrive {
  /// Téléchargement des fichiers listés par la sauvegarde, et contrôle de chacun.
  telechargement,

  /// Copie de sécurité des données actuelles.
  copieDeSecurite,

  /// Remplacement des données et des fichiers.
  remplacement,
}

/// Où en est une restauration depuis Drive.
class ProgressionRestaurationDrive {
  const ProgressionRestaurationDrive.telechargement({
    this.fichiersFaits = 0,
    this.fichiersTotal = 0,
    this.octetsFaits = 0,
    this.octetsTotal = 0,
    this.fichierEnCours,
  }) : etape = EtapeRestaurationDrive.telechargement,
       _fraction = null;

  const ProgressionRestaurationDrive.locale(this.etape, double? fraction)
    : fichiersFaits = 0,
      fichiersTotal = 0,
      octetsFaits = 0,
      octetsTotal = 0,
      fichierEnCours = null,
      _fraction = fraction;

  final EtapeRestaurationDrive etape;
  final int fichiersFaits;
  final int fichiersTotal;
  final int octetsFaits;
  final int octetsTotal;

  /// Nom du fichier en cours de téléchargement.
  final String? fichierEnCours;

  final double? _fraction;

  /// Numéro de l'étape (à partir de 1) sur 3.
  int get numeroEtape => etape.index + 1;

  /// Avancement de l'étape, de 0 à 1 ; `null` quand on ne peut pas le chiffrer.
  double? get fraction {
    if (etape != EtapeRestaurationDrive.telechargement) return _fraction;
    if (octetsTotal > 0) return (octetsFaits / octetsTotal).clamp(0.0, 1.0).toDouble();
    if (fichiersTotal > 0) return (fichiersFaits / fichiersTotal).clamp(0.0, 1.0).toDouble();
    return null;
  }
}

/// Une sauvegarde de Drive téléchargée et lue, prête à être restaurée après confirmation.
class PreparationRestaurationDrive {
  const PreparationRestaurationDrive({required this.sauvegarde, required this.archive, required this.examen});

  final SauvegardeDrive sauvegarde;

  /// La petite archive « données seules », téléchargée dans le dossier de travail.
  final File archive;
  final ExamenDonneesSeules examen;
}

/// Sauvegardes des données sur Google Drive, et restauration depuis Drive (étape 7 de l'évolution).
///
/// - **Une sauvegarde Drive est petite** : les données (toutes les tables) et la liste des fichiers avec leur empreinte
///   SHA-256. Les photos, factures, devis et pièces jointes ne sont pas recopiés : ils sont déjà dans leurs dossiers Drive
///   (étape 6), et la sauvegarde ne liste que ceux dont on est **sûr** qu'ils y sont.
/// - **Sauvegarder** envoie d'abord les fichiers manquants, puis la sauvegarde des données, qu'elle vérifie sur Drive. Rien
///   n'est ajouté si rien n'a changé depuis la dernière.
/// - **Tout est gardé** : chaque sauvegarde reste sur Drive, l'application ne supprime jamais rien (voir [ClientDrive]).
/// - **Restaurer** (aussi sur un téléphone neuf) : télécharge la sauvegarde choisie, puis chaque fichier qu'elle liste, en
///   vérifiant taille et empreinte, et seulement ensuite remplace les données (voir
///   [ServiceSauvegarde.restaurerDonneesSeules] : copie de sécurité, tout ou rien).
///
/// Le réglage « envoi automatique » et le dernier bilan sont dans un petit fichier du téléphone ([fichierEtat]), hors de la
/// base et de la sauvegarde.
class ServiceSauvegardeDrive {
  ServiceSauvegardeDrive({
    required ClientDrive client,
    required ServiceDrive envoi,
    required ServiceSauvegarde sauvegarde,
    required Directory dossierTravail,
    required File fichierEtat,
    DateTime Function()? horloge,
  }) : _client = client,
       _envoi = envoi,
       _sauvegarde = sauvegarde,
       _travail = dossierTravail,
       _fichierEtat = fichierEtat,
       _horloge = horloge ?? DateTime.now;

  final ClientDrive _client;
  final ServiceDrive _envoi;
  final ServiceSauvegarde _sauvegarde;
  final Directory _travail;
  final File _fichierEtat;
  final DateTime Function() _horloge;

  /// L'envoi automatique ne passe qu'une fois par jour, au plus.
  static const Duration delaiEnvoiAutomatique = Duration(days: 1);

  // Une seule opération à la fois (sauvegarde, préparation ou restauration).
  bool _occupe = false;

  /// Une sauvegarde ou une restauration est en cours (une seule opération à la fois).
  bool get occupe => _occupe;

  Directory get _dossierSauvegardes => Directory('${_travail.path}${Platform.pathSeparator}sauvegardes');
  Directory get _dossierRestauration => Directory('${_travail.path}${Platform.pathSeparator}restauration');

  Future<T> _exclusif<T>(Future<T> Function() travail) async {
    if (_occupe) throw const ErreurDrive('Une opération sur Drive est déjà en cours. Attendez qu’elle soit finie.');
    _occupe = true;
    try {
      return await travail();
    } finally {
      _occupe = false;
    }
  }

  // ---------------------------------------------------------------------------
  // État : réglage et dernier bilan
  // ---------------------------------------------------------------------------

  /// Le réglage et le dernier bilan. Un fichier illisible donne les valeurs de départ (envoi automatique désactivé).
  Future<EtatSauvegardesDrive> lireEtat() async {
    try {
      if (!await _fichierEtat.exists()) return const EtatSauvegardesDrive();
      return EtatSauvegardesDrive.depuisJson(jsonDecode(await _fichierEtat.readAsString()));
    } catch (_) {
      return const EtatSauvegardesDrive();
    }
  }

  // Les modifications de l'état se suivent : lire, changer, écrire sans qu'une autre s'intercale.
  Future<void> _etatEnSerie = Future<void>.value();

  Future<void> _modifierEtat(EtatSauvegardesDrive Function(EtatSauvegardesDrive etat) modification) {
    final Completer<void> fini = Completer<void>();
    _etatEnSerie = _etatEnSerie.then((_) async {
      try {
        final EtatSauvegardesDrive nouveau = modification(await lireEtat());
        await _fichierEtat.parent.create(recursive: true);
        final File provisoire = File('${_fichierEtat.path}.tmp');
        await provisoire.writeAsString(jsonEncode(nouveau.versJson()), flush: true);
        await provisoire.rename(_fichierEtat.path);
      } catch (erreur) {
        // L'état est une commodité : ne pas pouvoir l'écrire ne doit rien casser (le réglage reviendra à son ancienne valeur).
        debugPrint('État des sauvegardes Drive non enregistré : $erreur');
      }
      fini.complete();
    });
    return fini.future;
  }

  /// Active ou désactive l'envoi automatique.
  Future<void> reglerEnvoiAutomatique({required bool actif}) =>
      _modifierEtat((EtatSauvegardesDrive etat) => etat.copier(envoiAutomatique: actif));

  /// L'envoi automatique doit-il passer maintenant ? (activé, et pas encore passé depuis un jour)
  Future<bool> automatiqueEstDu() async =>
      envoiAutomatiqueDu(await lireEtat(), _horloge(), delai: delaiEnvoiAutomatique);

  // ---------------------------------------------------------------------------
  // Dossier des sauvegardes sur Drive
  // ---------------------------------------------------------------------------

  /// Le dossier « Sauvegardes » sous le dossier principal ; `null` s'il n'existe pas (et que [creer] est faux).
  Future<String?> _dossierDesSauvegardes({required bool creer}) async {
    String? racine = await _client.trouverDossier(nomDossierRacineDrive);
    if (racine == null) {
      if (!creer) return null;
      racine = await _client.creerDossier(nomDossierRacineDrive);
    }
    String? id = await _client.trouverDossier(nomDossierSauvegardesDrive, parentId: racine);
    if (id == null && creer) id = await _client.creerDossier(nomDossierSauvegardesDrive, parentId: racine);
    return id;
  }

  /// Les sauvegardes qui sont sur Drive, de la plus récente à la plus ancienne (aucune : liste vide). Lève une [ErreurDrive]
  /// si Drive est injoignable.
  Future<List<SauvegardeDrive>> listerSauvegardes() async {
    final String? id = await _dossierDesSauvegardes(creer: false);
    if (id == null) return const <SauvegardeDrive>[];
    return sauvegardesDrive(await _client.lister(id));
  }

  // ---------------------------------------------------------------------------
  // Reprise d'un appareil à l'autre
  // ---------------------------------------------------------------------------

  /// Compare cet appareil et Drive, **sans rien modifier** : Drive a-t-il une version plus récente, envoyée d'un autre
  /// appareil ? cet appareil a-t-il du neuf à envoyer ? (voir `drive_synchro.dart`). Lève une [ErreurDrive] si Drive est
  /// injoignable.
  Future<ConstatSynchro> constater() async {
    final List<SauvegardeDrive> existantes = await listerSauvegardes();
    final EtatSauvegardesDrive etat = await lireEtat();
    final String empreinte = await _sauvegarde.empreinteLocale();

    // Un appareil qui a envoyé des sauvegardes avant la synchronisation a gardé la dernière : c'est sa référence, sans
    // l'empreinte de ses données d'alors (on ne peut pas dire s'il a changé depuis).
    ReferenceSynchro? reference = etat.reference;
    final BilanSauvegardeDrive? derniere = etat.derniere;
    if (reference == null && derniere != null) {
      reference = ReferenceSynchro(nom: derniere.nom, date: dateDeNomSauvegardeDrive(derniere.nom) ?? derniere.date);
    }

    final SauvegardeDrive? distante = existantes.firstOrNull;
    final bool vierge = reference == null && await _sauvegarde.donneesVierges();
    return constaterSynchro(
      reference: reference,
      distante: distante,
      empreinteLocale: empreinte,
      donneesVierges: vierge,
      fichiersEnAttente: etat.fichiersNonEnvoyes.isNotEmpty,
    );
  }

  /// La personne garde les données de cet appareil plutôt que de reprendre la version [distante] de Drive : celle-ci reste sur
  /// Drive (rien n'est supprimé) mais n'est plus proposée ; le prochain envoi ajoutera une version plus récente, celle de
  /// cet appareil.
  Future<void> garderCetAppareil(SauvegardeDrive distante) {
    return _modifierEtat(
      (EtatSauvegardesDrive etat) => etat.copier(
        reference: ReferenceSynchro(nom: distante.nom, date: distante.date, empreinteLocale: etat.reference?.empreinteLocale),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sauvegarder
  // ---------------------------------------------------------------------------

  /// Sauvegarde sur Drive : envoie les fichiers manquants, puis les données. [annulation] arrête l'envoi des fichiers à la fin du
  /// fichier en cours (les données ne sont alors pas sauvegardées).
  ///
  /// Lève une [ErreurDrive] si Google est injoignable ou si la connexion est perdue avant de commencer, ou si la sauvegarde
  /// envoyée n'est pas retrouvée sur Drive ; une `ErreurMetier` si les données ne peuvent pas être lues ou préparées.
  Future<ResultatSauvegardeDrive> sauvegarder({
    void Function(ProgressionSauvegardeDrive progression)? progression,
    AnnulationEnvoi? annulation,
  }) {
    return _exclusif(() => _sauvegarder(progression, annulation));
  }

  /// À appeler à l'ouverture de l'application : sauvegarde si l'envoi automatique est activé et n'est pas passé depuis un jour.
  /// Retourne `null` si ce n'était pas le moment. Le dernier passage n'est noté que si la sauvegarde est allée jusqu'au bout :
  /// un échec (pas de réseau) est retenté à la prochaine ouverture.
  Future<ResultatSauvegardeDrive?> sauvegarderSiBesoin({
    void Function(ProgressionSauvegardeDrive progression)? progression,
    AnnulationEnvoi? annulation,
  }) async {
    if (!await automatiqueEstDu()) return null;
    return sauvegarder(progression: progression, annulation: annulation);
  }

  Future<ResultatSauvegardeDrive> _sauvegarder(
    void Function(ProgressionSauvegardeDrive progression)? progression,
    AnnulationEnvoi? annulation,
  ) async {
    progression?.call(const ProgressionSauvegardeDrive.preparation());
    await _viderDossier(_dossierSauvegardes, recreer: false);

    // 1. Les fichiers : la sauvegarde ne liste que ceux dont on sait qu'ils sont sur Drive.
    final ResultatEnvoi envoi = await _envoi.envoyer(
      progression: (ProgressionEnvoi p) =>
          progression?.call(ProgressionSauvegardeDrive(EtapeSauvegardeDrive.fichiers, fichiers: p)),
      annulation: annulation,
    );
    final List<String> nonEnvoyes = <String>[
      for (final ErreurEnvoi e in envoi.rapport.erreurs) '${e.dossier.nomLocal}/${e.nom}',
    ];
    if (envoi.arret != null || envoi.rapport.interrompu) {
      return ResultatSauvegardeDrive(
        issue: IssueSauvegardeDrive.interrompue,
        envoi: envoi.rapport,
        fichiersNonEnvoyes: nonEnvoyes,
        arret: envoi.arret,
      );
    }

    // 2. Les données, et ce qu'il y a déjà sur Drive.
    progression?.call(const ProgressionSauvegardeDrive(EtapeSauvegardeDrive.donnees));
    final DonneesSeules donnees = await _sauvegarde.lireDonneesSeules(fichiersConfirmes: envoi.confirmes);
    final String dossierId = (await _dossierDesSauvegardes(creer: true))!;
    final List<SauvegardeDrive> existantes = sauvegardesDrive(await _client.lister(dossierId));
    final SauvegardeDrive? derniere = existantes.firstOrNull;
    final DateTime maintenant = _horloge();

    final BilanSauvegardeDrive bilan;
    final IssueSauvegardeDrive issue;
    if (derniere != null && derniere.empreinte == donnees.empreinte) {
      // Rien de neuf : on n'ajoute pas une sauvegarde identique.
      issue = IssueSauvegardeDrive.dejaAJour;
      final BilanSauvegardeDrive? connu = (await lireEtat()).derniere;
      bilan = connu != null && connu.nom == derniere.nom
          ? connu
          : BilanSauvegardeDrive(date: derniere.date, nom: derniere.nom, octets: derniere.octets);
    } else {
      issue = IssueSauvegardeDrive.faite;
      bilan = await _envoyerSauvegarde(donnees, dossierId, maintenant, progression);
    }

    // Cet appareil et cette version de Drive sont identiques : c'est la référence de la prochaine comparaison. (L'empreinte est
    // celle de l'instantané envoyé : ce qui a été saisi pendant l'envoi compte comme du neuf.)
    final ReferenceSynchro reference = ReferenceSynchro(
      nom: bilan.nom,
      date: dateDeNomSauvegardeDrive(bilan.nom) ?? bilan.date,
      empreinteLocale: donnees.empreinteLocale,
    );
    await _modifierEtat(
      (EtatSauvegardesDrive etat) => etat.copier(
        derniereVerification: maintenant,
        derniere: bilan,
        fichiersNonEnvoyes: nonEnvoyes,
        reference: reference,
      ),
    );
    return ResultatSauvegardeDrive(
      issue: issue,
      envoi: envoi.rapport,
      sauvegarde: bilan,
      fichiersNonEnvoyes: nonEnvoyes,
    );
  }

  /// Écrit l'archive des données dans le dossier de travail, l'envoie, puis vérifie qu'elle est sur Drive avec la bonne taille.
  Future<BilanSauvegardeDrive> _envoyerSauvegarde(
    DonneesSeules donnees,
    String dossierId,
    DateTime maintenant,
    void Function(ProgressionSauvegardeDrive progression)? progression,
  ) async {
    progression?.call(const ProgressionSauvegardeDrive(EtapeSauvegardeDrive.envoi));
    final String nom = nomSauvegardeDrive(maintenant);
    final File archive = File('${_dossierSauvegardes.path}${Platform.pathSeparator}$nom');
    try {
      await _sauvegarde.ecrireDonneesSeules(donnees, archive);
      final int octets = await archive.length();
      await _client.envoyer(fichier: archive, nom: nom, dossierId: dossierId, empreinte: donnees.empreinte);

      // Vérification : le fichier est bien dans le dossier Drive, de la bonne taille.
      final List<FichierDistant> apres = await _client.lister(dossierId);
      final bool retrouvee = apres.any((FichierDistant f) => f.nom == nom && (f.octets == null || f.octets == octets));
      if (!retrouvee) {
        throw const ErreurDrive(
          'La sauvegarde envoyée n’a pas été retrouvée sur Drive : elle n’est pas comptée. Réessayez.',
        );
      }
      return BilanSauvegardeDrive(date: maintenant, nom: nom, octets: octets, fichiers: donnees.nombreFichiers);
    } finally {
      await _effacerFichier(archive);
      await _effacerFichier(File('${archive.path}.tmp'));
    }
  }

  // ---------------------------------------------------------------------------
  // Restaurer
  // ---------------------------------------------------------------------------

  /// Télécharge la sauvegarde [choisie] (un petit fichier) et la lit, **sans rien modifier** : à montrer à la personne avant de
  /// lui demander confirmation. Appeler ensuite [restaurer], ou [abandonnerRestauration] si elle renonce.
  Future<PreparationRestaurationDrive> preparerRestauration(SauvegardeDrive choisie) {
    return _exclusif(() async {
      final Directory dossier = await _viderDossier(_dossierRestauration, recreer: true);
      try {
        final File archive = File('${dossier.path}${Platform.pathSeparator}${choisie.nom}');
        await _client.telecharger(id: choisie.id, destination: archive);
        final ExamenDonneesSeules examen = await _sauvegarde.examinerDonneesSeules(archive);
        return PreparationRestaurationDrive(sauvegarde: choisie, archive: archive, examen: examen);
      } catch (_) {
        await _viderDossier(_dossierRestauration, recreer: false);
        rethrow;
      }
    });
  }

  /// Remplace **toutes** les données par celles de la sauvegarde préparée. Les fichiers qu'elle liste sont téléchargés depuis
  /// leurs dossiers Drive et contrôlés (taille et empreinte) avant que quoi que ce soit ne soit touché ; un fichier absent de
  /// Drive ou abîmé n'est pas remis en place et est signalé dans le résultat. Si un téléchargement échoue (pas de réseau), tout
  /// est abandonné : rien n'a été modifié.
  Future<ResultatRestauration> restaurer(
    PreparationRestaurationDrive preparation, {
    void Function(ProgressionRestaurationDrive progression)? progression,
  }) {
    return _exclusif(() async {
      try {
        final ResultatRestauration resultat = await _sauvegarde.restaurerDonneesSeules(
          preparation.archive,
          recuperer: (List<EmpreinteFichier> annonces, Directory Function(String dossier) destination) =>
              _recuperer(annonces, destination, progression),
          surProgression: (ProgressionSauvegarde p) {
            final EtapeRestaurationDrive? etape = switch (p.etape) {
              EtapeSauvegarde.copieDeSecurite => EtapeRestaurationDrive.copieDeSecurite,
              EtapeSauvegarde.remplacement => EtapeRestaurationDrive.remplacement,
              _ => null,
            };
            if (etape != null) progression?.call(ProgressionRestaurationDrive.locale(etape, p.fraction));
          },
        );
        await _noterReprise(preparation.sauvegarde);
        return resultat;
      } finally {
        await _viderDossier(_dossierRestauration, recreer: false);
      }
    });
  }

  /// Après une restauration réussie : les données de cet appareil sont celles de [reprise], qui devient sa référence. Ne fait
  /// jamais échouer la restauration (sans référence, la prochaine comparaison demandera simplement à la personne de choisir).
  Future<void> _noterReprise(SauvegardeDrive reprise) async {
    try {
      final String empreinte = await _sauvegarde.empreinteLocale();
      await _modifierEtat(
        (EtatSauvegardesDrive etat) => etat.copier(
          reference: ReferenceSynchro(nom: reprise.nom, date: reprise.date, empreinteLocale: empreinte),
          fichiersNonEnvoyes: const <String>[],
        ),
      );
    } catch (erreur) {
      debugPrint('Référence de synchronisation non enregistrée après la restauration : $erreur');
    }
  }

  /// La personne renonce : efface le téléchargement préparé.
  Future<void> abandonnerRestauration() => _viderDossier(_dossierRestauration, recreer: false);

  /// Télécharge chaque fichier annoncé depuis son dossier Drive, dans le dossier provisoire, et le contrôle. Retourne ceux qui
  /// sont en place. Un fichier introuvable sur Drive (ou de taille différente, ou abîmé) est laissé de côté ; une erreur de
  /// Drive ou du réseau arrête tout.
  Future<Set<String>> _recuperer(
    List<EmpreinteFichier> annonces,
    Directory Function(String dossier) destination,
    void Function(ProgressionRestaurationDrive progression)? progression,
  ) async {
    final Set<String> installes = <String>{};
    if (annonces.isEmpty) return installes;

    final Map<DossierDrive, String> ids = await _envoi.dossiersDrive(creer: false);
    if (ids.isEmpty) {
      throw const ErreurDrive(
        'Les dossiers des photos et des documents sont introuvables sur ce Drive. '
        'Vérifiez que le compte Google connecté est le bon.',
      );
    }

    final int octetsTotal = annonces.fold<int>(0, (int somme, EmpreinteFichier f) => somme + f.octets);
    int octetsFaits = 0;
    final Map<DossierDrive, List<FichierDistant>> distants = <DossierDrive, List<FichierDistant>>{};

    void signaler(int fichiersFaits, String? nom, int octetsEnCours) => progression?.call(
      ProgressionRestaurationDrive.telechargement(
        fichiersFaits: fichiersFaits,
        fichiersTotal: annonces.length,
        octetsFaits: octetsFaits + octetsEnCours,
        octetsTotal: octetsTotal,
        fichierEnCours: nom,
      ),
    );

    for (int i = 0; i < annonces.length; i++) {
      final EmpreinteFichier annonce = annonces[i];
      final List<String> morceaux = annonce.chemin.split('/');
      final DossierDrive? dossier = DossierDrive.values.where((DossierDrive d) => d.nomLocal == morceaux.first).firstOrNull;
      final String nom = morceaux.last;
      final String? idDossier = dossier == null ? null : ids[dossier];
      if (dossier == null || idDossier == null) {
        octetsFaits += annonce.octets;
        continue;
      }
      signaler(i, nom, 0);

      final List<FichierDistant> dansLeDossier = distants[dossier] ??= await _client.lister(idDossier);
      // Le fichier du même nom et de la même taille : un fichier de même nom mais d'une autre taille est une autre version
      // (un PDF refait depuis), pas celui que la sauvegarde liste.
      final FichierDistant? trouve = dansLeDossier
          .where((FichierDistant f) => f.nom == nom && (f.octets == null || f.octets == annonce.octets))
          .firstOrNull;
      if (trouve == null) {
        octetsFaits += annonce.octets;
        continue;
      }

      final File cible = File('${destination(morceaux.first).path}${Platform.pathSeparator}$nom');
      await _client.telecharger(
        id: trouve.id,
        destination: cible,
        progression: (int recus) => signaler(i, nom, recus),
      );
      final ({int octets, String sha256}) lu = await _empreinte(cible);
      if (lu.octets == annonce.octets && lu.sha256 == annonce.sha256) {
        installes.add(annonce.chemin);
      } else {
        // Abîmé ou modifié depuis : on ne le remet pas en place.
        await _effacerFichier(cible);
      }
      octetsFaits += annonce.octets;
    }
    signaler(annonces.length, null, 0);
    return installes;
  }

  // ---------------------------------------------------------------------------
  // Fichiers de travail
  // ---------------------------------------------------------------------------

  Future<({int octets, String sha256})> _empreinte(File fichier) async {
    int octets = 0;
    final Stream<List<int>> flux = fichier.openRead().map((List<int> morceau) {
      octets += morceau.length;
      return morceau;
    });
    final String empreinte = (await sha256.bind(flux).first).toString();
    return (octets: octets, sha256: empreinte);
  }

  /// Vide le dossier de travail [dossier] (et le recrée vide si [recreer]).
  Future<Directory> _viderDossier(Directory dossier, {required bool recreer}) async {
    try {
      if (await dossier.exists()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Un reste de téléchargement est écrasé à la prochaine opération.
    }
    if (recreer) await dossier.create(recursive: true);
    return dossier;
  }

  Future<void> _effacerFichier(File fichier) async {
    try {
      if (await fichier.exists()) await fichier.delete();
    } on FileSystemException {
      // Le dossier de travail est vidé au début de la prochaine sauvegarde.
    }
  }
}
