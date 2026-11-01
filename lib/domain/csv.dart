/// Fabrication de fichiers CSV lisibles par un tableur français (Excel, LibreOffice, Numbers).
///
/// - Séparateur **point-virgule** : en France, le tableur réserve la virgule aux décimales (`12,50`), donc
///   un CSV à virgules s'ouvrirait en une seule colonne.
/// - Fins de ligne `\r\n`, comme Excel.
/// - Une cellule qui contient un point-virgule, un guillemet ou un retour à la ligne est entourée de guillemets
///   (les guillemets qu'elle contient sont doublés).
///
/// Le fichier est ensuite écrit en UTF-8 avec une « marque d'ordre des octets » (voir `ExportCsv`) pour que
/// les accents s'affichent correctement dans Excel.
const String separateurCsv = ';';

/// Protège une cellule si elle contient un caractère qui casserait le tableau.
String echapperCsv(String valeur) {
  final bool aProteger =
      valeur.contains(separateurCsv) ||
      valeur.contains('"') ||
      valeur.contains('\n') ||
      valeur.contains('\r');
  if (!aProteger) return valeur;
  return '"${valeur.replaceAll('"', '""')}"';
}

/// Texte d'un fichier CSV : la ligne d'[entetes], puis une ligne par élément de [lignes].
/// Chaque ligne doit avoir autant de cellules que d'en-têtes.
String construireCsv(List<String> entetes, List<List<String>> lignes) {
  final StringBuffer texte = StringBuffer();

  void ecrire(List<String> cellules) {
    assert(
      cellules.length == entetes.length,
      'Une ligne du CSV a ${cellules.length} cellule(s) pour ${entetes.length} colonne(s).',
    );
    texte
      ..write(cellules.map(echapperCsv).join(separateurCsv))
      ..write('\r\n');
  }

  ecrire(entetes);
  lignes.forEach(ecrire);
  return texte.toString();
}

/// Un montant en centimes écrit pour un tableur : `1250` → « 12,50 », `-300` → « -3,00 ».
/// Toujours deux décimales, sans espace ni symbole : le tableur peut en faire des sommes.
String montantCsv(int centimes) {
  final String signe = centimes < 0 ? '-' : '';
  final int absolu = centimes.abs();
  return '$signe${absolu ~/ 100},${(absolu % 100).toString().padLeft(2, '0')}';
}
