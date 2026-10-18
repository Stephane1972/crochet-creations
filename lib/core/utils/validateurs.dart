import 'money.dart';

/// Validateurs des champs de formulaire. Chacun retourne `null` si la saisie est bonne,
/// sinon le message (en français) à afficher sous le champ.

/// Texte obligatoire : [message] si le champ est vide ou ne contient que des espaces.
String? validerObligatoire(String? valeur, String message) {
  if (valeur == null || valeur.trim().isEmpty) return message;
  return null;
}

/// Longueur maximale d'un texte.
String? validerLongueurMax(String? valeur, int max, String libelle) {
  if (valeur != null && valeur.trim().length > max) {
    return '$libelle est trop long ($max caractères maximum).';
  }
  return null;
}

/// Montant en euros obligatoire (« 12,50 »).
String? validerMontantObligatoire(String? valeur, String message) {
  if (valeur == null || valeur.trim().isEmpty) return message;
  return parseMontantEuros(valeur) == null ? 'Montant invalide (exemple : 12,50).' : null;
}

/// Montant en euros facultatif : vide accepté.
String? validerMontantFacultatif(String? valeur) {
  if (valeur == null || valeur.trim().isEmpty) return null;
  return parseMontantEuros(valeur) == null ? 'Montant invalide (exemple : 12,50).' : null;
}

/// Nombre entier positif ou nul ; vide accepté sauf si [obligatoire].
String? validerEntier(String? valeur, {bool obligatoire = false, int max = 999999}) {
  final String texte = valeur?.trim() ?? '';
  if (texte.isEmpty) return obligatoire ? 'Ce champ est obligatoire.' : null;
  final int? nombre = int.tryParse(texte);
  if (nombre == null || nombre < 0) return 'Entrez un nombre entier (0 ou plus).';
  if (nombre > max) return 'Valeur trop grande (maximum $max).';
  return null;
}

/// Lit un entier saisi ; `null` si le champ est vide ou invalide.
int? lireEntier(String? valeur) => int.tryParse(valeur?.trim() ?? '');
