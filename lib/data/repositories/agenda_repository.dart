import 'package:drift/drift.dart';

import '../../domain/agenda.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_devis.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import 'client_vues.dart';

/// Longueur maximale du titre d'un événement.
const int longueurMaxTitreEvenement = 120;

/// Longueur maximale des précisions d'un événement.
const int longueurMaxNotesEvenement = 1000;

/// Ce que saisit l'utilisatrice pour un événement du calendrier.
class DonneesEvenement {
  const DonneesEvenement({
    required this.titre,
    required this.jour,
    this.journeeEntiere = true,
    this.heureDebut,
    this.heureFin,
    this.notes = '',
  });

  final String titre;

  /// Le jour de l'événement (l'heure de cette date est ignorée).
  final DateTime jour;
  final bool journeeEntiere;

  /// Heures de début et de fin, comptées depuis minuit (ignorées pour un événement « toute la journée »). Sans heure de
  /// début, un événement à heure fixe commence à minuit.
  final Duration? heureDebut;
  final Duration? heureFin;
  final String notes;

  String get titrePropre => titre.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Début et fin tels qu'ils sont enregistrés : minuit sans fin pour « toute la journée », sinon le jour à l'heure choisie.
  ({DateTime debut, DateTime? fin}) get horaires {
    final DateTime minuit = jourDe(jour);
    if (journeeEntiere) return (debut: minuit, fin: null);
    // On compose l'heure sur le jour (`DateTime(a, m, j, h, min)`) : un changement d'heure ne décale pas l'événement.
    DateTime a(Duration depuisMinuit) =>
        DateTime(minuit.year, minuit.month, minuit.day, depuisMinuit.inHours, depuisMinuit.inMinutes % 60);
    final DateTime debut = a(heureDebut ?? Duration.zero);
    final Duration? fin = heureFin;
    return (debut: debut, fin: fin == null ? null : a(fin));
  }

  /// Lance [DonneeInvalide] (message en français) si une valeur est impossible.
  void valider() {
    if (titrePropre.isEmpty) throw const DonneeInvalide('Donnez un titre à l’événement.');
    if (titrePropre.length > longueurMaxTitreEvenement) {
      throw const DonneeInvalide('Le titre d’un événement est limité à $longueurMaxTitreEvenement caractères.');
    }
    if (notes.trim().length > longueurMaxNotesEvenement) {
      throw const DonneeInvalide('Les précisions d’un événement sont limitées à $longueurMaxNotesEvenement caractères.');
    }
    final Duration? fin = heureFin;
    if (!journeeEntiere && fin != null && fin <= (heureDebut ?? Duration.zero)) {
      throw const DonneeInvalide('L’heure de fin doit être après l’heure de début.');
    }
  }
}

/// Le calendrier : les événements de l'utilisatrice (créer, modifier, supprimer) et tout ce qui s'y affiche (avec les
/// cours, les devis et les jours de déclaration, qui viennent de leurs propres tables).
class AgendaRepository {
  AgendaRepository(this._db);

  final AppDatabase _db;

  // --- Événements de l'utilisatrice --------------------------------------------

  Future<EvenementAgenda?> obtenir(int id) =>
      (_db.select(_db.evenementsAgenda)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Tous les événements, du plus proche au plus lointain.
  Future<List<EvenementAgenda>> lister() =>
      (_db.select(_db.evenementsAgenda)..orderBy([(t) => OrderingTerm.asc(t.debutLe), (t) => OrderingTerm.asc(t.id)])).get();

  /// Crée un événement. Lance [DonneeInvalide] si le titre est vide ou trop long ou si l'heure de fin n'est pas après celle de début.
  Future<EvenementAgenda> creer(DonneesEvenement donnees) async {
    donnees.valider();
    final ({DateTime debut, DateTime? fin}) h = donnees.horaires;
    final int id = await _db
        .into(_db.evenementsAgenda)
        .insert(
          EvenementsAgendaCompanion.insert(
            titre: donnees.titrePropre,
            notes: Value(donnees.notes.trim()),
            debutLe: h.debut,
            finLe: Value(h.fin),
            journeeEntiere: Value(donnees.journeeEntiere),
          ),
        );
    return (await obtenir(id))!;
  }

  /// Modifie un événement. Lance [ElementIntrouvable] s'il a été supprimé entre-temps.
  Future<EvenementAgenda> modifier(int id, DonneesEvenement donnees) async {
    donnees.valider();
    final ({DateTime debut, DateTime? fin}) h = donnees.horaires;
    final int modifies = await (_db.update(_db.evenementsAgenda)..where((t) => t.id.equals(id))).write(
      EvenementsAgendaCompanion(
        titre: Value(donnees.titrePropre),
        notes: Value(donnees.notes.trim()),
        debutLe: Value(h.debut),
        finLe: Value(h.fin),
        journeeEntiere: Value(donnees.journeeEntiere),
        modifieLe: Value(DateTime.now()),
      ),
    );
    if (modifies == 0) throw const ElementIntrouvable('Cet événement n’existe plus.');
    return (await obtenir(id))!;
  }

  /// Supprime un événement. Aucun autre élément de l'application n'en dépend. Un événement déjà supprimé est ignoré.
  Future<void> supprimer(int id) => (_db.delete(_db.evenementsAgenda)..where((t) => t.id.equals(id))).go();

  // --- Ce qui s'affiche dans le calendrier --------------------------------------

  /// Tout ce qui est prévu du [debut] (inclus) à la [fin] (exclue), tous types confondus. [filtres] masque des types.
  ///
  /// - **Cours** : ceux qui ne sont ni annulés ni archivés, au jour et à l'heure de leur début, avec leur durée et leur lieu.
  /// - **Devis** : le dernier jour de validité d'un devis encore ouvert (brouillon ou envoyé, pas encore expiré).
  /// - **Déclaration** : le dernier jour de chaque mois.
  /// - **Mes événements** : ceux de l'utilisatrice.
  Future<List<EntreeAgenda>> entrees(DateTime debut, DateTime fin, {FiltresAgenda filtres = const FiltresAgenda(), DateTime? maintenant}) async {
    final List<EntreeAgenda> resultat = <EntreeAgenda>[];

    if (filtres.cours) {
      final List<CoursFiche> cours =
          await (_db.select(_db.cours)..where(
                (t) =>
                    t.archiveLe.isNull() &
                    t.statut.equalsValue(StatutCours.annule).not() &
                    t.debutLe.isBiggerOrEqualValue(debut) &
                    t.debutLe.isSmallerThanValue(fin),
              ))
              .get();
      for (final CoursFiche c in cours) {
        resultat.add(
          EntreeAgenda(
            type: TypeEntreeAgenda.cours,
            titre: c.titre,
            debut: c.debutLe,
            fin: c.debutLe.add(Duration(minutes: c.dureeMinutes)),
            lieu: c.lieu,
            identifiant: c.id,
          ),
        );
      }
    }

    if (filtres.devis) {
      final DateTime instant = maintenant ?? DateTime.now();
      final List<DevisFiche> devis =
          await (_db.select(_db.devis)..where(
                (t) =>
                    t.statut.isInValues(<StatutDevis>[StatutDevis.brouillon, StatutDevis.envoye]) &
                    t.dateValidite.isBiggerOrEqualValue(debut) &
                    t.dateValidite.isSmallerThanValue(fin),
              ))
              .get();
      if (devis.isNotEmpty) {
        final Map<int, Client> clients = <int, Client>{for (final Client c in await _db.select(_db.clients).get()) c.id: c};
        for (final DevisFiche d in devis) {
          final DateTime? validite = d.dateValidite;
          if (validite == null) continue;
          // Un devis dont la validité est déjà dépassée est « Expiré » : il n'y a plus rien à y faire.
          if (validiteDepassee(validite, instant)) continue;
          final Client? client = d.clientId == null ? null : clients[d.clientId];
          resultat.add(
            EntreeAgenda(
              type: TypeEntreeAgenda.devis,
              titre: 'Fin de validité du devis ${d.numero}',
              debut: jourDe(validite),
              journeeEntiere: true,
              detail: nomClientOuCopie(client: client, copie: d.clientNom, sinon: 'Sans client'),
              identifiant: d.id,
            ),
          );
        }
      }
    }

    if (filtres.declaration) resultat.addAll(echeancesDeclaration(debut, fin));

    if (filtres.evenements) {
      final List<EvenementAgenda> evenements =
          await (_db.select(_db.evenementsAgenda)..where((t) => t.debutLe.isBiggerOrEqualValue(debut) & t.debutLe.isSmallerThanValue(fin))).get();
      for (final EvenementAgenda e in evenements) {
        resultat.add(
          EntreeAgenda(
            type: TypeEntreeAgenda.evenement,
            titre: e.titre,
            debut: e.debutLe,
            fin: e.finLe,
            journeeEntiere: e.journeeEntiere,
            detail: e.notes.trim().isEmpty ? null : e.notes.trim(),
            identifiant: e.id,
          ),
        );
      }
    }

    resultat.sort(comparerEntrees);
    return resultat;
  }

  /// Ce qui est prévu du [debut] à la [fin], mis à jour automatiquement (cours, devis, client ou événement modifié).
  /// [horloge] donne l'heure « maintenant » (un devis dont la validité est dépassée n'est plus montré) ; les tests la fixent.
  Stream<List<EntreeAgenda>> observerEntrees(
    DateTime debut,
    DateTime fin, {
    FiltresAgenda filtres = const FiltresAgenda(),
    DateTime Function()? horloge,
  }) => observerTables(
    _db,
    <ResultSetImplementation>{_db.cours, _db.devis, _db.clients, _db.evenementsAgenda},
    () => entrees(debut, fin, filtres: filtres, maintenant: horloge?.call()),
  );

  /// Annonce, sans rien relire, que ce qui alimente le calendrier a changé (un cours, un devis, un client ou un événement
  /// créé, modifié ou supprimé). Sert à relancer la synchronisation vers Google Agenda ; la valeur émise n'a pas de sens.
  Stream<int> observerChangements() => observerTables<int>(
    _db,
    <ResultSetImplementation>{_db.cours, _db.devis, _db.clients, _db.evenementsAgenda},
    () async => 0,
  );
}
