import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';

/// Toutes les factures, la plus récente d'abord, mises à jour automatiquement.
final facturesProvider = StreamProvider.autoDispose<List<Facture>>(
  (ref) => ref.watch(factureRepositoryProvider).observerListe(),
);

/// Une facture (`null` si elle n'existe pas), mise à jour automatiquement (annulation).
final factureProvider = StreamProvider.autoDispose.family<Facture?, int>(
  (ref, int id) => ref.watch(factureRepositoryProvider).observerFacture(id),
);

/// Le PDF d'une facture (refabriqué s'il n'est plus sur le téléphone).
final facturePdfProvider = FutureProvider.autoDispose.family<Uint8List, int>(
  (ref, int id) => ref.watch(factureRepositoryProvider).obtenirPdf(id),
);

/// Affiche un PDF dans l'écran. Les tests le remplacent : l'aperçu réel rasterise le PDF avec le moteur
/// d'impression d'Android, qui n'existe pas dans un test.
typedef ConstructeurApercuPdf = Widget Function(BuildContext context, Uint8List pdf, String nomFichier);

final constructeurApercuPdfProvider = Provider<ConstructeurApercuPdf>((ref) => apercuPdfSysteme);

/// Aperçu du PDF (pages défilantes, zoom au pincement), sans la barre d'actions du paquet `printing` :
/// le partage et l'impression ont leurs propres boutons dans l'écran.
Widget apercuPdfSysteme(BuildContext context, Uint8List pdf, String nomFichier) {
  return PdfPreview(
    build: (PdfPageFormat format) async => pdf,
    pdfFileName: nomFichier,
    useActions: false,
    allowPrinting: false,
    allowSharing: false,
    canChangePageFormat: false,
    canChangeOrientation: false,
    canDebug: false,
    maxPageWidth: 700,
    onError: (BuildContext context, Object erreur) =>
        const Center(child: Text('Impossible d’afficher l’aperçu de ce document.')),
  );
}
