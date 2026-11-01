import 'dart:io';

/// Contenu et nommage des sauvegardes (archives .zip).
///
/// Une sauvegarde est un fichier `.zip` qui contient :
/// - `donnees.json` : un « manifeste » (application, version du format et du schéma, date) et **toutes les
///   lignes des 15 tables** de la base, telles qu'elles sont enregistrées ;
/// - `fichiers/photos_produits/…`, `fichiers/factures/…`, `fichiers/devis/…` : les photos et les PDF.
///
/// Le même `donnees.json` sert à l'export JSON complet (sans les fichiers).
abstract final class FormatSauvegarde {
  /// Identifiant écrit dans le manifeste : une archive d'une autre application est refusée.
  static const String application = 'crochet-creations';

  /// Version du **format de l'archive**. À augmenter si l'organisation du fichier change.
  static const int version = 1;

  static const String fichierDonnees = 'donnees.json';
  static const String prefixeFichiers = 'fichiers/';

  /// Noms des dossiers de fichiers, à l'intérieur de `fichiers/` et sur le téléphone.
  static const String dossierPhotos = 'photos_produits';
  static const String dossierFactures = 'factures';
  static const String dossierDevis = 'devis';

  static const List<String> dossiersFichiers = <String>[dossierPhotos, dossierFactures, dossierDevis];

  /// Les 15 tables, **dans l'ordre où on peut les remplir** : une table vient après celles qu'elle référence
  /// (une vente après son client, une ligne après sa vente...). On les vide dans l'ordre inverse.
  /// Un test vérifie que cette liste est exactement celle de la base : une nouvelle table doit y être ajoutée.
  static const List<String> tables = <String>[
    'parametres_entreprise',
    'numerotation_documents',
    'produits',
    'variantes_produit',
    'photos_produit',
    'clients',
    'cours',
    'ventes',
    'lignes_vente',
    'paiements',
    'factures',
    'devis',
    'lignes_devis',
    'inscriptions_cours',
    'depenses',
  ];
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
  });

  final File fichier;
  final TypeSauvegarde type;

  /// Date et heure de la sauvegarde, lues dans le nom du fichier.
  final DateTime date;

  /// Taille du fichier.
  final int octets;

  String get nom => fichier.uri.pathSegments.last;
}

/// Ce que dit le manifeste d'une archive, lu avant de la restaurer.
class ManifesteSauvegarde {
  const ManifesteSauvegarde({
    required this.creeLe,
    required this.versionApplication,
    required this.nombreFichiers,
    required this.lignes,
  });

  final DateTime? creeLe;
  final String versionApplication;

  /// Photos et PDF contenus dans l'archive.
  final int nombreFichiers;

  /// Nombre de lignes de chaque table (nom de la table → nombre).
  final Map<String, int> lignes;

  int lignesDe(String table) => lignes[table] ?? 0;
}

/// Écrit [octets] dans [cible] sans jamais laisser un fichier à moitié écrit : on écrit dans un fichier
/// provisoire, puis on le renomme.
Future<void> ecrireAtomiquement(File cible, List<int> octets) async {
  await cible.parent.create(recursive: true);
  final File provisoire = File('${cible.path}.tmp');
  await provisoire.writeAsBytes(octets, flush: true);
  await provisoire.rename(cible.path);
}
