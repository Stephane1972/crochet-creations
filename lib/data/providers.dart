import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/document_devis.dart';
import '../domain/document_facture.dart';
import 'database/app_database.dart';
import 'partage/service_documents.dart';
import 'pdf/devis_pdf.dart';
import 'pdf/facture_pdf.dart';
import 'pdf/ressources_pdf.dart';
import 'repositories/client_repository.dart';
import 'repositories/devis_repository.dart';
import 'repositories/facture_repository.dart';
import 'repositories/numerotation_repository.dart';
import 'repositories/parametres_repository.dart';
import 'repositories/produit_repository.dart';
import 'repositories/vente_repository.dart';
import 'stockage/selecteur_photo.dart';
import 'stockage/stockage_pdf.dart';
import 'stockage/stockage_photos.dart';

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
