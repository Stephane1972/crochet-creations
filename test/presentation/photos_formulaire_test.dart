import 'dart:io';

import 'package:crochet_creations/data/stockage/stockage_photos.dart';
import 'package:crochet_creations/presentation/produits/photos_formulaire.dart';
import 'package:flutter_test/flutter_test.dart';

/// Photos du formulaire produit : copie dans le dossier de l'application, et suppression
/// des fichiers au bon moment (jamais avant l'enregistrement pour une photo déjà enregistrée).
void main() {
  late Directory racine;
  late Directory sources;
  late StockagePhotos stockage;
  late PhotosFormulaire photos;

  setUp(() async {
    racine = await Directory.systemTemp.createTemp('photos_test_');
    sources = Directory('${racine.path}/galerie')..createSync();
    stockage = StockagePhotos(Directory('${racine.path}/photos_produits'));
    photos = PhotosFormulaire(stockage: stockage);
  });
  tearDown(() => racine.delete(recursive: true));

  /// Crée une « photo de la galerie » et retourne son chemin.
  String photoGalerie(String nom, {String contenu = 'image'}) {
    final File f = File('${sources.path}/$nom')..writeAsStringSync(contenu);
    return f.path;
  }

  bool existe(String nomEnregistre) => stockage.fichier(nomEnregistre).existsSync();

  group('StockagePhotos', () {
    test('copie la photo et retourne un nom de fichier relatif', () async {
      final String nom = await stockage.enregistrer(photoGalerie('IMG_1.JPG', contenu: 'abc'));

      expect(nom, isNot(contains('/')));
      expect(nom, endsWith('.jpg'));
      expect(stockage.fichier(nom).readAsStringSync(), 'abc');
    });

    test('deux photos du même nom ne s’écrasent pas', () async {
      final String chemin = photoGalerie('photo.png');
      final String a = await stockage.enregistrer(chemin);
      final String b = await stockage.enregistrer(chemin);
      expect(a, isNot(b));
      expect(existe(a) && existe(b), isTrue);
    });

    test('extension inconnue : .jpg', () async {
      final String nom = await stockage.enregistrer(photoGalerie('photo.xyz'));
      expect(nom, endsWith('.jpg'));
    });

    test('la copie reste disponible si l’original disparaît', () async {
      final String chemin = photoGalerie('a.jpg', contenu: 'x');
      final String nom = await stockage.enregistrer(chemin);
      File(chemin).deleteSync();
      expect(existe(nom), isTrue);
    });

    test('fichier source introuvable : erreur', () async {
      await expectLater(
        stockage.enregistrer('${sources.path}/absente.jpg'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('supprimer ne plante pas si le fichier n’existe plus', () async {
      await stockage.supprimer('inconnu.jpg');
      final String nom = await stockage.enregistrer(photoGalerie('a.jpg'));
      await stockage.supprimer(nom);
      expect(existe(nom), isFalse);
    });

    test('un chemin absolu est conservé tel quel', () {
      expect(stockage.fichier('/tmp/x/a.jpg').path, '/tmp/x/a.jpg');
    });
  });

  group('PhotosFormulaire', () {
    test('la photo principale choisie est copiée', () async {
      await photos.remplacerPrincipale(photoGalerie('a.jpg'));
      expect(photos.principale, isNotNull);
      expect(existe(photos.principale!), isTrue);
      expect(photos.fichiersAjoutes, <String>{photos.principale!});
    });

    test('remplacer une photo ajoutée dans la session supprime l’ancien fichier tout de suite', () async {
      await photos.remplacerPrincipale(photoGalerie('a.jpg'));
      final String premiere = photos.principale!;

      await photos.remplacerPrincipale(photoGalerie('b.jpg'));

      expect(existe(premiere), isFalse);
      expect(existe(photos.principale!), isTrue);
    });

    test('remplacer une photo déjà enregistrée ne supprime rien avant l’enregistrement', () async {
      final String ancienne = await stockage.enregistrer(photoGalerie('ancienne.jpg'));
      photos = PhotosFormulaire(stockage: stockage, principale: ancienne);

      await photos.remplacerPrincipale(photoGalerie('nouvelle.jpg'));
      expect(existe(ancienne), isTrue); // toujours là : un abandon ne doit rien faire perdre

      await photos.apresEnregistrement();
      expect(existe(ancienne), isFalse);
      expect(existe(photos.principale!), isTrue);
    });

    test('retirer la photo principale enregistrée : supprimée après l’enregistrement seulement', () async {
      final String ancienne = await stockage.enregistrer(photoGalerie('ancienne.jpg'));
      photos = PhotosFormulaire(stockage: stockage, principale: ancienne);

      await photos.remplacerPrincipale(null);
      expect(photos.principale, isNull);
      expect(existe(ancienne), isTrue);

      await photos.apresEnregistrement();
      expect(existe(ancienne), isFalse);
    });

    test('abandon : les photos copiées pour rien sont supprimées, les photos enregistrées restent', () async {
      final String enregistree = await stockage.enregistrer(photoGalerie('deja.jpg'));
      photos = PhotosFormulaire(stockage: stockage, principale: enregistree);

      await photos.remplacerPrincipale(photoGalerie('nouvelle.jpg'));
      final String nouvelle = photos.principale!;
      await photos.ajouterSecondaire(photoGalerie('autre.jpg'));
      final String secondaire = photos.secondaires.single.chemin;

      await photos.abandonner();

      expect(existe(nouvelle), isFalse);
      expect(existe(secondaire), isFalse);
      expect(existe(enregistree), isTrue);
    });

    test('photos secondaires : ajout, puis retrait d’une photo enregistrée', () async {
      final String ancienne = await stockage.enregistrer(photoGalerie('s1.jpg'));
      final PhotoForm existante = PhotoForm(id: 7, chemin: ancienne);
      photos = PhotosFormulaire(stockage: stockage, secondaires: <PhotoForm>[existante]);

      await photos.ajouterSecondaire(photoGalerie('s2.jpg'));
      expect(photos.secondaires.length, 2);
      expect(photos.nouvellesSecondaires, hasLength(1));
      expect(photos.idsASupprimer, isEmpty);

      await photos.retirerSecondaire(existante);
      expect(photos.secondaires.length, 1);
      expect(photos.idsASupprimer, <int>[7]);
      expect(existe(ancienne), isTrue); // supprimée après l'enregistrement

      await photos.apresEnregistrement();
      expect(existe(ancienne), isFalse);
      expect(existe(photos.secondaires.single.chemin), isTrue);
      expect(photos.idsASupprimer, isEmpty);
    });

    test('retirer une photo secondaire ajoutée à l’instant supprime son fichier tout de suite', () async {
      await photos.ajouterSecondaire(photoGalerie('s.jpg'));
      final PhotoForm photo = photos.secondaires.single;

      await photos.retirerSecondaire(photo);

      expect(existe(photo.chemin), isFalse);
      expect(photos.secondaires, isEmpty);
      expect(photos.idsASupprimer, isEmpty);
    });

    test('si la copie échoue, l’état ne change pas', () async {
      await photos.remplacerPrincipale(photoGalerie('a.jpg'));
      final String avant = photos.principale!;

      await expectLater(
        photos.remplacerPrincipale('${sources.path}/absente.jpg'),
        throwsA(isA<FileSystemException>()),
      );

      expect(photos.principale, avant);
      expect(existe(avant), isTrue);
    });
  });
}
