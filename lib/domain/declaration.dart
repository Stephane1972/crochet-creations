/// Le rappel de la déclaration des recettes : quand il sonne (3 jours avant la fin du mois, puis le dernier jour, à 9 h),
/// ce qu'il dit, et l'identifiant de chaque notification. Des règles pures, sans notification ni écran : elles se testent
/// seules.
library;

import '../core/utils/date_fr.dart';
import 'agenda.dart';

/// Le premier rappel sonne ce nombre de jours avant le dernier jour du mois.
const int joursAvantDeclaration = 3;

/// Heure à laquelle sonnent les rappels (heure locale).
const int heureRappelDeclaration = 9;

/// Les rappels sont programmés pour ce nombre de mois à venir, à partir du mois en cours. À chaque ouverture de
/// l'application, la programmation est refaite : elle ne s'arrête que si l'application reste fermée plus d'un an.
const int moisProgrammesDeclaration = 12;

/// Les deux rappels d'un mois.
enum TypeRappelDeclaration {
  /// 3 jours avant la fin du mois.
  avance,

  /// Le dernier jour du mois.
  dernierJour,
}

/// Une notification à programmer.
class RappelDeclaration {
  const RappelDeclaration({
    required this.id,
    required this.quand,
    required this.type,
    required this.dernierJour,
    required this.titre,
    required this.texte,
  });

  /// Identifiant de la notification (voir [identifiantRappel]).
  final int id;

  /// Instant (heure locale) où la notification doit apparaître.
  final DateTime quand;
  final TypeRappelDeclaration type;

  /// Le dernier jour du mois concerné (à minuit).
  final DateTime dernierJour;
  final String titre;
  final String texte;

  @override
  bool operator ==(Object other) =>
      other is RappelDeclaration &&
      other.id == id &&
      other.quand == quand &&
      other.type == type &&
      other.dernierJour == dernierJour &&
      other.titre == titre &&
      other.texte == texte;

  @override
  int get hashCode => Object.hash(id, quand, type, dernierJour, titre, texte);

  @override
  String toString() => 'RappelDeclaration($id, $quand, ${type.name})';
}

/// Titre des deux rappels.
const String titreRappelDeclaration = 'Déclaration des recettes';

/// Identifiant stable d'une notification : l'année, le mois et le type (par exemple 2026110 pour le rappel de novembre
/// 2026 envoyé 3 jours avant, 2026111 pour celui du dernier jour). Le même rappel reprogrammé remplace donc l'ancien.
int identifiantRappel(DateTime dernierJour, TypeRappelDeclaration type) =>
    dernierJour.year * 1000 + dernierJour.month * 10 + type.index;

/// Vrai si [id] est un identifiant de rappel de déclaration (pour ne toucher qu'à ses propres notifications).
bool estIdentifiantRappel(int id) => id >= 1000000 && id < 10000000;

/// Le texte d'un rappel pour le [dernierJour] d'un mois.
String texteRappelDeclaration(DateTime dernierJour, TypeRappelDeclaration type) {
  final String jour = formatDateLongue(dernierJour);
  switch (type) {
    case TypeRappelDeclaration.avance:
      return 'Fin de mois $jour (dans $joursAvantDeclaration jours) : pensez à préparer la déclaration de vos recettes.';
    case TypeRappelDeclaration.dernierJour:
      return 'Fin de mois aujourd’hui ($jour) : pensez à déclarer vos recettes à l’organisme.';
  }
}

/// Les rappels à venir, du plus proche au plus lointain : pour chacun des [mois] mois à partir du mois de [maintenant],
/// un rappel [joursAvantDeclaration] jours avant la fin du mois et un le dernier jour, à [heureRappelDeclaration] h.
/// Ceux dont l'heure est déjà passée n'en font pas partie.
List<RappelDeclaration> prochainsRappelsDeclaration(DateTime maintenant, {int mois = moisProgrammesDeclaration}) {
  final List<RappelDeclaration> rappels = <RappelDeclaration>[];
  for (int i = 0; i < mois; i++) {
    // `DateTime(année, mois + i)` passe seul à l'année suivante après décembre.
    final DateTime debutDuMois = DateTime(maintenant.year, maintenant.month + i);
    final DateTime dernierJour = dernierJourDuMois(debutDuMois.year, debutDuMois.month);
    for (final TypeRappelDeclaration type in TypeRappelDeclaration.values) {
      final int retrait = type == TypeRappelDeclaration.avance ? joursAvantDeclaration : 0;
      // Composé jour par jour (et non en retirant 72 h) : un changement d'heure ne décale pas le rappel.
      final DateTime quand = DateTime(dernierJour.year, dernierJour.month, dernierJour.day - retrait, heureRappelDeclaration);
      if (!quand.isAfter(maintenant)) continue;
      rappels.add(
        RappelDeclaration(
          id: identifiantRappel(dernierJour, type),
          quand: quand,
          type: type,
          dernierJour: dernierJour,
          titre: titreRappelDeclaration,
          texte: texteRappelDeclaration(dernierJour, type),
        ),
      );
    }
  }
  return rappels;
}
