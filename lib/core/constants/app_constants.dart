/// Constantes générales de l'application.
abstract final class AppConstants {
  static const String nomApplication = 'Crochet & Créations';
  static const String accroche = 'Votre atelier, bien rangé';

  /// À garder synchronisée avec la ligne `version:` de pubspec.yaml.
  static const String version = '0.1.0';

  /// Seuils de la franchise en base de TVA (micro-entreprise), en centimes.
  /// Ventes de biens : 85 000 € — prestations de services : 37 500 €.
  static const int seuilTvaVentesCentimes = 85000 * 100;
  static const int seuilTvaServicesCentimes = 37500 * 100;
}
