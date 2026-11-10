import 'dart:io';

/// Contenu et nommage des sauvegardes (archives .zip).
///
/// Une sauvegarde est un fichier `.zip` qui contient :
/// - `donnees.json` : un « manifeste » (application, version du format et du schéma, date, sauvegarde complète
///   ou non) et **toutes les lignes des 20 tables** de la base, telles qu'elles sont enregistrées ;
/// - `fichiers.json` (format 2) : la **liste des fichiers** de l'archive, avec la taille et l'empreinte SHA-256 de
///   chacun, pour vérifier à la restauration que rien n'a été abîmé ;
/// - `fichiers/photos_produits/…`, `fichiers/factures/…`, `fichiers/devis/…`, `fichiers/notes_pieces_jointes/…` : les
///   photos, les PDF et les pièces jointes des notes (photos, vidéos, documents).
///
/// Le même `donnees.json` sert à l'export JSON complet (sans les fichiers).
abstract final class FormatSauvegarde {
  /// Identifiant écrit dans le manifeste : une archive d'une autre application est refusée.
  static const String application = 'crochet-creations';

  /// Version du **format de l'archive**. À augmenter si l'organisation du fichier change.
  ///
  /// - 1 : `donnees.json` + fichiers, archive fabriquée en mémoire ;
  /// - 2 : ajout de `fichiers.json` (taille et SHA-256 de chaque fichier) et, dans le manifeste, `complete`
  ///   et `fichiersAbsents`. Les archives du format 1 se restaurent toujours (sans contrôle des empreintes).
  static const int version = 2;

  static const String fichierDonnees = 'donnees.json';
  static const String fichierListe = 'fichiers.json';
  static const String prefixeFichiers = 'fichiers/';

  /// Noms des dossiers de fichiers, à l'intérieur de `fichiers/` et sur le téléphone.
  static const String dossierPhotos = 'photos_produits';
  static const String dossierFactures = 'factures';
  static const String dossierDevis = 'devis';
  static const String dossierPiecesJointes = 'notes_pieces_jointes';

  static const List<String> dossiersFichiers = <String>[
    dossierPhotos,
    dossierFactures,
    dossierDevis,
    dossierPiecesJointes,
  ];

  /// Les 20 tables, **dans l'ordre où on peut les remplir** : une table vient après celles qu'elle référence
  /// (une vente après son client, une ligne après sa vente...). On les vide dans l'ordre inverse.
  /// Un test vérifie que cette liste est exactement celle de la base : une nouvelle table doit y être ajoutée.
  static const List<String> tables = <String>[
    'parametres_entreprise',
    'numerotation_documents',
    'categories_produit',
    'produits',
    'variantes_produit',
    'photos_produit',
    'clients',
    'cours',
    'lieux_vente',
    'ventes',
    'lignes_vente',
    'paiements',
    'factures',
    'devis',
    'lignes_devis',
    'inscriptions_cours',
    'depenses',
    'categories_note',
    'notes',
    'pieces_jointes_note',
  ];

  /// Les colonnes de la base qui contiennent un **nom de fichier**. Un test vérifie qu'elles existent : une
  /// nouvelle colonne de ce genre (une pièce jointe, plus tard) doit être ajoutée ici, sinon la sauvegarde ne
  /// saurait pas dire qu'un fichier manque.
  static const List<ColonneFichier> colonnesFichiers = <ColonneFichier>[
    ColonneFichier(table: 'produits', colonne: 'photo_principale_chemin', dossier: dossierPhotos),
    ColonneFichier(table: 'photos_produit', colonne: 'chemin', dossier: dossierPhotos),
    ColonneFichier(table: 'cours', colonne: 'photo_chemin', dossier: dossierPhotos),
    ColonneFichier(table: 'depenses', colonne: 'photo_ticket_chemin', dossier: dossierPhotos),
    ColonneFichier(table: 'parametres_entreprise', colonne: 'logo_chemin', dossier: dossierPhotos),
    // Photos, vidéos et documents joints aux notes : irremplaçables, comme les photos.
    ColonneFichier(table: 'pieces_jointes_note', colonne: 'nom_fichier', dossier: dossierPiecesJointes),
    // Un PDF de facture se refabrique à la demande : son absence n'est pas une perte. (Un devis ne cite pas
    // son PDF dans la base : il est rangé sous son numéro, et refabriqué de la même façon.)
    ColonneFichier(table: 'factures', colonne: 'pdf_chemin', dossier: dossierFactures, remplacable: true),
  ];

  /// Les fichiers cités par les lignes de [tables] (nom de table → lignes), sous la forme `dossier/nom`.
  /// Seuls les fichiers **irremplaçables** (les photos) comptent pour dire si une sauvegarde est complète.
  static Set<String> fichiersIrremplacablesCites(Map<String, List<Map<String, Object?>>> tables) {
    final Set<String> cites = <String>{};
    for (final ColonneFichier colonne in colonnesFichiers) {
      if (colonne.remplacable) continue;
      for (final Map<String, Object?> ligne in tables[colonne.table] ?? const <Map<String, Object?>>[]) {
        final Object? valeur = ligne[colonne.colonne];
        if (valeur is! String) continue;
        final String nom = nomDeFichier(valeur);
        if (nom.isNotEmpty) cites.add('${colonne.dossier}/$nom');
      }
    }
    return cites;
  }

  /// La base ne garde que des noms de fichiers ; par prudence, un éventuel chemin est ramené à son dernier morceau.
  static String nomDeFichier(String valeur) {
    final List<String> morceaux = valeur.trim().split(RegExp(r'[/\\]'));
    return morceaux.isEmpty ? '' : morceaux.last;
  }
}

/// Une colonne de la base qui contient le nom d'un fichier (photo, PDF).
class ColonneFichier {
  const ColonneFichier({
    required this.table,
    required this.colonne,
    required this.dossier,
    this.remplacable = false,
  });

  final String table;
  final String colonne;

  /// Le dossier où se trouve le fichier (voir [FormatSauvegarde.dossiersFichiers]).
  final String dossier;

  /// Le fichier peut être refabriqué par l'application (les PDF de facture et de devis).
  final bool remplacable;
}

/// D'où vient une sauvegarde conservée sur le téléphone.
enum TypeSauvegarde {
  /// Faite toute seule à l'ouverture de l'application (la plus ancienne est supprimée au-delà de 7).
  auto('auto', 'Automatique'),

  /// Demandée par la personne : conservée jusqu'à ce qu'elle la supprime.
  manuelle('manuelle', 'Manuelle'),

  /// Copie de sécurité faite juste avant une restauration (les 3 dernières sont conservées).
  avantRestauration('avant-restauration', 'Avant une restauration');

  const TypeSauvegarde(this.code, this.libelle);

  /// Écrit dans le nom du fichier.
  final String code;
  final String libelle;
}

/// Une sauvegarde rangée dans le dossier des sauvegardes de l'application.
class SauvegardeLocale {
  const SauvegardeLocale({
    required this.fichier,
    required this.type,
    required this.date,
    required this.octets,
    this.complete = true,
    this.fichiersAbsents = const <String>[],
  });

  final File fichier;
  final TypeSauvegarde type;

  /// Date et heure de la sauvegarde, lues dans le nom du fichier.
  final DateTime date;

  /// Taille du fichier.
  final int octets;

  /// `false` si des photos citées par les données manquaient sur le téléphone au moment de la sauvegarde
  /// (le nom du fichier se termine alors par « -incomplete »).
  final bool complete;

  /// Les photos qui manquaient (`photos_produits/nom.jpg`). Connues seulement juste après la création ;
  /// dans la liste des sauvegardes, on sait seulement si la sauvegarde est [complete].
  final List<String> fichiersAbsents;

  String get nom => fichier.uri.pathSegments.last;
}

/// Ce que dit une archive, lu avant de la restaurer.
class ManifesteSauvegarde {
  const ManifesteSauvegarde({
    required this.creeLe,
    required this.versionApplication,
    required this.nombreFichiers,
    required this.lignes,
    this.format = 1,
    this.fichiersAbsents = const <String>[],
  });

  final DateTime? creeLe;
  final String versionApplication;

  /// Photos et PDF contenus dans l'archive.
  final int nombreFichiers;

  /// Nombre de lignes de chaque table (nom de la table → nombre).
  final Map<String, int> lignes;

  /// Version du format de l'archive (voir [FormatSauvegarde.version]).
  final int format;

  /// Les photos citées par les données mais absentes de l'archive (`photos_produits/nom.jpg`), trouvées en
  /// comparant les données et le contenu de l'archive : c'est vrai pour toutes les archives, même anciennes.
  final List<String> fichiersAbsents;

  /// Toutes les photos citées par les données sont dans l'archive.
  bool get complete => fichiersAbsents.isEmpty;

  /// L'archive contient la liste des empreintes : chaque fichier est contrôlé avant la restauration.
  bool get empreintesVerifiables => format >= 2;

  int lignesDe(String table) => lignes[table] ?? 0;
}

/// Une étape du travail en cours (pour dire où on en est).
enum EtapeSauvegarde {
  /// Création : lecture de la base.
  lectureDonnees,

  /// Création : liste des photos et PDF, taille et empreinte SHA-256 de chacun.
  empreintes,

  /// Création : écriture des fichiers dans l'archive.
  ecritureFichiers,

  /// Création : relecture de l'archive écrite.
  verification,

  /// Restauration : lecture et contrôle des fichiers de l'archive.
  controleFichiers,

  /// Restauration : copie de sécurité des données actuelles.
  copieDeSecurite,

  /// Restauration : remplacement des données et des fichiers.
  remplacement,
}

/// Où en est une sauvegarde ou une restauration : [fait] sur [total] pour l'étape [etape].
class ProgressionSauvegarde {
  const ProgressionSauvegarde(this.etape, this.fait, this.total);

  final EtapeSauvegarde etape;
  final int fait;
  final int total;

  /// Position dans la suite des étapes, à partir de 1, et nombre d'étapes de l'opération.
  int get numeroEtape => switch (etape) {
    EtapeSauvegarde.lectureDonnees => 1,
    EtapeSauvegarde.empreintes => 2,
    EtapeSauvegarde.ecritureFichiers => 3,
    EtapeSauvegarde.verification => 4,
    EtapeSauvegarde.controleFichiers => 1,
    EtapeSauvegarde.copieDeSecurite => 2,
    EtapeSauvegarde.remplacement => 3,
  };

  int get nombreEtapes => switch (etape) {
    EtapeSauvegarde.lectureDonnees ||
    EtapeSauvegarde.empreintes ||
    EtapeSauvegarde.ecritureFichiers ||
    EtapeSauvegarde.verification => 4,
    EtapeSauvegarde.controleFichiers || EtapeSauvegarde.copieDeSecurite || EtapeSauvegarde.remplacement => 3,
  };

  /// Avancement de l'étape, de 0 à 1 ; `null` quand on ne peut pas le chiffrer (barre sans position).
  double? get fraction => total <= 0 ? null : (fait / total).clamp(0.0, 1.0);
}

/// Reçoit l'avancement d'une sauvegarde ou d'une restauration.
typedef SurProgression = void Function(ProgressionSauvegarde progression);

/// Un fichier de l'archive, avec sa taille et son empreinte SHA-256 (`fichiers.json`).
class EmpreinteFichier {
  const EmpreinteFichier({required this.chemin, required this.octets, required this.sha256});

  /// `dossier/nom`, par exemple `photos_produits/photo_1.jpg`.
  final String chemin;
  final int octets;
  final String sha256;

  Map<String, Object?> versJson() => <String, Object?>{'chemin': chemin, 'octets': octets, 'sha256': sha256};
}

/// Écrit [octets] dans [cible] sans jamais laisser un fichier à moitié écrit : on écrit dans un fichier
/// provisoire, puis on le renomme.
Future<void> ecrireAtomiquement(File cible, List<int> octets) async {
  await cible.parent.create(recursive: true);
  final File provisoire = File('${cible.path}.tmp');
  await provisoire.writeAsBytes(octets, flush: true);
  await provisoire.rename(cible.path);
}
