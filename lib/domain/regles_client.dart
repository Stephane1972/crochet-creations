/// Règles de saisie d'une fiche client. Chaque fonction retourne `null` si la valeur est bonne
/// (ou vide : ces champs sont facultatifs), sinon le message en français à afficher.
///
/// Les mêmes règles servent au formulaire et au dépôt de données : une fiche refusée à l'écran
/// l'est aussi par la base, avec le même message.
library;

/// « nom@domaine.extension » : sans espace, un seul « @ », un point dans le domaine.
final RegExp _formeEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s.]+$');

/// Numéro de téléphone : chiffres, espaces et signes usuels (« + ( ) . - / »).
final RegExp _caracteresTelephone = RegExp(r'^[0-9 +().\-/]+$');

/// Code postal : lettres, chiffres, espaces et tirets (3 à 10 caractères), pour accepter
/// aussi les adresses à l'étranger.
final RegExp _formeCodePostal = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 \-]{1,8}[A-Za-z0-9]$');

String _chiffres(String texte) => texte.replaceAll(RegExp(r'\D'), '');

String? verifierEmail(String? valeur) {
  final String texte = valeur?.trim() ?? '';
  if (texte.isEmpty) return null;
  return _formeEmail.hasMatch(texte) ? null : 'L’adresse e-mail n’est pas valide.';
}

String? verifierTelephone(String? valeur) {
  final String texte = valeur?.trim() ?? '';
  if (texte.isEmpty) return null;
  final int nombreDeChiffres = _chiffres(texte).length;
  final bool valide =
      _caracteresTelephone.hasMatch(texte) && nombreDeChiffres >= 6 && nombreDeChiffres <= 15;
  return valide ? null : 'Le numéro de téléphone n’est pas valide.';
}

String? verifierCodePostal(String? valeur) {
  final String texte = valeur?.trim() ?? '';
  if (texte.isEmpty) return null;
  return _formeCodePostal.hasMatch(texte) ? null : 'Le code postal n’est pas valide.';
}

/// SIREN (9 chiffres) ou SIRET (14 chiffres), avec ou sans espaces.
String? verifierSiret(String? valeur) {
  final String texte = valeur?.trim() ?? '';
  if (texte.isEmpty) return null;
  final bool seulementDesChiffres = RegExp(r'^[0-9 .]+$').hasMatch(texte);
  final int nombreDeChiffres = _chiffres(texte).length;
  final bool valide = seulementDesChiffres && (nombreDeChiffres == 9 || nombreDeChiffres == 14);
  return valide ? null : 'Le SIREN (9 chiffres) ou le SIRET (14 chiffres) n’est pas valide.';
}
