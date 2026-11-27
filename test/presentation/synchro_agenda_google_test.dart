import 'package:crochet_creations/data/agenda/service_agenda_google.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/drive/compte_google.dart';
import 'package:crochet_creations/data/providers.dart';
import 'package:crochet_creations/data/repositories/agenda_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/presentation/agenda/agenda_google_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/aide_agenda_google.dart';
import '../data/aide_base.dart';
import '../data/aide_drive.dart';

/// Le déclenchement de la synchronisation vers Google Agenda : à la demande, et après les modifications du calendrier.
void main() {
  late AppDatabase db;
  late ParametresRepository parametres;
  late AgendaRepository agenda;
  late FauxCompteGoogle compte;
  late FauxClientAgendaGoogle google;
  late DateTime maintenant;
  late ProviderContainer conteneur;

  /// Assez long pour que deux écritures qui se suivent tombent dans la même attente, assez court pour un test.
  const Duration delai = Duration(milliseconds: 300);

  setUp(() async {
    db = creerBaseEnMemoire();
    parametres = ParametresRepository(db);
    agenda = AgendaRepository(db);
    compte = FauxCompteGoogle()
      ..dejaConnecte = const ProfilGoogle(email: 'stef@exemple.fr')
      ..agendaAccorde = true;
    google = FauxClientAgendaGoogle();
    maintenant = DateTime(2026, 11, 23, 10);
    await parametres.enregistrerFiltresAgenda(const FiltresAgenda(declaration: false));
    conteneur = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        compteGoogleProvider.overrideWithValue(compte),
        clientAgendaGoogleProvider.overrideWithValue(google),
        horlogeProvider.overrideWithValue(() => maintenant),
        delaiSynchroAgendaGoogleProvider.overrideWithValue(delai),
      ],
    );
  });
  tearDown(() async {
    conteneur.dispose();
    await db.close();
  });

  SynchroAgendaGoogleNotifier notifier() => conteneur.read(synchroAgendaGoogleProvider.notifier);
  EtatSynchroAgendaGoogle etat() => conteneur.read(synchroAgendaGoogleProvider);

  Future<EvenementAgenda> evenement(String titre, DateTime jour) => agenda.creer(DonneesEvenement(titre: titre, jour: jour));

  /// Attend (au plus [secondes] secondes) que [condition] soit vraie.
  Future<void> attendre(bool Function() condition, {int secondes = 5}) async {
    for (int i = 0; i < secondes * 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('au départ : rien en cours, aucun bilan', () {
    expect(etat().enCours, isFalse);
    expect(etat().bilan, isNull);
    expect(etat().quand, isNull);
  });

  test('activer puis synchroniser : « en cours », puis le bilan et son heure', () async {
    await evenement('Marché de Noël', DateTime(2026, 12, 12));

    final Future<BilanSynchro> activation = notifier().activer();
    expect(etat().enCours, isTrue);
    final BilanSynchro bilan = await activation;

    expect(bilan.issue, IssueSynchro.reussie);
    expect(etat().enCours, isFalse);
    expect(etat().bilan, same(bilan));
    expect(etat().quand, maintenant);
    expect(google.calendriers.values.single.keys, <String>['ptite1']);
  });

  test('« désactivée » n’efface pas le dernier bilan affiché', () async {
    await evenement('Marché de Noël', DateTime(2026, 12, 12));
    final BilanSynchro premier = await notifier().activer();

    await notifier().desactiver();
    final BilanSynchro suivant = await notifier().synchroniser();

    expect(suivant.issue, IssueSynchro.desactivee);
    expect(etat().enCours, isFalse);
    expect(etat().bilan, same(premier));
  });

  test('une demande refusée (autorisation fermée) est montrée comme telle', () async {
    compte
      ..agendaAccorde = false
      ..reponseDemandeAgenda = false;

    final BilanSynchro bilan = await notifier().activer();

    expect(bilan.issue, IssueSynchro.annulee);
    expect(etat().bilan!.issue, IssueSynchro.annulee);
    expect((await parametres.lireAgendaGoogle()).actif, isFalse);
  });

  test('la lecture de départ de la base ne déclenche pas de synchronisation', () async {
    await parametres.enregistrerAgendaGoogle(actif: true);
    notifier(); // le notifier se met à l'écoute de la base

    await Future<void>.delayed(delai * 3);

    expect(google.journal, isEmpty);
  });

  test('plusieurs modifications de suite ne font qu’une synchronisation, après le délai', () async {
    await evenement('Marché de Noël', DateTime(2026, 12, 12));
    await notifier().activer();
    expect(google.appels('lister'), 1);
    // La première lecture de la base est passée : les écritures suivantes sont de vraies modifications.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await evenement('Salon créateurs', DateTime(2026, 12, 20));
    await evenement('Atelier tricot', DateTime(2026, 12, 21));
    // Pas tout de suite : on attend que les modifications cessent.
    expect(google.appels('lister'), 1);

    await attendre(() => google.calendriers.values.single.length == 3);
    expect(google.calendriers.values.single.keys, containsAll(<String>['ptite1', 'ptite2', 'ptite3']));
    // Et une fois seulement : rien d'autre ne part ensuite.
    await Future<void>.delayed(delai * 2);
    expect(google.appels('lister'), 2);
    expect(google.appels('creerCalendrier'), 1);
  });

  test('supprimer un élément le marque « [Annulé] » dans Google après le délai, sans rien supprimer', () async {
    final EvenementAgenda perdu = await evenement('Marché de Noël', DateTime(2026, 12, 12));
    await notifier().activer();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await agenda.supprimer(perdu.id);

    await attendre(() => google.calendriers.values.single['ptite1']?.estAnnule ?? false);
    expect(google.calendriers.values.single['ptite1']!.titre, '[Annulé] Marché de Noël');
    expect(google.appels('supprimer'), 0);
  });

  test('sans activation, une modification ne contacte pas Google', () async {
    notifier();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await evenement('Marché de Noël', DateTime(2026, 12, 12));
    await Future<void>.delayed(delai * 3);

    expect(google.journal, isEmpty);
    expect(etat().bilan, isNull);
  });
}
