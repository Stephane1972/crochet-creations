import 'dart:io';

import 'package:crochet_creations/app.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/providers.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/stockage/selecteur_photo.dart';
import 'package:crochet_creations/data/stockage/stockage_photos.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/splash/splash_screen.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux appareil photo : choisit toujours le fichier [chemin] (ou annule si `null`).
class FauxSelecteurPhoto implements SelecteurPhoto {
  String? chemin;
  int appels = 0;

  @override
  Future<String?> choisir(SourcePhoto source) async {
    appels++;
    return chemin;
  }
}

/// Tout ce qu'il faut pour tester des écrans : base en mémoire, dossier de photos temporaire,
/// faux sélecteur de photo.
class EnvironnementTest {
  EnvironnementTest._(this.db, this.dossier) : produits = ProduitRepository(db, NumerotationRepository(db));

  final AppDatabase db;
  final Directory dossier;
  final ProduitRepository produits;
  final FauxSelecteurPhoto selecteur = FauxSelecteurPhoto();

  static Future<EnvironnementTest> creer(WidgetTester tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // « closeStreamsSynchronously » : sans cela, la base garde un minuteur après le test.
    final AppDatabase db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    final Directory dossier = (await tester.runAsync(() => Directory.systemTemp.createTemp('crochet_test_')))!;
    return EnvironnementTest._(db, dossier);
  }

  Directory get dossierPhotos => Directory('${dossier.path}/photos_produits');

  List<Override> get overrides => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    stockagePhotosProvider.overrideWithValue(StockagePhotos(dossierPhotos)),
    selecteurPhotoProvider.overrideWithValue(selecteur),
  ];

  /// Exécute un travail « réel » (base, fichiers) hors du temps simulé du test.
  Future<T> travailler<T>(WidgetTester tester, Future<T> Function() action) async {
    final T? resultat = await tester.runAsync<T>(action);
    return resultat as T;
  }

  /// Crée une « photo de la galerie » et retourne son chemin.
  Future<String> photoGalerie(WidgetTester tester, String nom) {
    return travailler(tester, () async {
      final File f = File('${dossier.path}/$nom');
      await f.writeAsString('image');
      return f.path;
    });
  }

  /// Enregistre une vente contenant ce produit.
  Future<void> ajouterVente(
    WidgetTester tester, {
    required int produitId,
    int quantite = 1,
    int prix = 2500,
    DateTime? date,
    String designation = 'Doudou lapin',
  }) {
    return travailler(tester, () async {
      final int venteId = await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              sousTotalCentimes: prix * quantite,
              totalCentimes: prix * quantite,
              dateVente: date == null ? const Value.absent() : Value(date),
            ),
          );
      await db
          .into(db.lignesVente)
          .insert(
            LignesVenteCompanion.insert(
              venteId: venteId,
              designation: designation,
              quantite: quantite,
              prixUnitaireCentimes: prix,
              totalLigneCentimes: prix * quantite,
              produitId: Value(produitId),
            ),
          );
    });
  }

  /// Crée un produit (hors temps simulé).
  Future<Produit> creerProduit(
    WidgetTester tester, {
    String nom = 'Doudou lapin',
    CategorieProduit categorie = CategorieProduit.doudou,
    int prix = 2500,
    int stock = 5,
    int seuil = 2,
    StatutProduit statut = StatutProduit.disponible,
    String? matieres,
    String? photo,
  }) {
    return travailler(
      tester,
      () => produits.creer(
        DonneesProduit(
          nom: nom,
          categorie: categorie,
          prixVenteCentimes: prix,
          quantiteStock: stock,
          seuilAlerteStock: seuil,
          statut: statut,
          matieres: matieres,
          photoPrincipaleChemin: photo,
        ),
      ),
    );
  }

  /// Libère la base et le dossier temporaire (à appeler en fin de test).
  Future<void> fermer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      if (await dossier.exists()) await dossier.delete(recursive: true);
    });
  }
}

/// Laisse le temps aux lectures de la base (et aux copies de fichiers) de se terminer,
/// puis redessine l'écran.
Future<void> laisserFinir(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Démarre l'application, attend la fin du splash et arrive sur l'accueil.
Future<void> ouvrirAccueil(
  WidgetTester tester,
  EnvironnementTest env, {
  Size taille = const Size(800, 1600),
}) async {
  // Écran haut, comme un téléphone : évite de faire défiler dans les tests.
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(overrides: env.overrides, child: const CrochetApp()));
  expect(find.text('Crochet & Créations'), findsOneWidget); // splash

  await tester.pump(SplashScreen.duree + const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

Finder ongletNav(String libelle) {
  return find.descendant(of: find.byType(NavigationBar), matching: find.text(libelle));
}

/// Appuie sur un élément en le faisant défiler à l'écran au besoin, puis laisse finir les animations.
Future<void> appuyer(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pumpAndSettle();
  await tester.tap(cible);
  await tester.pumpAndSettle();
  await laisserFinir(tester);
}

/// Saisit un texte dans le champ portant ce libellé.
Future<void> saisir(WidgetTester tester, String libelle, String texte) async {
  final Finder champ = find.widgetWithText(TextFormField, libelle);
  await tester.ensureVisible(champ);
  await tester.pumpAndSettle();
  await tester.enterText(champ, texte);
  await tester.pump();
}

/// Appuie sur la flèche « retour » de la barre du haut. (`tester.pageBack()` cherche l'info-bulle
/// anglaise « Back » : elle est « Retour » dans l'application, qui est en français.)
Future<void> retourArriere(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}
