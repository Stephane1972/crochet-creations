/// Règles de saisie du profil « Mon entreprise » et informations nécessaires pour facturer.
///
/// Chaque contrôle retourne `null` si la valeur est bonne (ou vide : ces champs sont facultatifs
/// à l'enregistrement du profil), sinon le message en français à afficher. Les mêmes règles servent
/// au formulaire et au dépôt de données.
library;

/// Conditions de paiement proposées tant que rien d'autre n'est saisi.
const String conditionsPaiementParDefaut = 'Paiement à réception de la facture.';

/// Message de remerciement proposé tant que rien d'autre n'est saisi.
const String remerciementParDefaut = 'Merci pour votre confiance !';

String _chiffres(String texte) => texte.replaceAll(RegExp(r'\D'), '');

/// Le SIREN de l'entreprise : exactement 9 chiffres (espaces acceptés).
///
/// Le SIRET (14 chiffres) commence par le SIREN : le message le rappelle, car c'est l'erreur la plus fréquente.
String? verifierSiren(String? valeur) {
  final String texte = valeur?.trim() ?? '';
  if (texte.isEmpty) return null;
  if (RegExp(r'[^\d\s.]').hasMatch(texte)) return 'Le SIREN ne contient que des chiffres.';
  final int nombre = _chiffres(texte).length;
  if (nombre == 9) return null;
  if (nombre == 14) return 'C’est un SIRET (14 chiffres) : gardez les 9 premiers chiffres, ils forment le SIREN.';
  return 'Le SIREN comporte 9 chiffres.';
}

/// Le SIREN sans espaces ni points : « 123 456 789 » → « 123456789 ».
String normaliserSiren(String valeur) => _chiffres(valeur);

/// Le SIREN présenté par groupes de trois chiffres, comme sur un avis de situation :
/// « 123456789 » → « 123 456 789 ». Une valeur qui n'a pas 9 chiffres est rendue telle quelle.
String formaterSiren(String valeur) {
  final String chiffres = _chiffres(valeur);
  if (chiffres.length != 9) return valeur.trim();
  return '${chiffres.substring(0, 3)} ${chiffres.substring(3, 6)} ${chiffres.substring(6)}';
}

/// Un IBAN : forme (2 lettres, 2 chiffres, puis 11 à 30 lettres ou chiffres) et clé de contrôle
/// (modulo 97). Les espaces sont acceptés.
String? verifierIban(String? valeur) {
  final String texte = (valeur ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (texte.isEmpty) return null;
  if (!_ibanValide(texte)) return 'IBAN incorrect : vérifiez les chiffres et les lettres.';
  return null;
}

bool _ibanValide(String compact) {
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(compact)) return false;
  // On déplace les 4 premiers caractères à la fin, puis chaque lettre vaut 10 (A) à 35 (Z).
  final String reordonne = compact.substring(4) + compact.substring(0, 4);
  int reste = 0;
  for (final int unite in reordonne.codeUnits) {
    final int valeur = unite >= 65 ? unite - 55 : unite - 48;
    reste = (valeur >= 10 ? reste * 100 + valeur : reste * 10 + valeur) % 97;
  }
  return reste == 1;
}

/// L'IBAN en majuscules, par groupes de 4 : « fr1420041010… » → « FR14 2004 1010… ».
String formaterIban(String valeur) {
  final String compact = valeur.replaceAll(RegExp(r'\s'), '').toUpperCase();
  final StringBuffer sortie = StringBuffer();
  for (int i = 0; i < compact.length; i += 4) {
    if (i > 0) sortie.write(' ');
    sortie.write(compact.substring(i, i + 4 > compact.length ? compact.length : i + 4));
  }
  return sortie.toString();
}

bool _vide(String? valeur) => (valeur?.trim() ?? '').isEmpty;

/// Ce qu'il manque au profil pour pouvoir établir une facture (liste vide : tout y est).
///
/// Une facture doit porter le nom de l'entreprise, son adresse et son SIREN. Le téléphone, l'e-mail,
/// l'IBAN et les messages restent facultatifs.
List<String> informationsManquantes({
  String? nomCommercial,
  String? nomResponsable,
  String? adresse,
  String? codePostal,
  String? ville,
  String? siren,
}) {
  final List<String> manque = <String>[];
  if (_vide(nomCommercial) && _vide(nomResponsable)) manque.add('le nom de l’entreprise');
  if (_vide(adresse)) manque.add('l’adresse');
  if (_vide(codePostal) || _vide(ville)) manque.add('le code postal et la ville');
  if (_vide(siren)) {
    manque.add('le numéro SIREN');
  } else if (verifierSiren(siren) != null) {
    manque.add('un numéro SIREN valide (9 chiffres)');
  }
  return manque;
}
