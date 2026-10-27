import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crochet_creations/app.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/providers.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/devis_repository.dart';
import 'package:crochet_creations/data/repositories/facture_repository.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/data/partage/service_documents.dart';
import 'package:crochet_creations/data/stockage/selecteur_photo.dart';
import 'package:crochet_creations/data/stockage/stockage_pdf.dart';
import 'package:crochet_creations/data/stockage/stockage_photos.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/document_devis.dart';
import 'package:crochet_creations/domain/document_facture.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/presentation/factures/factures_providers.dart';
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

/// Faux fabricant de PDF : rapide, sans polices ni logo. Garde les documents reçus pour que les tests
/// vérifient ce qui serait imprimé ; peut être réglé pour échouer.
class FauxGenerateurPdf {
  final List<DocumentFacture> documents = <DocumentFacture>[];
  bool echouer = false;

  DocumentFacture? get dernier => documents.isEmpty ? null : documents.last;

  Future<Uint8List> call(DocumentFacture document) async {
    documents.add(document);
    if (echouer) throw StateError('Fabrication du PDF impossible.');
    return Uint8List.fromList(utf8.encode('%PDF-FAUX ${document.numero}'));
  }
}

/// Faux fabricant de PDF de devis : comme [FauxGenerateurPdf], pour les devis.
class FauxGenerateurDevisPdf {
  final List<DocumentDevis> documents = <DocumentDevis>[];
  bool echouer = false;

  DocumentDevis? get dernier => documents.isEmpty ? null : documents.last;

  Future<Uint8List> call(DocumentDevis document) async {
    documents.add(document);
    if (echouer) throw StateError('Fabrication du PDF impossible.');
    return Uint8List.fromList(utf8.encode('%PDF-FAUX ${document.numero}'));
  }
}

/// Faux partage et fausse impression : gardent ce qui serait envoyé à Android (feuille de partage,
/// dialogue d'impression), qu'un test ne peut pas ouvrir.
class FauxServiceDocuments implements ServiceDocuments {
  /// « nom du fichier | sujet » de chaque partage.
  final List<String> partages = <String>[];
  final List<String> cheminsPartages = <String>[];

  /// « nom du document : contenu du PDF » de chaque impression.
  final List<String> impressions = <String>[];

  @override
  Future<void> partager({
    required String cheminFichier,
    required String nomFichier,
    required String sujet,
  }) async {
    cheminsPartages.add(cheminFichier);
    partages.add('$nomFichier | $sujet');
  }

  @override
  Future<void> imprimer({required Uint8List octets, required String nomDocument}) async {
    impressions.add('$nomDocument : ${utf8.decode(octets)}');
  }
}

/// Tout ce qu'il faut pour tester des écrans : base en mémoire, dossiers de photos et de factures
/// temporaires, faux sélecteur de photo, faux fabricant de PDF.
class EnvironnementTest {
  EnvironnementTest._(this.db, this.dossier)
    : produits = ProduitRepository(db, NumerotationRepository(db)),
      clients = ClientRepository(db);

  final AppDatabase db;
  final Directory dossier;
  final ProduitRepository produits;
  final ClientRepository clients;
  late final VenteRepository ventes = VenteRepository(db, produits);
  late final ParametresRepository parametres = ParametresRepository(db);
  final FauxSelecteurPhoto selecteur = FauxSelecteurPhoto();
  final FauxGenerateurPdf generateurPdf = FauxGenerateurPdf();
  final FauxServiceDocuments documents = FauxServiceDocuments();
  final FauxGenerateurDevisPdf generateurDevisPdf = FauxGenerateurDevisPdf();
  late final StockagePdf stockageFactures = StockagePdf(dossierFactures);
  late final StockagePdf stockageDevis = StockagePdf(dossierDevis);
  late final FactureRepository factures = FactureRepository(
    db,
    NumerotationRepository(db),
    parametres,
    stockageFactures,
    generateurPdf.call,
  );
  late final DevisRepository devis = DevisRepository(
    db,
    NumerotationRepository(db),
    ventes,
    factures,
    parametres,
    stockageDevis,
    generateurDevisPdf.call,
  );

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
  Directory get dossierFactures => Directory('${dossier.path}/factures');
  Directory get dossierDevis => Directory('${dossier.path}/devis');

  List<Override> get overrides => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    stockagePhotosProvider.overrideWithValue(StockagePhotos(dossierPhotos)),
    selecteurPhotoProvider.overrideWithValue(selecteur),
    stockageFacturesProvider.overrideWithValue(stockageFactures),
    stockageDevisProvider.overrideWithValue(stockageDevis),
    generateurFacturePdfProvider.overrideWithValue(generateurPdf.call),
    generateurDevisPdfProvider.overrideWithValue(generateurDevisPdf.call),
    serviceDocumentsProvider.overrideWithValue(documents),
    // L'aperçu réel rasterise le PDF avec le moteur d'impression d'Android : ici, on en affiche le texte.
    constructeurApercuPdfProvider.overrideWithValue(
      (BuildContext context, Uint8List pdf, String nomFichier) => Center(child: Text('Aperçu : ${utf8.decode(pdf)}')),
    ),
  ];

  /// Exécute un travail « réel » (base, fichiers) hors du temps simulé du test.
  Future<T> travailler<T>(WidgetTester tester, Future<T> Function() action) async {
    final T? resultat = await tester.runAsync<T>(action);
    return resultat as T;
  }

  /// Écrit dans la base **pendant qu'un écran qui la lit « en direct » est affiché**.
  ///
  /// Le travail s'exécute dans le temps simulé du test, comme un enregistrement fait depuis
  /// l'application : les écrans ouverts se mettent alors à jour tout seuls. Le faire avec
  /// [travailler] (hors temps simulé) bloquait le test (verrou de la base pris par une lecture en
  /// direct qui attend le temps simulé) ou n'actualisait pas l'écran.
  Future<T> ecrireEcranOuvert<T>(WidgetTester tester, Future<T> Function() action) async {
    bool fini = false;
    T? resultat;
    Object? erreur;
    StackTrace? pile;
    unawaited(
      action().then(
        (T valeur) {
          resultat = valeur;
          fini = true;
        },
        onError: (Object e, StackTrace p) {
          erreur = e;
          pile = p;
          fini = true;
        },
      ),
    );
    for (int i = 0; i < 40 && !fini; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (!fini) fail('L’écriture dans la base n’est pas terminée.');
    if (erreur != null) Error.throwWithStackTrace(erreur!, pile!);
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

  Future<T> _faire<T>(WidgetTester tester, Future<T> Function() action, {required bool ecranOuvert}) {
    return ecranOuvert ? ecrireEcranOuvert(tester, action) : travailler(tester, action);
  }

  /// Crée un client (hors temps simulé, sauf si [ecranOuvert] : voir [ecrireEcranOuvert]).
  Future<Client> creerClient(WidgetTester tester, DonneesClient donnees, {bool ecranOuvert = false}) {
    return _faire(tester, () => clients.creer(donnees), ecranOuvert: ecranOuvert);
  }

  /// Enregistre une vente (sans ligne) au nom de ce client, avec son paiement si [paiement] est donné.
  /// [ecranOuvert] : voir [ecrireEcranOuvert].
  Future<int> ajouterVenteClient(
    WidgetTester tester, {
    required int clientId,
    int total = 2500,
    DateTime? date,
    StatutVente statut = StatutVente.validee,
    ModePaiement? paiement,
    bool ecranOuvert = false,
  }) {
    return _faire(tester, () async {
      final int venteId = await db
          .into(db.ventes)
          .insert(
            VentesCompanion.insert(
              sousTotalCentimes: total,
              totalCentimes: total,
              clientId: Value(clientId),
              dateVente: date == null ? const Value.absent() : Value(date),
              statut: Value(statut),
            ),
          );
      if (paiement != null) {
        await db
            .into(db.paiements)
            .insert(
              PaiementsCompanion.insert(
                venteId: venteId,
                montantCentimes: total,
                modePaiement: paiement,
                datePaiement: date == null ? const Value.absent() : Value(date),
              ),
            );
      }
      return venteId;
    }, ecranOuvert: ecranOuvert);
  }

  /// Valide une vente de ce produit (hors temps simulé), au nom du client si [clientId] est donné,
  /// avec un paiement du total si [paiement] est donné. À faire **avant** d'ouvrir l'application.
  Future<Vente> validerVente(
    WidgetTester tester, {
    required Produit produit,
    int quantite = 1,
    int? clientId,
    ModePaiement? paiement,
  }) {
    return travailler(
      tester,
      () => ventes.valider(
        clientId: clientId,
        panier: const Panier().ajouter(
          produitId: produit.id,
          designation: produit.nom,
          prixUnitaireCentimes: produit.prixVenteCentimes,
          quantite: quantite,
          stockDisponible: produit.quantiteStock,
        ),
        paiement: paiement == null
            ? null
            : PaiementSaisi(mode: paiement, montantCentimes: produit.prixVenteCentimes * quantite),
      ),
    );
  }

  /// Crée un devis (hors temps simulé, sauf si [ecranOuvert] : voir [ecrireEcranOuvert]) : une couverture
  /// sur mesure à [prix] centimes, valable 30 jours par défaut. À faire **avant** d'ouvrir l'application.
  Future<DevisFiche> creerDevis(
    WidgetTester tester, {
    int? clientId,
    String designation = 'Couverture bébé sur mesure',
    int prix = 6000,
    int quantite = 1,
    int acompte = 0,
    DateTime? validite,
    String? delai,
    bool ecranOuvert = false,
  }) {
    return _faire(
      tester,
      () => devis.creer(
        DevisSaisi(
          clientId: clientId,
          panier: const Panier().ajouter(
            designation: designation,
            nature: NatureLigne.service,
            prixUnitaireCentimes: prix,
            quantite: quantite,
          ),
          dateValidite: validite ?? DateTime.now().add(const Duration(days: 30)),
          delaiRealisation: delai,
          acompteCentimes: acompte,
        ),
      ),
      ecranOuvert: ecranOuvert,
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

/// Fait avancer le temps simulé, en laissant la base travailler, jusqu'à ce que [condition] soit
/// vraie (au plus [essais] tours). Utile quand un écran se met à jour après une chaîne de lectures
/// de la base (l'historique d'un client en enchaîne sept) : huit tours de [laisserFinir] ne suffisent pas.
Future<void> attendreJusqua(WidgetTester tester, bool Function() condition, {int essais = 200}) async {
  for (int i = 0; i < essais && !condition(); i++) {
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
