/// Nettoie une saisie facultative : espaces retirés aux extrémités, et `null` si le texte est vide.
String? nullSiVide(String? valeur) {
  final String? nettoye = valeur?.trim();
  if (nettoye == null || nettoye.isEmpty) return null;
  return nettoye;
}
