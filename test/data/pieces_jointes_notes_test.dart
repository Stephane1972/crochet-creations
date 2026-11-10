import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/note_repository.dart';
import 'package:crochet_creations/data/stockage/stockage_pieces_jointes.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/pieces_jointes.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

/// Un fichier « choisi » de [octets] octets, lu par morceaux comme le ferait le téléphone.
FichierChoisi _choisi(
  String nom, {
  int octets = 10,
  TypePieceJointe? type,
  bool annoncer = true,
  int morceau = 1024 * 1024,
}) {
  return FichierChoisi(
    nom: nom,
    type: type ?? typePieceJointeDepuisNom(nom),
    octets: annoncer ? octets : null,
    lire: () async* {
      int restant = octets;
      while (restant > 0) {
        final int n = restant < morceau ? restant : morceau;
        yield List<int>.filled(n, 7);
        restant -= n;
      }
    },
  );
}

Matcher _refus(String morceau) =>
    throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains(morceau)));

void main() {
  late Directory racine;
  late StockagePiecesJointes stockage;

  setUp(() async {
    racine = await Directory.systemTemp.createTemp('pieces_jointes_');
    stockage = StockagePiecesJointes(Directory('${racine.path}/notes_pieces_jointes'));
  });
  tearDown(() async {
    if (await racine.exists()) await racine.delete(recursive: true);
  });

  Future<List<String>> noms() async {
    if (!await stockage.dossier.exists()) return <String>[];
    return <String>[
      await for (final FileSystemEntity e in stockage.dossier.list()) e.uri.pathSegments.where((s) => s.isNotEmpty).last,
    ]..sort();
  }

  group('règles et limites', () {
    test('les limites annoncées : 25 Mo les photos et les documents, 150 Mo les vidéos, 20 pièces par note', () {
      expect(limiteOctets(TypePieceJointe.photo), 25 * 1024 * 1024);
      expect(limiteOctets(TypePieceJointe.document), 25 * 1024 * 1024);
      expect(limiteOctets(TypePieceJointe.video), 150 * 1024 * 1024);
      expect(nombreMaxPiecesJointes, 20);
      expect(
        libelleLimitesPiecesJointes(),
        'Photos et documents : 25 Mo au plus chacun. Vidéos : 150 Mo au plus. 20 pièces jointes au plus par note.',
      );
    });

    test('le type vient de l’extension : photo, vidéo, sinon document', () {
      expect(typePieceJointeDepuisNom('IMG_001.JPG'), TypePieceJointe.photo);
      expect(typePieceJointeDepuisNom('scan.heic'), TypePieceJointe.photo);
      expect(typePieceJointeDepuisNom('tuto.MP4'), TypePieceJointe.video);
      expect(typePieceJointeDepuisNom('patron.pdf'), TypePieceJointe.document);
      expect(typePieceJointeDepuisNom('devis.xlsx'), TypePieceJointe.document);
      expect(typePieceJointeDepuisNom('sans_extension'), TypePieceJointe.document);
      expect(typePieceJointeDepuisNom('/sdcard/Movies/film.mov'), TypePieceJointe.video);
    });

    test('les tailles se lisent en o, Ko et Mo', () {
      expect(formaterTailleFichier(850), '850 o');
      expect(formaterTailleFichier(12 * 1024), '12 Ko');
      expect(formaterTailleFichier((1.4 * 1024 * 1024).round()), '1,4 Mo');
    });

    test('un fichier trop gros ou vide est refusé avec un message qui dit la limite', () {
      expect(erreurTaillePieceJointe(TypePieceJointe.photo, 25 * 1024 * 1024), isNull);
      expect(erreurTaillePieceJointe(TypePieceJointe.photo, 25 * 1024 * 1024 + 1, nom: 'IMG.jpg'), contains('25 Mo'));
      expect(erreurTaillePieceJointe(TypePieceJointe.photo, 25 * 1024 * 1024 + 1, nom: 'IMG.jpg'), contains('« IMG.jpg »'));
      expect(erreurTaillePieceJointe(TypePieceJointe.video, 100 * 1024 * 1024), isNull);
      expect(erreurTaillePieceJointe(TypePieceJointe.video, 150 * 1024 * 1024 + 1), contains('150 Mo'));
      expect(erreurTaillePieceJointe(TypePieceJointe.document, 0), contains('vide'));
    });

    test('20 pièces jointes au plus par note', () {
      expect(erreurNombrePiecesJointes(20), isNull);
      expect(erreurNombrePiecesJointes(21), contains('20'));
    });

    test('le nom affiché est nettoyé et raccourci, extension gardée', () {
      expect(nettoyerNomPieceJointe('  /sdcard/Download/  Patron   poncho.pdf '), 'Patron poncho.pdf');
      expect(nettoyerNomPieceJointe(null), 'Sans nom');
      expect(nettoyerNomPieceJointe('   '), 'Sans nom');
      final String long = '${'a' * 200}.pdf';
      final String court = nettoyerNomPieceJointe(long);
      expect(court.length, longueurMaxNomPieceJointe);
      expect(court, endsWith('.pdf'));
    });

    test('l’extension de stockage est sûre : lettres et chiffres, sinon « bin »', () {
      expect(extensionDeStockage('Patron.PDF'), 'pdf');
      expect(extensionDeStockage('archive.tar.gz'), 'gz');
      expect(extensionDeStockage('sans_extension'), 'bin');
      expect(extensionDeStockage('bizarre.p d'), 'bin');
      expect(extensionDeStockage('trop_long.abcdefghijkl'), 'bin');
    });
  });

  group('ranger un fichier', () {
    test('copie le fichier sous un nom unique qui garde l’extension, et dit sa taille', () async {
      final PieceRangee piece = await stockage.enregistrer(_choisi('Patron poncho.pdf', octets: 2500));

      expect(piece.nomAffiche, 'Patron poncho.pdf');
      expect(piece.type, TypePieceJointe.document);
      expect(piece.octets, 2500);
      expect(piece.nomFichier, endsWith('.pdf'));
      expect(piece.nomFichier, isNot(contains(' ')));
      expect(await stockage.fichier(piece.nomFichier).length(), 2500);
      expect(await noms(), <String>[piece.nomFichier]);
    });

    test('deux fichiers de même nom ne s’écrasent pas', () async {
      final PieceRangee a = await stockage.enregistrer(_choisi('photo.jpg'));
      final PieceRangee b = await stockage.enregistrer(_choisi('photo.jpg'));
      expect(a.nomFichier, isNot(b.nomFichier));
      expect(await noms(), hasLength(2));
    });

    test('une vidéo de 30 Mo passe (limite 150 Mo), mais pas une photo de 30 Mo (limite 25 Mo)', () async {
      final PieceRangee video = await stockage.enregistrer(_choisi('film.mp4', octets: 30 * 1024 * 1024));
      expect(video.type, TypePieceJointe.video);
      expect(await stockage.fichier(video.nomFichier).length(), 30 * 1024 * 1024);

      await expectLater(
        stockage.enregistrer(_choisi('grosse.jpg', octets: 30 * 1024 * 1024)),
        _refus('limite est de 25 Mo pour les photos'),
      );
      expect(await noms(), <String>[video.nomFichier]);
    });

    test('un fichier trop gros annoncé par le sélecteur est refusé sans rien copier', () async {
      await expectLater(
        stockage.enregistrer(_choisi('gros.pdf', octets: limiteOctetsDocument + 1)),
        _refus('25 Mo'),
      );
      expect(await stockage.dossier.exists(), isFalse);
    });

    test('un fichier dont la taille n’est connue qu’en cours de copie est refusé dès qu’il dépasse, et rien ne reste', () async {
      await expectLater(
        stockage.enregistrer(_choisi('gros.pdf', octets: limiteOctetsDocument + 1, annoncer: false)),
        _refus('dépasse la limite de 25 Mo'),
      );
      expect(await noms(), isEmpty); // ni fichier, ni fichier provisoire
    });

    test('un fichier vide est refusé', () async {
      await expectLater(stockage.enregistrer(_choisi('vide.pdf', octets: 0, annoncer: false)), _refus('vide'));
      expect(await noms(), isEmpty);
    });

    test('une lecture qui échoue en route laisse le dossier propre, et l’erreur remonte', () async {
      final FichierChoisi casse = FichierChoisi(
        nom: 'cassé.pdf',
        type: TypePieceJointe.document,
        lire: () async* {
          yield List<int>.filled(1000, 1);
          throw const FileSystemException('lecture impossible');
        },
      );
      await expectLater(stockage.enregistrer(casse), throwsA(isA<FileSystemException>()));
      expect(await noms(), isEmpty);
    });

    test('le nom enregistré en base ne peut jamais faire sortir du dossier', () async {
      final PieceRangee piece = await stockage.enregistrer(_choisi('a.pdf'));
      expect(stockage.fichier('../../etc/${piece.nomFichier}').parent.path, stockage.dossier.path);
      expect(stockage.fichier(r'..\..\x\fichier.pdf').parent.path, stockage.dossier.path);
    });

    test('supprimer efface le fichier, et ne se plaint pas s’il a déjà disparu', () async {
      final PieceRangee piece = await stockage.enregistrer(_choisi('a.pdf'));
      await stockage.supprimer(piece.nomFichier);
      await stockage.supprimer(piece.nomFichier);
      await stockage.supprimer('jamais_existe.pdf');
      expect(await noms(), isEmpty);
    });
  });

  group('pièces jointes d’une note', () {
    late AppDatabase db;
    late NoteRepository notes;

    setUp(() {
      db = creerBaseEnMemoire();
      notes = NoteRepository(db, stockagePiecesJointes: stockage);
    });
    tearDown(() => db.close());

    Future<PieceRangee> ranger(String nom, {int octets = 10}) => stockage.enregistrer(_choisi(nom, octets: octets));

    test('créer une note avec ses pièces jointes les enregistre dans l’ordre, avec leur nom, leur type et leur taille', () async {
      final PieceRangee photo = await ranger('Modèle.jpg', octets: 300);
      final PieceRangee pdf = await ranger('Patron.pdf', octets: 900);
      final Note note = await notes.creer(titre: 'Poncho', piecesJointes: <PieceRangee>[photo, pdf]);

      final List<PieceJointeNote> pieces = await notes.listerPiecesJointes(note.id);
      expect(pieces.map((PieceJointeNote p) => p.nomAffiche), <String>['Modèle.jpg', 'Patron.pdf']);
      expect(pieces.map((PieceJointeNote p) => p.typeFichier), <TypePieceJointe>[TypePieceJointe.photo, TypePieceJointe.document]);
      expect(pieces.map((PieceJointeNote p) => p.octets), <int>[300, 900]);
      expect(pieces.map((PieceJointeNote p) => p.nomFichier), <String>[photo.nomFichier, pdf.nomFichier]);
      expect(await notes.nombrePiecesJointesParNote(), <int, int>{note.id: 2});
    });

    test('une note sans pièce jointe n’apparaît pas dans le décompte', () async {
      final Note seule = await notes.creer(titre: 'Seule');
      final Note avec = await notes.creer(titre: 'Avec', piecesJointes: <PieceRangee>[await ranger('a.pdf')]);
      expect(await notes.nombrePiecesJointesParNote(), <int, int>{avec.id: 1});
      expect(await notes.listerPiecesJointes(seule.id), isEmpty);
    });

    test('plus de 20 pièces jointes : refusé, et rien n’est enregistré', () async {
      final List<PieceRangee> trop = <PieceRangee>[for (int i = 0; i < 21; i++) await ranger('f$i.pdf')];
      await expectLater(notes.creer(titre: 'Trop', piecesJointes: trop), _refus('20 pièces jointes'));
      expect(await notes.lister(), isEmpty);
      expect(await db.select(db.piecesJointesNote).get(), isEmpty);

      final Note vingt = await notes.creer(titre: 'Vingt', piecesJointes: trop.take(20).toList());
      expect(await notes.listerPiecesJointes(vingt.id), hasLength(20));
    });

    test('une pièce jointe trop grosse pour son type est refusée : la note n’est pas créée', () async {
      const PieceRangee enorme = PieceRangee(
        nomFichier: 'piece_x.jpg',
        nomAffiche: 'Enorme.jpg',
        type: TypePieceJointe.photo,
        octets: 26 * 1024 * 1024,
      );
      await expectLater(notes.creer(titre: 'Trop lourde', piecesJointes: <PieceRangee>[enorme]), _refus('25 Mo'));
      expect(await notes.lister(), isEmpty);
    });

    test('modifier ajoute et retire des pièces jointes ; les fichiers retirés sont effacés, les autres restent', () async {
      final PieceRangee a = await ranger('a.pdf');
      final PieceRangee b = await ranger('b.pdf');
      final Note note = await notes.creer(titre: 'Poncho', piecesJointes: <PieceRangee>[a, b]);
      final List<PieceJointeNote> avant = await notes.listerPiecesJointes(note.id);

      final PieceRangee c = await ranger('c.jpg');
      await notes.modifier(
        note.id,
        titre: 'Poncho',
        ajouts: <PieceRangee>[c],
        retraits: <int>{avant.first.id},
      );

      final List<PieceJointeNote> apres = await notes.listerPiecesJointes(note.id);
      expect(apres.map((PieceJointeNote p) => p.nomFichier), <String>[b.nomFichier, c.nomFichier]);
      expect(await noms(), <String>[b.nomFichier, c.nomFichier]..sort());
    });

    test('ajouter ou retirer une pièce jointe fait remonter la note ; ne rien changer, non', () async {
      final Note note = await notes.creer(titre: 'Poncho');
      await (db.update(db.notes)..where((t) => t.id.equals(note.id))).write(
        NotesCompanion(modifieLe: Value(DateTime(2026, 1, 1))),
      );

      await notes.modifier(note.id, titre: 'Poncho');
      expect((await notes.obtenir(note.id))!.modifieLe, DateTime(2026, 1, 1));

      await notes.modifier(note.id, titre: 'Poncho', ajouts: <PieceRangee>[await ranger('a.pdf')]);
      expect((await notes.obtenir(note.id))!.modifieLe.isAfter(DateTime(2026, 1, 1)), isTrue);
    });

    test('une pièce jointe d’une autre note ne peut pas être retirée par erreur', () async {
      final Note une = await notes.creer(titre: 'Une', piecesJointes: <PieceRangee>[await ranger('a.pdf')]);
      final Note autre = await notes.creer(titre: 'Autre', piecesJointes: <PieceRangee>[await ranger('b.pdf')]);
      final int idDeLautre = (await notes.listerPiecesJointes(autre.id)).single.id;

      await notes.modifier(une.id, titre: 'Une', retraits: <int>{idDeLautre});

      expect(await notes.listerPiecesJointes(une.id), hasLength(1));
      expect(await notes.listerPiecesJointes(autre.id), hasLength(1));
      expect(await noms(), hasLength(2));
    });

    test('au-delà de 20 en comptant les ajouts et les retraits : refusé, et rien ne change', () async {
      final List<PieceRangee> dixNeuf = <PieceRangee>[for (int i = 0; i < 19; i++) await ranger('f$i.pdf')];
      final Note note = await notes.creer(titre: 'Presque pleine', piecesJointes: dixNeuf);
      final PieceRangee deux = await ranger('x.pdf');
      final PieceRangee trois = await ranger('y.pdf');

      await expectLater(
        notes.modifier(note.id, titre: 'Presque pleine', ajouts: <PieceRangee>[deux, trois]),
        _refus('20 pièces jointes'),
      );
      expect(await notes.listerPiecesJointes(note.id), hasLength(19));

      // En retirant une pièce, on a de la place pour deux ajouts.
      final int premier = (await notes.listerPiecesJointes(note.id)).first.id;
      await notes.modifier(note.id, titre: 'Presque pleine', ajouts: <PieceRangee>[deux, trois], retraits: <int>{premier});
      expect(await notes.listerPiecesJointes(note.id), hasLength(20));
    });

    test('supprimer une note supprime ses pièces jointes en base et leurs fichiers, pas ceux des autres notes', () async {
      final PieceRangee a = await ranger('a.pdf');
      final PieceRangee b = await ranger('b.pdf');
      final Note supprimee = await notes.creer(titre: 'À supprimer', piecesJointes: <PieceRangee>[a]);
      final Note gardee = await notes.creer(titre: 'À garder', piecesJointes: <PieceRangee>[b]);

      await notes.supprimer(supprimee.id);

      expect(await db.select(db.piecesJointesNote).get().then((l) => l.map((p) => p.noteId)), <int>[gardee.id]);
      expect(await noms(), <String>[b.nomFichier]);
    });

    test('le décompte suit les ajouts et les suppressions en direct', () async {
      final Note note = await notes.creer(titre: 'Poncho');
      final List<Map<int, int>> recus = <Map<int, int>>[];
      final StreamSubscription<Map<int, int>> abonnement = notes.observerNombrePiecesJointesParNote().listen(recus.add);
      addTearDown(abonnement.cancel);
      await pumpEventQueue();
      expect(recus.last, isEmpty);

      await notes.modifier(note.id, titre: 'Poncho', ajouts: <PieceRangee>[await ranger('a.pdf'), await ranger('b.pdf')]);
      await pumpEventQueue();
      expect(recus.last, <int, int>{note.id: 2});

      await notes.supprimer(note.id);
      await pumpEventQueue();
      expect(recus.last, isEmpty);
    });
  });
}
