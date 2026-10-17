/// Formate un montant exprimé en centimes d'euro.
///
/// Les montants sont toujours stockés en **centimes (entiers)** dans l'application,
/// pour éviter les erreurs d'arrondi des nombres à virgule sur les factures.
///
/// Exemples : `123456` → « 1 234,56 € » ; `8500000` avec `avecCentimes: false` → « 85 000 € ».
/// Les espaces sont insécables, pour qu'un montant ne soit jamais coupé en fin de ligne.
String formatEuros(int centimes, {bool avecCentimes = true}) {
  final bool negatif = centimes < 0;
  final int absolu = centimes.abs();
  final String entier = _grouperParTrois((absolu ~/ 100).toString());
  final String decimales = (absolu % 100).toString().padLeft(2, '0');
  final String nombre = avecCentimes ? '$entier,$decimales' : entier;
  final String signe = negatif ? '−' : '';
  return '$signe$nombre €';
}

String _grouperParTrois(String chiffres) {
  final StringBuffer tampon = StringBuffer();
  for (int i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) {
      tampon.write(' ');
    }
    tampon.write(chiffres[i]);
  }
  return tampon.toString();
}
