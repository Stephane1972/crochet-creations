/// Présente une durée en minutes : `45` → « 45 min », `120` → « 2 h », `150` → « 2 h 30 ».
String formatDuree(int minutes) {
  if (minutes <= 0) return '0 min';
  final int heures = minutes ~/ 60;
  final int reste = minutes % 60;
  if (heures == 0) return '$reste min';
  if (reste == 0) return '$heures h';
  return '$heures h ${reste.toString().padLeft(2, '0')}';
}
