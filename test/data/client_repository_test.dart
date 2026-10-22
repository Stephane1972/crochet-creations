import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/client_vues.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late ClientRepository repo;

  setUp(() {
    db = creerBaseEnMemoire();
    repo = ClientRepository(db);
  });
  tearDown(() => db.close());

  test('création d’un particulier', () async {
    final Client c = await repo.creer(
      const DonneesClient(
        civilite: Civilite.madame,
        prenom: ' Camille ',
        nom: 'Martin',
        telephone: '06 12 34 56 78',
        email: 'camille@exemple.fr',
        codePostal: '31000',
        ville: 'Toulouse',
      ),
    );
    expect(c.typeClient, TypeClient.particulier);
    expect(c.civilite, Civilite.madame);
    expect(c.prenom, 'Camille');
    expect(c.nom, 'Martin');
    expect(c.adresse, isNull);
    expect(c.archiveLe, isNull);
  });

  test('un professionnel peut n’avoir qu’une raison sociale', () async {
    final Client c = await repo.creer(
      const DonneesClient(
        typeClient: TypeClient.professionnel,
        raisonSociale: 'Boutique La Pelote',
        siret: '123 456 789 00012',
      ),
    );
    expect(c.typeClient, TypeClient.professionnel);
    expect(c.raisonSociale, 'Boutique La Pelote');
  });

  test('une fiche sans nom, ou avec un e-mail invalide, est refusée', () async {
    await expectLater(repo.creer(const DonneesClient(telephone: '0600000000')), throwsA(isA<DonneeInvalide>()));
    await expectLater(repo.creer(const DonneesClient(nom: '   ')), throwsA(isA<DonneeInvalide>()));
    await expectLater(
      repo.creer(const DonneesClient(nom: 'Martin', email: 'pas-un-email')),
      throwsA(isA<DonneeInvalide>()),
    );
    expect(await repo.lister(), isEmpty);
  });

  test('modification et client introuvable', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    final Client modifie = await repo.modifier(c.id, const DonneesClient(nom: 'Martin', ville: 'Albi'));
    expect(modifie.ville, 'Albi');
    await expectLater(repo.modifier(999, const DonneesClient(nom: 'X')), throwsA(isA<ElementIntrouvable>()));
  });

  test('archivage : masqué de la liste mais conservé, puis restauration', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    await repo.archiver(c.id);
    expect(await repo.lister(), isEmpty);
    expect(await repo.lister(inclureArchives: true), hasLength(1));
    await repo.restaurer(c.id);
    expect(await repo.lister(), hasLength(1));
  });

  test('la liste est triée par nom', () async {
    await repo.creer(const DonneesClient(nom: 'Roux', prenom: 'Léa'));
    await repo.creer(const DonneesClient(nom: 'Bernard', prenom: 'Zoé'));
    await repo.creer(const DonneesClient(nom: 'bernard', prenom: 'Alice'));

    final List<Client> liste = await repo.observerClients().first;
    expect(liste.map((c) => '${c.prenom} ${c.nom}'), <String>['Alice bernard', 'Zoé Bernard', 'Léa Roux']);
  });

  // --- Règles de saisie ------------------------------------------------------

  /// Vérifie que la fiche est refusée avec ce message exact, et que rien n'est enregistré.
  Future<void> refuse(DonneesClient donnees, String message) async {
    await expectLater(
      repo.creer(donnees),
      throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', message)),
    );
    expect(await repo.lister(inclureArchives: true), isEmpty);
  }

  test('les messages d’erreur sont ceux du formulaire', () async {
    await refuse(
      const DonneesClient(telephone: '0600000000'),
      'Indiquez au moins un prénom, un nom ou une raison sociale.',
    );
    await refuse(
      const DonneesClient(nom: 'Martin', email: 'pas-un-email'),
      'L’adresse e-mail n’est pas valide.',
    );
    await refuse(
      const DonneesClient(nom: 'Martin', telephone: '12'),
      'Le numéro de téléphone n’est pas valide.',
    );
    await refuse(
      const DonneesClient(nom: 'Martin', codePostal: '!!'),
      'Le code postal n’est pas valide.',
    );
    await refuse(
      const DonneesClient(typeClient: TypeClient.professionnel, raisonSociale: 'Atelier', siret: '1234'),
      'Le SIREN (9 chiffres) ou le SIRET (14 chiffres) n’est pas valide.',
    );
  });

  test('un SIREN de 9 chiffres est accepté pour un professionnel', () async {
    final Client c = await repo.creer(
      const DonneesClient(typeClient: TypeClient.professionnel, raisonSociale: 'Atelier', siret: '123456789'),
    );
    expect(c.siret, '123456789');
  });

  test('la modification applique aussi les règles de saisie', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    await expectLater(
      repo.modifier(c.id, const DonneesClient(nom: 'Martin', email: 'oups')),
      throwsA(isA<DonneeInvalide>()),
    );
    expect((await repo.obtenir(c.id))!.email, isNull);
  });

  // --- Fiche observée --------------------------------------------------------

  test('observerClient : la fiche, puis null pour un client inconnu', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    expect((await repo.observerClient(c.id).first)!.nom, 'Martin');
    expect(await repo.observerClient(999).first, isNull);
  });

  // --- Historique ------------------------------------------------------------

  test('un nouveau client a un historique vide', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    final HistoriqueClient h = await repo.historique(c.id);
    expect(h.estVide, isTrue);
    expect(h.totalAchatsCentimes, 0);
    expect(h.nombreVentesValidees, 0);
  });

  test('l’historique réunit devis, ventes, factures, paiements et cours du client, le plus récent d’abord',
      () async {
    final Client camille = await repo.creer(const DonneesClient(prenom: 'Camille', nom: 'Martin'));
    final Client autre = await repo.creer(const DonneesClient(nom: 'Autre'));

    Future<int> vente(int? clientId, int total, DateTime date, {StatutVente statut = StatutVente.validee}) =>
        db
            .into(db.ventes)
            .insert(
              VentesCompanion.insert(
                sousTotalCentimes: total,
                totalCentimes: total,
                clientId: Value(clientId),
                dateVente: Value(date),
                statut: Value(statut),
                statutPaiement: const Value(StatutPaiement.payee),
              ),
            );

    final int v1 = await vente(camille.id, 2500, DateTime(2026, 10, 1));
    final int v2 = await vente(camille.id, 1500, DateTime(2026, 10, 15));
    final int v3 = await vente(camille.id, 9900, DateTime(2026, 10, 20), statut: StatutVente.annulee);
    final int vAutre = await vente(autre.id, 7700, DateTime(2026, 10, 10));
    await vente(null, 3300, DateTime(2026, 10, 12)); // client de passage : aucune fiche

    Future<void> paiement(int venteId, int montant, DateTime date, ModePaiement mode) => db
        .into(db.paiements)
        .insert(
          PaiementsCompanion.insert(
            venteId: venteId,
            montantCentimes: montant,
            modePaiement: mode,
            datePaiement: Value(date),
          ),
        );
    await paiement(v1, 2500, DateTime(2026, 10, 1), ModePaiement.especes);
    await paiement(v2, 1500, DateTime(2026, 10, 15), ModePaiement.carte);
    await paiement(v3, 9900, DateTime(2026, 10, 20), ModePaiement.virement);
    await paiement(v3, -9900, DateTime(2026, 10, 21), ModePaiement.virement); // remboursement
    await paiement(vAutre, 7700, DateTime(2026, 10, 10), ModePaiement.carte);

    Future<void> facture(String numero, int venteId, int total, DateTime date) => db
        .into(db.factures)
        .insert(
          FacturesCompanion.insert(
            numero: numero,
            venteId: venteId,
            dateVentePrestation: date,
            totalCentimes: total,
            clientId: Value(camille.id),
            dateEmission: Value(date),
          ),
        );
    await facture('FACT-2026-0001', v1, 2500, DateTime(2026, 10, 1));
    await facture('FACT-2026-0002', v2, 1500, DateTime(2026, 10, 15));

    Future<void> devis(String numero, int? clientId, DateTime date) => db
        .into(db.devis)
        .insert(
          DevisCompanion.insert(
            numero: numero,
            sousTotalCentimes: 4000,
            totalCentimes: 4000,
            clientId: Value(clientId),
            dateEmission: Value(date),
          ),
        );
    await devis('DEVIS-2026-0001', camille.id, DateTime(2026, 9, 20));
    await devis('DEVIS-2026-0002', camille.id, DateTime(2026, 10, 5));
    await devis('DEVIS-2026-0003', autre.id, DateTime(2026, 10, 6));

    final int tricot = await db
        .into(db.cours)
        .insert(
          CoursCompanion.insert(
            titre: 'Initiation au crochet',
            debutLe: DateTime(2026, 11, 7, 14),
            dureeMinutes: 120,
            prixCentimes: 4500,
            places: 6,
          ),
        );
    final int amigurumi = await db
        .into(db.cours)
        .insert(
          CoursCompanion.insert(
            titre: 'Amigurumis',
            debutLe: DateTime(2026, 12, 5, 14),
            dureeMinutes: 120,
            prixCentimes: 5000,
            places: 6,
          ),
        );
    await db
        .into(db.inscriptionsCours)
        .insert(InscriptionsCoursCompanion.insert(coursId: tricot, clientId: camille.id, prixCentimes: 4500));
    await db
        .into(db.inscriptionsCours)
        .insert(
          InscriptionsCoursCompanion.insert(
            coursId: amigurumi,
            clientId: camille.id,
            prixCentimes: 5000,
            statut: const Value(StatutInscription.listeAttente),
          ),
        );
    await db
        .into(db.inscriptionsCours)
        .insert(InscriptionsCoursCompanion.insert(coursId: tricot, clientId: autre.id, prixCentimes: 4500));

    final HistoriqueClient h = await repo.historique(camille.id);

    // Ventes : seulement celles de Camille, la plus récente d'abord.
    expect(h.ventes.map((VenteClient v) => v.venteId), <int>[v3, v2, v1]);
    expect(h.ventes.first.statut, StatutVente.annulee);
    // Le total ne compte que les ventes validées.
    expect(h.nombreVentesValidees, 2);
    expect(h.totalAchatsCentimes, 4000);

    // Paiements : ceux des ventes de Camille uniquement, remboursement compris.
    expect(h.paiements.map((PaiementClient p) => p.montantCentimes), <int>[-9900, 9900, 1500, 2500]);
    expect(h.paiements.first.mode, ModePaiement.virement);
    expect(h.paiements.map((PaiementClient p) => p.venteId), <int>[v3, v3, v2, v1]);

    expect(h.factures.map((Facture f) => f.numero), <String>['FACT-2026-0002', 'FACT-2026-0001']);
    expect(h.devis.map((DevisFiche d) => d.numero), <String>['DEVIS-2026-0002', 'DEVIS-2026-0001']);

    // Cours : le plus récent d'abord, avec le titre du cours.
    expect(h.inscriptions.map((InscriptionClient i) => i.titreCours), <String>[
      'Amigurumis',
      'Initiation au crochet',
    ]);
    expect(h.inscriptions.first.statut, StatutInscription.listeAttente);
    expect(h.inscriptions.last.prixCentimes, 4500);
    expect(h.estVide, isFalse);

    // L'autre client ne voit que ses propres lignes.
    final HistoriqueClient ha = await repo.historique(autre.id);
    expect(ha.ventes.map((VenteClient v) => v.venteId), <int>[vAutre]);
    expect(ha.paiements, hasLength(1));
    expect(ha.factures, isEmpty);
    expect(ha.devis.map((DevisFiche d) => d.numero), <String>['DEVIS-2026-0003']);
    expect(ha.inscriptions, hasLength(1));
  });

  test('observerHistorique se met à jour quand une vente est enregistrée', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));

    final List<int> nombresDeVentes = <int>[];
    Completer<void> prochain = Completer<void>();
    final StreamSubscription<HistoriqueClient> abonnement = repo.observerHistorique(c.id).listen((
      HistoriqueClient h,
    ) {
      nombresDeVentes.add(h.ventes.length);
      if (!prochain.isCompleted) prochain.complete();
    });

    await prochain.future.timeout(const Duration(seconds: 5));
    expect(nombresDeVentes, <int>[0]);

    prochain = Completer<void>();
    await db.insererVente(clientId: c.id);
    await prochain.future.timeout(const Duration(seconds: 5));
    expect(nombresDeVentes.last, 1);

    await abonnement.cancel();
  });
}
