/// La synchronisation du calendrier vers Google Agenda : ce qui est envoyé, comment chaque élément est reconnu d'une
/// synchronisation à l'autre, et ce qu'il faut faire (créer, modifier, marquer « [Annulé] ») pour que Google Agenda reflète
/// le calendrier de l'application. Des règles pures, sans réseau ni base de données : elles se testent seules.
///
/// Le sens est unique : l'application écrit dans Google Agenda, elle n'y lit rien d'autre que ses propres événements.
library;

import 'agenda.dart';

/// Le seul droit Google Agenda demandé : créer un agenda **à elle** et y gérer des événements. L'application ne voit aucun
/// autre agenda de la personne ni les événements qu'elle y a mis.
const String porteeAgenda = 'https://www.googleapis.com/auth/calendar.app.created';

/// Le nom de l'agenda que l'application crée dans Google Agenda.
const String nomAgendaGoogle = 'Un p’tit crochet dans les stocks';

/// Le fuseau horaire de l'agenda créé (les événements à heure fixe sont de toute façon envoyés avec leur heure exacte).
const String fuseauAgendaGoogle = 'Europe/Paris';

/// Ce qui est écrit au début du titre d'un événement dont l'élément a disparu de l'application (événement supprimé, cours
/// annulé ou archivé, devis accepté ou expiré...). L'application ne supprime jamais rien dans Google Agenda sans qu'on le lui
/// demande : elle marque.
const String prefixeAnnule = '[Annulé] ';

/// Combien de mois avant le mois en cours, et après lui, sont synchronisés.
const int moisPassesSynchronises = 1;
const int moisFutursSynchronises = 12;

/// Les propriétés privées posées sur chaque événement envoyé : elles permettent de retrouver les événements de l'application
/// (et eux seuls) et de savoir de quel type ils sont.
const String proprieteCrochet = 'crochet';
const String proprieteType = 'type';

/// La phrase ajoutée à la fin de la description de chaque événement envoyé.
const String noteAgendaGoogle =
    'Envoyé par « Un p’tit crochet dans les stocks » : une modification faite ici sera remplacée à la prochaine synchronisation.';

/// Le titre d'un événement sans titre (un titre vide est refusé par l'application, mais mieux vaut ne rien casser).
const String titreSansNom = '(sans titre)';

/// La période synchronisée : du premier jour du mois précédent (inclus) au premier jour du mois qui suit les
/// [moisFutursSynchronises] mois à venir (exclu), en heure locale.
({DateTime debut, DateTime fin}) fenetreSynchro(DateTime maintenant) => (
  debut: DateTime(maintenant.year, maintenant.month - moisPassesSynchronises),
  fin: DateTime(maintenant.year, maintenant.month + moisFutursSynchronises + 1),
);

// -----------------------------------------------------------------------------
// Un événement Google Agenda
// -----------------------------------------------------------------------------

/// Un événement tel qu'il est (ou sera) dans Google Agenda. Les dates sont en heure universelle (UTC) : pour un événement
/// « toute la journée », minuit UTC du jour (la **fin est exclue**, comme chez Google : le lendemain) ; pour un événement à
/// heure fixe, l'instant exact.
class EvenementGoogle {
  const EvenementGoogle({
    required this.id,
    required this.titre,
    required this.debut,
    required this.fin,
    required this.journeeEntiere,
    this.description = '',
    this.lieu = '',
    this.type,
  });

  /// L'identifiant de l'événement dans l'agenda (voir [identifiantEvenementGoogle]).
  final String id;
  final String titre;
  final String description;
  final String lieu;
  final bool journeeEntiere;
  final DateTime debut;
  final DateTime fin;

  /// Le type d'élément de l'application (`null` : inconnu).
  final TypeEntreeAgenda? type;

  /// Vrai si l'événement est déjà marqué « [Annulé] ».
  bool get estAnnule => titre.startsWith(prefixeAnnule);

  /// Le même événement, marqué « [Annulé] » (inchangé s'il l'est déjà).
  EvenementGoogle annule() => estAnnule
      ? this
      : EvenementGoogle(
          id: id,
          titre: '$prefixeAnnule$titre',
          debut: debut,
          fin: fin,
          journeeEntiere: journeeEntiere,
          description: description,
          lieu: lieu,
          type: type,
        );

  /// Vrai si [autre] dit la même chose : même titre, mêmes précisions, même lieu, mêmes dates. Les espaces autour des textes
  /// et le type de saut de ligne ne comptent pas (Google peut les normaliser) : sinon on réécrirait tout à chaque fois.
  bool memeContenu(EvenementGoogle autre) =>
      id == autre.id &&
      titre.trim() == autre.titre.trim() &&
      _normaliser(description) == _normaliser(autre.description) &&
      lieu.trim() == autre.lieu.trim() &&
      journeeEntiere == autre.journeeEntiere &&
      debut.isAtSameMomentAs(autre.debut) &&
      fin.isAtSameMomentAs(autre.fin);

  static String _normaliser(String texte) => texte.replaceAll('\r\n', '\n').trim();

  @override
  String toString() => 'EvenementGoogle($id, $titre, $debut → $fin)';
}

/// Minuit UTC du jour de [date] (le jour tel qu'il est écrit en heure locale).
DateTime jourUtc(DateTime date) => DateTime.utc(date.year, date.month, date.day);

String _deux(int n) => n.toString().padLeft(2, '0');

/// `AAAAMMJJ` : 20261130.
String _aaaammjj(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_deux(d.month)}${_deux(d.day)}';

/// L'identifiant de l'événement qui représente [entree] dans Google Agenda : toujours le même pour le même élément, d'une
/// synchronisation à l'autre et d'un appareil à l'autre. C'est ce qui permet de **modifier** un événement plutôt que d'en
/// créer un second.
///
/// Google n'accepte, dans un identifiant choisi, que les lettres de « a » à « v » et les chiffres (5 caractères au moins) :
/// `ptitc12` (cours n° 12), `ptitq7` (devis n° 7), `ptite3` (événement n° 3), `ptitd20261130` (déclaration du 30 novembre
/// 2026). `null` si l'élément n'a pas de numéro (ce qui n'arrive que pour une déclaration, identifiée par sa date).
String? identifiantEvenementGoogle(EntreeAgenda entree) {
  switch (entree.type) {
    case TypeEntreeAgenda.declaration:
      return 'ptitd${_aaaammjj(entree.debut)}';
    case TypeEntreeAgenda.cours:
      return entree.identifiant == null ? null : 'ptitc${entree.identifiant}';
    case TypeEntreeAgenda.devis:
      return entree.identifiant == null ? null : 'ptitq${entree.identifiant}';
    case TypeEntreeAgenda.evenement:
      return entree.identifiant == null ? null : 'ptite${entree.identifiant}';
  }
}

/// L'événement Google qui représente [entree] (`null` s'il n'a pas d'identifiant).
///
/// - Toute la journée : la date du jour, fin exclue (le lendemain).
/// - À heure fixe : l'instant exact ; sans fin connue (ou fin avant le début), une heure.
/// - La description reprend la précision de l'entrée, puis [noteAgendaGoogle].
EvenementGoogle? evenementDepuisEntree(EntreeAgenda entree) {
  final String? id = identifiantEvenementGoogle(entree);
  if (id == null) return null;
  final String titre = entree.titre.trim().isEmpty ? titreSansNom : entree.titre.trim();
  final String detail = (entree.detail ?? '').trim();
  final String description = detail.isEmpty ? noteAgendaGoogle : '$detail\n\n$noteAgendaGoogle';
  final String lieu = (entree.lieu ?? '').trim();
  if (entree.journeeEntiere) {
    final DateTime jour = jourUtc(entree.debut);
    return EvenementGoogle(
      id: id,
      titre: titre,
      description: description,
      lieu: lieu,
      journeeEntiere: true,
      debut: jour,
      fin: DateTime.utc(jour.year, jour.month, jour.day + 1),
      type: entree.type,
    );
  }
  final DateTime debut = entree.debut.toUtc();
  final DateTime? fin = entree.fin;
  return EvenementGoogle(
    id: id,
    titre: titre,
    description: description,
    lieu: lieu,
    journeeEntiere: false,
    debut: debut,
    fin: fin != null && fin.isAfter(entree.debut) ? fin.toUtc() : debut.add(const Duration(hours: 1)),
    type: entree.type,
  );
}

/// Les événements Google des [entrees] (celles sans identifiant sont ignorées ; si deux ont le même identifiant, la première
/// l'emporte).
List<EvenementGoogle> evenementsDepuisEntrees(Iterable<EntreeAgenda> entrees) {
  final Map<String, EvenementGoogle> parId = <String, EvenementGoogle>{};
  for (final EntreeAgenda entree in entrees) {
    final EvenementGoogle? evenement = evenementDepuisEntree(entree);
    if (evenement != null) parId.putIfAbsent(evenement.id, () => evenement);
  }
  return parId.values.toList();
}

// -----------------------------------------------------------------------------
// Ce qu'il faut faire
// -----------------------------------------------------------------------------

/// Ce qu'il faut faire dans Google Agenda pour qu'il reflète le calendrier.
class PlanSynchro {
  const PlanSynchro({
    this.aCreer = const <EvenementGoogle>[],
    this.aRemplacer = const <EvenementGoogle>[],
    this.aAnnuler = const <EvenementGoogle>[],
    this.inchanges = 0,
    this.dejaAnnules = 0,
  });

  /// Les événements qui n'existent pas encore.
  final List<EvenementGoogle> aCreer;

  /// Les événements qui existent mais ne sont plus à l'identique (date, titre, lieu... modifiés, ou événement revenu après
  /// avoir été marqué « [Annulé] ») : ils sont remplacés par la version à jour.
  final List<EvenementGoogle> aRemplacer;

  /// Les événements dont l'élément a disparu de l'application : ils sont remplacés par leur version marquée « [Annulé] ».
  final List<EvenementGoogle> aAnnuler;

  /// Les événements déjà à jour.
  final int inchanges;

  /// Les événements déjà marqués « [Annulé] » dont l'élément n'est toujours pas revenu : on n'y touche plus.
  final int dejaAnnules;

  /// Le nombre d'écritures à faire dans Google Agenda.
  int get total => aCreer.length + aRemplacer.length + aAnnuler.length;

  bool get vide => total == 0;
}

int _comparer(EvenementGoogle a, EvenementGoogle b) {
  final int parDate = a.debut.compareTo(b.debut);
  return parDate != 0 ? parDate : a.id.compareTo(b.id);
}

/// Compare ce qui doit être dans Google Agenda ([souhaites], tiré du calendrier) à ce qui y est ([existants], les événements
/// de l'application déjà envoyés dans la période) et dit quoi faire.
///
/// - Un événement souhaité qui n'existe pas : **à créer**. Qui existe à l'identique : rien. Qui existe autrement : **à remplacer**
///   (c'est aussi ainsi qu'un événement marqué « [Annulé] » redevient normal si son élément revient).
/// - Un événement existant que plus aucun élément ne demande : **à marquer « [Annulé] »**, sauf s'il l'est déjà, ou si son type
///   est masqué par les [filtres] (la personne a choisi de ne pas synchroniser ce type : on n'y touche pas), ou si son type est
///   inconnu. **Rien n'est jamais supprimé.**
PlanSynchro planifierSynchro({
  required Iterable<EvenementGoogle> souhaites,
  required Iterable<EvenementGoogle> existants,
  FiltresAgenda filtres = const FiltresAgenda(),
}) {
  final Map<String, EvenementGoogle> existantsParId = <String, EvenementGoogle>{for (final EvenementGoogle e in existants) e.id: e};
  final Map<String, EvenementGoogle> souhaitesParId = <String, EvenementGoogle>{for (final EvenementGoogle e in souhaites) e.id: e};

  final List<EvenementGoogle> aCreer = <EvenementGoogle>[];
  final List<EvenementGoogle> aRemplacer = <EvenementGoogle>[];
  final List<EvenementGoogle> aAnnuler = <EvenementGoogle>[];
  int inchanges = 0;
  int dejaAnnules = 0;

  for (final EvenementGoogle souhaite in souhaitesParId.values) {
    final EvenementGoogle? existant = existantsParId[souhaite.id];
    if (existant == null) {
      aCreer.add(souhaite);
    } else if (existant.memeContenu(souhaite)) {
      inchanges++;
    } else {
      aRemplacer.add(souhaite);
    }
  }

  for (final EvenementGoogle existant in existantsParId.values) {
    if (souhaitesParId.containsKey(existant.id)) continue;
    final TypeEntreeAgenda? type = existant.type;
    if (type == null || !filtres.accepte(type)) continue; // type inconnu ou non synchronisé : on n'y touche pas
    if (existant.estAnnule) {
      dejaAnnules++;
    } else {
      aAnnuler.add(existant.annule());
    }
  }

  return PlanSynchro(
    aCreer: aCreer..sort(_comparer),
    aRemplacer: aRemplacer..sort(_comparer),
    aAnnuler: aAnnuler..sort(_comparer),
    inchanges: inchanges,
    dejaAnnules: dejaAnnules,
  );
}

// -----------------------------------------------------------------------------
// Le résultat, en mots
// -----------------------------------------------------------------------------

/// Ce qui s'est passé à la dernière synchronisation.
class ResultatSynchro {
  const ResultatSynchro({
    required this.quand,
    this.crees = 0,
    this.modifies = 0,
    this.annules = 0,
    this.inchanges = 0,
    this.echecs = 0,
  });

  final DateTime quand;
  final int crees;
  final int modifies;
  final int annules;
  final int inchanges;

  /// Les écritures que Google a refusées ou qui n'ont pas pu être faites (elles seront retentées à la prochaine fois).
  final int echecs;

  bool get complet => echecs == 0;
}

String _pluriel(int n, String singulier, String pluriel) => '$n ${n > 1 ? pluriel : singulier}';

/// Le résultat en une phrase : « 3 ajoutés, 1 modifié, 40 déjà à jour. »
String resumeSynchro(ResultatSynchro resultat) {
  final List<String> parties = <String>[
    if (resultat.crees > 0) _pluriel(resultat.crees, 'ajouté', 'ajoutés'),
    if (resultat.modifies > 0) _pluriel(resultat.modifies, 'modifié', 'modifiés'),
    if (resultat.annules > 0) _pluriel(resultat.annules, 'marqué « [Annulé] »', 'marqués « [Annulé] »'),
    if (resultat.echecs > 0) '${resultat.echecs} en échec',
  ];
  if (parties.isEmpty) {
    return resultat.inchanges > 0
        ? 'Tout est déjà à jour (${_pluriel(resultat.inchanges, 'élément', 'éléments')}).'
        : 'Rien à envoyer : aucun élément dans la période.';
  }
  if (resultat.inchanges > 0) parties.add('${resultat.inchanges} déjà à jour');
  return '${parties.join(', ')}.';
}
