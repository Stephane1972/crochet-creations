import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Partage et impression des documents PDF. Les écrans passent par cette interface : les tests la remplacent
/// par un faux service, car la feuille de partage et le dialogue d'impression sont ceux du téléphone.
abstract class ServiceDocuments {
  /// Ouvre la feuille de partage d'Android (messagerie, e-mail, enregistrement...) avec le PDF en pièce jointe.
  Future<void> partager({required String cheminFichier, required String nomFichier, required String sujet});

  /// Ouvre le dialogue d'impression d'Android (imprimante, « Enregistrer au format PDF »...).
  Future<void> imprimer({required Uint8List octets, required String nomDocument});
}

class ServiceDocumentsSysteme implements ServiceDocuments {
  @override
  Future<void> partager({required String cheminFichier, required String nomFichier, required String sujet}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(cheminFichier, mimeType: 'application/pdf', name: nomFichier)],
        subject: sujet,
      ),
    );
  }

  @override
  Future<void> imprimer({required Uint8List octets, required String nomDocument}) async {
    await Printing.layoutPdf(name: nomDocument, onLayout: (_) async => octets);
  }
}
