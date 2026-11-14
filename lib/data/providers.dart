import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/document_devis.dart';
import '../domain/document_facture.dart';
import 'database/app_database.dart';
import 'drive/compte_google.dart';
import 'drive/service_drive.dart';
import 'partage/service_documents.dart';
import 'partage/service_partage_fichiers.dart';
import 'pdf/devis_pdf.dart';
import 'pdf/facture_pdf.dart';
import 'pdf/ressources_pdf.dart';
import 'repositories/categorie_note_repository.dart';
import 'repositories/categorie_repository.dart';
import 'repositories/client_repository.dart';
import 'repositories/cours_repository.dart';
import 'repositories/depense_repository.dart';
import 'repositories/devis_repository.dart';
import 'repositories/facture_repository.dart';
import 'repositories/lieu_vente_repository.dart';
import 'repositories/note_repository.dart';
import 'repositories/numerotation_repository.dart';
import 'repositories/parametres_repository.dart';
import 'repositories/produit_repository.dart';
import 'repositories/statistiques_repository.dart';
import 'repositories/vente_repository.dart';
import 'sauvegarde/export_csv.dart';
import 'sauvegarde/selecteur_fichier.dart';
import 'sauvegarde/service_sauvegarde.dart';
import 'stockage/ouvreur_piece_jointe.dart';
import 'stockage/selecteur_photo.dart';
import 'stockage/selecteur_piece_jointe.dart';
import 'stockage/stockage_pdf.dart';
import 'stockage/stockage_photos.dart';
import 'stockage/stockage_pieces_jointes.dart';

/// Base de données ouverte par `main()` au démarrage (voir `lib/main.dart`).
/// Les tests la remplacent par une base en mémoire.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

final parametresRepositoryProvider = Provider<ParametresRepository>(
  (ref) => ParametresRepository(ref.watch(appDatabaseProvider)),
);

final numerotationRepositoryProvider = Provider<NumerotationRepository>(
  (ref) => NumerotationRepository(ref.watch(appDatabaseProvider)),
);

final produitRepositoryProvider = Provider<ProduitRepository>(
  (ref) => ProduitRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(numerotationRepositoryProvider),
  ),
);

final categorieRepositoryProvider = Provider<CategorieRepository>(
  (ref) => CategorieRepository(ref.watch(appDatabaseProvider)),
);

final lieuVenteRepositoryProvider = Provider<LieuVenteRepository>(
  (ref) => LieuVenteRepository(ref.watch(appDatabaseProvider)),
);

final categorieNoteRepositoryProvider = Provider<CategorieNoteRepository>(
  (ref) => CategorieNoteRepository(ref.watch(appDatabaseProvider)),
);

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepository(
    ref.watch(appDatabaseProvider),
    stockagePiecesJointes: ref.watch(stockagePiecesJointesProvider),
  ),
);

/// Dossier des pièces jointes des notes, fourni au démarrage (voir `lib/main.dart`).
/// Les tests le remplacent par un dossier temporaire.
final stockagePiecesJointesProvider = Provider<StockagePiecesJointes>((ref) {
  throw UnimplementedError(
    'stockagePiecesJointesProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// Appareil photo, galerie et sélecteur de fichiers, pour joindre un fichier à une note. Les tests le remplacent par
/// un faux sélecteur.
final selecteurPieceJointeProvider = Provider<SelecteurPieceJointe>((ref) => SelecteurPieceJointeSysteme());

/// Ouverture d'une vidéo ou d'un document dans une autre application. Les tests le remplacent par un faux ouvreur.
final ouvreurPieceJointeProvider = Provider<OuvreurPieceJointe>((ref) => const OuvreurPieceJointeSysteme());

final clientRepositoryProvider = Provider<ClientRepository>(
  (ref) => ClientRepository(ref.watch(appDatabaseProvider)),
);

final venteRepositoryProvider = Provider<VenteRepository>(
  (ref) => VenteRepository(ref.watch(appDatabaseProvider), ref.watch(produitRepositoryProvider)),
);

/// Dossier des photos des produits, fourni au démarrage (voir `lib/main.dart`).
/// Les tests le remplacent par un dossier temporaire.
final stockagePhotosProvider = Provider<StockagePhotos>((ref) {
  throw UnimplementedError(
    'stockagePhotosProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// Appareil photo et galerie. Les tests le remplacent par un faux sélecteur.
final selecteurPhotoProvider = Provider<SelecteurPhoto>((ref) => SelecteurPhotoSysteme());

/// Dossier des PDF des factures, fourni au démarrage (voir `lib/main.dart`).
/// Les tests le remplacent par un dossier temporaire.
final stockageFacturesProvider = Provider<StockagePdf>((ref) {
  throw UnimplementedError(
    'stockageFacturesProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// Dossier des PDF des devis, fourni au démarrage (voir `lib/main.dart`).
/// Les tests le remplacent par un dossier temporaire.
final stockageDevisProvider = Provider<StockagePdf>((ref) {
  throw UnimplementedError(
    'stockageDevisProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// Polices et logo des PDF, lus une seule fois dans les ressources de l'application.
final ressourcesPdfProvider = FutureProvider<RessourcesPdf>((ref) => chargerRessourcesPdf());

/// Fabrique le PDF d'une facture. Les tests le remplacent par un générateur rapide, sans ressources.
final generateurFacturePdfProvider = Provider<GenerateurFacturePdf>((ref) {
  return (DocumentFacture document) async {
    final RessourcesPdf ressources = await ref.read(ressourcesPdfProvider.future);
    return genererFacturePdf(document, ressources);
  };
});

final factureRepositoryProvider = Provider<FactureRepository>(
  (ref) => FactureRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(numerotationRepositoryProvider),
    ref.watch(parametresRepositoryProvider),
    ref.watch(stockageFacturesProvider),
    ref.watch(generateurFacturePdfProvider),
  ),
);

/// Partage et impression du PDF (feuille de partage et dialogue d'impression d'Android).
/// Les tests le remplacent par un faux service.
final serviceDocumentsProvider = Provider<ServiceDocuments>((ref) => ServiceDocumentsSysteme());

/// Fabrique le PDF d'un devis. Les tests le remplacent par un générateur rapide, sans ressources.
final generateurDevisPdfProvider = Provider<GenerateurDevisPdf>((ref) {
  return (DocumentDevis document) async {
    final RessourcesPdf ressources = await ref.read(ressourcesPdfProvider.future);
    return genererDevisPdf(document, ressources);
  };
});

final devisRepositoryProvider = Provider<DevisRepository>(
  (ref) => DevisRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(numerotationRepositoryProvider),
    ref.watch(venteRepositoryProvider),
    ref.watch(factureRepositoryProvider),
    ref.watch(parametresRepositoryProvider),
    ref.watch(stockageDevisProvider),
    ref.watch(generateurDevisPdfProvider),
  ),
);

final coursRepositoryProvider = Provider<CoursRepository>(
  (ref) => CoursRepository(ref.watch(appDatabaseProvider), ref.watch(venteRepositoryProvider)),
);

final depenseRepositoryProvider = Provider<DepenseRepository>(
  (ref) => DepenseRepository(ref.watch(appDatabaseProvider)),
);

final statistiquesRepositoryProvider = Provider<StatistiquesRepository>(
  (ref) => StatistiquesRepository(ref.watch(appDatabaseProvider)),
);

/// L'heure « maintenant », dont dépendent les périodes des statistiques (aujourd'hui, cette semaine, ce mois-ci...).
/// Les tests la remplacent par une heure fixe.
final horlogeProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Sauvegarde et restauration, fournies au démarrage (voir `lib/main.dart`).
/// Les tests les remplacent par un service qui travaille dans un dossier temporaire.
final serviceSauvegardeProvider = Provider<ServiceSauvegarde>((ref) {
  throw UnimplementedError(
    'serviceSauvegardeProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// La connexion au compte Google (Google Drive, étape 6 de l'évolution), fournie au démarrage (voir `lib/main.dart`) :
/// la même instance sert à l'écran de connexion et à l'envoi. Les tests la remplacent par une fausse connexion.
final compteGoogleProvider = Provider<CompteGoogle>((ref) {
  throw UnimplementedError(
    'compteGoogleProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// Envoi des fichiers vers Google Drive, à la demande, fourni au démarrage (voir `lib/main.dart`).
/// Les tests le remplacent par un service qui parle à un faux Drive, dans un dossier temporaire.
final serviceDriveProvider = Provider<ServiceDrive>((ref) {
  throw UnimplementedError(
    'serviceDriveProvider doit être fourni au démarrage (overrides du ProviderScope).',
  );
});

/// Export des données en CSV (un .zip, un fichier par type de données).
final exportCsvProvider = Provider<ExportCsv>(
  (ref) => ExportCsv(ref.watch(appDatabaseProvider), horloge: ref.watch(horlogeProvider)),
);

/// Sélecteur de fichiers d'Android, pour restaurer une sauvegarde. Les tests le remplacent par un faux sélecteur.
final selecteurFichierSauvegardeProvider = Provider<SelecteurFichierSauvegarde>(
  (ref) => SelecteurFichierSysteme(),
);

/// Partage d'un fichier (sauvegarde, export) par la feuille de partage d'Android. Les tests le remplacent par
/// un faux service.
final servicePartageFichiersProvider = Provider<ServicePartageFichiers>(
  (ref) => ServicePartageFichiersSysteme(),
);
