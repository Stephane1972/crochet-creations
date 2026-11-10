import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder;
import 'package:archive/archive_io.dart' show InputFileStream, OutputFileStream, ZipFileEncoder;
import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/erreurs.dart';
import '../database/app_database.dart';
import 'espace_libre.dart';
import 'format_sauvegarde.dart';

/// Ce qu'une restauration a remis en place.
class ResultatRestauration {
  const ResultatRestauration({required this.lignes, required this.fichiers, this.fichiersAbsents = const <String>[]});

  /// Lignes de la base (produits, clients, ventes...) et fichiers (photos, PDF).
  final int lignes;
  final int fichiers;

  /// Les photos citées par les données mais absentes de la sauvegarde (elle était incomplète) : elles n'ont
  /// pas pu être remises.
  final List<String> fichiersAbsents;
}

/// Sauvegarde et restauration des données (étape 11, rendues fiables à l'étape 3 du plan d'évolution).
///
/// - **Sauvegarder** : une archive `.zip` avec toute la base et les fichiers (voir [FormatSauvegarde]), rangée
///   dans le dossier des sauvegardes de l'application. L'archive est **écrite en flux** (jamais entièrement en
///   mémoire : des vidéos pourront s'y ajouter), avec la liste des fichiers et leur empreinte SHA-256, puis
///   **relue** pour vérifier qu'elle est entière. Elle est dite **incomplète** si des photos citées par les
///   données manquent sur le téléphone.
/// - **Sauvegarde automatique** : à l'ouverture de l'application, si la dernière date de plus d'un jour ;
///   les 7 dernières sont conservées.
/// - **Restaurer** : lit l'archive depuis un fichier, **vérifie l'empreinte de chaque fichier avant de toucher
///   à quoi que ce soit**, puis remplace **tout** (données, photos, PDF), après une copie de sécurité de ce qui
///   existait. Si la restauration échoue, rien n'a été modifié.
///
/// Tout est lu et écrit tel quel (lignes SQL → JSON → lignes SQL) : aucun calcul n'est refait, un montant
/// ou un numéro de facture revient donc exactement comme il était.
class ServiceSauvegarde {
  ServiceSauvegarde({
    required AppDatabase base,
    required this.dossierSauvegardes,
    required this.dossierExports,
    required Directory dossierPhotos,
    required Directory dossierFactures,
    required Directory dossierDevis,
    DateTime Function()? horloge,
    ControleEspaceLibre? espaceLibre,
  }) : _base = base,
       _dossiers = <String, Directory>{
         FormatSauvegarde.dossierPhotos: dossierPhotos,
         FormatSauvegarde.dossierFactures: dossierFactures,
         FormatSauvegarde.dossierDevis: dossierDevis,
       },
       _horloge = horloge ?? DateTime.now,
       _espaceLibre = espaceLibre ?? const ControleEspaceLibreInconnu();

  /// Nombre de sauvegardes automatiques conservées.
  static const int sauvegardesAutomatiquesConservees = 7;

  /// Nombre de copies de sécurité (avant restauration) conservées.
  static const int copiesDeSecuriteConservees = 3;

  /// Une sauvegarde automatique est faite si la dernière date de cette durée ou plus.
  static const Duration delaiSauvegardeAutomatique = Duration(days: 1);

  /// Place laissée libre en plus de ce qu'il faut écrire (le téléphone a besoin de respirer).
  static const int margeEspaceLibre = 10 * 1024 * 1024;

  final AppDatabase _base;
  final Map<String, Directory> _dossiers;
  final DateTime Function() _horloge;
  final ControleEspaceLibre _espaceLibre;

  /// Où sont rangées les sauvegardes (créé à la première).
  final Directory dossierSauvegardes;

  /// Où sont écrits les fichiers d'export (CSV, JSON) avant d'être partagés.
  final Directory dossierExports;

  static const String _messageNonReconnu = 'Ce fichier n’est pas une sauvegarde de l’application.';
  static const String _messageTropRecente =
      'Cette sauvegarde a été faite avec une version plus récente de l’application. '
      'Mettez l’application à jour avant de la restaurer.';
  static const String _messageIncompatible =
      'Cette sauvegarde est abîmée ou incompatible : rien n’a été modifié.';
  static const String _messageIntrouvable = 'Ce fichier est introuvable sur le téléphone.';

  // Une seule sauvegarde ou restauration à la fois : sinon l'une effacerait les fichiers provisoires de l'autre.
  Future<void> _derniere = Future<void>.value();

  Future<T> _enSerie<T>(Future<T> Function() travail) {
    final Completer<T> resultat = Completer<T>();
    _derniere = _derniere.then((_) async {
      try {
        resultat.complete(await travail());
      } catch (erreur, pile) {
        resultat.completeError(erreur, pile);
      }
    });
    return resultat.future;
  }

  // ---------------------------------------------------------------------------
  // Créer, lister, supprimer
  // ---------------------------------------------------------------------------

  /// Fabrique une sauvegarde du moment et la range dans le dossier des sauvegardes.
  ///
  /// Dans l'ordre : lecture de la base → liste des photos et PDF avec leur empreinte SHA-256 → contrôle de la
  /// place libre → écriture de l'archive dans un fichier provisoire → relecture de l'archive → le fichier
  /// prend son vrai nom. Au moindre problème, le fichier provisoire est effacé : on ne garde jamais une
  /// sauvegarde à moitié écrite.
  ///
  /// [surProgression] est prévenue à chaque avancée (pour la barre de progression de l'écran).
  Future<SauvegardeLocale> creer(TypeSauvegarde type, {SurProgression? surProgression}) {
    return _enSerie(() => _creer(type, surProgression));
  }

  Future<SauvegardeLocale> _creer(TypeSauvegarde type, SurProgression? surProgression) async {
    final DateTime maintenant = _horloge();
    await dossierSauvegardes.create(recursive: true);
    await _effacerProvisoires();

    void avancer(EtapeSauvegarde etape, int fait, int total) =>
        surProgression?.call(ProgressionSauvegarde(etape, fait, total));

    // 1. Les données.
    avancer(EtapeSauvegarde.lectureDonnees, 0, 1);
    final _InstantaneBase donnees = await _lireBase();
    avancer(EtapeSauvegarde.lectureDonnees, 1, 1);

    // 2. Les photos et PDF : la liste, la taille et l'empreinte de chacun.
    final List<_FichierLocal> presents = await _fichiersPresents();
    final List<_FichierLocal> lisibles = <_FichierLocal>[];
    final List<EmpreinteFichier> empreintes = <EmpreinteFichier>[];
    avancer(EtapeSauvegarde.empreintes, 0, presents.length);
    for (int i = 0; i < presents.length; i++) {
      final _FichierLocal f = presents[i];
      try {
        // Un nom que la restauration refuserait n'entre pas dans l'archive ; un fichier illisible non plus.
        if (_lireChemin(f.chemin) != null) {
          final ({int octets, String sha256}) lu = await _empreinte(f.fichier);
          empreintes.add(EmpreinteFichier(chemin: f.chemin, octets: lu.octets, sha256: lu.sha256));
          lisibles.add(f);
        }
      } on FileSystemException catch (erreur) {
        debugPrint('Fichier illisible, il ne sera pas sauvegardé : ${f.chemin} ($erreur)');
      }
      avancer(EtapeSauvegarde.empreintes, i + 1, presents.length);
    }

    // Une sauvegarde est « incomplète » si une photo citée par les données manque (ou est illisible).
    final Set<String> disponibles = empreintes.map((EmpreinteFichier e) => e.chemin).toSet();
    final List<String> absents =
        FormatSauvegarde.fichiersIrremplacablesCites(donnees.tables).difference(disponibles).toList()..sort();

    final List<int> jsonDonnees = _jsonDonnees(
      donnees,
      date: maintenant,
      nombreFichiers: empreintes.length,
      fichiersAbsents: absents,
    );
    final List<int> jsonListe = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'format': FormatSauvegarde.version,
        'fichiers': empreintes.map((EmpreinteFichier e) => e.versJson()).toList(),
      }),
    );

    final int octetsFichiers = empreintes.fold<int>(0, (int somme, EmpreinteFichier e) => somme + e.octets);
    await _verifierPlace(octetsFichiers + jsonDonnees.length + jsonListe.length, 'faire la sauvegarde');

    // 3. L'archive, écrite dans un fichier provisoire.
    final File provisoire = File(
      '${dossierSauvegardes.path}${Platform.pathSeparator}${_nomFichier(type, maintenant, 1, true)}.tmp',
    );
    final File fichier;
    try {
      final ZipFileEncoder encodeur = ZipFileEncoder()..create(provisoire.path);
      try {
        encodeur.addArchiveFile(ArchiveFile.bytes(FormatSauvegarde.fichierDonnees, jsonDonnees));
        encodeur.addArchiveFile(ArchiveFile.bytes(FormatSauvegarde.fichierListe, jsonListe));
        avancer(EtapeSauvegarde.ecritureFichiers, 0, lisibles.length);
        for (int i = 0; i < lisibles.length; i++) {
          // Photos et PDF sont déjà compressés : on les range tels quels, sans calcul inutile.
          await encodeur.addFile(
            lisibles[i].fichier,
            '${FormatSauvegarde.prefixeFichiers}${lisibles[i].chemin}',
            ZipFileEncoder.store,
          );
          avancer(EtapeSauvegarde.ecritureFichiers, i + 1, lisibles.length);
        }
      } finally {
        await encodeur.close();
      }

      // 4. Relecture : l'archive écrite contient bien tout ce qu'elle annonce.
      avancer(EtapeSauvegarde.verification, 0, 1);
      await _verifierArchiveEcrite(provisoire, empreintes);
      avancer(EtapeSauvegarde.verification, 1, 1);

      fichier = await _fichierLibre(type, maintenant, complete: absents.isEmpty);
      await provisoire.rename(fichier.path);
    } catch (erreur, pile) {
      await _effacer(provisoire);
      if (erreur is ErreurMetier) rethrow;
      debugPrint('Sauvegarde impossible : $erreur\n$pile');
      if (_disqueRempli(erreur)) {
        throw const DonneeInvalide(
          'Le téléphone est plein : la sauvegarde n’a pas pu être écrite et a été abandonnée. '
          'Libérez de la place (supprimez d’anciennes sauvegardes de la liste, des photos ou des applications '
          'inutiles), puis recommencez.',
        );
      }
      rethrow;
    }

    await _purger(type);
    return SauvegardeLocale(
      fichier: fichier,
      type: type,
      date: maintenant,
      octets: await fichier.length(),
      complete: absents.isEmpty,
      fichiersAbsents: absents,
    );
  }

  /// Les sauvegardes conservées sur le téléphone, de la plus récente à la plus ancienne.
  Future<List<SauvegardeLocale>> lister() async {
    if (!await dossierSauvegardes.exists()) return <SauvegardeLocale>[];
    final List<SauvegardeLocale> resultat = <SauvegardeLocale>[];
    await for (final FileSystemEntity entite in dossierSauvegardes.list()) {
      if (entite is! File) continue;
      final String nom = entite.uri.pathSegments.last;
      final ({TypeSauvegarde type, DateTime date, bool complete})? lu = _lireNom(nom);
      if (lu == null) continue; // fichier provisoire ou étranger : ignoré
      resultat.add(
        SauvegardeLocale(
          fichier: entite,
          type: lu.type,
          date: lu.date,
          octets: await entite.length(),
          complete: lu.complete,
        ),
      );
    }
    resultat.sort((SauvegardeLocale a, SauvegardeLocale b) {
      final int parDate = b.date.compareTo(a.date);
      return parDate != 0 ? parDate : b.nom.compareTo(a.nom);
    });
    return resultat;
  }

  /// Supprime une sauvegarde du téléphone. Sans erreur si elle n'existe déjà plus.
  Future<void> supprimer(SauvegardeLocale sauvegarde) async {
    try {
      if (await sauvegarde.fichier.exists()) await sauvegarde.fichier.delete();
    } on FileSystemException {
      // Un fichier impossible à supprimer reste simplement dans la liste.
    }
  }

  // ---------------------------------------------------------------------------
  // Sauvegarde automatique
  // ---------------------------------------------------------------------------

  /// Date de la dernière sauvegarde (automatique ou manuelle), `null` s'il n'y en a pas.
  /// Les copies de sécurité d'avant une restauration ne comptent pas : elles contiennent d'anciennes données.
  Future<DateTime?> derniereSauvegarde() async {
    for (final SauvegardeLocale s in await lister()) {
      if (s.type != TypeSauvegarde.avantRestauration) return s.date;
    }
    return null;
  }

  /// À appeler à l'ouverture de l'application : fait une sauvegarde automatique si la dernière date d'un jour
  /// ou plus (ou s'il n'y en a aucune). Retourne la sauvegarde faite, `null` si ce n'était pas nécessaire.
  Future<SauvegardeLocale?> sauvegarderAutomatiquementSiBesoin() async {
    final DateTime? derniere = await derniereSauvegarde();
    if (derniere != null && _horloge().difference(derniere) < delaiSauvegardeAutomatique) return null;
    return creer(TypeSauvegarde.auto);
  }

  // ---------------------------------------------------------------------------
  // Contenu des archives
  // ---------------------------------------------------------------------------

  /// L'export JSON complet : les mêmes données que l'archive, sans les photos ni les PDF.
  Future<Uint8List> fabriquerJson() async {
    final _InstantaneBase donnees = await _lireBase();
    return Uint8List.fromList(
      _jsonDonnees(donnees, date: _horloge(), nombreFichiers: (await _fichiersPresents()).length),
    );
  }

  /// Écrit l'export JSON du jour dans le dossier des exports (`crochet-creations-donnees-2026-10-31.json`) ;
  /// un fichier du même nom est remplacé.
  Future<File> ecrireJson() async {
    final DateTime maintenant = _horloge();
    String deux(int n) => n.toString().padLeft(2, '0');
    final String nom = 'crochet-creations-donnees-${maintenant.year}-${deux(maintenant.month)}-${deux(maintenant.day)}.json';
    final File fichier = File('${dossierExports.path}${Platform.pathSeparator}$nom');
    await ecrireAtomiquement(fichier, await fabriquerJson());
    return fichier;
  }

  /// Lit toute la base d'un seul tenant (un instantané cohérent, même si l'application écrit en même temps).
  Future<_InstantaneBase> _lireBase() async {
    final Map<String, List<Map<String, Object?>>> tables = <String, List<Map<String, Object?>>>{};
    await _base.transaction(() async {
      for (final String table in FormatSauvegarde.tables) {
        final List<QueryRow> resultat = await _base.customSelect('SELECT * FROM "$table" ORDER BY id').get();
        tables[table] = resultat.map<Map<String, Object?>>((QueryRow ligne) => ligne.data).toList();
      }
    });
    return _InstantaneBase(tables);
  }

  /// `donnees.json` : le manifeste et toutes les lignes de toutes les tables. [fichiersAbsents] n'est donné que
  /// pour une archive (l'export JSON n'a pas de fichiers).
  List<int> _jsonDonnees(
    _InstantaneBase donnees, {
    required DateTime date,
    required int nombreFichiers,
    List<String>? fichiersAbsents,
  }) {
    final Map<String, Object?> document = <String, Object?>{
      'manifeste': <String, Object?>{
        'application': FormatSauvegarde.application,
        'format': FormatSauvegarde.version,
        'versionSchema': AppDatabase.versionSchema,
        'versionApplication': AppConstants.version,
        'creeLe': date.toIso8601String(),
        'nombreFichiers': nombreFichiers,
        'lignes': <String, int>{
          for (final String table in FormatSauvegarde.tables) table: donnees.tables[table]!.length,
        },
        if (fichiersAbsents != null) 'complete': fichiersAbsents.isEmpty,
        if (fichiersAbsents != null) 'fichiersAbsents': fichiersAbsents,
      },
      'tables': donnees.tables,
    };
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(document));
  }

  /// Les photos et PDF présents sur le téléphone (les fichiers provisoires `.tmp` sont ignorés), dossier par dossier.
  Future<List<_FichierLocal>> _fichiersPresents() async {
    final List<_FichierLocal> resultat = <_FichierLocal>[];
    for (final MapEntry<String, Directory> dossier in _dossiers.entries) {
      if (!await dossier.value.exists()) continue;
      final List<_FichierLocal> dansLeDossier = <_FichierLocal>[];
      await for (final FileSystemEntity entite in dossier.value.list()) {
        if (entite is! File) continue;
        final String nom = entite.uri.pathSegments.last;
        if (nom.endsWith('.tmp')) continue;
        dansLeDossier.add(_FichierLocal(dossier: dossier.key, nom: nom, fichier: entite));
      }
      dansLeDossier.sort((_FichierLocal a, _FichierLocal b) => a.nom.compareTo(b.nom));
      resultat.addAll(dansLeDossier);
    }
    return resultat;
  }

  /// Taille et empreinte SHA-256 d'un fichier, lues en flux (le fichier n'est jamais entièrement en mémoire).
  Future<({int octets, String sha256})> _empreinte(File fichier) async {
    int octets = 0;
    final Stream<List<int>> flux = fichier.openRead().map((List<int> morceau) {
      octets += morceau.length;
      return morceau;
    });
    final String empreinte = (await sha256.bind(flux).first).toString();
    return (octets: octets, sha256: empreinte);
  }

  /// Relit l'archive qu'on vient d'écrire : elle doit s'ouvrir, contenir `donnees.json`, `fichiers.json` et
  /// exactement les fichiers annoncés, avec les bonnes tailles. (Les empreintes sont contrôlées à la restauration.)
  Future<void> _verifierArchiveEcrite(File archive, List<EmpreinteFichier> attendus) async {
    const DonneeInvalide echec = DonneeInvalide(
      'La sauvegarde écrite n’a pas pu être vérifiée (un fichier a peut-être changé pendant la copie) : '
      'elle a été abandonnée. Recommencez.',
    );
    final InputFileStream flux = InputFileStream(archive.path);
    try {
      final Archive contenu = ZipDecoder().decodeStream(flux);
      final Map<String, int> tailles = <String, int>{
        for (final ArchiveFile entree in contenu)
          if (entree.isFile) entree.name: entree.size,
      };
      if (!tailles.containsKey(FormatSauvegarde.fichierDonnees) ||
          !tailles.containsKey(FormatSauvegarde.fichierListe) ||
          tailles.length != attendus.length + 2) {
        throw echec;
      }
      for (final EmpreinteFichier attendu in attendus) {
        if (tailles['${FormatSauvegarde.prefixeFichiers}${attendu.chemin}'] != attendu.octets) throw echec;
      }
    } on ErreurMetier {
      rethrow;
    } catch (_) {
      throw echec;
    } finally {
      await flux.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Place libre
  // ---------------------------------------------------------------------------

  /// Vérifie qu'il y a la place d'écrire [necessaire] octets (plus une marge), si on sait la mesurer.
  Future<void> _verifierPlace(int necessaire, String action) async {
    final int? libre = await _espaceLibre.octetsLibres(dossierSauvegardes);
    if (libre == null) return;
    final int besoin = necessaire + margeEspaceLibre;
    if (libre >= besoin) return;
    throw DonneeInvalide(
      'Il n’y a pas assez de place sur le téléphone pour $action : il faut environ ${_enMegaoctets(besoin)} '
      'et il en reste ${_enMegaoctets(libre, arrondiSuperieur: false)}. Libérez de la place (supprimez '
      'd’anciennes sauvegardes de la liste, des photos ou des applications inutiles), puis recommencez.',
    );
  }

  String _enMegaoctets(int octets, {bool arrondiSuperieur = true}) {
    final double mo = octets / (1024 * 1024);
    return '${(arrondiSuperieur ? mo.ceil() : mo.floor())} Mo';
  }

  /// Le système a refusé d'écrire parce qu'il n'y a plus de place (ENOSPC).
  bool _disqueRempli(Object erreur) {
    if (erreur is! FileSystemException) return false;
    final OSError? os = erreur.osError;
    return os != null && (os.errorCode == 28 || os.message.toLowerCase().contains('no space'));
  }

  // ---------------------------------------------------------------------------
  // Restauration
  // ---------------------------------------------------------------------------

  /// Vérifie que [archive] est bien une sauvegarde de cette application et lit son manifeste, sans rien modifier.
  /// À appeler avant de demander confirmation : l'erreur (« ce n'est pas une sauvegarde »...) vient tout de suite.
  Future<ManifesteSauvegarde> examiner(File archive) async {
    final _Contenu contenu = await _lireArchive(archive);
    try {
      return contenu.manifeste;
    } finally {
      await contenu.fermer();
    }
  }

  /// Remplace **toutes** les données (base, photos, PDF) par celles de la sauvegarde [archive].
  ///
  /// Dans l'ordre : lecture de l'archive → extraction des fichiers dans un dossier provisoire, en **vérifiant
  /// la taille et l'empreinte SHA-256 de chacun** (rien n'est touché si l'archive est abîmée) → copie de sécurité
  /// des données actuelles → remplacement de la base en une seule transaction (tout ou rien) → mise en place
  /// des fichiers.
  Future<ResultatRestauration> restaurer(File archive, {SurProgression? surProgression}) {
    return _enSerie(() => _restaurer(archive, surProgression));
  }

  Future<ResultatRestauration> _restaurer(File archive, SurProgression? surProgression) async {
    final _Contenu contenu = await _lireArchive(archive);
    try {
      // 1. Les fichiers, écrits à côté et contrôlés un par un.
      final int octetsFichiers = contenu.fichiers.fold<int>(0, (int somme, _FichierArchive f) => somme + f.octets);
      await _verifierPlace(octetsFichiers, 'restaurer cette sauvegarde');
      try {
        await _extraireFichiers(contenu, surProgression);
      } on ErreurMetier {
        await _abandonnerPreparation();
        rethrow;
      } catch (erreur, pile) {
        debugPrint('Extraction impossible : $erreur\n$pile');
        await _abandonnerPreparation();
        if (_disqueRempli(erreur)) {
          throw const DonneeInvalide(
            'Le téléphone est plein : la restauration a été abandonnée, rien n’a été modifié. '
            'Libérez de la place, puis recommencez.',
          );
        }
        throw const DonneeInvalide(_messageIncompatible);
      }

      // 2. La copie de sécurité de ce qui existe (l'archive n'est plus utile : tout est lu, rien n'en dépend).
      try {
        await _creer(TypeSauvegarde.avantRestauration, (ProgressionSauvegarde p) {
          // L'avancement de la copie de sécurité est ramené à une seule étape de la restauration.
          final double global = ((p.numeroEtape - 1) + (p.fraction ?? 0)) / p.nombreEtapes;
          surProgression?.call(ProgressionSauvegarde(EtapeSauvegarde.copieDeSecurite, (global * 1000).round(), 1000));
        });
      } catch (_) {
        await _abandonnerPreparation();
        rethrow;
      }

      // 3. La base, puis les fichiers.
      surProgression?.call(const ProgressionSauvegarde(EtapeSauvegarde.remplacement, 0, 1));
      try {
        await _remplacerDonnees(contenu);
      } on ErreurMetier {
        await _abandonnerPreparation();
        rethrow;
      } catch (erreur, pile) {
        debugPrint('Restauration impossible : $erreur\n$pile');
        await _abandonnerPreparation();
        throw const DonneeInvalide(_messageIncompatible);
      }

      // Les écrans ouverts relisent la base : Drift n'a pas vu passer ces écritures, on le prévient.
      _base.markTablesUpdated(_base.allTables);

      await _installerFichiers();
      surProgression?.call(const ProgressionSauvegarde(EtapeSauvegarde.remplacement, 1, 1));

      int lignes = 0;
      for (final List<Map<String, Object?>> t in contenu.tables.values) {
        lignes += t.length;
      }
      return ResultatRestauration(
        lignes: lignes,
        fichiers: contenu.fichiers.length,
        fichiersAbsents: contenu.manifeste.fichiersAbsents,
      );
    } finally {
      await contenu.fermer();
    }
  }

  /// Ouvre l'archive et vérifie tout ce qu'on peut vérifier sans toucher à la base ni extraire un fichier.
  Future<_Contenu> _lireArchive(File fichier) async {
    final InputFileStream flux;
    final Archive archive;
    if (!await fichier.exists()) throw const DonneeInvalide(_messageIntrouvable);
    try {
      flux = InputFileStream(fichier.path);
    } catch (_) {
      throw const DonneeInvalide(_messageIntrouvable);
    }
    try {
      archive = ZipDecoder().decodeStream(flux);
    } catch (_) {
      await flux.close();
      throw const DonneeInvalide(_messageNonReconnu);
    }

    try {
      return _lireContenu(archive, flux);
    } catch (_) {
      await flux.close();
      rethrow;
    }
  }

  _Contenu _lireContenu(Archive archive, InputFileStream flux) {
    final ArchiveFile? entreeDonnees = archive.find(FormatSauvegarde.fichierDonnees);
    if (entreeDonnees == null) throw const DonneeInvalide(_messageNonReconnu);

    final Object? document = _decoderJson(entreeDonnees);
    if (document is! Map) throw const DonneeInvalide(_messageNonReconnu);

    final Object? manifeste = document['manifeste'];
    if (manifeste is! Map || manifeste['application'] != FormatSauvegarde.application) {
      throw const DonneeInvalide(_messageNonReconnu);
    }
    final Object? format = manifeste['format'];
    final Object? schema = manifeste['versionSchema'];
    if (format is! int || schema is! int) throw const DonneeInvalide(_messageNonReconnu);
    // Une sauvegarde plus ancienne est acceptée (ses colonnes sont vérifiées à l'écriture) ; plus récente, non.
    if (format > FormatSauvegarde.version || schema > AppDatabase.versionSchema) {
      throw const DonneeInvalide(_messageTropRecente);
    }

    final Object? tablesBrutes = document['tables'];
    if (tablesBrutes is! Map) throw const DonneeInvalide(_messageNonReconnu);
    final Map<String, List<Map<String, Object?>>> tables = <String, List<Map<String, Object?>>>{};
    final Map<String, int> comptes = <String, int>{};
    for (final String table in FormatSauvegarde.tables) {
      final Object? brutes = tablesBrutes[table];
      final List<Map<String, Object?>> lignes = <Map<String, Object?>>[];
      if (brutes != null) {
        if (brutes is! List) throw const DonneeInvalide(_messageIncompatible);
        for (final Object? brute in brutes) {
          lignes.add(_ligneValide(brute));
        }
      }
      tables[table] = lignes;
      comptes[table] = lignes.length;
    }

    // Format 2 : la liste des fichiers, avec la taille et l'empreinte de chacun.
    final Map<String, EmpreinteFichier>? annonces = format >= 2 ? _lireListeFichiers(archive) : null;

    final List<_FichierArchive> fichiers = <_FichierArchive>[];
    final Set<String> chemins = <String>{};
    for (final ArchiveFile entree in archive) {
      if (!entree.isFile || entree.name == FormatSauvegarde.fichierDonnees) continue;
      if (!entree.name.startsWith(FormatSauvegarde.prefixeFichiers)) continue;
      // fichiers/<dossier>/<nom> : rien d'autre. Un nom qui remonte dans l'arborescence est refusé.
      final String chemin = entree.name.substring(FormatSauvegarde.prefixeFichiers.length);
      final ({String dossier, String nom})? lu = _lireChemin(chemin);
      if (lu == null || !chemins.add(chemin)) throw const DonneeInvalide(_messageIncompatible);
      final EmpreinteFichier? annonce = annonces?[chemin];
      if (annonces != null && (annonce == null || annonce.octets != entree.size)) {
        throw const DonneeInvalide(_messageIncompatible);
      }
      fichiers.add(
        _FichierArchive(dossier: lu.dossier, nom: lu.nom, entree: entree, octets: entree.size, empreinte: annonce?.sha256),
      );
    }
    // Tout ce que la liste annonce doit être dans l'archive.
    if (annonces != null && annonces.keys.any((String chemin) => !chemins.contains(chemin))) {
      throw const DonneeInvalide(_messageIncompatible);
    }

    // Les photos citées par les données mais absentes de l'archive : vrai pour toute archive, même ancienne.
    final List<String> absents = FormatSauvegarde.fichiersIrremplacablesCites(tables).difference(chemins).toList()
      ..sort();

    final Object? creeLe = manifeste['creeLe'];
    final Object? version = manifeste['versionApplication'];
    return _Contenu(
      manifeste: ManifesteSauvegarde(
        creeLe: creeLe is String ? DateTime.tryParse(creeLe) : null,
        versionApplication: version is String ? version : '?',
        nombreFichiers: fichiers.length,
        lignes: comptes,
        format: format,
        fichiersAbsents: absents,
      ),
      tables: tables,
      fichiers: fichiers,
      flux: flux,
      // Une sauvegarde du schéma 1 ou 2 n'a pas de catégories : les produits y portent les clés des cinq de départ.
      sansCategories: tablesBrutes['categories_produit'] == null,
      // Une sauvegarde d'avant le schéma 4 n'a pas de lieux de vente : ses ventes sont « Non renseigné ».
      sansLieux: tablesBrutes['lieux_vente'] == null,
      // Une sauvegarde d'avant le schéma 5 n'a pas de bloc-notes : on crée les catégories de notes de départ.
      sansCategoriesNote: tablesBrutes['categories_note'] == null,
    );
  }

  /// `fichiers.json` : « dossier/nom » → taille et empreinte annoncées.
  Map<String, EmpreinteFichier> _lireListeFichiers(Archive archive) {
    final ArchiveFile? entree = archive.find(FormatSauvegarde.fichierListe);
    if (entree == null) throw const DonneeInvalide(_messageIncompatible);
    final Object? document = _decoderJson(entree);
    final Object? liste = document is Map ? document['fichiers'] : null;
    if (liste is! List) throw const DonneeInvalide(_messageIncompatible);

    final RegExp modeleEmpreinte = RegExp(r'^[0-9a-f]{64}$');
    final Map<String, EmpreinteFichier> annonces = <String, EmpreinteFichier>{};
    for (final Object? brut in liste) {
      if (brut is! Map) throw const DonneeInvalide(_messageIncompatible);
      final Object? chemin = brut['chemin'];
      final Object? octets = brut['octets'];
      final Object? empreinte = brut['sha256'];
      if (chemin is! String ||
          octets is! int ||
          octets < 0 ||
          empreinte is! String ||
          !modeleEmpreinte.hasMatch(empreinte) ||
          _lireChemin(chemin) == null ||
          annonces.containsKey(chemin)) {
        throw const DonneeInvalide(_messageIncompatible);
      }
      annonces[chemin] = EmpreinteFichier(chemin: chemin, octets: octets, sha256: empreinte);
    }
    return annonces;
  }

  /// `photos_produits/photo_1.jpg` → dossier et nom ; `null` si ce n'est pas un chemin que l'application range
  /// (dossier inconnu, chemin qui remonte, séparateur étranger...).
  ({String dossier, String nom})? _lireChemin(String chemin) {
    final List<String> morceaux = chemin.split('/');
    final bool valide =
        morceaux.length == 2 &&
        _dossiers.containsKey(morceaux[0]) &&
        morceaux[1].isNotEmpty &&
        morceaux[1] != '.' &&
        morceaux[1] != '..' &&
        !morceaux[1].contains('\\') &&
        !morceaux[1].contains(':');
    return valide ? (dossier: morceaux[0], nom: morceaux[1]) : null;
  }

  Object? _decoderJson(ArchiveFile entree) {
    try {
      return jsonDecode(utf8.decode(entree.content));
    } catch (_) {
      throw const DonneeInvalide(_messageIncompatible);
    }
  }

  /// Une ligne de table : des colonnes dont les valeurs sont des nombres, du texte ou vides.
  Map<String, Object?> _ligneValide(Object? brute) {
    if (brute is! Map) throw const DonneeInvalide(_messageIncompatible);
    final Map<String, Object?> ligne = <String, Object?>{};
    for (final MapEntry<Object?, Object?> colonne in brute.entries) {
      final Object? cle = colonne.key;
      final Object? valeur = colonne.value;
      if (cle is! String) throw const DonneeInvalide(_messageIncompatible);
      if (valeur != null && valeur is! int && valeur is! double && valeur is! String) {
        throw const DonneeInvalide(_messageIncompatible);
      }
      ligne[cle] = valeur;
    }
    return ligne;
  }

  /// Vide toutes les tables puis les remplit avec l'archive, en une seule transaction : en cas de problème
  /// (colonne inconnue, ligne refusée par une contrainte de la base...), elle est annulée et rien n'a changé.
  Future<void> _remplacerDonnees(_Contenu contenu) async {
    await _base.transaction(() async {
      // Les colonnes réellement présentes : celles de l'archive sont vérifiées avant d'écrire du SQL.
      final Map<String, Set<String>> colonnes = <String, Set<String>>{};
      for (final String table in FormatSauvegarde.tables) {
        final List<QueryRow> infos = await _base.customSelect('PRAGMA table_info("$table")').get();
        colonnes[table] = infos.map((QueryRow ligne) => ligne.read<String>('name')).toSet();
      }

      for (final String table in FormatSauvegarde.tables.reversed) {
        await _base.customStatement('DELETE FROM "$table"');
      }

      for (final String table in FormatSauvegarde.tables) {
        for (final Map<String, Object?> ligne in contenu.tables[table]!) {
          final List<String> noms = ligne.keys.toList();
          if (noms.isEmpty) continue;
          for (final String nom in noms) {
            if (!colonnes[table]!.contains(nom)) throw const DonneeInvalide(_messageIncompatible);
          }
          final String colonnesSql = noms.map((String n) => '"$n"').join(', ');
          final String valeursSql = List<String>.filled(noms.length, '?').join(', ');
          await _base.customStatement(
            'INSERT INTO "$table" ($colonnesSql) VALUES ($valeursSql)',
            noms.map((String n) => ligne[n]).toList(),
          );
        }
      }

      // La ligne unique des réglages doit toujours exister, même si l'archive n'en contenait pas.
      await _base.customStatement('INSERT OR IGNORE INTO parametres_entreprise (id) VALUES (1)');

      // Une sauvegarde faite avant les catégories modifiables : on recrée les cinq catégories de départ.
      if (contenu.sansCategories) await _base.insererCategoriesDeDepart();

      // Une sauvegarde faite avant les lieux de vente : on crée les lieux de départ (les ventes restent « Non renseigné »).
      if (contenu.sansLieux) await _base.insererLieuxDeDepart();

      // Une sauvegarde faite avant le bloc-notes : on crée les deux catégories de notes de départ (il n'y a pas de notes).
      if (contenu.sansCategoriesNote) await _base.insererCategoriesNoteDeDepart();
    });
  }

  // --- Fichiers : écrits à côté, puis échangés d'un coup avec les dossiers actuels ------------------------

  Directory _provisoire(Directory cible) => Directory('${cible.path}.restauration');
  Directory _ancien(Directory cible) => Directory('${cible.path}.ancien');

  /// Écrit chaque fichier de l'archive dans le dossier provisoire, puis relit ce qui a été écrit : la taille
  /// (et, pour une archive du format 2, l'empreinte SHA-256) doit être celle annoncée, sinon l'archive est abîmée.
  Future<void> _extraireFichiers(_Contenu contenu, SurProgression? surProgression) async {
    for (final MapEntry<String, Directory> dossier in _dossiers.entries) {
      final Directory provisoire = _provisoire(dossier.value);
      if (await provisoire.exists()) await provisoire.delete(recursive: true);
      await provisoire.create(recursive: true);
    }
    final int total = contenu.fichiers.length;
    surProgression?.call(ProgressionSauvegarde(EtapeSauvegarde.controleFichiers, 0, total));
    for (int i = 0; i < total; i++) {
      final _FichierArchive f = contenu.fichiers[i];
      final File cible = File('${_provisoire(_dossiers[f.dossier]!).path}${Platform.pathSeparator}${f.nom}');
      final OutputFileStream sortie = OutputFileStream(cible.path);
      try {
        f.entree.writeContent(sortie);
      } finally {
        await sortie.close();
      }
      final ({int octets, String sha256}) lu = await _empreinte(cible);
      if (lu.octets != f.octets || (f.empreinte != null && lu.sha256 != f.empreinte)) {
        throw DonneeInvalide(
          'Cette sauvegarde est abîmée : le fichier « ${f.nom} » ne correspond pas à son empreinte. '
          'Rien n’a été modifié.',
        );
      }
      surProgression?.call(ProgressionSauvegarde(EtapeSauvegarde.controleFichiers, i + 1, total));
    }
  }

  Future<void> _abandonnerPreparation() async {
    for (final Directory cible in _dossiers.values) {
      final Directory provisoire = _provisoire(cible);
      try {
        if (await provisoire.exists()) await provisoire.delete(recursive: true);
      } on FileSystemException {
        // Un dossier provisoire oublié est écrasé à la prochaine restauration.
      }
    }
  }

  Future<void> _installerFichiers() async {
    for (final Directory cible in _dossiers.values) {
      final Directory provisoire = _provisoire(cible);
      final Directory ancien = _ancien(cible);
      if (await ancien.exists()) await ancien.delete(recursive: true);
      final bool avaitUnDossier = await cible.exists();
      if (avaitUnDossier) await cible.rename(ancien.path);
      try {
        await provisoire.rename(cible.path);
      } catch (_) {
        // On remet les anciens fichiers en place avant de signaler le problème.
        if (avaitUnDossier && await ancien.exists()) await ancien.rename(cible.path);
        rethrow;
      }
      try {
        if (await ancien.exists()) await ancien.delete(recursive: true);
      } on FileSystemException {
        // Les anciens fichiers restent dans un dossier à part : sans conséquence.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Noms des fichiers de sauvegarde
  // ---------------------------------------------------------------------------

  static final RegExp _modeleNom = RegExp(
    r'^crochet-creations-(auto|manuelle|avant-restauration)-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})(?:-\d+)?(-incomplete)?\.zip$',
  );

  /// `crochet-creations-manuelle-2026-10-31-134912.zip` → type et date ; `null` si ce n'est pas une sauvegarde.
  /// Un nom qui finit par `-incomplete` est une sauvegarde incomplète.
  ({TypeSauvegarde type, DateTime date, bool complete})? _lireNom(String nom) {
    final RegExpMatch? m = _modeleNom.firstMatch(nom);
    if (m == null) return null;
    final TypeSauvegarde type = TypeSauvegarde.values.firstWhere((TypeSauvegarde t) => t.code == m.group(1));
    final DateTime date = DateTime(
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
      int.parse(m.group(7)!),
    );
    return (type: type, date: date, complete: m.group(8) == null);
  }

  /// `crochet-creations-manuelle-2026-10-31-134912.zip` ; `-2` si deux sauvegardes tombent dans la même seconde ;
  /// `-incomplete` avant `.zip` quand des photos manquaient.
  String _nomFichier(TypeSauvegarde type, DateTime date, int numero, bool complete) {
    String deux(int n) => n.toString().padLeft(2, '0');
    final String horodatage =
        '${date.year.toString().padLeft(4, '0')}-${deux(date.month)}-${deux(date.day)}-'
        '${deux(date.hour)}${deux(date.minute)}${deux(date.second)}';
    return 'crochet-creations-${type.code}-$horodatage${numero > 1 ? '-$numero' : ''}${complete ? '' : '-incomplete'}.zip';
  }

  /// Un nom qui n'existe pas encore (deux sauvegardes dans la même seconde reçoivent « -2 », « -3 »...).
  Future<File> _fichierLibre(TypeSauvegarde type, DateTime date, {required bool complete}) async {
    File fichier(int numero, bool entiere) =>
        File('${dossierSauvegardes.path}${Platform.pathSeparator}${_nomFichier(type, date, numero, entiere)}');
    for (int numero = 1; ; numero++) {
      if (!await fichier(numero, true).exists() && !await fichier(numero, false).exists()) {
        return fichier(numero, complete);
      }
    }
  }

  /// Efface les fichiers provisoires laissés par une sauvegarde interrompue (application fermée en route).
  Future<void> _effacerProvisoires() async {
    await for (final FileSystemEntity entite in dossierSauvegardes.list()) {
      if (entite is File && entite.path.endsWith('.zip.tmp')) await _effacer(entite);
    }
  }

  Future<void> _effacer(File fichier) async {
    try {
      if (await fichier.exists()) await fichier.delete();
    } on FileSystemException {
      // Un fichier provisoire impossible à effacer sera retenté à la prochaine sauvegarde.
    }
  }

  /// Supprime les plus anciennes sauvegardes de ce type au-delà du nombre à conserver.
  Future<void> _purger(TypeSauvegarde type) async {
    final int? limite = switch (type) {
      TypeSauvegarde.auto => sauvegardesAutomatiquesConservees,
      TypeSauvegarde.avantRestauration => copiesDeSecuriteConservees,
      TypeSauvegarde.manuelle => null,
    };
    if (limite == null) return;
    final List<SauvegardeLocale> memeType = (await lister())
        .where((SauvegardeLocale s) => s.type == type)
        .toList();
    for (final SauvegardeLocale ancienne in memeType.skip(limite)) {
      await supprimer(ancienne);
    }
  }
}

/// Toutes les lignes de toutes les tables, lues d'un seul tenant.
class _InstantaneBase {
  const _InstantaneBase(this.tables);

  final Map<String, List<Map<String, Object?>>> tables;
}

/// Une photo ou un PDF du téléphone.
class _FichierLocal {
  const _FichierLocal({required this.dossier, required this.nom, required this.fichier});

  final String dossier;
  final String nom;
  final File fichier;

  /// `dossier/nom`, comme dans `fichiers.json`.
  String get chemin => '$dossier/$nom';
}

/// Une archive lue et vérifiée, prête à être restaurée. Le fichier reste ouvert jusqu'à [fermer].
class _Contenu {
  const _Contenu({
    required this.manifeste,
    required this.tables,
    required this.fichiers,
    required this.flux,
    required this.sansCategories,
    required this.sansLieux,
    required this.sansCategoriesNote,
  });

  final ManifesteSauvegarde manifeste;
  final Map<String, List<Map<String, Object?>>> tables;
  final List<_FichierArchive> fichiers;
  final InputFileStream flux;

  /// L'archive ne contient pas la table des catégories (sauvegarde d'un schéma antérieur au 3).
  final bool sansCategories;

  /// L'archive ne contient pas la table des lieux de vente (sauvegarde d'un schéma antérieur au 4).
  final bool sansLieux;

  /// L'archive ne contient pas la table des catégories de notes (sauvegarde d'un schéma antérieur au 5).
  final bool sansCategoriesNote;

  Future<void> fermer() => flux.close();
}

class _FichierArchive {
  const _FichierArchive({
    required this.dossier,
    required this.nom,
    required this.entree,
    required this.octets,
    required this.empreinte,
  });

  final String dossier;
  final String nom;
  final ArchiveFile entree;

  /// Taille annoncée (celle de l'entrée de l'archive).
  final int octets;

  /// SHA-256 annoncé dans `fichiers.json` ; `null` pour une archive du format 1.
  final String? empreinte;
}
