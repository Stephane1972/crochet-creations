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
  return '$signe$nombre €';
}

String _grouperParTrois(String chiffres) {
  final StringBuffer tampon = StringBuffer();
  for (int i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) {
      tampon.write(' ');
    }
    tampon.write(chiffres[i]);
  }
  return tampon.toString();
}

/// Un montant saisi à la main est limité à 9 999 999,99 € : au-delà, c'est une faute de frappe.
final RegExp _montantSaisi = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$');

/// Lit un montant saisi en euros et le convertit en centimes.
///
/// Accepte la virgule ou le point comme séparateur, les espaces (y compris insécables)
/// et le symbole « € » : `12,50`, `12.5`, `1 200 €`. Retourne `null` si la saisie n'est pas
/// un montant valide (texte, plus de deux décimales, nombre négatif...).
int? parseMontantEuros(String saisie) {
  final String propre = saisie
      .replaceAll('€', '')
      .replaceAll(RegExp(r'[\s  ]'), '')
      .replaceAll(',', '.');
  final RegExpMatch? m = _montantSaisi.firstMatch(propre);
  if (m == null) return null;
  final int euros = int.parse(m.group(1)!);
  final String decimales = (m.group(2) ?? '').padRight(2, '0');
  return euros * 100 + (decimales.isEmpty ? 0 : int.parse(decimales));
}

/// Montant en centimes présenté dans un champ de saisie : `1250` → « 12,50 », `1200` → « 12 ».
String formatMontantSaisie(int centimes) {
  final int absolu = centimes.abs();
  final String signe = centimes < 0 ? '-' : '';
  if (absolu % 100 == 0) return '$signe${absolu ~/ 100}';
  return '$signe${absolu ~/ 100},${(absolu % 100).toString().padLeft(2, '0')}';
}
