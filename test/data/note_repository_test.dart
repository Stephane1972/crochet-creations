import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/categorie_note_repository.dart';
import 'package:crochet_creations/data/repositories/note_repository.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late CategorieNoteRepository categories;

  setUp(() {
    db = creerBaseEnMemoire();
    notes = NoteRepository(db);
    categories = CategorieNoteRepository(db);
  });
  tearDown(() => db.close());

  Matcher refus(String morceau) =>
      throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains(morceau)));

  Future<CategorieNote> categorie(String nom) async =>
      (await categories.lister()).firstWhere((CategorieNote c) => c.nom == nom);

  /// Rend une note « ancienne » (date de modification fixée), pour tester l'ordre sans attendre.
  Future<void> vieillir(int id, DateTime date) async {
    await (db.update(db.notes)..where((t) => t.id.equals(id))).write(NotesCompanion(modifieLe: Value(date)));
  }

  group('créer', () {
    test('enregistre le titre, le texte et la catégorie ; titre et texte sont nettoyés', () async {
      final CategorieNote futures = await categorie('Futures commandes');
      final Note note = await notes.creer(
        titre: '  Doudou   pour Léa ',
        contenu: '\n Lapin rose\n\n30 cm \n',
        categorieId: futures.id,
      );

      expect(note.titre, 'Doudou pour Léa');
      expect(note.contenu, 'Lapin rose\n\n30 cm');
      expect(note.categorieId, futures.id);
      expect((await notes.obtenir(note.id))!.titre, 'Doudou pour Léa');
    });

    test('le texte et la catégorie sont facultatifs : « Sans catégorie » par défaut', () async {
      final Note note = await notes.creer(titre: 'Idée de bonnet');
      expect(note.contenu, '');
      expect(note.categorieId, isNull);
    });

    test('refuse un titre vide ou trop long, et rien n’est enregistré', () async {
      await expectLater(notes.creer(titre: '   ', contenu: 'Du texte'), refus('Donnez un titre'));
      await expectLater(notes.creer(titre: 'a' * 121), refus('limité à 120'));
      expect(await notes.lister(), isEmpty);
    });

    test('refuse une catégorie qui n’existe pas, et rien n’est enregistré', () async {
      await expectLater(notes.creer(titre: 'Orpheline', categorieId: 999), throwsA(isA<ElementIntrouvable>()));
      expect(await notes.lister(), isEmpty);
    });
  });

  group('lister', () {
    test('la note modifiée en dernier est en tête', () async {
      final Note a = await notes.creer(titre: 'A');
      final Note b = await notes.creer(titre: 'B');
      final Note c = await notes.creer(titre: 'C');
      await vieillir(a.id, DateTime(2026, 1, 1));
      await vieillir(b.id, DateTime(2026, 3, 1));
      await vieillir(c.id, DateTime(2026, 2, 1));

      expect((await notes.lister()).map((Note n) => n.titre), <String>['B', 'C', 'A']);
    });

    test('à date égale, la plus récente (créée en dernier) passe devant', () async {
      final DateTime jour = DateTime(2026, 5, 5);
      final Note a = await notes.creer(titre: 'A');
      final Note b = await notes.creer(titre: 'B');
      await vieillir(a.id, jour);
      await vieillir(b.id, jour);
      expect((await notes.lister()).map((Note n) => n.titre), <String>['B', 'A']);
    });

    test('observer envoie la liste mise à jour après un ajout, et observerNote suit une note', () async {
      final Note note = await notes.creer(titre: 'Départ');
      final Future<void> liste = expectLater(
        notes.observer().map((List<Note> l) => l.length),
        emitsThrough(2),
      );
      final Future<void> titres = expectLater(
        notes.observerNote(note.id).map((Note? n) => n?.titre),
        emitsThrough('Modifiée'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notes.creer(titre: 'Deuxième');
      await notes.modifier(note.id, titre: 'Modifiée');
      await liste;
      await titres;
    });

    test('observerNote envoie null quand la note est supprimée', () async {
      final Note note = await notes.creer(titre: 'À supprimer');
      final Future<void> verification = expectLater(notes.observerNote(note.id), emitsThrough(isNull));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notes.supprimer(note.id);
      await verification;
    });
  });

  group('modifier', () {
    test('change le titre, le texte et la catégorie, et la note remonte en tête', () async {
      final CategorieNote futures = await categorie('Futures commandes');
      final CategorieNote documents = await categorie('Documents entreprise');
      final Note a = await notes.creer(titre: 'A', categorieId: futures.id);
      final Note b = await notes.creer(titre: 'B');
      await vieillir(a.id, DateTime(2026, 1, 1));
      await vieillir(b.id, DateTime(2026, 2, 1));

      final Note modifiee = await notes.modifier(
        a.id,
        titre: ' Devis  mercerie ',
        contenu: 'Mercredi',
        categorieId: documents.id,
      );

      expect(modifiee.titre, 'Devis mercerie');
      expect(modifiee.contenu, 'Mercredi');
      expect(modifiee.categorieId, documents.id);
      expect(modifiee.modifieLe.isAfter(DateTime(2026, 2, 1)), isTrue);
      expect((await notes.lister()).first.id, a.id);
    });

    test('on peut retirer la catégorie : la note devient « Sans catégorie »', () async {
      final CategorieNote futures = await categorie('Futures commandes');
      final Note a = await notes.creer(titre: 'A', categorieId: futures.id);
      final Note apres = await notes.modifier(a.id, titre: 'A', categorieId: null);
      expect(apres.categorieId, isNull);
    });

    test('enregistrer sans rien changer ne fait pas remonter la note', () async {
      final CategorieNote futures = await categorie('Futures commandes');
      final Note a = await notes.creer(titre: 'A', contenu: 'Texte', categorieId: futures.id);
      final DateTime ancienne = DateTime(2026, 1, 1);
      await vieillir(a.id, ancienne);

      final Note apres = await notes.modifier(a.id, titre: ' A ', contenu: 'Texte\n', categorieId: futures.id);

      expect(apres.modifieLe, ancienne);
    });

    test('refuse un titre invalide ou une catégorie inconnue : la note ne change pas', () async {
      final Note a = await notes.creer(titre: 'A', contenu: 'Texte');
      await expectLater(notes.modifier(a.id, titre: '', contenu: 'Autre'), refus('Donnez un titre'));
      await expectLater(
        notes.modifier(a.id, titre: 'B', categorieId: 999),
        throwsA(isA<ElementIntrouvable>()),
      );
      final Note intacte = (await notes.obtenir(a.id))!;
      expect(intacte.titre, 'A');
      expect(intacte.contenu, 'Texte');
      expect(intacte.categorieId, isNull);
    });

    test('une note inconnue est signalée', () async {
      await expectLater(notes.modifier(999, titre: 'X'), throwsA(isA<ElementIntrouvable>()));
    });
  });

  group('supprimer', () {
    test('supprime la note, et seulement elle', () async {
      final CategorieNote futures = await categorie('Futures commandes');
      final Note a = await notes.creer(titre: 'A', categorieId: futures.id);
      final Note b = await notes.creer(titre: 'B', categorieId: futures.id);

      await notes.supprimer(a.id);

      expect((await notes.lister()).map((Note n) => n.id), <int>[b.id]);
      expect(await categories.obtenir(futures.id), isNotNull);
    });

    test('une note inconnue est signalée', () async {
      await expectLater(notes.supprimer(999), throwsA(isA<ElementIntrouvable>()));
    });
  });
}
