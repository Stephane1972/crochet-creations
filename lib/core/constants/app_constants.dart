/// Constantes générales de l'application.
abstract final class AppConstants {
  static const String nomApplication = 'Crochet & Créations';
  static const String accroche = 'Votre atelier, bien rangé';

  /// À garder synchronisée avec la ligne `version:` de pubspec.yaml.
  static const String version = '0.8.0';

  /// Seuils de la franchise en base de TVA (micro-entreprise), en centimes.
  /// Ventes de biens : 85 000 € — prestations de services : 37 500 €.
  static const int seuilTvaVentesCentimes = 85000 * 100;
  static const int seuilTvaServicesCentimes = 37500 * 100;

  /// Mention obligatoire sur toutes les factures (franchise en base de TVA).
  /// Le texte doit rester exactement celui-ci.
  static const String mentionTvaFranchise = 'TVA non applicable, article 293 B du CGI';

  /// Nom du fichier de la base de données sur le téléphone (`crochet_creations.sqlite`).
  static const String nomBaseDeDonnees = 'crochet_creations';
}
