import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/agenda_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late AgendaRepository repo;

  setUp(() {
    db = creerBaseEnMemoire();
    repo = AgendaRepository(db);
  });
  tearDown(() => db.close());

  Future<int> cours(
    String titre,
    DateTime debut, {
    int duree = 120,
    String? lieu,
    StatutCours statut = StatutCours.planifie,
    DateTime? archive,
  }) => db
      .into(db.cours)
      .insert(
        CoursCompanion.insert(
          titre: titre,
          debutLe: debut,
          dureeMinutes: duree,
          prixCentimes: 4500,
          places: 4,
          lieu: Value(lieu),
          statut: Value(statut),
          archiveLe: Value(archive),
        ),
      );

  Future<int> devis(
    String numero,
    DateTime? validite, {
    StatutDevis statut = StatutDevis.envoye,
    int? clientId,
    String? clientNom,
  }) => db
      .into(db.devis)
      .insert(
        DevisCompanion.insert(
          numero: numero,
          sousTotalCentimes: 6000,
          totalCentimes: 6000,
          dateEmission: Value(DateTime(2026, 1, 1)),
          dateValidite: Value(validite),
          statut: Value(statut),
          clientId: Value(clientId),
          clientNom: Value(clientNom),
        ),
      );

  DonneesEvenement donnees({
    String titre = 'Marché de Noël',
    DateTime? jour,
    bool journeeEntiere = true,
    Duration? debut,
    Duration? fin,
    String notes = '',
  }) => DonneesEvenement(
    titre: titre,
    jour: jour ?? DateTime(2026, 12, 12),
    journeeEntiere: journeeEntiere,
    heureDebut: debut,
    heureFin: fin,
    notes: notes,
  );

  final DateTime debutNovembre = DateTime(2026, 11, 1);
  final DateTime debutDecembre = DateTime(2026, 12, 1);

  group('événements de l’utilisatrice', () {
    test('un événement sur toute la journée est enregistré à minuit, sans heure de fin', () async {
      final EvenementAgenda e = await repo.creer(
        donnees(titre: '  Marché   de Noël ', jour: DateTime(2026, 12, 12, 15, 40), notes: '  Prévoir la nappe  '),
      );

      expect(e.titre, 'Marché de Noël');
      expect(e.notes, 'Prévoir la nappe');
      expect(e.debutLe, DateTime(2026, 12, 12));
      expect(e.finLe, isNull);
      expect(e.journeeEntiere, isTrue);
      expect(await repo.obtenir(e.id), isNotNull);
    });

    test('un événement à heure fixe : le jour, l’heure de début et l’heure de fin', () async {
      final EvenementAgenda e = await repo.creer(
        donnees(journeeEntiere: false, debut: const Duration(hours: 9, minutes: 30), fin: const Duration(hours: 17)),
      );

      expect(e.journeeEntiere, isFalse);
      expect(e.debutLe, DateTime(2026, 12, 12, 9, 30));
      expect(e.finLe, DateTime(2026, 12, 12, 17));
    });

    test('sans heure de début, un événement à heure fixe commence à minuit ; sans heure de fin, il n’en a pas', () async {
      final EvenementAgenda e = await repo.creer(donnees(journeeEntiere: false));
      expect(e.debutLe, DateTime(2026, 12, 12));
      expect(e.finLe, isNull);
    });

    test('sur toute la journée, les heures saisies sont ignorées', () async {
      final EvenementAgenda e = await repo.creer(
        donnees(debut: const Duration(hours: 18), fin: const Duration(hours: 9)),
      );
      expect(e.debutLe, DateTime(2026, 12, 12));
      expect(e.finLe, isNull);
    });

    test('un titre vide, trop long ou des précisions trop longues sont refusés avec un message clair', () async {
      await expectLater(
        repo.creer(donnees(titre: '   ')),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('titre'))),
      );
      await expectLater(repo.creer(donnees(titre: 'a' * (longueurMaxTitreEvenement + 1))), throwsA(isA<DonneeInvalide>()));
      await expectLater(repo.creer(donnees(notes: 'a' * (longueurMaxNotesEvenement + 1))), throwsA(isA<DonneeInvalide>()));
      expect(await repo.lister(), isEmpty);
    });

    test('l’heure de fin doit être après l’heure de début', () async {
      await expectLater(
        repo.creer(donnees(journeeEntiere: false, debut: const Duration(hours: 10), fin: const Duration(hours: 10))),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('fin'))),
      );
      await expectLater(
        repo.creer(donnees(journeeEntiere: false, debut: const Duration(hours: 10), fin: const Duration(hours: 9))),
        throwsA(isA<DonneeInvalide>()),
      );
      // Une fin sans heure de début : le début est minuit.
      await expectLater(repo.creer(donnees(journeeEntiere: false, fin: Duration.zero)), throwsA(isA<DonneeInvalide>()));
      expect(await repo.lister(), isEmpty);
    });

    test('la liste va du plus proche au plus lointain', () async {
      await repo.creer(donnees(titre: 'Fin', jour: DateTime(2026, 12, 24)));
      await repo.creer(donnees(titre: 'Début', jour: DateTime(2026, 11, 3)));
      await repo.creer(donnees(titre: 'Milieu', jour: DateTime(2026, 12, 1)));

      expect((await repo.lister()).map((EvenementAgenda e) => e.titre), <String>['Début', 'Milieu', 'Fin']);
    });

    test('modifier change le titre, le jour, les heures et les précisions', () async {
      final EvenementAgenda e = await repo.creer(donnees());

      final EvenementAgenda modifie = await repo.modifier(
        e.id,
        donnees(
          titre: 'Salon du fait main',
          jour: DateTime(2026, 11, 28),
          journeeEntiere: false,
          debut: const Duration(hours: 10),
          fin: const Duration(hours: 18),
          notes: 'Stand 14',
        ),
      );

      expect(modifie.id, e.id);
      expect(modifie.titre, 'Salon du fait main');
      expect(modifie.debutLe, DateTime(2026, 11, 28, 10));
      expect(modifie.finLe, DateTime(2026, 11, 28, 18));
      expect(modifie.journeeEntiere, isFalse);
      expect(modifie.notes, 'Stand 14');
      expect(await repo.lister(), hasLength(1));
    });

    test('passer un événement sur toute la journée retire son heure de fin', () async {
      final EvenementAgenda e = await repo.creer(
        donnees(journeeEntiere: false, debut: const Duration(hours: 9), fin: const Duration(hours: 11)),
      );
      final EvenementAgenda modifie = await repo.modifier(e.id, donnees());
      expect(modifie.debutLe, DateTime(2026, 12, 12));
      expect(modifie.finLe, isNull);
    });

    test('une modification refusée ne change rien ; un événement supprimé entre-temps est signalé', () async {
      final EvenementAgenda e = await repo.creer(donnees());

      await expectLater(repo.modifier(e.id, donnees(titre: '')), throwsA(isA<DonneeInvalide>()));
      expect((await repo.obtenir(e.id))!.titre, 'Marché de Noël');

      await repo.supprimer(e.id);
      await expectLater(repo.modifier(e.id, donnees()), throwsA(isA<ElementIntrouvable>()));
    });

    test('supprimer retire l’événement ; supprimer deux fois ne fait pas d’erreur', () async {
      final EvenementAgenda e = await repo.creer(donnees());
      final EvenementAgenda autre = await repo.creer(donnees(titre: 'Autre'));

      await repo.supprimer(e.id);
      await repo.supprimer(e.id);

      expect(await repo.obtenir(e.id), isNull);
      expect((await repo.lister()).single.id, autre.id);
    });
  });

  group('ce qui s’affiche dans le calendrier', () {
    test('les cours : au jour et à l’heure de leur début, avec leur durée et leur lieu', () async {
      final int id = await cours('Initiation au crochet', DateTime(2026, 11, 23, 14), duree: 150, lieu: 'Atelier de Camille');

      final List<EntreeAgenda> entrees = await repo.entrees(debutNovembre, debutDecembre);

      final EntreeAgenda e = entrees.firstWhere((EntreeAgenda x) => x.type == TypeEntreeAgenda.cours);
      expect(e.titre, 'Initiation au crochet');
      expect(e.debut, DateTime(2026, 11, 23, 14));
      expect(e.fin, DateTime(2026, 11, 23, 16, 30));
      expect(e.lieu, 'Atelier de Camille');
      expect(e.journeeEntiere, isFalse);
      expect(e.identifiant, id);
    });

    test('un cours annulé ou archivé n’est pas affiché ; un cours hors de la période non plus', () async {
      await cours('Annulé', DateTime(2026, 11, 10, 10), statut: StatutCours.annule);
      await cours('Archivé', DateTime(2026, 11, 11, 10), archive: DateTime(2026, 11, 12));
      await cours('Avant', DateTime(2026, 10, 31, 23, 59));
      await cours('Après', DateTime(2026, 12, 1));
      await cours('Dedans', DateTime(2026, 11, 1));

      final List<EntreeAgenda> entrees = await repo.entrees(debutNovembre, debutDecembre, filtres: const FiltresAgenda(declaration: false));

      expect(entrees.map((EntreeAgenda e) => e.titre), <String>['Dedans']);
    });

    test('un devis ouvert : son dernier jour de validité, avec le nom du client', () async {
      final int clientId = await db.insererClient(nom: 'Camille Martin');
      final int id = await devis('DEVIS-2026-0001', DateTime(2026, 11, 20), clientId: clientId, statut: StatutDevis.brouillon);

      final List<EntreeAgenda> entrees = await repo.entrees(
        debutNovembre,
        debutDecembre,
        maintenant: DateTime(2026, 11, 10, 9),
      );

      final EntreeAgenda e = entrees.firstWhere((EntreeAgenda x) => x.type == TypeEntreeAgenda.devis);
      expect(e.titre, 'Fin de validité du devis DEVIS-2026-0001');
      expect(e.debut, DateTime(2026, 11, 20));
      expect(e.journeeEntiere, isTrue);
      expect(e.detail, contains('Camille Martin'));
      expect(e.identifiant, id);
    });

    test('un devis sans client : « Sans client » ; avec une fiche supprimée : le nom gardé', () async {
      await devis('DEVIS-2026-0001', DateTime(2026, 11, 20));
      await devis('DEVIS-2026-0002', DateTime(2026, 11, 21), clientNom: 'Léa Durand');

      final List<EntreeAgenda> entrees = await repo.entrees(
        debutNovembre,
        debutDecembre,
        filtres: const FiltresAgenda(declaration: false),
        maintenant: DateTime(2026, 11, 10),
      );

      expect(entrees.map((EntreeAgenda e) => e.detail), <String>['Sans client', 'Léa Durand (client supprimé)']);
    });

    test('un devis accepté, refusé ou expiré, ou sans date de validité, n’est pas affiché', () async {
      await devis('DEVIS-2026-0001', DateTime(2026, 11, 20), statut: StatutDevis.accepte);
      await devis('DEVIS-2026-0002', DateTime(2026, 11, 20), statut: StatutDevis.refuse);
      await devis('DEVIS-2026-0003', DateTime(2026, 11, 20), statut: StatutDevis.expire);
      await devis('DEVIS-2026-0004', null);

      final List<EntreeAgenda> entrees = await repo.entrees(
        debutNovembre,
        debutDecembre,
        filtres: const FiltresAgenda(declaration: false),
        maintenant: DateTime(2026, 11, 10),
      );

      expect(entrees, isEmpty);
    });

    test('un devis dont la validité est dépassée n’est plus affiché ; le dernier jour, il l’est encore', () async {
      await devis('DEVIS-2026-0001', DateTime(2026, 11, 20));
      const FiltresAgenda seulementLesDevis = FiltresAgenda(cours: false, declaration: false, evenements: false);

      expect(
        await repo.entrees(debutNovembre, debutDecembre, filtres: seulementLesDevis, maintenant: DateTime(2026, 11, 20, 21, 30)),
        hasLength(1),
      );
      expect(
        await repo.entrees(debutNovembre, debutDecembre, filtres: seulementLesDevis, maintenant: DateTime(2026, 11, 21, 0, 5)),
        isEmpty,
      );
    });

    test('la déclaration des recettes : le dernier jour de chaque mois de la période', () async {
      final List<EntreeAgenda> entrees = await repo.entrees(DateTime(2026, 10, 26), DateTime(2026, 12, 7));

      expect(entrees.map((EntreeAgenda e) => e.debut), <DateTime>[DateTime(2026, 10, 31), DateTime(2026, 11, 30)]);
      expect(entrees.every((EntreeAgenda e) => e.type == TypeEntreeAgenda.declaration), isTrue);
    });

    test('les événements de l’utilisatrice, tels qu’elle les a saisis', () async {
      final EvenementAgenda e = await repo.creer(
        donnees(
          titre: 'Salon',
          jour: DateTime(2026, 11, 28),
          journeeEntiere: false,
          debut: const Duration(hours: 10),
          fin: const Duration(hours: 18),
          notes: 'Stand 14',
        ),
      );
      await repo.creer(donnees(titre: 'Hors période', jour: DateTime(2026, 12, 1)));

      final List<EntreeAgenda> entrees = await repo.entrees(
        debutNovembre,
        debutDecembre,
        filtres: const FiltresAgenda(declaration: false),
      );

      final EntreeAgenda entree = entrees.single;
      expect(entree.type, TypeEntreeAgenda.evenement);
      expect(entree.titre, 'Salon');
      expect(entree.debut, DateTime(2026, 11, 28, 10));
      expect(entree.fin, DateTime(2026, 11, 28, 18));
      expect(entree.detail, 'Stand 14');
      expect(entree.identifiant, e.id);
    });

    test('chaque filtre masque son type, et seulement lui', () async {
      await cours('Atelier', DateTime(2026, 11, 5, 14));
      await devis('DEVIS-2026-0001', DateTime(2026, 11, 6));
      await repo.creer(donnees(titre: 'Marché', jour: DateTime(2026, 11, 7)));
      final DateTime maintenant = DateTime(2026, 11, 1);

      Future<Set<TypeEntreeAgenda>> types(FiltresAgenda filtres) async =>
          (await repo.entrees(debutNovembre, debutDecembre, filtres: filtres, maintenant: maintenant))
              .map((EntreeAgenda e) => e.type)
              .toSet();

      expect(await types(const FiltresAgenda()), TypeEntreeAgenda.values.toSet());
      for (final TypeEntreeAgenda type in TypeEntreeAgenda.values) {
        expect(
          await types(const FiltresAgenda().avec(type, affiche: false)),
          TypeEntreeAgenda.values.toSet()..remove(type),
          reason: '${type.name} masqué',
        );
      }
      expect(
        await types(const FiltresAgenda(cours: false, devis: false, declaration: false, evenements: false)),
        isEmpty,
      );
    });

    test('tout est rangé par jour, puis par heure', () async {
      await cours('Atelier', DateTime(2026, 11, 30, 14));
      await repo.creer(donnees(titre: 'Matin', jour: DateTime(2026, 11, 30), journeeEntiere: false, debut: const Duration(hours: 9)));
      await repo.creer(donnees(titre: 'Veille', jour: DateTime(2026, 11, 29)));
      await repo.creer(donnees(titre: 'Tôt', jour: DateTime(2026, 11, 3), journeeEntiere: false, debut: const Duration(hours: 10)));

      final List<EntreeAgenda> entrees = await repo.entrees(debutNovembre, debutDecembre);

      // Le 3, puis le 29, puis le 30 : la déclaration (toute la journée) d'abord, puis 9 h, puis 14 h.
      expect(entrees.map((EntreeAgenda e) => e.titre), <String>['Tôt', 'Veille', titreDeclaration, 'Matin', 'Atelier']);
    });

    test('le début de la période est compris, la fin est exclue', () async {
      await repo.creer(donnees(titre: 'Premier', jour: DateTime(2026, 11, 1)));
      await repo.creer(donnees(titre: 'Dernier', jour: DateTime(2026, 11, 30)));
      await repo.creer(donnees(titre: 'Suivant', jour: DateTime(2026, 12, 1)));

      final List<EntreeAgenda> entrees = await repo.entrees(
        debutNovembre,
        debutDecembre,
        filtres: const FiltresAgenda(declaration: false),
      );

      expect(entrees.map((EntreeAgenda e) => e.titre), <String>['Premier', 'Dernier']);
    });
  });

  group('mise à jour automatique', () {
    /// Attend qu'au moins [nombre] listes aient été reçues.
    Future<void> attendre(List<List<EntreeAgenda>> recues, int nombre) async {
      for (int i = 0; i < 500 && recues.length < nombre; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(recues.length, greaterThanOrEqualTo(nombre));
    }

    test('un événement, un cours ou un devis ajoutés ou supprimés rafraîchissent la liste', () async {
      final List<List<EntreeAgenda>> recues = <List<EntreeAgenda>>[];
      final StreamSubscription<List<EntreeAgenda>> abonnement = repo
          .observerEntrees(
            debutNovembre,
            debutDecembre,
            filtres: const FiltresAgenda(declaration: false),
            horloge: () => DateTime(2026, 11, 1),
          )
          .listen(recues.add);

      await attendre(recues, 1);
      expect(recues.last, isEmpty);

      final EvenementAgenda e = await repo.creer(donnees(jour: DateTime(2026, 11, 12)));
      await attendre(recues, 2);
      expect(recues.last.map((EntreeAgenda x) => x.titre), <String>['Marché de Noël']);

      await cours('Atelier', DateTime(2026, 11, 14, 10));
      await attendre(recues, 3);
      expect(recues.last, hasLength(2));

      await devis('DEVIS-2026-0001', DateTime(2026, 11, 20));
      await attendre(recues, 4);
      expect(recues.last, hasLength(3));

      await repo.supprimer(e.id);
      await attendre(recues, 5);
      expect(recues.last.map((EntreeAgenda x) => x.type), <TypeEntreeAgenda>[TypeEntreeAgenda.cours, TypeEntreeAgenda.devis]);

      await abonnement.cancel();
    });

    test('le flux des changements signale tout ce qui alimente le calendrier (pour la synchro Google Agenda)', () async {
      int signaux = 0;
      final StreamSubscription<int> abonnement = repo.observerChangements().listen((int _) => signaux++);
      Future<void> attendreSignaux(int nombre) async {
        for (int i = 0; i < 500 && signaux < nombre; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(signaux, greaterThanOrEqualTo(nombre));
      }

      // Le premier signal est la lecture de départ.
      await attendreSignaux(1);

      final EvenementAgenda e = await repo.creer(donnees(jour: DateTime(2026, 11, 12)));
      await attendreSignaux(2);

      await cours('Atelier', DateTime(2026, 11, 14, 10));
      await attendreSignaux(3);

      await devis('DEVIS-2026-0001', DateTime(2026, 11, 20));
      await attendreSignaux(4);

      await db.insererClient();
      await attendreSignaux(5);

      await repo.supprimer(e.id);
      await attendreSignaux(6);

      await abonnement.cancel();
    });
  });

  group('réglages d’affichage', () {
    late ParametresRepository parametres;

    setUp(() => parametres = ParametresRepository(db));

    test('au départ, tout est affiché', () async {
      expect(ParametresRepository.filtresAgendaDe(await parametres.lire()), const FiltresAgenda());
    });

    test('le choix est mémorisé, type par type', () async {
      await parametres.enregistrerFiltresAgenda(const FiltresAgenda(devis: false, declaration: false));

      final FiltresAgenda lus = ParametresRepository.filtresAgendaDe(await parametres.lire());
      expect(lus.cours, isTrue);
      expect(lus.devis, isFalse);
      expect(lus.declaration, isFalse);
      expect(lus.evenements, isTrue);

      await parametres.enregistrerFiltresAgenda(lus.avec(TypeEntreeAgenda.devis, affiche: true));
      expect(ParametresRepository.filtresAgendaDe(await parametres.lire()), const FiltresAgenda(declaration: false));
    });

    test('changer l’affichage ne touche pas au reste du profil', () async {
      await parametres.modifier(const ParametresEntrepriseCompanion(nomCommercial: Value('Les Mailles de Camille')));

      await parametres.enregistrerFiltresAgenda(const FiltresAgenda(cours: false));

      expect((await parametres.lire()).nomCommercial, 'Les Mailles de Camille');
    });

    test('le flux des réglages se met à jour quand le choix change', () async {
      final List<FiltresAgenda> recus = <FiltresAgenda>[];
      final StreamSubscription<Entreprise> abonnement = parametres.observer().listen(
        (Entreprise e) => recus.add(ParametresRepository.filtresAgendaDe(e)),
      );
      for (int i = 0; i < 500 && recus.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(recus.first, const FiltresAgenda());

      await parametres.enregistrerFiltresAgenda(const FiltresAgenda(evenements: false));
      for (int i = 0; i < 500 && recus.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(recus.last, const FiltresAgenda(evenements: false));

      await abonnement.cancel();
    });
  });
}
