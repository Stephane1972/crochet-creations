import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/theme/theme_mode_provider.dart';
import 'data/database/app_database.dart';
import 'data/providers.dart';
import 'data/repositories/parametres_repository.dart';
import 'data/sauvegarde/espace_libre.dart';
import 'data/sauvegarde/service_sauvegarde.dart';
import 'data/stockage/selecteur_photo.dart';
import 'data/stockage/stockage_pdf.dart';
import 'data/stockage/stockage_photos.dart';
import 'data/stockage/stockage_pieces_jointes.dart';
import 'presentation/common/photo_retrouvee.dart';
import 'presentation/startup/erreur_demarrage_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Ouverture de la base avant le premier écran : création ou mise à jour du schéma,
    // puis lecture du mode jour / nuit mémorisé (pas de clignotement au démarrage).
    final AppDatabase base = AppDatabase();
    final ParametresRepository parametres = ParametresRepository(base);
    final ThemeMode modeInitial = await parametres.lireModeTheme();

    // Photos des produits : dossier privé de l'application (créé à la première photo).
    final Directory documents = await getApplicationDocumentsDirectory();
    final StockagePhotos photos = StockagePhotos(
      Directory('${documents.path}${Platform.pathSeparator}photos_produits'),
    );

    // PDF des factures et des devis : même espace privé, un fichier par document.
    final StockagePdf factures = StockagePdf(
      Directory('${documents.path}${Platform.pathSeparator}factures'),
    );
    final StockagePdf devis = StockagePdf(
      Directory('${documents.path}${Platform.pathSeparator}devis'),
    );

    // Pièces jointes des notes (photos, vidéos, documents) : un dossier à part, dans le même espace privé.
    final StockagePiecesJointes piecesJointes = StockagePiecesJointes(
      Directory('${documents.path}${Platform.pathSeparator}notes_pieces_jointes'),
    );

    // Sauvegardes : un dossier à part, et un dossier pour les fichiers d'export avant partage.
    final ServiceSauvegarde sauvegarde = ServiceSauvegarde(
      base: base,
      dossierSauvegardes: Directory('${documents.path}${Platform.pathSeparator}sauvegardes'),
      dossierExports: Directory('${documents.path}${Platform.pathSeparator}exports'),
      dossierPhotos: photos.dossier,
      dossierFactures: factures.dossier,
      dossierDevis: devis.dossier,
      dossierPiecesJointes: piecesJointes.dossier,
      espaceLibre: const ControleEspaceLibreSysteme(),
    );

    // Photo prise juste avant qu'Android ferme l'application (rare) : retrouvée une seule fois, ici, puis proposée
    // dans la feuille de choix de photo.
    final String? photoRetrouvee = await SelecteurPhotoSysteme().retrouverPhotoPerdue();

    runApp(
      ProviderScope(
        overrides: [
          photoRetrouveeInitialeProvider.overrideWithValue(photoRetrouvee),
          appDatabaseProvider.overrideWithValue(base),
          stockagePhotosProvider.overrideWithValue(photos),
          stockageFacturesProvider.overrideWithValue(factures),
          stockageDevisProvider.overrideWithValue(devis),
          stockagePiecesJointesProvider.overrideWithValue(piecesJointes),
          serviceSauvegardeProvider.overrideWithValue(sauvegarde),
          modeThemeInitialProvider.overrideWithValue(modeInitial),
          modeThemeStoreProvider.overrideWithValue(parametres),
        ],
        child: const CrochetApp(),
      ),
    );

    // Sauvegarde automatique : si la dernière date d'un jour ou plus. En arrière-plan, après l'affichage du
    // premier écran : elle ne retarde pas le démarrage, et un échec ne gêne jamais l'utilisation.
    unawaited(_sauvegardeAutomatique(sauvegarde));
  } catch (erreur, pile) {
    debugPrint('Ouverture de la base impossible : $erreur\n$pile');
    runApp(ErreurDemarrageApp(erreur: erreur));
  }
}

Future<void> _sauvegardeAutomatique(ServiceSauvegarde sauvegarde) async {
  try {
    await sauvegarde.sauvegarderAutomatiquementSiBesoin();
  } catch (erreur, pile) {
    debugPrint('Sauvegarde automatique impossible : $erreur\n$pile');
  }
}
