import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Polices et logo nécessaires pour fabriquer un PDF. Fournis tels quels à `genererFacturePdf` : la mise
/// en page ne lit aucun fichier elle-même, ce qui permet de la tester sans l'application.
class RessourcesPdf {
  const RessourcesPdf({
    required this.police,
    required this.policeMoyenne,
    required this.policeSemiGras,
    required this.policeGras,
    required this.logo,
  });

  /// Poppins (licence OFL) : les mêmes polices que l'application, avec « € », guillemets et accents.
  final Uint8List police;
  final Uint8List policeMoyenne;
  final Uint8List policeSemiGras;
  final Uint8List policeGras;

  /// Logo de l'entreprise (JPEG sur fond blanc), imprimé en haut à gauche des factures et des devis.
  final Uint8List logo;
}

/// Lit les polices et le logo dans les ressources de l'application.
Future<RessourcesPdf> chargerRessourcesPdf([AssetBundle? bundle]) async {
  final AssetBundle source = bundle ?? rootBundle;
  Future<Uint8List> octets(String chemin) async {
    final ByteData donnees = await source.load(chemin);
    return donnees.buffer.asUint8List(donnees.offsetInBytes, donnees.lengthInBytes);
  }

  return RessourcesPdf(
    police: await octets('assets/fonts/Poppins-Regular.ttf'),
    policeMoyenne: await octets('assets/fonts/Poppins-Medium.ttf'),
    policeSemiGras: await octets('assets/fonts/Poppins-SemiBold.ttf'),
    policeGras: await octets('assets/fonts/Poppins-Bold.ttf'),
    logo: await octets('assets/images/logo_entreprise.jpg'),
  );
}
