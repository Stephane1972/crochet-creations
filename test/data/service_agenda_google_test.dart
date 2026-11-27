import 'package:crochet_creations/data/agenda/client_agenda_google.dart';
import 'package:crochet_creations/data/agenda/service_agenda_google.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/drive/compte_google_indisponible.dart';
import 'package:crochet_creations/data/repositories/agenda_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/domain/agenda_google.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_agenda_google.dart';
import 'aide_base.dart';
import 'aide_drive.dart';

void main() {
  late AppDatabase db;
  late ParametresRepository parametres;
  late AgendaRepository agenda;
  late FauxCompteGoogle compte;
  late FauxClientAgendaGoogle google;
  late DateTime maintenant;
  late ServiceAgendaGoogle service;

  setUp(() async {
    db = creerBaseEnMemoire();
    parametres = ParametresRepository(db);
    agenda = AgendaRepository(db);
    compte = FauxCompteGoogle()
      ..dejaConnecte = const ProfilGoogle(email: 'stef@exemple.fr')
      ..agendaAccorde = true;
    google = FauxClientAgendaGoogle();
    maintenant = DateTime(2026, 11, 23, 10);
    service = ServiceAgendaGoogle(
      agenda: agenda,
      parametres: parametres,
      compte: compte,
      client: google,
      horloge: () => maintenant,
    );
    // Les jours de déclaration (un par mois, 14 sur la période) brouilleraient les comptes : sauf mention contraire, on ne
    // synchronise que le reste.
    await parametres.enregistrerFiltresAgenda(const FiltresAgenda(declaration: false));
  });
  tearDown(() => db.close());

  Future<EvenementAgenda> evenement(String titre, DateTime jour) => agenda.creer(DonneesEvenement(titre: titre, jour: jour));

  Future<int> cours(String titre, DateTime debut) => db
      .into(db.cours)
      .insert(CoursCompanion.insert(titre: titre, debutLe: debut, dureeMinutes: 120, prixCentimes: 4500, places: 4));

  Future<String> calendrierMemorise() async => (await parametres.lireAgendaGoogle()).calendrier!;

  /// Active la synchronisation et vérifie que la première synchronisation s'est bien passée.
  Future<void> activerEtSynchroniser() async {
    final BilanSynchro bilan = await service.activer();
    expect(bilan.issue, IssueSynchro.reussie, reason: bilan.message);
  }

  group('disponibilité', () {
    test('disponible avec un compte qui sait demander le droit « agenda » et un client', () {
      expect(service.disponible, isTrue);
    });

    test('indisponible avec un compte sans droit « agenda » (Windows sans connexion) : rien n’est tenté', () async {
      final ServiceAgendaGoogle sansCompte = ServiceAgendaGoogle(
        agenda: agenda,
        parametres: parametres,
        compte: const CompteGoogleIndisponible(),
        client: google,
      );

      expect(sansCompte.disponible, isFalse);
      expect((await sansCompte.activer()).issue, IssueSynchro.indisponible);
      expect((await sansCompte.synchroniser()).issue, IssueSynchro.indisponible);
      expect(await sansCompte.droitAccorde(), isFalse);
      expect(google.journal, isEmpty);
    });

    test('indisponible sans client Google Agenda', () async {
      final ServiceAgendaGoogle sansClient = ServiceAgendaGoogle(agenda: agenda, parametres: parametres, compte: compte);

      expect(sansClient.disponible, isFalse);
      expect((await sansClient.activer()).issue, IssueSynchro.indisponible);
    });

    test('le droit est accordé seulement si la personne est connectée et l’a donné', () async {
      expect(await service.droitAccorde(), isTrue);

      compte.agendaAccorde = false;
      expect(await service.droitAccorde(), isFalse);

      compte
        ..agendaAccorde = true
        ..dejaConnecte = null;
      expect(await service.droitAccorde(), isFalse);
    });
  });

  group('activer', () {
    test('droit déjà accordé : mémorise le choix, crée l’agenda et y envoie le calendrier', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.reussie);
      expect(bilan.resultat!.crees, 1);
      expect(compte.demandesAgenda, 0);
      expect(google.appels('creerCalendrier'), 1);
      final ({bool actif, String? calendrier}) reglage = await parametres.lireAgendaGoogle();
      expect(reglage.actif, isTrue);
      expect(reglage.calendrier, 'agenda-test-1');
      final EvenementGoogle? envoye = google.evenement('agenda-test-1', 'ptite1');
      expect(envoye, isNotNull);
      expect(envoye!.titre, 'Marché de Noël');
      expect(envoye.journeeEntiere, isTrue);
      expect(envoye.debut, DateTime.utc(2026, 12, 12));
      expect(envoye.fin, DateTime.utc(2026, 12, 13));
      expect(envoye.type, TypeEntreeAgenda.evenement);
    });

    test('droit absent : il est demandé, puis la synchronisation a lieu', () async {
      compte.agendaAccorde = false;
      await evenement('Marché de Noël', DateTime(2026, 12, 12));

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.reussie);
      expect(compte.demandesAgenda, 1);
      expect(compte.agendaAccorde, isTrue);
      expect((await parametres.lireAgendaGoogle()).actif, isTrue);
    });

    test('si la personne ferme la fenêtre d’autorisation : rien n’est activé, rien n’est envoyé', () async {
      compte
        ..agendaAccorde = false
        ..reponseDemandeAgenda = false;
      await evenement('Marché de Noël', DateTime(2026, 12, 12));

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.annulee);
      final ({bool actif, String? calendrier}) reglage = await parametres.lireAgendaGoogle();
      expect(reglage.actif, isFalse);
      expect(reglage.calendrier, isNull);
      expect(google.journal, isEmpty);
    });

    test('une erreur d’autorisation est expliquée et n’active rien', () async {
      compte
        ..agendaAccorde = false
        ..erreurDAutorisationAgenda = const ErreurDrive('Google a refusé le droit « Google Agenda ».');

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.droitAbsent);
      expect(bilan.message, 'Google a refusé le droit « Google Agenda ».');
      expect((await parametres.lireAgendaGoogle()).actif, isFalse);
      expect(google.journal, isEmpty);
    });

    test('si la personne n’est pas connectée à Google : rien n’est demandé ni activé', () async {
      compte.dejaConnecte = null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.nonConnecte);
      expect(compte.demandesAgenda, 0);
      expect((await parametres.lireAgendaGoogle()).actif, isFalse);
      expect(google.journal, isEmpty);
    });
  });

  group('synchroniser', () {
    test('sans activation, ne fait rien', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));

      expect((await service.synchroniser()).issue, IssueSynchro.desactivee);
      expect(google.journal, isEmpty);
    });

    test('envoie les cours et les événements, chacun avec son identifiant stable', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await cours('Atelier crochet', DateTime(2026, 12, 5, 18));

      final BilanSynchro bilan = await service.activer();

      expect(bilan.resultat!.crees, 2);
      final String agendaGoogle = await calendrierMemorise();
      expect(google.evenement(agendaGoogle, 'ptite1')!.type, TypeEntreeAgenda.evenement);
      final EvenementGoogle atelier = google.evenement(agendaGoogle, 'ptitc1')!;
      expect(atelier.titre, 'Atelier crochet');
      expect(atelier.journeeEntiere, isFalse);
      expect(atelier.debut, DateTime(2026, 12, 5, 18).toUtc());
      expect(atelier.fin, DateTime(2026, 12, 5, 20).toUtc());
      expect(atelier.type, TypeEntreeAgenda.cours);
    });

    test('envoie aussi les jours de déclaration quand ils sont affichés', () async {
      await parametres.enregistrerFiltresAgenda(const FiltresAgenda());
      final ({DateTime debut, DateTime fin}) fenetre = fenetreSynchro(maintenant);
      final int attendues = echeancesDeclaration(fenetre.debut, fenetre.fin).length;
      expect(attendues, 14);

      final BilanSynchro bilan = await service.activer();

      expect(bilan.resultat!.crees, attendues);
      final String agendaGoogle = await calendrierMemorise();
      expect(google.evenement(agendaGoogle, 'ptitd20261130'), isNotNull);
      expect(google.evenement(agendaGoogle, 'ptitd20271130'), isNotNull);
    });

    test('une seconde synchronisation sans changement n’écrit rien', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await cours('Atelier crochet', DateTime(2026, 12, 5, 18));
      await activerEtSynchroniser();
      final int ecrituresAvant = google.ecritures.length;

      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.issue, IssueSynchro.reussie);
      expect(bilan.resultat!.crees, 0);
      expect(bilan.resultat!.modifies, 0);
      expect(bilan.resultat!.annules, 0);
      expect(bilan.resultat!.inchanges, 2);
      expect(google.ecritures, hasLength(ecrituresAvant));
    });

    test('le résultat porte l’heure de la synchronisation', () async {
      await activerEtSynchroniser();

      expect((await service.synchroniser()).resultat!.quand, maintenant);
    });

    test('modifier un élément modifie son événement, sans en créer un second', () async {
      final EvenementAgenda e = await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();

      await agenda.modifier(e.id, DonneesEvenement(titre: 'Marché de printemps', jour: DateTime(2026, 12, 13)));
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.resultat!.modifies, 1);
      expect(bilan.resultat!.crees, 0);
      expect(google.calendriers[agendaGoogle], hasLength(1));
      final EvenementGoogle modifie = google.evenement(agendaGoogle, 'ptite1')!;
      expect(modifie.titre, 'Marché de printemps');
      expect(modifie.debut, DateTime.utc(2026, 12, 13));
      expect(google.ecritures.last, 'remplacer:ptite1');
    });

    test('un élément supprimé de l’application est marqué « [Annulé] » dans Google, jamais supprimé', () async {
      final EvenementAgenda perdu = await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await evenement('Salon créateurs', DateTime(2026, 12, 20));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();

      await agenda.supprimer(perdu.id);
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.issue, IssueSynchro.reussie);
      expect(bilan.resultat!.annules, 1);
      expect(google.appels('supprimer'), 0);
      expect(google.calendriers[agendaGoogle], hasLength(2));
      final EvenementGoogle annule = google.evenement(agendaGoogle, 'ptite${perdu.id}')!;
      expect(annule.titre, '[Annulé] Marché de Noël');
      expect(annule.estAnnule, isTrue);
      expect(google.evenement(agendaGoogle, 'ptite2')!.titre, 'Salon créateurs');

      // Une fois marqué, on n'y touche plus.
      final int ecrituresAvant = google.ecritures.length;
      final BilanSynchro suivante = await service.synchroniser();
      expect(suivante.resultat!.annules, 0);
      expect(suivante.resultat!.inchanges, 1);
      expect(google.ecritures, hasLength(ecrituresAvant));
    });

    test('un cours annulé est marqué « [Annulé] », et redevient normal s’il est rétabli', () async {
      final int id = await cours('Atelier crochet', DateTime(2026, 12, 5, 18));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();

      await (db.update(db.cours)..where((t) => t.id.equals(id))).write(const CoursCompanion(statut: Value(StatutCours.annule)));
      expect((await service.synchroniser()).resultat!.annules, 1);
      expect(google.evenement(agendaGoogle, 'ptitc$id')!.titre, '[Annulé] Atelier crochet');

      await (db.update(db.cours)..where((t) => t.id.equals(id))).write(const CoursCompanion(statut: Value(StatutCours.planifie)));
      final BilanSynchro retour = await service.synchroniser();

      expect(retour.resultat!.modifies, 1);
      expect(google.evenement(agendaGoogle, 'ptitc$id')!.titre, 'Atelier crochet');
      expect(google.appels('supprimer'), 0);
    });

    test('les types masqués par les filtres ne sont pas envoyés', () async {
      await parametres.enregistrerFiltresAgenda(const FiltresAgenda(declaration: false, evenements: false));
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await cours('Atelier crochet', DateTime(2026, 12, 5, 18));

      final BilanSynchro bilan = await service.activer();

      expect(bilan.resultat!.crees, 1);
      final String agendaGoogle = await calendrierMemorise();
      expect(google.evenement(agendaGoogle, 'ptitc1'), isNotNull);
      expect(google.evenement(agendaGoogle, 'ptite1'), isNull);
    });

    test('masquer un type après coup ne touche pas à ce qui est déjà dans Google', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();
      final int ecrituresAvant = google.ecritures.length;

      await parametres.enregistrerFiltresAgenda(const FiltresAgenda(declaration: false, evenements: false));
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.issue, IssueSynchro.reussie);
      expect(bilan.resultat!.annules, 0);
      expect(google.ecritures, hasLength(ecrituresAvant));
      expect(google.evenement(agendaGoogle, 'ptite1')!.titre, 'Marché de Noël');
    });

    test('ce qui est hors de la période (du mois dernier à 12 mois plus tard) n’est pas envoyé', () async {
      await evenement('Trop ancien', DateTime(2026, 8, 1));
      await evenement('Dans la période', DateTime(2026, 10, 1));
      await evenement('Dernier jour de la période', DateTime(2027, 11, 30));
      await evenement('Trop loin', DateTime(2027, 12, 1));

      final BilanSynchro bilan = await service.activer();

      expect(bilan.resultat!.crees, 2);
      final String agendaGoogle = await calendrierMemorise();
      expect(google.evenement(agendaGoogle, 'ptite1'), isNull);
      expect(google.evenement(agendaGoogle, 'ptite2'), isNotNull);
      expect(google.evenement(agendaGoogle, 'ptite3'), isNotNull);
      expect(google.evenement(agendaGoogle, 'ptite4'), isNull);
    });

    test('limite connue : un élément déplacé hors de la période est marqué « [Annulé] » (il n’est plus dans la période)', () async {
      final EvenementAgenda e = await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();

      await agenda.modifier(e.id, DonneesEvenement(titre: 'Marché de Noël', jour: DateTime(2030, 12, 12)));
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.resultat!.annules, 1);
      expect(google.evenement(agendaGoogle, 'ptite1')!.estAnnule, isTrue);
      expect(google.appels('supprimer'), 0);
    });

    test('un événement supprimé à la main dans Google Agenda y est recréé', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();

      google.retirerDansGoogle(agendaGoogle, 'ptite1');
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.resultat!.crees, 1);
      expect(google.evenement(agendaGoogle, 'ptite1')!.titre, 'Marché de Noël');
    });

    test('un événement modifié à la main dans Google Agenda est remplacé par la version de l’application', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();
      final EvenementGoogle original = google.evenement(agendaGoogle, 'ptite1')!;
      google.poser(
        agendaGoogle,
        EvenementGoogle(
          id: original.id,
          titre: 'Titre changé à la main',
          debut: original.debut,
          fin: original.fin,
          journeeEntiere: true,
          description: original.description,
          type: original.type,
        ),
      );

      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.resultat!.modifies, 1);
      expect(google.evenement(agendaGoogle, 'ptite1')!.titre, 'Marché de Noël');
    });

    test('un événement qui n’est pas de l’application (pas de type connu) n’est jamais touché', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();
      google.poser(
        agendaGoogle,
        EvenementGoogle(
          id: 'ptitz99',
          titre: 'Inconnu',
          debut: DateTime.utc(2026, 12, 14),
          fin: DateTime.utc(2026, 12, 15),
          journeeEntiere: true,
        ),
      );

      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.resultat!.annules, 0);
      expect(google.evenement(agendaGoogle, 'ptitz99')!.titre, 'Inconnu');
    });

    test('agenda supprimé dans Google Agenda : « introuvable », rien d’automatique, puis nouvel agenda sur demande', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String ancien = await calendrierMemorise();

      google.supprimerAgendaDansGoogle(ancien);
      final BilanSynchro perdu = await service.synchroniser();

      expect(perdu.issue, IssueSynchro.agendaIntrouvable);
      expect(google.appels('creerCalendrier'), 1);
      expect(await calendrierMemorise(), ancien);

      final BilanSynchro refait = await service.recreerAgenda();

      expect(refait.issue, IssueSynchro.reussie);
      expect(refait.resultat!.crees, 1);
      expect(google.appels('creerCalendrier'), 2);
      final String nouveau = await calendrierMemorise();
      expect(nouveau, isNot(ancien));
      expect(google.evenement(nouveau, 'ptite1'), isNotNull);
      expect((await parametres.lireAgendaGoogle()).actif, isTrue);
    });

    test('droit retiré : « droit absent », et Google n’est pas appelé', () async {
      await activerEtSynchroniser();
      final int appelsAvant = google.journal.length;

      compte.agendaAccorde = false;
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.issue, IssueSynchro.droitAbsent);
      expect(google.journal, hasLength(appelsAvant));
    });

    test('personne n’est connecté : « non connecté », et Google n’est pas appelé', () async {
      await activerEtSynchroniser();
      final int appelsAvant = google.journal.length;

      compte.dejaConnecte = null;
      final BilanSynchro bilan = await service.synchroniser();

      expect(bilan.issue, IssueSynchro.nonConnecte);
      expect(google.journal, hasLength(appelsAvant));
    });

    test('deux demandes en même temps ne font qu’une synchronisation', () async {
      await parametres.enregistrerAgendaGoogle(actif: true);
      await evenement('Marché de Noël', DateTime(2026, 12, 12));

      final Future<BilanSynchro> premiere = service.synchroniser();
      final Future<BilanSynchro> seconde = service.synchroniser();

      expect(identical(premiere, seconde), isTrue);
      final List<BilanSynchro> bilans = await Future.wait(<Future<BilanSynchro>>[premiere, seconde]);
      expect(bilans.every((BilanSynchro b) => b.issue == IssueSynchro.reussie), isTrue);
      expect(google.appels('creerCalendrier'), 1);
      expect(google.appels('creer'), 1);

      // Terminée, la suivante est une vraie nouvelle synchronisation.
      final Future<BilanSynchro> suivante = service.synchroniser();
      expect(identical(premiere, suivante), isFalse);
      expect((await suivante).resultat!.inchanges, 1);
    });
  });

  group('désactiver', () {
    test('garde l’agenda et ce qu’il contient ; réactiver reprend le même agenda, sans doublon', () async {
      await evenement('Marché de Noël', DateTime(2026, 12, 12));
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();

      await service.desactiver();

      expect((await parametres.lireAgendaGoogle()).actif, isFalse);
      expect(await calendrierMemorise(), agendaGoogle);
      expect(google.evenement(agendaGoogle, 'ptite1'), isNotNull);
      expect((await service.synchroniser()).issue, IssueSynchro.desactivee);

      final BilanSynchro reactive = await service.activer();

      expect(reactive.issue, IssueSynchro.reussie);
      expect(reactive.resultat!.inchanges, 1);
      expect(google.appels('creerCalendrier'), 1);
      expect(google.appels('creer'), 1);
      expect(google.appels('supprimer'), 0);
    });
  });

  group('pannes', () {
    test('une écriture refusée est comptée, le reste est envoyé, et elle est retentée à la fois suivante', () async {
      await evenement('Un', DateTime(2026, 12, 11));
      await evenement('Deux', DateTime(2026, 12, 12));
      await evenement('Trois', DateTime(2026, 12, 13));
      google.panne = (String operation, String? id) =>
          operation == 'creer' && id == 'ptite2' ? const ErreurDrive('Google refuse cet événement.') : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.partielle);
      expect(bilan.resultat!.crees, 2);
      expect(bilan.resultat!.echecs, 1);
      expect(bilan.message, 'Google refuse cet événement.');
      final String agendaGoogle = await calendrierMemorise();
      expect(google.evenement(agendaGoogle, 'ptite2'), isNull);

      google.panne = null;
      final BilanSynchro reprise = await service.synchroniser();

      expect(reprise.issue, IssueSynchro.reussie);
      expect(reprise.resultat!.crees, 1);
      expect(reprise.resultat!.inchanges, 2);
      expect(google.evenement(agendaGoogle, 'ptite2')!.titre, 'Deux');
    });

    test('après 3 échecs de suite, on s’arrête : les écritures restantes seront retentées', () async {
      for (int jour = 10; jour < 15; jour++) {
        await evenement('Événement $jour', DateTime(2026, 12, jour));
      }
      google.panne = (String operation, String? id) => operation == 'creer' ? const ErreurDrive('Google ne répond pas.') : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.partielle);
      expect(bilan.resultat!.crees, 0);
      expect(bilan.resultat!.echecs, 5);
      expect(google.appels('creer'), 3);
    });

    test('une écriture réussie remet le compte des échecs de suite à zéro', () async {
      for (int jour = 10; jour < 15; jour++) {
        await evenement('Événement $jour', DateTime(2026, 12, jour));
      }
      // Échecs sur 1, 2, 4 et 5 : jamais 3 de suite.
      const Set<String> refuses = <String>{'ptite1', 'ptite2', 'ptite4', 'ptite5'};
      google.panne = (String operation, String? id) =>
          operation == 'creer' && refuses.contains(id) ? const ErreurDrive('Google refuse.') : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.partielle);
      expect(bilan.resultat!.crees, 1);
      expect(bilan.resultat!.echecs, 4);
      expect(google.appels('creer'), 5);
    });

    test('une autorisation perdue en cours de route arrête tout et demande de la redonner', () async {
      await evenement('Un', DateTime(2026, 12, 11));
      await evenement('Deux', DateTime(2026, 12, 12));
      google.panne = (String operation, String? id) =>
          operation == 'creer' ? const ErreurDrive('Google a retiré l’autorisation.', autorisationAExpire: true) : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.droitAbsent);
      expect(bilan.message, 'Google a retiré l’autorisation.');
      expect(google.appels('creer'), 1);
    });

    test('réseau coupé à la lecture : l’erreur est expliquée telle quelle', () async {
      await evenement('Un', DateTime(2026, 12, 11));
      google.panne = (String operation, String? id) =>
          operation == 'lister' ? const ErreurDrive('Pas de connexion à Internet.') : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.erreur);
      expect(bilan.message, 'Pas de connexion à Internet.');
      expect(google.appels('creer'), 0);
    });

    test('une erreur inattendue ne remonte jamais : elle est dans le bilan', () async {
      await evenement('Un', DateTime(2026, 12, 11));
      google.panne = (String operation, String? id) => operation == 'creer' ? StateError('boum') : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.erreur);
      expect(bilan.message, contains('La synchronisation a échoué'));
    });

    test('si l’agenda ne peut pas être créé, rien n’est mémorisé et la prochaine fois on réessaie', () async {
      await evenement('Un', DateTime(2026, 12, 11));
      google.panne = (String operation, String? id) =>
          operation == 'creerCalendrier' ? const ErreurDrive('Google Agenda a refusé de créer l’agenda.') : null;

      final BilanSynchro bilan = await service.activer();

      expect(bilan.issue, IssueSynchro.erreur);
      expect(bilan.message, 'Google Agenda a refusé de créer l’agenda.');
      expect((await parametres.lireAgendaGoogle()).calendrier, isNull);

      google.panne = null;
      expect((await service.synchroniser()).issue, IssueSynchro.reussie);
      // Le premier essai a échoué avant de créer quoi que ce soit : c'est donc le premier agenda.
      expect(await calendrierMemorise(), 'agenda-test-1');
      expect(google.appels('creerCalendrier'), 2);
    });
  });

  group('nettoyer', () {
    /// Trois événements envoyés, puis deux supprimés de l'application : deux sont marqués « [Annulé] » dans Google.
    Future<String> deuxAnnules() async {
      final EvenementAgenda un = await evenement('Un', DateTime(2026, 12, 11));
      final EvenementAgenda deux = await evenement('Deux', DateTime(2026, 12, 12));
      await evenement('Trois', DateTime(2026, 12, 13));
      await activerEtSynchroniser();
      await agenda.supprimer(un.id);
      await agenda.supprimer(deux.id);
      expect((await service.synchroniser()).resultat!.annules, 2);
      return calendrierMemorise();
    }

    test('liste les événements « [Annulé] » puis ne supprime qu’eux, sur demande', () async {
      final String agendaGoogle = await deuxAnnules();

      final List<EvenementGoogle> annules = await service.evenementsAnnules();
      expect(annules.map((EvenementGoogle e) => e.id).toSet(), <String>{'ptite1', 'ptite2'});
      expect(google.appels('supprimer'), 0);

      final ({int supprimes, int echecs}) resultat = await service.nettoyer();

      expect(resultat.supprimes, 2);
      expect(resultat.echecs, 0);
      expect(google.calendriers[agendaGoogle]!.keys, <String>['ptite3']);
      expect(google.evenement(agendaGoogle, 'ptite3')!.titre, 'Trois');
      // Rien n'est supprimé dans l'application.
      expect(await agenda.lister(), hasLength(1));
      // Et la synchronisation suivante ne les recrée pas.
      final int ecrituresAvant = google.ecritures.length;
      final BilanSynchro suivante = await service.synchroniser();
      expect(suivante.issue, IssueSynchro.reussie);
      expect(suivante.resultat!.inchanges, 1);
      expect(google.ecritures, hasLength(ecrituresAvant));
    });

    test('rien à nettoyer : rien n’est supprimé', () async {
      await evenement('Un', DateTime(2026, 12, 11));
      await activerEtSynchroniser();

      expect(await service.evenementsAnnules(), isEmpty);
      final ({int supprimes, int echecs}) resultat = await service.nettoyer();

      expect(resultat.supprimes, 0);
      expect(resultat.echecs, 0);
      expect(google.appels('supprimer'), 0);
    });

    test('trouve aussi les événements « [Annulé] » hors de la période synchronisée', () async {
      await activerEtSynchroniser();
      final String agendaGoogle = await calendrierMemorise();
      google.poser(
        agendaGoogle,
        EvenementGoogle(
          id: 'ptite77',
          titre: '[Annulé] Vieux marché',
          debut: DateTime.utc(2024, 3, 2),
          fin: DateTime.utc(2024, 3, 3),
          journeeEntiere: true,
          type: TypeEntreeAgenda.evenement,
        ),
      );

      expect((await service.evenementsAnnules()).map((EvenementGoogle e) => e.id), <String>['ptite77']);
    });

    test('une suppression refusée est comptée, les autres sont faites', () async {
      await deuxAnnules();
      google.panne = (String operation, String? id) =>
          operation == 'supprimer' && id == 'ptite1' ? const ErreurDrive('Google refuse de supprimer.') : null;

      final ({int supprimes, int echecs}) resultat = await service.nettoyer();

      expect(resultat.supprimes, 1);
      expect(resultat.echecs, 1);
    });

    test('sans connexion à Google : une erreur lisible', () async {
      await activerEtSynchroniser();
      compte.dejaConnecte = null;

      await expectLater(
        service.evenementsAnnules(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Connectez-vous'))),
      );
      await expectLater(service.nettoyer(), throwsA(isA<ErreurDrive>()));
    });

    test('sans droit « agenda » : une erreur qui demande de le redonner', () async {
      await activerEtSynchroniser();
      compte.agendaAccorde = false;

      await expectLater(
        service.nettoyer(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.autorisationAExpire, 'autorisationAExpire', isTrue)),
      );
      expect(google.appels('supprimer'), 0);
    });

    test('agenda jamais créé : rien à nettoyer, expliqué', () async {
      await expectLater(
        service.evenementsAnnules(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('Aucun agenda Google'))),
      );
    });

    test('agenda supprimé dans Google Agenda : une erreur lisible, pas une exception technique', () async {
      await activerEtSynchroniser();
      google.supprimerAgendaDansGoogle(await calendrierMemorise());

      await expectLater(
        service.nettoyer(),
        throwsA(isA<ErreurDrive>().having((ErreurDrive e) => e.message, 'message', contains('introuvable'))),
      );
    });
  });

  test('CalendrierIntrouvable a un message lisible', () {
    expect(const CalendrierIntrouvable().toString(), contains('introuvable'));
  });
}
