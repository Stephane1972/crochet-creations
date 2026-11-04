import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/erreurs.dart';
import '../database/app_database.dart';
import 'format_sauvegarde.dart';

/// Ce qu'une restauration a remis en place.
class ResultatRestauration {
  const ResultatRestauration({required this.lignes, required this.fichiers});

  /// Lignes de la base (produits, clients, ventes...) et fichiers (photos, PDF).
  final int lignes;
  final int fichiers;
}

/// Sauvegarde et restauration des données (étape 11).
///
/// - **Sauvegarder** : une archive `.zip` avec toute la base et les fichiers (voir [FormatSauvegarde]), rangée
///   dans le dossier des sauvegardes de l'application.
/// - **Sauvegarde automatique** : à l'ouverture de l'application, si la dernière date de plus d'un jour ;
///   les 7 dernières sont conservées.
/// - **Restaurer** : remplace **tout** (données, photos, PDF) par le contenu de l'archive, après une copie de
///   sécurité de ce qui existait. Si la restauration échoue, rien n'a été modifié.
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
  }) : _base = base,
       _dossiers = <String, Directory>{
         FormatSauvegarde.dossierPhotos: dossierPhotos,
         FormatSauvegarde.dossierFactures: dossierFactures,
         FormatSauvegarde.dossierDevis: dossierDevis,
       },
       _horloge = horloge ?? DateTime.now;

  /// Nombre de sauvegardes automatiques conservées.
  static const int sauvegardesAutomatiquesConservees = 7;

  /// Nombre de copies de sécurité (avant restauration) conservées.
  static const int copiesDeSecuriteConservees = 3;

  /// Une sauvegarde automatique est faite si la dernière date de cette durée ou plus.
  static const Duration delaiSauvegardeAutomatique = Duration(days: 1);

  final AppDatabase _base;
  final Map<String, Directory> _dossiers;
  final DateTime Function() _horloge;

  /// Où sont rangées les sauvegardes (créé à la première).
  final Directory dossierSauvegardes;

  /// Où sont écrits les fichiers d'export (CSV, JSON) avant d'être partagés.
  final Directory dossierExports;

  static const String _messageNonReconnu = 'Ce fichier n’est pas une sauvegarde de Crochet & Créations.';
  static const String _messageTropRecente =
      'Cette sauvegarde a été faite avec une version plus récente de l’application. '
      'Mettez l’application à jour avant de la restaurer.';
  static const String _messageIncompatible =
      'Cette sauvegarde est abîmée ou incompatible : rien n’a été modifié.';

  // ---------------------------------------------------------------------------
  // Créer, lister, supprimer
  // ---------------------------------------------------------------------------

  /// Fabrique une sauvegarde du moment et la range dans le dossier des sauvegardes.
  Future<SauvegardeLocale> creer(TypeSauvegarde type) async {
    final DateTime maintenant = _horloge();
    final Uint8List octets = await fabriquerArchive();
    final File fichier = await _fichierLibre(type, maintenant);
    await ecrireAtomiquement(fichier, octets);
    await _purger(type);
    return SauvegardeLocale(fichier: fichier, type: type, date: maintenant, octets: octets.length);
  }

  /// Les sauvegardes conservées sur le téléphone, de la plus récente à la plus ancienne.
  Future<List<SauvegardeLocale>> lister() async {
    if (!await dossierSauvegardes.exists()) return <SauvegardeLocale>[];
    final List<SauvegardeLocale> resultat = <SauvegardeLocale>[];
    await for (final FileSystemEntity entite in dossierSauvegardes.list()) {
      if (entite is! File) continue;
      final String nom = entite.uri.pathSegments.last;
      final ({TypeSauvegarde type, DateTime date})? lu = _lireNom(nom);
      if (lu == null) continue; // fichier provisoire ou étranger : ignoré
      resultat.add(
        SauvegardeLocale(fichier: entite, type: lu.type, date: lu.date, octets: await entite.length()),
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

  /// L'archive .zip complète : `donnees.json` + photos et PDF.
  Future<Uint8List> fabriquerArchive() async {
    final Archive archive = Archive();
    final List<ArchiveFile> fichiers = await _lireFichiers();
    final List<int> json = await _fabriquerJson(nombreFichiers: fichiers.length);
    archive.add(ArchiveFile.bytes(FormatSauvegarde.fichierDonnees, json));
    fichiers.forEach(archive.add);
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// L'export JSON complet : les mêmes données que l'archive, sans les photos ni les PDF.
  Future<Uint8List> fabriquerJson() async {
    return Uint8List.fromList(await _fabriquerJson(nombreFichiers: await _compterFichiers()));
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
  Future<List<int>> _fabriquerJson({required int nombreFichiers}) async {
    final Map<String, Object?> tables = <String, Object?>{};
    final Map<String, int> lignes = <String, int>{};
    await _base.transaction(() async {
      for (final String table in FormatSauvegarde.tables) {
        final List<QueryRow> resultat = await _base.customSelect('SELECT * FROM "$table" ORDER BY id').get();
        tables[table] = resultat.map((QueryRow ligne) => ligne.data).toList();
        lignes[table] = resultat.length;
      }
    });
    final Map<String, Object?> document = <String, Object?>{
      'manifeste': <String, Object?>{
        'application': FormatSauvegarde.application,
        'format': FormatSauvegarde.version,
        'versionSchema': AppDatabase.versionSchema,
        'versionApplication': AppConstants.version,
        'creeLe': _horloge().toIso8601String(),
        'nombreFichiers': nombreFichiers,
        'lignes': lignes,
      },
      'tables': tables,
    };
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(document));
  }

  /// Les photos et PDF présents sur le téléphone (les fichiers provisoires `.tmp` sont ignorés), par dossier.
  Future<Map<String, List<File>>> _fichiersPresents() async {
    final Map<String, List<File>> resultat = <String, List<File>>{};
    for (final MapEntry<String, Directory> dossier in _dossiers.entries) {
      final List<File> presents = <File>[];
      if (await dossier.value.exists()) {
        await for (final FileSystemEntity entite in dossier.value.list()) {
          if (entite is File && !entite.path.endsWith('.tmp')) presents.add(entite);
        }
      }
      presents.sort((File a, File b) => a.path.compareTo(b.path));
      resultat[dossier.key] = presents;
    }
    return resultat;
  }

  Future<int> _compterFichiers() async {
    int total = 0;
    for (final List<File> liste in (await _fichiersPresents()).values) {
      total += liste.length;
    }
    return total;
  }

  /// Photos et PDF du téléphone, rangés dans `fichiers/<dossier>/<nom>`.
  Future<List<ArchiveFile>> _lireFichiers() async {
    final List<ArchiveFile> fichiers = <ArchiveFile>[];
    for (final MapEntry<String, List<File>> dossier in (await _fichiersPresents()).entries) {
      for (final File f in dossier.value) {
        final String nom = f.uri.pathSegments.last;
        fichiers.add(
          ArchiveFile.bytes('${FormatSauvegarde.prefixeFichiers}${dossier.key}/$nom', await f.readAsBytes()),
        );
      }
    }
    return fichiers;
  }

  // ---------------------------------------------------------------------------
  // Restauration
  // ---------------------------------------------------------------------------

  /// Vérifie qu'[octets] est bien une sauvegarde de cette application et lit son manifeste, sans rien modifier.
  /// À appeler avant de demander confirmation : l'erreur (« ce n'est pas une sauvegarde »...) vient tout de suite.
  ManifesteSauvegarde examiner(Uint8List octets) => _lireArchive(octets).manifeste;

  /// Remplace **toutes** les données (base, photos, PDF) par celles de la sauvegarde [octets].
  ///
  /// Dans l'ordre : lecture et vérification de l'archive (rien n'est touché si elle est mauvaise) → copie de
  /// sécurité des données actuelles → préparation des fichiers dans un dossier provisoire → remplacement de la
  /// base en une seule transaction (tout ou rien) → mise en place des fichiers.
  Future<ResultatRestauration> restaurer(Uint8List octets) async {
    final _Contenu contenu = _lireArchive(octets);

    await creer(TypeSauvegarde.avantRestauration);
    await _preparerFichiers(contenu);
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

    int lignes = 0;
    for (final List<Map<String, Object?>> t in contenu.tables.values) {
      lignes += t.length;
    }
    return ResultatRestauration(lignes: lignes, fichiers: contenu.fichiers.length);
  }

  /// Ouvre l'archive et vérifie tout ce qu'on peut vérifier sans toucher à la base.
  _Contenu _lireArchive(Uint8List octets) {
    final Archive archive = _decoderZip(octets);
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

    final List<_FichierArchive> fichiers = <_FichierArchive>[];
    for (final ArchiveFile entree in archive) {
      if (!entree.isFile || entree.name == FormatSauvegarde.fichierDonnees) continue;
      if (!entree.name.startsWith(FormatSauvegarde.prefixeFichiers)) continue;
      // fichiers/<dossier>/<nom> : rien d'autre. Un nom qui remonte dans l'arborescence est refusé.
      final List<String> morceaux = entree.name.split('/');
      final bool valide =
          morceaux.length == 3 &&
          _dossiers.containsKey(morceaux[1]) &&
          morceaux[2].isNotEmpty &&
          morceaux[2] != '.' &&
          morceaux[2] != '..' &&
          !morceaux[2].contains('\\') &&
          !morceaux[2].contains(':');
      if (!valide) throw const DonneeInvalide(_messageIncompatible);
      fichiers.add(_FichierArchive(dossier: morceaux[1], nom: morceaux[2], entree: entree));
    }

    final Object? creeLe = manifeste['creeLe'];
    final Object? version = manifeste['versionApplication'];
    return _Contenu(
      manifeste: ManifesteSauvegarde(
        creeLe: creeLe is String ? DateTime.tryParse(creeLe) : null,
        versionApplication: version is String ? version : '?',
        nombreFichiers: fichiers.length,
        lignes: comptes,
      ),
      tables: tables,
      fichiers: fichiers,
      // Une sauvegarde du schéma 1 ou 2 n'a pas de catégories : les produits y portent les clés des cinq de départ.
      sansCategories: tablesBrutes['categories_produit'] == null,
    );
  }

  Archive _decoderZip(Uint8List octets) {
    try {
      return ZipDecoder().decodeBytes(octets);
    } catch (_) {
      throw const DonneeInvalide(_messageNonReconnu);
    }
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
    });
  }

  // --- Fichiers : écrits à côté, puis échangés d'un coup avec les dossiers actuels ------------------------

  Directory _provisoire(Directory cible) => Directory('${cible.path}.restauration');
  Directory _ancien(Directory cible) => Directory('${cible.path}.ancien');

  Future<void> _preparerFichiers(_Contenu contenu) async {
    for (final MapEntry<String, Directory> dossier in _dossiers.entries) {
      final Directory provisoire = _provisoire(dossier.value);
      if (await provisoire.exists()) await provisoire.delete(recursive: true);
      await provisoire.create(recursive: true);
    }
    for (final _FichierArchive f in contenu.fichiers) {
      final Directory provisoire = _provisoire(_dossiers[f.dossier]!);
      await File('${provisoire.path}${Platform.pathSeparator}${f.nom}').writeAsBytes(f.entree.content);
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
    r'^crochet-creations-(auto|manuelle|avant-restauration)-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})(?:-\d+)?\.zip$',
  );

  /// `crochet-creations-manuelle-2026-10-31-134912.zip` → type et date ; `null` si ce n'est pas une sauvegarde.
  ({TypeSauvegarde type, DateTime date})? _lireNom(String nom) {
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
    return (type: type, date: date);
  }

  String _nomFichier(TypeSauvegarde type, DateTime date, int numero) {
    String deux(int n) => n.toString().padLeft(2, '0');
    final String horodatage =
        '${date.year.toString().padLeft(4, '0')}-${deux(date.month)}-${deux(date.day)}-'
        '${deux(date.hour)}${deux(date.minute)}${deux(date.second)}';
    return 'crochet-creations-${type.code}-$horodatage${numero > 1 ? '-$numero' : ''}.zip';
  }

  /// Un nom qui n'existe pas encore (deux sauvegardes dans la même seconde reçoivent « -2 », « -3 »...).
  Future<File> _fichierLibre(TypeSauvegarde type, DateTime date) async {
    for (int numero = 1; ; numero++) {
      final File f = File('${dossierSauvegardes.path}${Platform.pathSeparator}${_nomFichier(type, date, numero)}');
      if (!await f.exists()) return f;
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

/// Une archive lue et vérifiée, prête à être restaurée.
class _Contenu {
  const _Contenu({
    required this.manifeste,
    required this.tables,
    required this.fichiers,
    required this.sansCategories,
  });

  final ManifesteSauvegarde manifeste;
  final Map<String, List<Map<String, Object?>>> tables;
  final List<_FichierArchive> fichiers;

  /// L'archive ne contient pas la table des catégories (sauvegarde d'un schéma antérieur au 3).
  final bool sansCategories;
}

class _FichierArchive {
  const _FichierArchive({required this.dossier, required this.nom, required this.entree});

  final String dossier;
  final String nom;
  final ArchiveFile entree;
}
