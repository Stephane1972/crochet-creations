/// Erreurs « métier » : situations normales que l'interface doit expliquer
/// à l'utilisatrice avec un message clair (et non un plantage).
sealed class ErreurMetier implements Exception {
  const ErreurMetier(this.message);

  /// Message en français, affichable tel quel.
  final String message;

  @override
  String toString() => message;
}

/// Une valeur saisie est invalide (champ obligatoire vide, montant négatif...).
class DonneeInvalide extends ErreurMetier {
  const DonneeInvalide(super.message);
}

/// L'élément demandé n'existe pas (ou plus).
class ElementIntrouvable extends ErreurMetier {
  const ElementIntrouvable(super.message);
}

/// Le stock disponible ne suffit pas pour la quantité demandée.
class StockInsuffisant extends ErreurMetier {
  StockInsuffisant({
    required this.designation,
    required this.disponible,
    required this.demande,
  }) : super(
         'Stock insuffisant pour « $designation » : '
         '$disponible disponible(s), $demande demandé(s).',
       );

  final String designation;
  final int disponible;
  final int demande;
}

/// Le profil « Mon entreprise » ne permet pas encore d'établir une facture : il manque [manque].
class ProfilIncomplet extends ErreurMetier {
  ProfilIncomplet(this.manque)
    : super('Pour établir une facture, renseignez d’abord ${_enumerer(manque)} dans « Mon entreprise ».');

  /// Ce qui manque, en toutes lettres : « le nom de l’entreprise », « l’adresse »...
  final List<String> manque;

  static String _enumerer(List<String> elements) {
    if (elements.length <= 1) return elements.join();
    return '${elements.sublist(0, elements.length - 1).join(', ')} et ${elements.last}';
  }
}

/// La remise saisie est impossible (pourcentage au-delà de 100 %, montant supérieur au total...).
class RemiseInvalide extends ErreurMetier {
  const RemiseInvalide(super.message);
}
