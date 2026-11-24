/// Le calendrier : ce qui s'y affiche (cours, fin de validité d'un devis, jour de déclaration des recettes, événements
/// de l'utilisatrice), la grille d'un mois et les liens vers Google Agenda. Des règles pures, sans base de données ni
/// écran : elles se testent seules.
library;

/// Ce que montre une entrée du calendrier. Chaque type peut être affiché ou masqué (voir [FiltresAgenda]).
enum TypeEntreeAgenda {
  cours('Cours'),
  devis('Devis'),
  declaration('Déclaration'),
  evenement('Mes événements');

  const TypeEntreeAgenda(this.libelle);

  /// Le nom du filtre, tel qu'il est écrit sur l'écran.
  final String libelle;
}

/// Un élément du calendrier, quel que soit son origine (un cours, un devis, une échéance ou un événement à soi).
class EntreeAgenda {
  const EntreeAgenda({
    required this.type,
    required this.titre,
    required this.debut,
    this.fin,
    this.journeeEntiere = false,
    this.detail,
    this.lieu,
    this.identifiant,
  });

  final TypeEntreeAgenda type;
  final String titre;

  /// Début : pour une entrée « toute la journée », minuit du jour (l'heure n'est pas affichée).
  final DateTime debut;

  /// Fin, si on la connaît (un cours a une durée ; un événement peut ne pas avoir d'heure de fin).
  final DateTime? fin;
  final bool journeeEntiere;

  /// Une ligne de précision : le client d'un devis, la description d'un événement...
  final String? detail;
  final String? lieu;

  /// Numéro du cours, du devis ou de l'événement (vide pour une échéance de déclaration, qui n'est pas enregistrée).
  final int? identifiant;

  /// Le jour concerné (minuit, heure locale).
  DateTime get jour => jourDe(debut);
}

/// Les types d'entrées affichés : l'utilisatrice peut en masquer certains (le choix est mémorisé dans les réglages).
class FiltresAgenda {
  const FiltresAgenda({this.cours = true, this.devis = true, this.declaration = true, this.evenements = true});

  final bool cours;
  final bool devis;
  final bool declaration;
  final bool evenements;

  bool accepte(TypeEntreeAgenda type) => switch (type) {
    TypeEntreeAgenda.cours => cours,
    TypeEntreeAgenda.devis => devis,
    TypeEntreeAgenda.declaration => declaration,
    TypeEntreeAgenda.evenement => evenements,
  };

  /// Les mêmes filtres, avec [type] affiché ([affiche] vrai) ou masqué.
  FiltresAgenda avec(TypeEntreeAgenda type, {required bool affiche}) => FiltresAgenda(
    cours: type == TypeEntreeAgenda.cours ? affiche : cours,
    devis: type == TypeEntreeAgenda.devis ? affiche : devis,
    declaration: type == TypeEntreeAgenda.declaration ? affiche : declaration,
    evenements: type == TypeEntreeAgenda.evenement ? affiche : evenements,
  );

  @override
  bool operator ==(Object autre) =>
      autre is FiltresAgenda &&
      autre.cours == cours &&
      autre.devis == devis &&
      autre.declaration == declaration &&
      autre.evenements == evenements;

  @override
  int get hashCode => Object.hash(cours, devis, declaration, evenements);
}

// -----------------------------------------------------------------------------
// Jours et grille d'un mois
// -----------------------------------------------------------------------------

/// Minuit (heure locale) du jour de [date].
DateTime jourDe(DateTime date) => DateTime(date.year, date.month, date.day);

/// Le dernier jour du mois [mois] (1 à 12) de l'année [annee] : le 30 novembre, le 28 ou 29 février...
DateTime dernierJourDuMois(int annee, int mois) => DateTime(annee, mois + 1, 0);

/// Le premier jour du mois suivant (minuit) : la borne de fin, exclue, d'une recherche sur tout le mois.
DateTime debutMoisSuivant(int annee, int mois) => DateTime(annee, mois + 1, 1);

/// Les jours que montre la grille du mois [mois] de l'année [annee] : des semaines entières, du lundi au dimanche, qui
/// débordent sur le mois d'avant et le mois d'après (4 à 6 semaines).
List<DateTime> joursAffiches(int annee, int mois) {
  final DateTime premier = DateTime(annee, mois, 1);
  final int decalage = premier.weekday - DateTime.monday; // jours du mois précédent à montrer
  final int nombreDeJours = dernierJourDuMois(annee, mois).day;
  final int semaines = ((decalage + nombreDeJours) / 7).ceil();
  // On compose chaque jour par `DateTime(année, mois, jour)` et non en ajoutant 24 h : un changement d'heure ne décale rien.
  return <DateTime>[for (int i = 0; i < semaines * 7; i++) DateTime(annee, mois, 1 - decalage + i)];
}

/// Les entrées regroupées par jour. Dans un jour : d'abord celles « toute la journée », puis par heure, puis par titre.
Map<DateTime, List<EntreeAgenda>> regrouperParJour(Iterable<EntreeAgenda> entrees) {
  final Map<DateTime, List<EntreeAgenda>> parJour = <DateTime, List<EntreeAgenda>>{};
  for (final EntreeAgenda e in entrees) {
    parJour.putIfAbsent(e.jour, () => <EntreeAgenda>[]).add(e);
  }
  for (final List<EntreeAgenda> liste in parJour.values) {
    liste.sort(comparerEntrees);
  }
  return parJour;
}

/// Ordre d'affichage : par jour, puis dans un jour « toute la journée » d'abord, puis par heure, par type et par titre.
int comparerEntrees(EntreeAgenda a, EntreeAgenda b) {
  final int parJour = a.jour.compareTo(b.jour);
  if (parJour != 0) return parJour;
  if (a.journeeEntiere != b.journeeEntiere) return a.journeeEntiere ? -1 : 1;
  final int parHeure = a.debut.compareTo(b.debut);
  if (parHeure != 0) return parHeure;
  final int parType = a.type.index.compareTo(b.type.index);
  if (parType != 0) return parType;
  return a.titre.toLowerCase().compareTo(b.titre.toLowerCase());
}

// -----------------------------------------------------------------------------
// Déclaration des recettes
// -----------------------------------------------------------------------------

/// Le libellé de l'échéance de déclaration dans le calendrier.
const String titreDeclaration = 'Déclaration des recettes';

/// Les jours de déclaration entre [debut] (inclus) et [fin] (exclu) : le **dernier jour de chaque mois**.
List<EntreeAgenda> echeancesDeclaration(DateTime debut, DateTime fin) {
  final List<EntreeAgenda> echeances = <EntreeAgenda>[];
  // On parcourt les mois depuis celui de [debut] ; on ne garde que les derniers jours qui tombent dans l'intervalle.
  for (DateTime mois = DateTime(debut.year, debut.month); mois.isBefore(fin); mois = DateTime(mois.year, mois.month + 1)) {
    final DateTime dernier = dernierJourDuMois(mois.year, mois.month);
    if (dernier.isBefore(debut) || !dernier.isBefore(fin)) continue;
    echeances.add(
      EntreeAgenda(
        type: TypeEntreeAgenda.declaration,
        titre: titreDeclaration,
        debut: dernier,
        journeeEntiere: true,
        detail: 'Dernier jour du mois : à faire auprès de votre organisme.',
      ),
    );
  }
  return echeances;
}

// -----------------------------------------------------------------------------
// Google Agenda
// -----------------------------------------------------------------------------

const String _hoteGoogleAgenda = 'calendar.google.com';

/// L'adresse qui ouvre Google Agenda sur le mois du jour [jour] (aujourd'hui si absent), dans le navigateur.
///
/// [compte] : l'adresse e-mail du compte Google à utiliser (celui de Google Workspace, par exemple), quand on la connaît :
/// Google ouvre alors ce compte, même si le navigateur en a plusieurs.
Uri lienOuvrirGoogleAgenda({DateTime? jour, String? compte}) {
  final List<String> chemin = <String>['calendar', 'r'];
  if (jour != null) chemin.addAll(<String>['month', '${jour.year}', '${jour.month}', '${jour.day}']);
  return Uri(
    scheme: 'https',
    host: _hoteGoogleAgenda,
    pathSegments: chemin,
    queryParameters: _compte(compte),
  );
}

/// L'adresse qui ouvre, dans Google Agenda, la création d'un événement **déjà rempli** avec [entree] : il reste à
/// l'enregistrer. Rien n'est créé tant qu'on ne l'a pas fait.
///
/// Un événement à heure fixe est écrit en heure universelle (UTC) : Google l'affiche à la bonne heure, sans qu'on ait à
/// connaître le fuseau horaire. La déclaration des recettes revient chaque mois (le dernier jour).
Uri lienAjouterAGoogleAgenda(EntreeAgenda entree, {String? compte}) {
  final Map<String, String> champs = <String, String>{
    'action': 'TEMPLATE',
    'text': entree.titre,
    'dates': _datesGoogle(entree),
  };
  final String details = (entree.detail ?? '').trim();
  if (details.isNotEmpty) champs['details'] = details;
  final String lieu = (entree.lieu ?? '').trim();
  if (lieu.isNotEmpty) champs['location'] = lieu;
  if (entree.type == TypeEntreeAgenda.declaration) champs['recur'] = 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1';
  champs.addAll(_compte(compte) ?? const <String, String>{});
  return Uri(scheme: 'https', host: _hoteGoogleAgenda, pathSegments: <String>['calendar', 'render'], queryParameters: champs);
}

Map<String, String>? _compte(String? compte) {
  final String propre = (compte ?? '').trim();
  return propre.isEmpty ? null : <String, String>{'authuser': propre};
}

String _datesGoogle(EntreeAgenda entree) {
  if (entree.journeeEntiere) {
    // Journée entière : la date de fin est le lendemain (Google l'exclut).
    final DateTime lendemain = DateTime(entree.debut.year, entree.debut.month, entree.debut.day + 1);
    return '${_dateGoogle(entree.debut)}/${_dateGoogle(lendemain)}';
  }
  final DateTime fin = entree.fin != null && entree.fin!.isAfter(entree.debut)
      ? entree.fin!
      : entree.debut.add(const Duration(hours: 1));
  return '${_dateHeureGoogle(entree.debut)}/${_dateHeureGoogle(fin)}';
}

String _deux(int n) => n.toString().padLeft(2, '0');

String _dateGoogle(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_deux(d.month)}${_deux(d.day)}';

String _dateHeureGoogle(DateTime d) {
  final DateTime u = d.toUtc();
  return '${_dateGoogle(u)}T${_deux(u.hour)}${_deux(u.minute)}${_deux(u.second)}Z';
}
