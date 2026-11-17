// Export du catalogue (étape 8 de l'évolution) : les règles pures de l'archive « catalogue ».
//
// L'archive est faite pour être **donnée à quelqu'un d'autre** (une boutique, une amie qui prépare un marché, un site) : les
// produits à vendre, leurs prix de vente et leurs photos. Elle ne contient jamais les coûts des matières, les stocks, les
// clients, les ventes ni les factures. Ce n'est pas une sauvegarde (voir `ServiceSauvegarde`) : elle ne se restaure pas.

import 'csv.dart';

/// Un produit tel qu'il sort dans l'archive.
class ProduitCatalogue {
  const ProduitCatalogue({
    required this.reference,
    required this.nom,
    required this.categorie,
    required this.statut,
    required this.prixVenteCentimes,
    this.description,
    this.couleur,
    this.dimensions,
    this.matieres,
    this.variantes = const <String>[],
    this.photos = const <String>[],
  });

  final String reference;
  final String nom;

  /// Le nom de la catégorie (pas sa clé).
  final String categorie;

  /// Le statut en toutes lettres (« Disponible », « Sur commande »…).
  final String statut;
  final int prixVenteCentimes;
  final String? description;
  final String? couleur;
  final String? dimensions;
  final String? matieres;

  /// Les libellés des variantes (« Rose », « Taille M »…), sans leur stock.
  final List<String> variantes;

  /// Les noms des fichiers photo sur le téléphone, **la principale d'abord**, sans doublon.
  final List<String> photos;
}

/// Noms des fichiers de l'archive.
abstract final class FormatCatalogue {
  static const String fichierCsv = 'catalogue.csv';
  static const String fichierJson = 'catalogue.json';
  static const String fichierLisezmoi = 'LISEZMOI.txt';
  static const String dossierPhotos = 'photos';

  /// Les colonnes du CSV, dans l'ordre.
  static const List<String> entetesCsv = <String>[
    'Référence',
    'Nom',
    'Catégorie',
    'Statut',
    'Prix de vente (€)',
    'Description',
    'Couleur',
    'Dimensions',
    'Matières',
    'Variantes',
    'Photos',
  ];
}

/// Les photos d'un produit : la principale d'abord, puis les autres dans l'ordre, sans vide ni doublon.
List<String> photosDuProduit({String? principale, List<String> autres = const <String>[]}) {
  final List<String> resultat = <String>[];
  for (final String? nom in <String?>[principale, ...autres]) {
    final String propre = (nom ?? '').trim();
    if (propre.isEmpty || resultat.contains(propre)) continue;
    resultat.add(propre);
  }
  return resultat;
}

/// Un texte sûr pour un nom de fichier : lettres, chiffres, point, tiret et tiret bas ; le reste devient un tiret bas.
/// Jamais vide.
String nomSurPourFichier(String texte) {
  final String propre = texte.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  final String sansBords = propre.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  return sansBords.isEmpty ? 'produit' : sansBords;
}

/// Où va une photo dans l'archive : `photos/REF_1.jpg`. Le rang commence à 1 ; l'extension est celle du fichier du
/// téléphone (`jpg` à défaut).
String cheminPhotoArchive({required String reference, required int rang, required String nomFichier}) {
  final int point = nomFichier.lastIndexOf('.');
  final String brute = point < 0 ? '' : nomFichier.substring(point + 1).toLowerCase();
  final String extension = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(brute) ? brute : 'jpg';
  return '${FormatCatalogue.dossierPhotos}/${nomSurPourFichier(reference)}_$rang.$extension';
}

/// Les chemins, dans l'archive, des photos du produit (même ordre que [ProduitCatalogue.photos]).
List<String> cheminsPhotosArchive(ProduitCatalogue produit) => <String>[
  for (int i = 0; i < produit.photos.length; i++)
    cheminPhotoArchive(reference: produit.reference, rang: i + 1, nomFichier: produit.photos[i]),
];

/// Le tableau du catalogue, pour un tableur. [cheminsPhotos] : pour chaque référence, les chemins des photos **réellement
/// présentes** dans l'archive.
String construireCsvCatalogue(List<ProduitCatalogue> produits, Map<String, List<String>> cheminsPhotos) {
  return construireCsv(
    FormatCatalogue.entetesCsv,
    <List<String>>[
      for (final ProduitCatalogue p in produits)
        <String>[
          p.reference,
          p.nom,
          p.categorie,
          p.statut,
          montantCsv(p.prixVenteCentimes),
          p.description ?? '',
          p.couleur ?? '',
          p.dimensions ?? '',
          p.matieres ?? '',
          p.variantes.join(', '),
          (cheminsPhotos[p.reference] ?? const <String>[]).join(', '),
        ],
    ],
  );
}

/// Le même catalogue en JSON (pour un site ou un autre logiciel).
Map<String, Object?> construireJsonCatalogue({
  required String application,
  required DateTime exporteLe,
  required List<ProduitCatalogue> produits,
  required Map<String, List<String>> cheminsPhotos,
}) {
  return <String, Object?>{
    'application': application,
    'exporteLe': exporteLe.toIso8601String(),
    'nombreProduits': produits.length,
    'produits': <Object?>[
      for (final ProduitCatalogue p in produits)
        <String, Object?>{
          'reference': p.reference,
          'nom': p.nom,
          'categorie': p.categorie,
          'statut': p.statut,
          'prixVenteCentimes': p.prixVenteCentimes,
          'prixVenteEuros': p.prixVenteCentimes / 100,
          'description': p.description,
          'couleur': p.couleur,
          'dimensions': p.dimensions,
          'matieres': p.matieres,
          'variantes': p.variantes,
          'photos': cheminsPhotos[p.reference] ?? const <String>[],
        },
    ],
  };
}

/// Le petit mode d'emploi placé dans l'archive. [dateTexte] : la date de l'export, déjà écrite en toutes lettres.
String construireLisezmoiCatalogue({
  required String application,
  required String dateTexte,
  required int produits,
  required int photos,
  required List<String> photosManquantes,
}) {
  final StringBuffer t = StringBuffer()
    ..writeln('Catalogue – $application')
    ..writeln('Exporté le $dateTexte.')
    ..writeln()
    ..writeln('Contenu de cette archive :')
    ..writeln('- ${FormatCatalogue.fichierCsv} : le tableau des produits ($produits). Ouvrez-le avec Excel, LibreOffice ou Numbers ;')
    ..writeln('  les colonnes sont séparées par des points-virgules et les prix sont en euros.')
    ..writeln('- ${FormatCatalogue.fichierJson} : les mêmes informations, pour un site ou un autre logiciel.')
    ..writeln('- ${FormatCatalogue.dossierPhotos}/ : les photos des produits ($photos), nommées d’après la référence du produit.')
    ..writeln()
    ..writeln('Ne figurent jamais ici : les coûts des matières, les stocks, les clients, les ventes et les factures.');
  if (photosManquantes.isNotEmpty) {
    t
      ..writeln()
      ..writeln('Photos introuvables sur le téléphone (non incluses) :');
    for (final String m in photosManquantes) {
      t.writeln('- $m');
    }
  }
  return t.toString();
}
