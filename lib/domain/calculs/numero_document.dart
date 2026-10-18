import '../enums.dart';

/// Met en forme un numéro de document :
/// - factures et devis : `FACT-2026-0001`, `DEVIS-2026-0001` (une suite par année) ;
/// - références produit : `PRD-0001` (une seule suite, [annee] ignorée).
///
/// Au-delà de 9 999, le numéro s'allonge (`FACT-2026-10000`) sans jamais se répéter.
String formaterNumero(TypeCompteur type, {required int annee, required int numero}) {
  final String numeroTexte = numero.toString().padLeft(4, '0');
  if (type.parAnnee) {
    return '${type.prefixe}-$annee-$numeroTexte';
  }
  return '${type.prefixe}-$numeroTexte';
}
