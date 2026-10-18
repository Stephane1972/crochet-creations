/// Recherche tolérante : sans tenir compte des majuscules ni des accents
/// (« echarpe » trouve « Écharpe », « BOUCLES » trouve « boucles »).

const Map<String, String> _remplacements = <String, String>{
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ñ': 'n',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
  '’': "'",
};

/// Minuscules, sans accents, espaces multiples réduits à un seul.
String normaliserPourRecherche(String texte) {
  final StringBuffer tampon = StringBuffer();
  for (final int rune in texte.toLowerCase().runes) {
    final String caractere = String.fromCharCode(rune);
    tampon.write(_remplacements[caractere] ?? caractere);
  }
  return tampon.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Vrai si **chaque mot** de [requete] se retrouve dans l'un des [champs].
/// Une requête vide correspond à tout.
bool correspondALaRecherche(String requete, Iterable<String?> champs) {
  final String normalisee = normaliserPourRecherche(requete);
  if (normalisee.isEmpty) return true;
  final String texte = normaliserPourRecherche(champs.whereType<String>().join(' '));
  return normalisee.split(' ').every(texte.contains);
}
