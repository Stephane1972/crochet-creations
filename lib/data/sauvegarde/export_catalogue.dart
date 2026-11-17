import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show ArchiveFile;
import 'package:archive/archive_io.dart' show ZipFileEncoder;

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_fr.dart';
import '../../domain/catalogue_export.dart';
import '../database/app_database.dart';
import '../stockage/stockage_photos.dart';

/// Ce que l'export du catalogue a produit.
class ResultatCatalogue {
  const ResultatCatalogue({
    required this.fichier,
    required this.produits,
    required this.photos,
    required this.photosManquantes,
  });

  /// L'archive `.zip` écrite sur le téléphone.
  final File fichier;

  /// Nombre de produits dans le catalogue.
  final int produits;

  /// Nombre de photos placées dans l'archive.
  final int photos;

  /// Les photos que la base annonce mais qui sont introuvables sur le téléphone, sous la forme « REF : nom du fichier ».
  final List<String> photosManquantes;
}

/// Export du catalogue (étape 8) : un `.zip` avec le tableau des produits (CSV), les mêmes informations en JSON, les photos
/// et un petit mode d'emploi. Voir `catalogue_export.dart` pour ce qu'il contient (et ce qu'il ne contient jamais).
///
/// Les produits archivés n'y figurent pas. Les photos sont rangées telles quelles (déjà compressées), l'une après l'autre,
/// sans jamais toutes tenir en mémoire.
class ExportCatalogue {
  ExportCatalogue(this._base, this._photos, {DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;

  final AppDatabase _base;
  final StockagePhotos _photos;
  final DateTime Function() _horloge;

  /// Nom du fichier du jour : `crochet-creations-catalogue-2026-10-31.zip`.
  String nomArchive() {
    String deux(int n) => n.toString().padLeft(2, '0');
    final DateTime jour = _horloge();
    return 'crochet-creations-catalogue-${jour.year}-${deux(jour.month)}-${deux(jour.day)}.zip';
  }

  /// Les produits du catalogue (les produits archivés sont écartés), dans l'ordre des références, lus d'un seul tenant.
  Future<List<ProduitCatalogue>> lireProduits() {
    return _base.transaction(() async {
      final List<Produit> produits = (await _base.select(_base.produits).get())
          .where((Produit p) => p.archiveLe == null)
          .toList()
        ..sort((Produit a, Produit b) => a.reference.compareTo(b.reference));
      final Map<String, String> nomsCategories = <String, String>{
        for (final CategorieProduit c in await _base.select(_base.categoriesProduit).get()) c.cle: c.nom,
      };
      final List<VarianteProduit> variantes = await _base.select(_base.variantesProduit).get()
        ..sort((VarianteProduit a, VarianteProduit b) => a.id.compareTo(b.id));
      final List<PhotoProduit> photos = await _base.select(_base.photosProduit).get()
        ..sort((PhotoProduit a, PhotoProduit b) {
          final int parPosition = a.position.compareTo(b.position);
          return parPosition != 0 ? parPosition : a.id.compareTo(b.id);
        });

      final Map<int, List<String>> variantesDe = <int, List<String>>{};
      for (final VarianteProduit v in variantes) {
        if (v.archiveLe != null) continue;
        variantesDe.putIfAbsent(v.produitId, () => <String>[]).add(v.libelle);
      }
      final Map<int, List<String>> photosDe = <int, List<String>>{};
      for (final PhotoProduit p in photos) {
        photosDe.putIfAbsent(p.produitId, () => <String>[]).add(p.chemin);
      }

      return <ProduitCatalogue>[
        for (final Produit p in produits)
          ProduitCatalogue(
            reference: p.reference,
            nom: p.nom,
            categorie: nomsCategories[p.categorie] ?? p.categorie,
            statut: p.statut.libelle,
            prixVenteCentimes: p.prixVenteCentimes,
            description: _ouNull(p.description),
            couleur: _ouNull(p.couleur),
            dimensions: _ouNull(p.dimensions),
            matieres: _ouNull(p.matieres),
            variantes: variantesDe[p.id] ?? const <String>[],
            photos: photosDuProduit(principale: p.photoPrincipaleChemin, autres: photosDe[p.id] ?? const <String>[]),
          ),
      ];
    });
  }

  String? _ouNull(String? texte) => (texte == null || texte.trim().isEmpty) ? null : texte;

  /// Fabrique l'archive dans [dossier] (une archive du même jour est remplacée) et dit ce qu'elle contient.
  Future<ResultatCatalogue> ecrireArchive(Directory dossier) async {
    final List<ProduitCatalogue> produits = await lireProduits();

    // Les photos réellement présentes sur le téléphone ; les autres sont signalées, jamais inventées.
    final List<({File source, String chemin})> aRanger = <({File source, String chemin})>[];
    final Map<String, List<String>> cheminsPhotos = <String, List<String>>{};
    final List<String> manquantes = <String>[];
    for (final ProduitCatalogue p in produits) {
      final List<String> chemins = cheminsPhotosArchive(p);
      for (int i = 0; i < p.photos.length; i++) {
        final File source = _photos.fichier(p.photos[i]);
        if (await source.exists()) {
          aRanger.add((source: source, chemin: chemins[i]));
          cheminsPhotos.putIfAbsent(p.reference, () => <String>[]).add(chemins[i]);
        } else {
          manquantes.add('${p.reference} : ${p.photos[i]}');
        }
      }
    }

    final DateTime maintenant = _horloge();
    final List<int> csv = <int>[
      0xEF, 0xBB, 0xBF, // marque UTF-8 : Excel affiche ainsi les accents correctement
      ...utf8.encode(construireCsvCatalogue(produits, cheminsPhotos)),
    ];
    final List<int> json = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(
        construireJsonCatalogue(
          application: AppConstants.nomApplication,
          exporteLe: maintenant,
          produits: produits,
          cheminsPhotos: cheminsPhotos,
        ),
      ),
    );
    final List<int> lisezmoi = utf8.encode(
      construireLisezmoiCatalogue(
        application: AppConstants.nomApplication,
        dateTexte: formatDateLongue(maintenant),
        produits: produits.length,
        photos: aRanger.length,
        photosManquantes: manquantes,
      ),
    );

    await dossier.create(recursive: true);
    final File cible = File('${dossier.path}${Platform.pathSeparator}${nomArchive()}');
    final File provisoire = File('${cible.path}.tmp');
    try {
      final ZipFileEncoder encodeur = ZipFileEncoder()..create(provisoire.path);
      try {
        encodeur.addArchiveFile(ArchiveFile.bytes(FormatCatalogue.fichierLisezmoi, lisezmoi));
        encodeur.addArchiveFile(ArchiveFile.bytes(FormatCatalogue.fichierCsv, csv));
        encodeur.addArchiveFile(ArchiveFile.bytes(FormatCatalogue.fichierJson, json));
        for (final ({File source, String chemin}) photo in aRanger) {
          // Les photos sont déjà compressées : rangées telles quelles, une par une.
          await encodeur.addFile(photo.source, photo.chemin, ZipFileEncoder.store);
        }
      } finally {
        await encodeur.close();
      }
      await provisoire.rename(cible.path);
    } catch (_) {
      try {
        if (await provisoire.exists()) await provisoire.delete();
      } on FileSystemException {
        // Un fichier provisoire oublié est écrasé au prochain export.
      }
      rethrow;
    }

    return ResultatCatalogue(
      fichier: cible,
      produits: produits.length,
      photos: aRanger.length,
      photosManquantes: manquantes,
    );
  }
}
