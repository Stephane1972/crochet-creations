import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/categorie_note_repository.dart';
import 'package:crochet_creations/data/repositories/note_repository.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late CategorieNoteRepository categories;
  late NoteRepository notes;

  setUp(() {
    db = creerBaseEnMemoire();
    categories = CategorieNoteRepository(db);
    notes = NoteRepository(db);
  });
  tearDown(() => db.close());

  Matcher refus(String morceau) =>
      throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains(morceau)));

  Future<List<String>> noms() async => (await categories.lister()).map((CategorieNote c) => c.nom).toList();

  Future<CategorieNote> parNom(String nom) async =>
      (await categories.lister()).firstWhere((CategorieNote c) => c.nom == nom);

  group('lister', () {
    test('une base neuve a les deux catégories de départ, dans l’ordre', () async {
      expect(await noms(), <String>['Futures commandes', 'Documents entreprise']);
    });

    test('obtenir retrouve une catégorie, ou rien', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      expect((await categories.obtenir(futures.id))!.nom, 'Futures commandes');
      expect(await categories.obtenir(999), isNull);
    });

    test('le nombre de notes par catégorie ignore les notes sans catégorie', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      final CategorieNote documents = await parNom('Documents entreprise');
      await notes.creer(titre: 'Doudou pour Léa', categorieId: futures.id);
      await notes.creer(titre: 'Bonnet pour Max', categorieId: futures.id);
      await notes.creer(titre: 'Statuts', categorieId: documents.id);
      await notes.creer(titre: 'Idée en vrac'); // sans catégorie : dans aucune catégorie

      expect(await categories.nombreNotesParCategorie(), <int, int>{futures.id: 2, documents.id: 1});
      expect(await categories.nombreNotes(futures.id), 2);
      expect(await categories.nombreNotes((await categories.creer('Vide')).id), 0);
    });

    test('observer envoie la liste mise à jour après un ajout', () async {
      final Stream<List<CategorieNote>> flux = categories.observer();
      final Future<void> verification = expectLater(
        flux.map((List<CategorieNote> l) => l.length),
        emitsThrough(3),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await categories.creer('Modèles à essayer');
      await verification;
    });

    test('observerNombreNotesParCategorie suit les notes en direct', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      final Stream<Map<int, int>> flux = categories.observerNombreNotesParCategorie();
      final Future<void> verification = expectLater(
        flux.map((Map<int, int> m) => m[futures.id] ?? 0),
        emitsThrough(1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notes.creer(titre: 'Doudou pour Léa', categorieId: futures.id);
      await verification;
    });
  });

  group('créer', () {
    test('la nouvelle catégorie passe en dernier', () async {
      final CategorieNote modeles = await categories.creer('  Modèles   à essayer ');
      expect(modeles.nom, 'Modèles à essayer');
      expect(await noms(), <String>['Futures commandes', 'Documents entreprise', 'Modèles à essayer']);
      expect(modeles.position, greaterThan((await parNom('Documents entreprise')).position));
    });

    test('refuse un nom vide, trop long ou réservé', () async {
      await expectLater(categories.creer('   '), refus('Donnez un nom'));
      await expectLater(categories.creer('a' * 61), refus('limité à 60'));
      await expectLater(categories.creer('Sans catégorie'), refus('note sans catégorie'));
      expect(await noms(), hasLength(2));
    });

    test('refuse un nom déjà pris, sans tenir compte des majuscules, des accents ni des espaces', () async {
      await expectLater(categories.creer('futures COMMANDES'), refus('« Futures commandes » existe déjà'));
      await expectLater(categories.creer(' documents  entreprise '), refus('existe déjà'));
      expect(await noms(), hasLength(2));
    });

    test('après avoir supprimé toutes les catégories, on repart de zéro', () async {
      for (final CategorieNote c in await categories.lister()) {
        await categories.supprimer(c.id);
      }
      expect(await categories.lister(), isEmpty);
      final CategorieNote premiere = await categories.creer('Idées');
      expect(premiere.position, 0);
    });
  });

  group('renommer', () {
    test('change le nom sans toucher aux notes : elles gardent la même catégorie', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      final Note note = await notes.creer(titre: 'Doudou pour Léa', categorieId: futures.id);

      final CategorieNote renommee = await categories.renommer(futures.id, '  Commandes   à venir ');
      expect(renommee.id, futures.id);
      expect(renommee.nom, 'Commandes à venir');
      expect((await notes.obtenir(note.id))!.categorieId, futures.id);
    });

    test('une catégorie peut garder son nom, ou le changer de casse', () async {
      final CategorieNote documents = await parNom('Documents entreprise');
      expect((await categories.renommer(documents.id, 'Documents entreprise')).nom, 'Documents entreprise');
      expect((await categories.renommer(documents.id, 'DOCUMENTS ENTREPRISE')).nom, 'DOCUMENTS ENTREPRISE');
    });

    test('refuse le nom d’une autre catégorie, un nom invalide ou une catégorie inconnue', () async {
      final CategorieNote documents = await parNom('Documents entreprise');
      await expectLater(categories.renommer(documents.id, 'Futures commandes'), refus('existe déjà'));
      await expectLater(categories.renommer(documents.id, ''), refus('Donnez un nom'));
      await expectLater(categories.renommer(999, 'Autre'), throwsA(isA<ElementIntrouvable>()));
      expect((await parNom('Documents entreprise')).nom, 'Documents entreprise');
    });
  });

  group('supprimer', () {
    test('une catégorie sans note se supprime directement', () async {
      final CategorieNote documents = await parNom('Documents entreprise');
      expect(await categories.supprimer(documents.id), 0);
      expect(await noms(), <String>['Futures commandes']);
    });

    test('une catégorie qui a des notes ne se supprime pas sans destination, et rien ne bouge', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      await notes.creer(titre: 'Doudou pour Léa', categorieId: futures.id);
      await notes.creer(titre: 'Bonnet pour Max', categorieId: futures.id);

      await expectLater(categories.supprimer(futures.id), refus('contient 2 notes'));
      expect(await noms(), contains('Futures commandes'));
      expect(await categories.nombreNotes(futures.id), 2);
    });

    test('une seule note : le message est au singulier', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      await notes.creer(titre: 'Doudou pour Léa', categorieId: futures.id);
      await expectLater(categories.supprimer(futures.id), refus('contient 1 note : choisissez où la déplacer'));
    });

    test('les notes passent dans la catégorie choisie, et rien d’autre ne change (pas même leur date)', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      final CategorieNote documents = await parNom('Documents entreprise');
      final Note a = await notes.creer(titre: 'Doudou pour Léa', contenu: 'Rose', categorieId: futures.id);
      final Note b = await notes.creer(titre: 'Bonnet pour Max', categorieId: futures.id);
      final Note autre = await notes.creer(titre: 'Statuts', categorieId: documents.id);

      expect(await categories.supprimer(futures.id, deplacerVers: DestinationNotes.categorie(documents.id)), 2);

      for (final Note avant in <Note>[a, b]) {
        final Note apres = (await notes.obtenir(avant.id))!;
        expect(apres.categorieId, documents.id);
        expect(apres.titre, avant.titre);
        expect(apres.contenu, avant.contenu);
        expect(apres.modifieLe, avant.modifieLe);
      }
      expect((await notes.obtenir(autre.id))!.categorieId, documents.id);
      expect(await noms(), isNot(contains('Futures commandes')));
      expect(await categories.nombreNotes(documents.id), 3);
    });

    test('ou dans « Sans catégorie » : les notes n’ont plus de catégorie mais existent toujours', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      final Note note = await notes.creer(titre: 'Doudou pour Léa', contenu: 'Rose', categorieId: futures.id);

      expect(await categories.supprimer(futures.id, deplacerVers: const DestinationNotes.sansCategorie()), 1);

      final Note apres = (await notes.obtenir(note.id))!;
      expect(apres.categorieId, isNull);
      expect(apres.titre, 'Doudou pour Léa');
      expect(apres.contenu, 'Rose');
      expect(await db.select(db.notes).get(), hasLength(1));
    });

    test('refuse de déplacer les notes vers la catégorie qu’on supprime ou vers une catégorie inconnue : rien ne bouge', () async {
      final CategorieNote futures = await parNom('Futures commandes');
      final Note note = await notes.creer(titre: 'Doudou pour Léa', categorieId: futures.id);

      await expectLater(
        categories.supprimer(futures.id, deplacerVers: DestinationNotes.categorie(futures.id)),
        refus('autre catégorie'),
      );
      await expectLater(
        categories.supprimer(futures.id, deplacerVers: const DestinationNotes.categorie(999)),
        throwsA(isA<ElementIntrouvable>()),
      );
      expect((await notes.obtenir(note.id))!.categorieId, futures.id);
      expect(await noms(), contains('Futures commandes'));
    });

    test('une catégorie inconnue est signalée', () async {
      await expectLater(categories.supprimer(999), throwsA(isA<ElementIntrouvable>()));
    });
  });
}
