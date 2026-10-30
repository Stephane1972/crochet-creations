// Petits utilitaires de dates en français (sans dépendance supplémentaire).

const List<String> _jours = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _mois = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// « samedi 17 octobre », « dimanche 1er novembre ».
String formatDateLongue(DateTime date) {
  final String jour = _jours[date.weekday - 1];
  final String quantieme = date.day == 1 ? '1er' : '${date.day}';
  return '$jour $quantieme ${_mois[date.month - 1]}';
}

/// « Bonjour » le jour, « Bonsoir » de 18 h à 5 h.
String salutation(DateTime date) {
  return (date.hour >= 18 || date.hour < 5) ? 'Bonsoir' : 'Bonjour';
}

/// « 05/03/2026 ».
String formatDateCourte(DateTime date) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(date.day)}/${deux(date.month)}/${date.year}';
}

/// « octobre 2026 » : le mois [mois] (1 à 12) de l'année [annee].
String formatMois(int annee, int mois) => '${_mois[mois - 1]} $annee';

/// « 14 h 30 », « 9 h 00 ».
String formatHeure(DateTime date) {
  return '${date.hour} h ${date.minute.toString().padLeft(2, '0')}';
}
