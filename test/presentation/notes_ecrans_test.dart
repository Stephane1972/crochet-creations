import 'dart:async';
import 'dart:io';

import 'package:crochet_creations/core/router/app_routes.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/stockage/ouvreur_piece_jointe.dart';
import 'package:crochet_creations/data/stockage/selecteur_piece_jointe.dart';
import 'package:crochet_creations/data/stockage/stockage_pieces_jointes.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/pieces_jointes.dart';
import 'package:crochet_creations/presentation/more/more_screen.dart';
import 'package:crochet_creations/presentation/notes/categories_note_screen.dart';
import 'package:crochet_creations/presentation/notes/note_form_screen.dart';
import 'package:crochet_creations/presentation/notes/notes_screen.dart';
import 'package:crochet_creations/presentation/notes/pieces_jointes_section.dart';
import 'package:crochet_creations/presentation/settings/settings_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_widget.dart';

// Grand et haut : toute la page tient à l'écran, sans faire défiler.
const Size _grandEcran = Size(1000, 3000);

Finder dansNotes(Finder cible) => find.descendant(of: find.byType(NotesScreen), matching: cible);
Finder dansCategories(Finder cible) => find.descendant(of: find.byType(CategoriesNoteScreen), matching: cible);
Finder dansFormulaire(Finder cible) => find.descendant(of: find.byType(NoteFormScreen), matching: cible);
Finder dansDialogue(Finder cible) => find.descendant(of: find.byType(AlertDialog), matching: cible);
Finder dansFeuille(Finder cible) => find.descendant(of: find.byType(BottomSheet), matching: cible);

Finder puce(String libelle) => dansNotes(find.widgetWithText(ChoiceChip, libelle));
Finder boutonEnregistrer() => find.widgetWithText(TextButton, 'Enregistrer');
Finder boutonDeplacer() => dansDialogue(find.widgetWithText(FilledButton, 'Déplacer et supprimer'));

Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.tap(cible);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
  await tester.pumpAndSettle();
}

/// Attend qu'un élément apparaisse (le temps que la base réponde), puis laisse finir les animations.
Future<void> attendreAffichage(WidgetTester tester, Finder cible) async {
  await attendreJusqua(tester, () => cible.evaluate().isNotEmpty);
  expect(cible, findsWidgets, reason: 'Élément attendu : $cible');
  await tester.pumpAndSettle();
}

/// Attend la fin du chargement de l'écran courant (plus de roue de progression).
Future<void> attendreChargement(WidgetTester tester) async {
  await attendreJusqua(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

Future<void> saisirNom(WidgetTester tester, String texte) async {
  await tester.enterText(dansDialogue(find.byType(TextField)), texte);
  await tester.pump();
}

String texteDuChamp(WidgetTester tester, String libelle) {
  final TextFormField champ = tester.widget(find.widgetWithText(TextFormField, libelle));
  return champ.controller!.text;
}

/// Ouvre une route par-dessus l'accueil, comme le ferait un appui dans l'application.
Future<void> ouvrirRoute(WidgetTester tester, String route, {Object? arguments}) async {
  final NavigatorState navigateur = Navigator.of(tester.element(find.byType(NavigationBar)));
  unawaited(navigateur.pushNamed(route, arguments: arguments));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
}

/// Onglet Plus → Bloc-notes.
Future<void> ouvrirBlocNotes(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Plus'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Bloc-notes')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
  expect(find.byType(NotesScreen), findsOneWidget);
  await attendreChargement(tester);
}

/// Onglet Plus → Réglages → Catégories de notes.
Future<void> ouvrirCategoriesNote(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirAccueil(tester, env, taille: _grandEcran);
  await tester.tap(ongletNav('Plus'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text('Réglages')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);

  await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Catégories de notes')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await laisserFinir(tester);
  expect(find.byType(CategoriesNoteScreen), findsOneWidget);
  await attendreChargement(tester);
}

/// Attend que le formulaire d'une note soit prêt : champs affichés, catégories chargées (« … » disparu).
Future<void> attendreFormulaire(WidgetTester tester) async {
  await attendreAffichage(tester, find.widgetWithText(TextFormField, 'Titre *'));
  await attendreJusqua(tester, () => dansFormulaire(find.text('…')).evaluate().isEmpty);
  await tester.pumpAndSettle();
  expect(find.byType(NoteFormScreen), findsOneWidget);
}

/// Bloc-notes → « Nouvelle note » : le formulaire est ouvert et prêt.
Future<void> ouvrirNouvelleNote(WidgetTester tester, EnvironnementTest env) async {
  await ouvrirBlocNotes(tester, env);
  await toucher(tester, find.text('Nouvelle note'));
  await attendreFormulaire(tester);
}

/// Bloc-notes → un appui sur la note [titre] : le formulaire est ouvert, rempli.
Future<void> ouvrirLaNote(WidgetTester tester, EnvironnementTest env, String titre) async {
  await ouvrirBlocNotes(tester, env);
  await attendreAffichage(tester, dansNotes(find.text(titre)));
  await toucher(tester, dansNotes(find.text(titre)));
  await attendreFormulaire(tester);
}

Future<CategorieNote> categorieNommee(WidgetTester tester, EnvironnementTest env, String nom) async {
  final List<CategorieNote> toutes = await env.travailler(tester, () => env.categoriesNote.lister());
  return toutes.firstWhere((CategorieNote c) => c.nom == nom);
}

Future<Note> creerNote(
  WidgetTester tester,
  EnvironnementTest env, {
  required String titre,
  String contenu = '',
  String? categorie,
}) async {
  final int? categorieId = categorie == null ? null : (await categorieNommee(tester, env, categorie)).id;
  return env.travailler(tester, () => env.notes.creer(titre: titre, contenu: contenu, categorieId: categorieId));
}

Future<List<Note>> notesEnBase(WidgetTester tester, EnvironnementTest env) =>
    env.travailler(tester, () => env.notes.lister());

/// Ouvre la feuille « Catégorie » du formulaire.
Future<void> ouvrirFeuilleCategorie(WidgetTester tester) async {
  await toucher(tester, find.text('Catégorie de la note'));
  expect(find.byType(BottomSheet), findsOneWidget);
}

/// La coche de la feuille : le nom de la catégorie actuellement choisie.
Finder cocheSur(String nom) =>
    find.descendant(of: dansFeuille(find.widgetWithText(ListTile, nom)), matching: find.byIcon(Icons.check));

/// Une pièce jointe déjà rangée dans le téléphone (comme après un ajout enregistré).
Future<PieceRangee> rangerPiece(WidgetTester tester, EnvironnementTest env, String nom, {int octets = 2048}) {
  return env.travailler(
    tester,
    () => env.stockagePiecesJointes.enregistrer(
      FichierChoisi(
        nom: nom,
        type: typePieceJointeDepuisNom(nom),
        octets: octets,
        lire: () => Stream<List<int>>.value(List<int>.filled(octets, 1)),
      ),
    ),
  );
}

Future<Note> creerNoteAvecPieces(
  WidgetTester tester,
  EnvironnementTest env,
  String titre,
  List<PieceRangee> pieces,
) => env.travailler(tester, () => env.notes.creer(titre: titre, piecesJointes: pieces));

/// Les noms des fichiers rangés dans le dossier des pièces jointes (lecture directe, sans attendre).
List<String> fichiersRanges(EnvironnementTest env) {
  final Directory dossier = env.dossierPiecesJointes;
  if (!dossier.existsSync()) return <String>[];
  return dossier
      .listSync()
      .map((FileSystemEntity e) => e.uri.pathSegments.where((String s) => s.isNotEmpty).last)
      .toList()
    ..sort();
}

Finder boutonAjouterPiece() => find.byKey(const Key('ajouter-piece-jointe'));

/// Appuie sur « Ajouter une pièce jointe », puis sur [choix] dans la feuille.
Future<void> ajouterPiece(WidgetTester tester, String choix) async {
  await toucher(tester, boutonAjouterPiece());
  expect(find.byType(BottomSheet), findsOneWidget);
  // Pas de pumpAndSettle ici : pendant la copie du fichier, la roue de « Ajout en cours… » tourne sans fin.
  await tester.tap(dansFeuille(find.text(choix)));
  await tester.pump();
  await laisserFinir(tester);
}

void main() {
  // ---------------------------------------------------------------------------
  // La liste des notes
  // ---------------------------------------------------------------------------

  group('liste', () {
    testWidgets('Plus mène au bloc-notes : vide, il invite à écrire la première note', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirBlocNotes(tester, env);

      expect(dansNotes(find.text('Aucune note pour le moment.')), findsOneWidget);
      expect(dansNotes(find.text('Appuyez sur « Nouvelle note » pour écrire la première.')), findsOneWidget);
      // Les filtres : Toutes, les deux catégories de départ, Sans catégorie.
      for (final String nom in <String>['Toutes', 'Futures commandes', 'Documents entreprise', 'Sans catégorie']) {
        expect(puce(nom), findsOneWidget, reason: nom);
      }

      await env.fermer(tester);
    });

    testWidgets('chaque note montre son titre, un aperçu du texte, sa catégorie et sa date', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(
        tester,
        env,
        titre: 'Doudou pour Léa',
        contenu: 'Lapin rose, 30 cm',
        categorie: 'Futures commandes',
      );
      await creerNote(tester, env, titre: 'Idée de bonnet');
      await ouvrirBlocNotes(tester, env);
      await attendreAffichage(tester, dansNotes(find.text('Doudou pour Léa')));

      expect(dansNotes(find.text('Lapin rose, 30 cm')), findsOneWidget);
      expect(dansNotes(find.textContaining('Futures commandes · modifiée le ')), findsOneWidget);
      expect(dansNotes(find.text('Idée de bonnet')), findsOneWidget);
      expect(dansNotes(find.textContaining('Sans catégorie · modifiée le ')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('la note modifiée en dernier est en tête de liste', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Première');
      final Note deuxieme = await creerNote(tester, env, titre: 'Deuxième');
      await env.travailler(tester, () async {
        await (env.db.update(env.db.notes)..where((t) => t.id.equals(deuxieme.id))).write(
          NotesCompanion(modifieLe: Value(DateTime(2026, 1, 1))),
        );
      });
      await ouvrirBlocNotes(tester, env);
      await attendreAffichage(tester, dansNotes(find.text('Première')));

      final double hautPremiere = tester.getTopLeft(dansNotes(find.text('Première'))).dy;
      final double hautDeuxieme = tester.getTopLeft(dansNotes(find.text('Deuxième'))).dy;
      expect(hautPremiere, lessThan(hautDeuxieme));

      await env.fermer(tester);
    });
  });

  group('filtres', () {
    testWidgets('une catégorie, « Sans catégorie », puis « Toutes » : on ne voit que les notes concernées', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
      await creerNote(tester, env, titre: 'Statuts de l’entreprise', categorie: 'Documents entreprise');
      await creerNote(tester, env, titre: 'Idée de bonnet');
      await ouvrirBlocNotes(tester, env);
      await attendreAffichage(tester, dansNotes(find.text('Doudou pour Léa')));

      // « Toutes » par défaut.
      expect(dansNotes(find.text('Statuts de l’entreprise')), findsOneWidget);
      expect(dansNotes(find.text('Idée de bonnet')), findsOneWidget);

      await toucher(tester, puce('Futures commandes'));
      expect(dansNotes(find.text('Doudou pour Léa')), findsOneWidget);
      expect(dansNotes(find.text('Statuts de l’entreprise')), findsNothing);
      expect(dansNotes(find.text('Idée de bonnet')), findsNothing);

      await toucher(tester, puce('Sans catégorie'));
      expect(dansNotes(find.text('Idée de bonnet')), findsOneWidget);
      expect(dansNotes(find.text('Doudou pour Léa')), findsNothing);

      await toucher(tester, puce('Toutes'));
      expect(dansNotes(find.text('Doudou pour Léa')), findsOneWidget);
      expect(dansNotes(find.text('Statuts de l’entreprise')), findsOneWidget);
      expect(dansNotes(find.text('Idée de bonnet')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('une catégorie sans note, ou aucune note sans catégorie : l’écran le dit', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
      await ouvrirBlocNotes(tester, env);
      await attendreAffichage(tester, dansNotes(find.text('Doudou pour Léa')));

      await toucher(tester, puce('Documents entreprise'));
      expect(dansNotes(find.text('Aucune note dans « Documents entreprise ».')), findsOneWidget);
      expect(dansNotes(find.text('Doudou pour Léa')), findsNothing);

      await toucher(tester, puce('Sans catégorie'));
      expect(dansNotes(find.text('Aucune note sans catégorie.')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('une catégorie créée apparaît parmi les filtres', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirBlocNotes(tester, env);

      await env.travailler(tester, () => env.categoriesNote.creer('Modèles à essayer'));
      await attendreAffichage(tester, puce('Modèles à essayer'));

      await env.fermer(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // Créer, modifier, supprimer une note
  // ---------------------------------------------------------------------------

  group('nouvelle note', () {
    testWidgets('titre, texte et catégorie sont enregistrés, et la note apparaît dans la liste', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final CategorieNote futures = await categorieNommee(tester, env, 'Futures commandes');
      await ouvrirNouvelleNote(tester, env);
      expect(dansFormulaire(find.text('Nouvelle note')), findsOneWidget);
      expect(dansFormulaire(find.text('Sans catégorie')), findsOneWidget);

      await saisir(tester, 'Titre *', '  Doudou   pour Léa ');
      await saisir(tester, 'Texte', 'Lapin rose\n30 cm');
      await ouvrirFeuilleCategorie(tester);
      await toucher(tester, dansFeuille(find.text('Futures commandes')));
      expect(find.byType(BottomSheet), findsNothing);
      expect(dansFormulaire(find.text('Futures commandes')), findsOneWidget);

      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Note enregistrée.'));

      expect(find.byType(NoteFormScreen), findsNothing);
      await attendreAffichage(tester, dansNotes(find.text('Doudou pour Léa')));
      final Note note = (await notesEnBase(tester, env)).single;
      expect(note.titre, 'Doudou pour Léa');
      expect(note.contenu, 'Lapin rose\n30 cm');
      expect(note.categorieId, futures.id);

      await env.fermer(tester);
    });

    testWidgets('seul le titre est obligatoire : la note est « Sans catégorie » et sans texte', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await saisir(tester, 'Titre *', 'Idée de bonnet');
      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Note enregistrée.'));

      final Note note = (await notesEnBase(tester, env)).single;
      expect(note.titre, 'Idée de bonnet');
      expect(note.contenu, '');
      expect(note.categorieId, isNull);

      await env.fermer(tester);
    });

    testWidgets('un titre vide, ou fait d’espaces, est refusé : rien n’est enregistré', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await saisir(tester, 'Texte', 'Un texte sans titre');
      await toucher(tester, boutonEnregistrer());
      expect(find.text('Donnez un titre à la note.'), findsOneWidget);
      expect(find.text('Corrigez les champs signalés en rouge.'), findsOneWidget);

      await saisir(tester, 'Titre *', '    ');
      await toucher(tester, boutonEnregistrer());
      expect(find.text('Donnez un titre à la note.'), findsOneWidget);

      expect(find.byType(NoteFormScreen), findsOneWidget);
      expect(await notesEnBase(tester, env), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('un titre de plus de 120 caractères est refusé', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await saisir(tester, 'Titre *', 'a' * 121);
      await toucher(tester, boutonEnregistrer());

      expect(find.text('Le titre d’une note est limité à 120 caractères.'), findsOneWidget);
      expect(await notesEnBase(tester, env), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('« Nouvelle catégorie » dans la feuille crée la catégorie et la choisit aussitôt', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await saisir(tester, 'Titre *', 'Modèle de pull');
      await ouvrirFeuilleCategorie(tester);
      await toucher(tester, dansFeuille(find.text('Nouvelle catégorie')));
      expect(find.byType(AlertDialog), findsOneWidget);
      await saisirNom(tester, '  Modèles   à essayer ');
      await toucher(tester, dansDialogue(find.text('Créer')));

      // La feuille se ferme et la nouvelle catégorie est celle de la note.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(dansFormulaire(find.text('Modèles à essayer')), findsOneWidget);

      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Note enregistrée.'));
      final CategorieNote modeles = await categorieNommee(tester, env, 'Modèles à essayer');
      expect((await notesEnBase(tester, env)).single.categorieId, modeles.id);

      await env.fermer(tester);
    });

    testWidgets('la feuille coche la catégorie choisie ; un nom refusé laisse la boîte ouverte', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await ouvrirFeuilleCategorie(tester);
      expect(cocheSur('Sans catégorie'), findsOneWidget);
      expect(cocheSur('Futures commandes'), findsNothing);

      await toucher(tester, dansFeuille(find.text('Nouvelle catégorie')));
      await saisirNom(tester, 'futures commandes');
      await toucher(tester, dansDialogue(find.text('Créer')));
      expect(find.text('Une catégorie « Futures commandes » existe déjà.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Annuler')));
      expect(await env.travailler(tester, () => env.categoriesNote.lister()), hasLength(2));

      await env.fermer(tester);
    });

    testWidgets('quitter une saisie demande confirmation : rien n’est enregistré si on abandonne', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await saisir(tester, 'Titre *', 'Doudou pour Léa');

      // On choisit de continuer la saisie.
      await retourArriere(tester);
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteFormScreen), findsOneWidget);
      expect(texteDuChamp(tester, 'Titre *'), 'Doudou pour Léa');

      // On abandonne.
      await retourArriere(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteFormScreen), findsNothing);
      expect(await notesEnBase(tester, env), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('sans rien saisir, on quitte sans confirmation', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await retourArriere(tester);

      expect(find.text('Abandonner les modifications ?'), findsNothing);
      expect(find.byType(NoteFormScreen), findsNothing);

      await env.fermer(tester);
    });
  });

  group('modifier une note', () {
    testWidgets('le formulaire montre la note ; titre, texte et catégorie se modifient', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final CategorieNote documents = await categorieNommee(tester, env, 'Documents entreprise');
      await creerNote(
        tester,
        env,
        titre: 'Devis mercerie',
        contenu: 'À envoyer mercredi',
        categorie: 'Futures commandes',
      );
      await ouvrirLaNote(tester, env, 'Devis mercerie');

      expect(dansFormulaire(find.text('Modifier la note')), findsOneWidget);
      expect(texteDuChamp(tester, 'Titre *'), 'Devis mercerie');
      expect(texteDuChamp(tester, 'Texte'), 'À envoyer mercredi');
      expect(dansFormulaire(find.text('Futures commandes')), findsOneWidget);

      await saisir(tester, 'Titre *', 'Devis mercerie du Port');
      await saisir(tester, 'Texte', 'Envoyé le mercredi');
      await ouvrirFeuilleCategorie(tester);
      expect(cocheSur('Futures commandes'), findsOneWidget);
      await toucher(tester, dansFeuille(find.text('Documents entreprise')));
      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Modifications enregistrées.'));

      expect(find.byType(NoteFormScreen), findsNothing);
      await attendreAffichage(tester, dansNotes(find.text('Devis mercerie du Port')));
      final Note note = (await notesEnBase(tester, env)).single;
      expect(note.titre, 'Devis mercerie du Port');
      expect(note.contenu, 'Envoyé le mercredi');
      expect(note.categorieId, documents.id);

      await env.fermer(tester);
    });

    testWidgets('on peut retirer la catégorie : « Sans catégorie »', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Devis mercerie', categorie: 'Futures commandes');
      await ouvrirLaNote(tester, env, 'Devis mercerie');

      await ouvrirFeuilleCategorie(tester);
      await toucher(tester, dansFeuille(find.text('Sans catégorie')));
      expect(dansFormulaire(find.text('Sans catégorie')), findsOneWidget);
      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Modifications enregistrées.'));

      expect((await notesEnBase(tester, env)).single.categorieId, isNull);

      await env.fermer(tester);
    });

    testWidgets('changer seulement la catégorie compte comme une modification : quitter demande confirmation', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Devis mercerie');
      await ouvrirLaNote(tester, env, 'Devis mercerie');

      await ouvrirFeuilleCategorie(tester);
      await toucher(tester, dansFeuille(find.text('Futures commandes')));
      await retourArriere(tester);

      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteFormScreen), findsNothing);
      expect((await notesEnBase(tester, env)).single.categorieId, isNull);

      await env.fermer(tester);
    });

    testWidgets('une note qui n’existe plus est signalée', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirAccueil(tester, env, taille: _grandEcran);

      await ouvrirRoute(tester, AppRoutes.noteModifier, arguments: 999);
      await attendreAffichage(tester, find.text('Cette note n’existe plus.'));
      expect(find.widgetWithText(TextButton, 'Enregistrer'), findsNothing);

      await env.fermer(tester);
    });
  });

  group('supprimer une note', () {
    testWidgets('une confirmation, puis la note disparaît (et elle seule)', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
      await creerNote(tester, env, titre: 'Idée de bonnet', categorie: 'Futures commandes');
      await ouvrirLaNote(tester, env, 'Doudou pour Léa');

      await toucher(tester, find.byTooltip('Plus d’actions'));
      await toucher(tester, find.text('Supprimer la note'));
      expect(find.text('Supprimer cette note ?'), findsOneWidget);
      expect(dansDialogue(find.textContaining('« Doudou pour Léa » sera supprimée définitivement')), findsOneWidget);
      await toucher(tester, dansDialogue(find.text('Supprimer')));
      await attendreAffichage(tester, find.text('Note supprimée.'));

      expect(find.byType(NoteFormScreen), findsNothing);
      final List<Note> restantes = await notesEnBase(tester, env);
      expect(restantes.map((Note n) => n.titre), <String>['Idée de bonnet']);
      expect(dansNotes(find.text('Doudou pour Léa')), findsNothing);
      expect(dansNotes(find.text('Idée de bonnet')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('annuler la confirmation ne supprime rien', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Doudou pour Léa');
      await ouvrirLaNote(tester, env, 'Doudou pour Léa');

      await toucher(tester, find.byTooltip('Plus d’actions'));
      await toucher(tester, find.text('Supprimer la note'));
      await toucher(tester, dansDialogue(find.text('Annuler')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NoteFormScreen), findsOneWidget);
      expect(await notesEnBase(tester, env), hasLength(1));

      await env.fermer(tester);
    });

    testWidgets('on ne propose pas de supprimer une note qu’on est en train de créer', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      expect(find.byTooltip('Plus d’actions'), findsNothing);

      await env.fermer(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // Les catégories de notes
  // ---------------------------------------------------------------------------

  group('catégories de notes', () {
    testWidgets('Réglages mène aux deux catégories de départ, avec leur nombre de notes', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
      await creerNote(tester, env, titre: 'Bonnet pour Max', categorie: 'Futures commandes');
      await creerNote(tester, env, titre: 'Idée en vrac'); // sans catégorie : comptée nulle part
      await ouvrirCategoriesNote(tester, env);

      expect(dansCategories(find.text('Futures commandes')), findsOneWidget);
      expect(dansCategories(find.text('Documents entreprise')), findsOneWidget);
      await attendreAffichage(tester, dansCategories(find.text('2 notes')));
      expect(dansCategories(find.text('Aucune note')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('l’icône « Catégories de notes » du bloc-notes ouvre cet écran', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirBlocNotes(tester, env);

      await toucher(tester, find.byTooltip('Catégories de notes'));

      expect(find.byType(CategoriesNoteScreen), findsOneWidget);
      expect(dansCategories(find.text('Futures commandes')), findsOneWidget);

      await env.fermer(tester);
    });

    group('ajouter', () {
      testWidgets('une nouvelle catégorie apparaît à la fin de la liste', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        await ouvrirCategoriesNote(tester, env);

        await toucher(tester, find.text('Nouvelle catégorie'));
        expect(find.byType(AlertDialog), findsOneWidget);
        await saisirNom(tester, '  Modèles   à essayer ');
        await toucher(tester, dansDialogue(find.text('Créer')));

        expect(find.byType(AlertDialog), findsNothing);
        expect(dansCategories(find.text('Modèles à essayer')), findsOneWidget);
        expect(find.text('Catégorie « Modèles à essayer » créée.'), findsOneWidget);
        final List<CategorieNote> toutes = await env.travailler(tester, () => env.categoriesNote.lister());
        expect(toutes, hasLength(3));
        expect(toutes.last.nom, 'Modèles à essayer');

        await env.fermer(tester);
      });

      testWidgets('un nom vide, réservé ou déjà pris est expliqué dans la boîte, qui reste ouverte', (
        WidgetTester tester,
      ) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        await ouvrirCategoriesNote(tester, env);

        await toucher(tester, find.text('Nouvelle catégorie'));
        await toucher(tester, dansDialogue(find.text('Créer')));
        expect(find.text('Donnez un nom à la catégorie de notes.'), findsOneWidget);

        await saisirNom(tester, 'sans categorie');
        await toucher(tester, dansDialogue(find.text('Créer')));
        expect(
          find.text('« Sans catégorie » désigne une note sans catégorie : choisissez un autre nom.'),
          findsOneWidget,
        );

        // Ni les majuscules ni les accents ne font une autre catégorie.
        await saisirNom(tester, 'DOCUMENTS entreprise');
        await toucher(tester, dansDialogue(find.text('Créer')));
        expect(find.text('Une catégorie « Documents entreprise » existe déjà.'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);

        await toucher(tester, dansDialogue(find.text('Annuler')));
        expect(find.byType(AlertDialog), findsNothing);
        expect(await env.travailler(tester, () => env.categoriesNote.lister()), hasLength(2));

        await env.fermer(tester);
      });
    });

    group('renommer', () {
      testWidgets('le nouveau nom s’affiche, les notes restent dans la catégorie', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        final CategorieNote futures = await categorieNommee(tester, env, 'Futures commandes');
        final Note note = await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
        await ouvrirCategoriesNote(tester, env);

        await toucher(tester, find.byTooltip('Renommer Futures commandes'));
        expect(tester.widget<TextField>(dansDialogue(find.byType(TextField))).controller!.text, 'Futures commandes');
        await saisirNom(tester, 'Commandes à venir');
        await toucher(tester, dansDialogue(find.text('Enregistrer')));

        expect(dansCategories(find.text('Commandes à venir')), findsOneWidget);
        expect(dansCategories(find.text('Futures commandes')), findsNothing);
        expect(find.text('Catégorie renommée « Commandes à venir ».'), findsOneWidget);
        await attendreAffichage(tester, dansCategories(find.text('1 note')));
        final Note apres = (await notesEnBase(tester, env)).single;
        expect(apres.id, note.id);
        expect(apres.categorieId, futures.id);
        expect((await categorieNommee(tester, env, 'Commandes à venir')).id, futures.id);

        await env.fermer(tester);
      });

      testWidgets('le nom d’une autre catégorie est refusé', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        await ouvrirCategoriesNote(tester, env);

        await toucher(tester, find.byTooltip('Renommer Documents entreprise'));
        await saisirNom(tester, 'futures commandes');
        await toucher(tester, dansDialogue(find.text('Enregistrer')));

        expect(find.text('Une catégorie « Futures commandes » existe déjà.'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect((await categorieNommee(tester, env, 'Documents entreprise')).nom, 'Documents entreprise');

        await env.fermer(tester);
      });
    });

    group('supprimer', () {
      testWidgets('une catégorie sans note : une confirmation, puis elle disparaît', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        await ouvrirCategoriesNote(tester, env);

        await toucher(tester, find.byTooltip('Supprimer Documents entreprise'));
        expect(find.text('Supprimer cette catégorie ?'), findsOneWidget);
        await toucher(tester, dansDialogue(find.text('Supprimer')));

        expect(dansCategories(find.text('Documents entreprise')), findsNothing);
        expect(find.text('Catégorie « Documents entreprise » supprimée.'), findsOneWidget);
        expect(await env.travailler(tester, () => env.categoriesNote.lister()), hasLength(1));

        await env.fermer(tester);
      });

      testWidgets('annuler la confirmation ne supprime rien', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        await ouvrirCategoriesNote(tester, env);

        await toucher(tester, find.byTooltip('Supprimer Documents entreprise'));
        await toucher(tester, dansDialogue(find.text('Annuler')));

        expect(dansCategories(find.text('Documents entreprise')), findsOneWidget);
        expect(await env.travailler(tester, () => env.categoriesNote.lister()), hasLength(2));

        await env.fermer(tester);
      });

      testWidgets('avec des notes : on choisit où les déplacer, et elles y vont (aucune n’est supprimée)', (
        WidgetTester tester,
      ) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        final CategorieNote documents = await categorieNommee(tester, env, 'Documents entreprise');
        await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
        await creerNote(tester, env, titre: 'Bonnet pour Max', categorie: 'Futures commandes');
        await creerNote(tester, env, titre: 'Statuts', categorie: 'Documents entreprise');
        await ouvrirCategoriesNote(tester, env);
        await attendreAffichage(tester, dansCategories(find.text('2 notes')));

        await toucher(tester, find.byTooltip('Supprimer Futures commandes'));
        expect(dansDialogue(find.textContaining('contient 2 notes')), findsOneWidget);

        // Rien n'est présélectionné : le bouton attend un choix.
        expect(tester.widget<FilledButton>(boutonDeplacer()).onPressed, isNull);
        // La catégorie qu'on supprime ne fait pas partie des destinations ; « Sans catégorie » en fait partie.
        expect(dansDialogue(find.text('Futures commandes')), findsNothing);
        expect(dansDialogue(find.text('Sans catégorie')), findsOneWidget);
        expect(dansDialogue(find.text('Les notes n’auront plus de catégorie')), findsOneWidget);

        await tester.tap(dansDialogue(find.text('Documents entreprise')));
        await tester.pump();
        expect(tester.widget<FilledButton>(boutonDeplacer()).onPressed, isNotNull);
        await toucher(tester, boutonDeplacer());

        expect(dansCategories(find.text('Futures commandes')), findsNothing);
        expect(
          find.text('Catégorie « Futures commandes » supprimée. 2 notes déplacées vers « Documents entreprise ».'),
          findsOneWidget,
        );
        await attendreAffichage(tester, dansCategories(find.text('3 notes')));
        final List<Note> notes = await notesEnBase(tester, env);
        expect(notes, hasLength(3));
        expect(notes.every((Note n) => n.categorieId == documents.id), isTrue);

        await env.fermer(tester);
      });

      testWidgets('on peut garder les notes « Sans catégorie »', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        await creerNote(
          tester,
          env,
          titre: 'Statuts',
          contenu: 'Association loi 1901',
          categorie: 'Documents entreprise',
        );
        await ouvrirCategoriesNote(tester, env);
        await attendreAffichage(tester, dansCategories(find.text('1 note')));

        await toucher(tester, find.byTooltip('Supprimer Documents entreprise'));
        expect(dansDialogue(find.textContaining('contient 1 note')), findsOneWidget);
        await tester.tap(dansDialogue(find.text('Sans catégorie')));
        await tester.pump();
        await toucher(tester, boutonDeplacer());

        expect(dansCategories(find.text('Documents entreprise')), findsNothing);
        expect(
          find.text('Catégorie « Documents entreprise » supprimée. 1 note déplacée vers « Sans catégorie ».'),
          findsOneWidget,
        );
        final Note note = (await notesEnBase(tester, env)).single;
        expect(note.categorieId, isNull);
        expect(note.titre, 'Statuts');
        expect(note.contenu, 'Association loi 1901');

        await env.fermer(tester);
      });

      testWidgets('annuler le choix de la destination ne change rien', (WidgetTester tester) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        final CategorieNote futures = await categorieNommee(tester, env, 'Futures commandes');
        await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
        await ouvrirCategoriesNote(tester, env);
        await attendreAffichage(tester, dansCategories(find.text('1 note')));

        await toucher(tester, find.byTooltip('Supprimer Futures commandes'));
        await toucher(tester, dansDialogue(find.text('Annuler')));

        expect(dansCategories(find.text('Futures commandes')), findsOneWidget);
        expect((await notesEnBase(tester, env)).single.categorieId, futures.id);

        await env.fermer(tester);
      });

      testWidgets('la dernière catégorie qu’on supprime : ses notes passent « Sans catégorie »', (
        WidgetTester tester,
      ) async {
        final EnvironnementTest env = await EnvironnementTest.creer(tester);
        final CategorieNote documents = await categorieNommee(tester, env, 'Documents entreprise');
        await env.travailler(tester, () => env.categoriesNote.supprimer(documents.id));
        await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
        await ouvrirCategoriesNote(tester, env);
        await attendreAffichage(tester, dansCategories(find.text('1 note')));

        await toucher(tester, find.byTooltip('Supprimer Futures commandes'));
        // Aucune autre catégorie : seul « Sans catégorie » est proposé.
        await tester.tap(dansDialogue(find.text('Sans catégorie')));
        await tester.pump();
        await toucher(tester, boutonDeplacer());

        expect(dansCategories(find.textContaining('Aucune catégorie')), findsOneWidget);
        expect((await notesEnBase(tester, env)).single.categorieId, isNull);

        await env.fermer(tester);
      });
    });

    testWidgets('sans aucune catégorie, l’écran invite à en créer une', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      for (final CategorieNote c in await env.travailler(tester, () => env.categoriesNote.lister())) {
        await env.travailler(tester, () => env.categoriesNote.supprimer(c.id));
      }
      await ouvrirCategoriesNote(tester, env);

      expect(dansCategories(find.textContaining('Aucune catégorie')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('la catégorie choisie comme filtre est supprimée : la liste revient à « Toutes »', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNote(tester, env, titre: 'Doudou pour Léa', categorie: 'Futures commandes');
      await creerNote(tester, env, titre: 'Idée de bonnet');
      await ouvrirBlocNotes(tester, env);
      await attendreAffichage(tester, dansNotes(find.text('Doudou pour Léa')));

      await toucher(tester, puce('Documents entreprise'));
      expect(dansNotes(find.text('Aucune note dans « Documents entreprise ».')), findsOneWidget);

      await toucher(tester, find.byTooltip('Catégories de notes'));
      await toucher(tester, find.byTooltip('Supprimer Documents entreprise'));
      await toucher(tester, dansDialogue(find.text('Supprimer')));
      await retourArriere(tester);

      expect(find.byType(NotesScreen), findsOneWidget);
      expect(puce('Documents entreprise'), findsNothing);
      expect(dansNotes(find.text('Doudou pour Léa')), findsOneWidget);
      expect(dansNotes(find.text('Idée de bonnet')), findsOneWidget);

      await env.fermer(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // Les pièces jointes
  // ---------------------------------------------------------------------------

  group('pièces jointes', () {
    testWidgets('le formulaire annonce les limites avant tout ajout', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      expect(dansFormulaire(find.text('Pièces jointes')), findsOneWidget);
      expect(dansFormulaire(find.text('Ajouter une pièce jointe')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('limites-pieces-jointes'))).data,
        'Photos et documents : 25 Mo au plus chacun. Vidéos : 150 Mo au plus. 20 pièces jointes au plus par note.',
      );

      // La feuille de choix rappelle les limites aussi.
      await toucher(tester, boutonAjouterPiece());
      expect(dansFeuille(find.text('Prendre une photo')), findsOneWidget);
      expect(dansFeuille(find.text('Choisir une photo dans la galerie')), findsOneWidget);
      expect(dansFeuille(find.text('Filmer une vidéo')), findsOneWidget);
      expect(dansFeuille(find.text('Choisir une vidéo dans la galerie')), findsOneWidget);
      expect(dansFeuille(find.text('Choisir un document (PDF, Word, tableur…)')), findsOneWidget);
      expect(dansFeuille(find.textContaining('150 Mo au plus')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('joindre un document : il est copié dans le téléphone, et enregistré avec la note', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);
      env.selecteurPieceJointe.preparer('Patron poncho.pdf', TypePieceJointe.document, octets: 2048);

      await ajouterPiece(tester, 'Choisir un document (PDF, Word, tableur…)');
      await attendreAffichage(tester, dansFormulaire(find.text('Patron poncho.pdf')));

      expect(env.selecteurPieceJointe.sources, <SourcePieceJointe>[SourcePieceJointe.document]);
      expect(dansFormulaire(find.text('Document · 2 Ko')), findsOneWidget);
      expect(dansFormulaire(find.text('Pièces jointes (1 sur 20)')), findsOneWidget);
      expect(fichiersRanges(env), hasLength(1)); // déjà copié, pas encore dans la note

      await saisir(tester, 'Titre *', 'Poncho');
      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Note enregistrée.'));

      final Note note = (await notesEnBase(tester, env)).single;
      final List<PieceJointeNote> pieces = await env.travailler(tester, () => env.notes.listerPiecesJointes(note.id));
      expect(pieces, hasLength(1));
      expect(pieces.single.nomAffiche, 'Patron poncho.pdf');
      expect(pieces.single.typeFichier, TypePieceJointe.document);
      expect(pieces.single.octets, 2048);
      expect(fichiersRanges(env), <String>[pieces.single.nomFichier]);
      expect(env.dossierPiecesJointes.uri.pathSegments, contains('notes_pieces_jointes'));
      await attendreAffichage(tester, dansNotes(find.text('1 pièce jointe')));

      await env.fermer(tester);
    });

    testWidgets('photo de la galerie, vidéo de la galerie : le bon type est retenu', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      env.selecteurPieceJointe.preparer('Modèle.jpg', TypePieceJointe.photo);
      await ajouterPiece(tester, 'Choisir une photo dans la galerie');
      await attendreAffichage(tester, dansFormulaire(find.text('Modèle.jpg')));
      env.selecteurPieceJointe.preparer('Tuto.mp4', TypePieceJointe.video);
      await ajouterPiece(tester, 'Choisir une vidéo dans la galerie');
      await attendreAffichage(tester, dansFormulaire(find.text('Tuto.mp4')));

      expect(env.selecteurPieceJointe.sources, <SourcePieceJointe>[
        SourcePieceJointe.photoGalerie,
        SourcePieceJointe.videoGalerie,
      ]);
      expect(dansFormulaire(find.text('Photo · 100 o')), findsOneWidget);
      expect(dansFormulaire(find.text('Vidéo · 100 o')), findsOneWidget);
      expect(dansFormulaire(find.text('Pièces jointes (2 sur 20)')), findsOneWidget);

      await env.fermer(tester);
    });

    testWidgets('un fichier trop gros est refusé avec la limite, et rien n’est copié', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      env.selecteurPieceJointe.preparer('Gros.jpg', TypePieceJointe.photo, octets: 26 * 1024 * 1024);
      await ajouterPiece(tester, 'Choisir une photo dans la galerie');
      await attendreAffichage(tester, find.textContaining('la limite est de 25 Mo pour les photos'));
      expect(dansFormulaire(find.text('Gros.jpg')), findsNothing);

      env.selecteurPieceJointe.preparer('Film.mp4', TypePieceJointe.video, octets: 151 * 1024 * 1024);
      await ajouterPiece(tester, 'Choisir une vidéo dans la galerie');
      await attendreAffichage(tester, find.textContaining('la limite est de 150 Mo pour les vidéos'));
      expect(dansFormulaire(find.text('Film.mp4')), findsNothing);

      env.selecteurPieceJointe.preparer('Gros.pdf', TypePieceJointe.document, octets: 26 * 1024 * 1024);
      await ajouterPiece(tester, 'Choisir un document (PDF, Word, tableur…)');
      await attendreAffichage(tester, find.textContaining('la limite est de 25 Mo pour les documents'));

      expect(dansFormulaire(find.text('Pièces jointes')), findsOneWidget); // toujours aucune
      expect(fichiersRanges(env), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('annuler le choix du fichier n’ajoute rien et ne dit rien', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);

      await ajouterPiece(tester, 'Prendre une photo'); // le faux sélecteur annule (aucun fichier préparé)

      expect(env.selecteurPieceJointe.sources, <SourcePieceJointe>[SourcePieceJointe.photoAppareil]);
      expect(find.byType(SnackBar), findsNothing);
      expect(dansFormulaire(find.text('Pièces jointes')), findsOneWidget);
      expect(fichiersRanges(env), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('20 pièces jointes au plus : un 21e ajout est refusé avant même de choisir un fichier', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final List<PieceRangee> vingt = <PieceRangee>[
        for (int i = 0; i < 20; i++) await rangerPiece(tester, env, 'f$i.pdf', octets: 10),
      ];
      await creerNoteAvecPieces(tester, env, 'Pleine', vingt);
      await ouvrirLaNote(tester, env, 'Pleine');

      expect(dansFormulaire(find.text('Pièces jointes (20 sur 20)')), findsOneWidget);
      await toucher(tester, boutonAjouterPiece());

      expect(find.byType(BottomSheet), findsNothing);
      await attendreAffichage(tester, find.text('Une note peut avoir 20 pièces jointes au plus.'));
      expect(env.selecteurPieceJointe.sources, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('retirer une pièce jointe enregistrée : elle n’est effacée du téléphone qu’à « Enregistrer »', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final PieceRangee patron = await rangerPiece(tester, env, 'Patron.pdf');
      final PieceRangee photo = await rangerPiece(tester, env, 'Modèle.jpg');
      await creerNoteAvecPieces(tester, env, 'Poncho', <PieceRangee>[patron, photo]);
      await ouvrirLaNote(tester, env, 'Poncho');

      expect(dansFormulaire(find.text('Patron.pdf')), findsOneWidget);
      expect(dansFormulaire(find.text('Modèle.jpg')), findsOneWidget);
      await toucher(tester, find.byTooltip('Retirer cette pièce jointe').first);

      expect(dansFormulaire(find.text('Patron.pdf')), findsNothing);
      expect(dansFormulaire(find.text('Modèle.jpg')), findsOneWidget);
      expect(dansFormulaire(find.text('Pièces jointes (1 sur 20)')), findsOneWidget);
      expect(fichiersRanges(env), hasLength(2)); // rien n'est encore effacé

      await toucher(tester, boutonEnregistrer());
      await attendreAffichage(tester, find.text('Modifications enregistrées.'));
      await attendreJusqua(tester, () => fichiersRanges(env).length == 1);

      final Note note = (await notesEnBase(tester, env)).single;
      final List<PieceJointeNote> pieces = await env.travailler(tester, () => env.notes.listerPiecesJointes(note.id));
      expect(pieces.map((PieceJointeNote p) => p.nomAffiche), <String>['Modèle.jpg']);
      expect(fichiersRanges(env), <String>[photo.nomFichier]);

      await env.fermer(tester);
    });

    testWidgets('retirer une pièce jointe qu’on vient d’ajouter efface aussitôt sa copie', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await ouvrirNouvelleNote(tester, env);
      env.selecteurPieceJointe.preparer('Modèle.jpg', TypePieceJointe.photo);
      await ajouterPiece(tester, 'Choisir une photo dans la galerie');
      await attendreAffichage(tester, dansFormulaire(find.text('Modèle.jpg')));
      expect(fichiersRanges(env), hasLength(1));

      await toucher(tester, find.byTooltip('Retirer cette pièce jointe'));
      await attendreJusqua(tester, () => fichiersRanges(env).isEmpty);

      expect(dansFormulaire(find.text('Modèle.jpg')), findsNothing);
      expect(fichiersRanges(env), isEmpty);

      await env.fermer(tester);
    });

    testWidgets('abandonner la note efface les copies des pièces ajoutées, et seulement elles', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final PieceRangee existante = await rangerPiece(tester, env, 'Patron.pdf');
      await creerNoteAvecPieces(tester, env, 'Poncho', <PieceRangee>[existante]);
      await ouvrirLaNote(tester, env, 'Poncho');
      env.selecteurPieceJointe.preparer('Nouvelle.jpg', TypePieceJointe.photo);
      await ajouterPiece(tester, 'Choisir une photo dans la galerie');
      await attendreAffichage(tester, dansFormulaire(find.text('Nouvelle.jpg')));
      expect(fichiersRanges(env), hasLength(2));

      await retourArriere(tester);
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
      await tester.pumpAndSettle();
      await attendreJusqua(tester, () => fichiersRanges(env).length == 1);

      expect(find.byType(NoteFormScreen), findsNothing);
      expect(fichiersRanges(env), <String>[existante.nomFichier]);
      final Note note = (await notesEnBase(tester, env)).single;
      expect(await env.travailler(tester, () => env.notes.listerPiecesJointes(note.id)), hasLength(1));

      await env.fermer(tester);
    });

    testWidgets('un document ou une vidéo s’ouvre dans l’application du téléphone ; sans application, on le dit', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final PieceRangee patron = await rangerPiece(tester, env, 'Patron.pdf');
      final PieceRangee tuto = await rangerPiece(tester, env, 'Tuto.mp4');
      await creerNoteAvecPieces(tester, env, 'Poncho', <PieceRangee>[patron, tuto]);
      await ouvrirLaNote(tester, env, 'Poncho');

      await toucher(tester, dansFormulaire(find.text('Patron.pdf')));
      expect(env.ouvreurPieceJointe.ouverts, <String>[patron.nomFichier]);
      expect(find.byType(SnackBar), findsNothing);

      env.ouvreurPieceJointe.resultat = ResultatOuverture.aucuneApplication;
      await toucher(tester, dansFormulaire(find.text('Tuto.mp4')));
      await attendreAffichage(tester, find.text('Aucune application du téléphone ne sait ouvrir ce fichier.'));
      expect(env.ouvreurPieceJointe.ouverts, <String>[patron.nomFichier, tuto.nomFichier]);

      env.ouvreurPieceJointe.resultat = ResultatOuverture.introuvable;
      await toucher(tester, dansFormulaire(find.text('Patron.pdf')));
      await attendreAffichage(tester, find.text('Ce fichier est introuvable sur le téléphone.'));

      env.ouvreurPieceJointe.resultat = ResultatOuverture.echec;
      await toucher(tester, dansFormulaire(find.text('Patron.pdf')));
      await attendreAffichage(tester, find.text('Impossible d’ouvrir ce fichier.'));

      await env.fermer(tester);
    });

    testWidgets('une photo s’affiche en plein écran dans l’application, sans autre application', (
      WidgetTester tester,
    ) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final PieceRangee photo = await rangerPiece(tester, env, 'Modèle.jpg');
      await creerNoteAvecPieces(tester, env, 'Poncho', <PieceRangee>[photo]);
      await ouvrirLaNote(tester, env, 'Poncho');

      await toucher(tester, dansFormulaire(find.text('Modèle.jpg')));

      expect(find.byType(PhotoJointeScreen), findsOneWidget);
      expect(find.descendant(of: find.byType(PhotoJointeScreen), matching: find.text('Modèle.jpg')), findsOneWidget);
      expect(env.ouvreurPieceJointe.ouverts, isEmpty);

      await env.fermer(tester);
    });

    testWidgets('la liste des notes montre le nombre de pièces jointes de chacune', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      await creerNoteAvecPieces(tester, env, 'Poncho', <PieceRangee>[
        await rangerPiece(tester, env, 'a.pdf'),
        await rangerPiece(tester, env, 'b.jpg'),
      ]);
      await creerNoteAvecPieces(tester, env, 'Bonnet', <PieceRangee>[await rangerPiece(tester, env, 'c.mp4')]);
      await creerNote(tester, env, titre: 'Idée seule');
      await ouvrirBlocNotes(tester, env);

      await attendreAffichage(tester, dansNotes(find.text('2 pièces jointes')));
      expect(dansNotes(find.text('1 pièce jointe')), findsOneWidget);
      expect(dansNotes(find.textContaining('pièce')), findsNWidgets(2)); // la note sans pièce jointe n'en parle pas

      await env.fermer(tester);
    });

    testWidgets('supprimer la note supprime aussi ses pièces jointes, dans le téléphone', (WidgetTester tester) async {
      final EnvironnementTest env = await EnvironnementTest.creer(tester);
      final PieceRangee piece = await rangerPiece(tester, env, 'Patron.pdf');
      final PieceRangee autre = await rangerPiece(tester, env, 'Autre.pdf');
      await creerNoteAvecPieces(tester, env, 'À supprimer', <PieceRangee>[piece]);
      await creerNoteAvecPieces(tester, env, 'À garder', <PieceRangee>[autre]);
      await ouvrirLaNote(tester, env, 'À supprimer');

      await toucher(tester, find.byTooltip('Plus d’actions'));
      await toucher(tester, find.text('Supprimer la note'));
      await toucher(tester, dansDialogue(find.text('Supprimer')));
      await attendreAffichage(tester, find.text('Note supprimée.'));
      await attendreJusqua(tester, () => fichiersRanges(env).length == 1);

      expect(fichiersRanges(env), <String>[autre.nomFichier]);
      expect((await notesEnBase(tester, env)).map((Note n) => n.titre), <String>['À garder']);

      await env.fermer(tester);
    });
  });
}
