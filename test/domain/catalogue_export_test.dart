import 'package:crochet_creations/domain/catalogue_export.dart';
import 'package:flutter_test/flutter_test.dart';

ProduitCatalogue _produit({
  String reference = 'PRD-0001',
  String nom = 'Doudou lapin « Noisette »',
  List<String> variantes = const <String>['Rose – taille M', 'Bleu'],
  List<String> photos = const <String>['a.jpg', 'b.PNG'],
  String? description,
}) {
  return ProduitCatalogue(
    reference: reference,
    nom: nom,
    categorie: 'Doudou',
    statut: 'Disponible',
    prixVenteCentimes: 2550,
    description: description,
    couleur: 'Beige',
    matieres: 'Coton; laine mérinos',
    variantes: variantes,
    photos: photos,
  );
}

void main() {
  group('photosDuProduit', () {
    test('la photo principale d’abord, puis les autres, sans doublon ni vide', () {
      expect(
        photosDuProduit(principale: 'b.jpg', autres: <String>['a.jpg', 'b.jpg', ' ', 'c.jpg', 'a.jpg']),
        <String>['b.jpg', 'a.jpg', 'c.jpg'],
      );
    });

    test('sans photo principale, les autres gardent leur ordre', () {
      expect(photosDuProduit(autres: <String>['x.jpg', 'y.jpg']), <String>['x.jpg', 'y.jpg']);
      expect(photosDuProduit(principale: '  '), isEmpty);
    });
  });

  group('nomSurPourFichier', () {
    test('garde lettres, chiffres, point, tiret et tiret bas', () {
      expect(nomSurPourFichier('PRD-0001'), 'PRD-0001');
      expect(nomSurPourFichier('doudou_lapin.v2'), 'doudou_lapin.v2');
    });

    test('remplace le reste par un tiret bas et ne laisse ni dossier ni point au bord', () {
      expect(nomSurPourFichier('Doudou « lapin »/rose'), 'Doudou_lapin_rose');
      expect(nomSurPourFichier('../../etc'), 'etc');
      expect(nomSurPourFichier('   '), 'produit');
      expect(nomSurPourFichier('...'), 'produit');
    });
  });

  group('cheminPhotoArchive', () {
    test('photos/REF_rang.extension, extension en minuscules', () {
      expect(cheminPhotoArchive(reference: 'PRD-0001', rang: 1, nomFichier: 'photo_1.JPG'), 'photos/PRD-0001_1.jpg');
      expect(cheminPhotoArchive(reference: 'PRD-0001', rang: 2, nomFichier: 'x.png'), 'photos/PRD-0001_2.png');
    });

    test('jpg si le fichier n’a pas d’extension exploitable', () {
      expect(cheminPhotoArchive(reference: 'A', rang: 1, nomFichier: 'sans_extension'), 'photos/A_1.jpg');
      expect(cheminPhotoArchive(reference: 'A', rang: 1, nomFichier: 'x.tropLongueExtension'), 'photos/A_1.jpg');
    });

    test('la référence est rendue sûre', () {
      expect(cheminPhotoArchive(reference: 'A/B ../C', rang: 3, nomFichier: 'x.jpg'), 'photos/A_B_.._C_3.jpg');
    });

    test('cheminsPhotosArchive suit l’ordre des photos du produit', () {
      expect(cheminsPhotosArchive(_produit()), <String>['photos/PRD-0001_1.jpg', 'photos/PRD-0001_2.png']);
      expect(cheminsPhotosArchive(_produit(photos: const <String>[])), isEmpty);
    });
  });

  group('construireCsvCatalogue', () {
    test('une ligne d’en-têtes, puis un produit par ligne, prix en euros, point-virgule protégé', () {
      final String csv = construireCsvCatalogue(
        <ProduitCatalogue>[_produit(), _produit(reference: 'PRD-0002', nom: 'Panier', variantes: const <String>[], photos: const <String>[])],
        <String, List<String>>{
          'PRD-0001': <String>['photos/PRD-0001_1.jpg'],
        },
      );
      final List<String> lignes = csv.split('\r\n');
      expect(lignes.last, '');
      expect(lignes[0], FormatCatalogue.entetesCsv.join(';'));
      expect(lignes[0], startsWith('Référence;Nom;Catégorie;Statut;Prix de vente (€);'));
      expect(
        lignes[1],
        'PRD-0001;Doudou lapin « Noisette »;Doudou;Disponible;25,50;;Beige;;"Coton; laine mérinos";'
        'Rose – taille M, Bleu;photos/PRD-0001_1.jpg',
      );
      // Un produit sans variante ni photo : colonnes vides.
      expect(lignes[2], 'PRD-0002;Panier;Doudou;Disponible;25,50;;Beige;;"Coton; laine mérinos";;');
      expect(lignes, hasLength(4));
    });

    test('ne contient aucune colonne de coût, de stock ou de client', () {
      final String entetes = FormatCatalogue.entetesCsv.join(';').toLowerCase();
      for (final String interdit in <String>['coût', 'cout', 'stock', 'client', 'marge', 'vente n']) {
        expect(entetes, isNot(contains(interdit)), reason: interdit);
      }
    });
  });

  group('construireJsonCatalogue', () {
    test('les produits, leurs prix en centimes et en euros, et seulement les photos présentes', () {
      final Map<String, Object?> json = construireJsonCatalogue(
        application: 'Un p’tit crochet dans les stocks',
        exporteLe: DateTime(2026, 11, 16, 9, 30),
        produits: <ProduitCatalogue>[_produit(description: 'Doux')],
        cheminsPhotos: <String, List<String>>{
          'PRD-0001': <String>['photos/PRD-0001_2.png'],
        },
      );
      expect(json['application'], 'Un p’tit crochet dans les stocks');
      expect(json['exporteLe'], '2026-11-16T09:30:00.000');
      expect(json['nombreProduits'], 1);
      final Map<String, Object?> p = (json['produits']! as List<Object?>).single! as Map<String, Object?>;
      expect(p['reference'], 'PRD-0001');
      expect(p['prixVenteCentimes'], 2550);
      expect(p['prixVenteEuros'], 25.5);
      expect(p['description'], 'Doux');
      expect(p['variantes'], <String>['Rose – taille M', 'Bleu']);
      expect(p['photos'], <String>['photos/PRD-0001_2.png']);
      expect(p.keys, isNot(contains('quantiteStock')));
      expect(p.keys, isNot(contains('coutMatieres')));
    });
  });

  group('construireLisezmoiCatalogue', () {
    test('explique le contenu, et dit ce qui ne figure jamais dans l’archive', () {
      final String t = construireLisezmoiCatalogue(
        application: 'Un p’tit crochet dans les stocks',
        dateTexte: '16 novembre 2026',
        produits: 12,
        photos: 30,
        photosManquantes: const <String>[],
      );
      expect(t, contains('Exporté le 16 novembre 2026.'));
      expect(t, contains('catalogue.csv'));
      expect(t, contains('catalogue.json'));
      expect(t, contains('photos/'));
      expect(t, contains('les coûts des matières, les stocks, les clients'));
      expect(t, isNot(contains('introuvables')));
    });

    test('liste les photos introuvables', () {
      final String t = construireLisezmoiCatalogue(
        application: 'App',
        dateTexte: '16 novembre 2026',
        produits: 1,
        photos: 0,
        photosManquantes: const <String>['PRD-0001 : photo_9.jpg'],
      );
      expect(t, contains('Photos introuvables sur le téléphone (non incluses) :'));
      expect(t, contains('- PRD-0001 : photo_9.jpg'));
    });
  });
}
