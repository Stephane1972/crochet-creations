import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/cours_repository.dart';
import 'package:crochet_creations/data/repositories/cours_vues.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late VenteRepository ventes;
  late CoursRepository cours;

  setUp(() {
    db = creerBaseEnMemoire();
    ventes = VenteRepository(db, ProduitRepository(db, NumerotationRepository(db)));
    cours = CoursRepository(db, ventes);
  });
  tearDown(() => db.close());

  /// Un cours dans quinze jours, 4 places, 45 €.
  DonneesCours donnees({
    String titre = 'Initiation au crochet',
    int prix = 4500,
    int places = 4,
    DateTime? debut,
    String? lieu = 'Atelier de Camille',
    String? description = 'Les premiers points.',
    String? photo,
  }) => DonneesCours(
    titre: titre,
    description: description,
    debutLe: debut ?? DateTime.now().add(const Duration(days: 15)),
    dureeMinutes: 150,
    lieu: lieu,
    prixCentimes: prix,
    places: places,
    niveau: NiveauCours.debutant,
    materielInclus: true,
    photoChemin: photo,
  );

  Future<CoursFiche> unCours({int prix = 4500, int places = 4}) => cours.creer(donnees(prix: prix, places: places));

  int compteur = 0;
  Future<int> unClient([String? nom]) => db.insererClient(nom: nom ?? 'Cliente ${compteur++}');

  Future<List<Paiement>> paiementsDe(int venteId) =>
      (db.select(db.paiements)..where((t) => t.venteId.equals(venteId))).get();

  Future<String> message(Future<Object?> Function() action) async {
    try {
      await action();
    } on ErreurMetier catch (erreur) {
      return erreur.message;
    }
    fail('Une erreur était attendue.');
  }

  group('créer et modifier un cours', () {
    test('enregistre le cours, texte nettoyé et champs vides remplacés par rien', () async {
      final CoursFiche c = await cours.creer(donnees(titre: '  Amigurumi  ', lieu: '   ', description: ''));
      expect(c.titre, 'Amigurumi');
      expect(c.lieu, isNull);
      expect(c.description, isNull);
      expect(c.statut, StatutCours.planifie);
      expect(c.archiveLe, isNull);
      expect(c.places, 4);
      expect(c.niveau, NiveauCours.debutant);
      expect(c.materielInclus, isTrue);
    });

    test('refuse des informations impossibles, sans rien enregistrer', () async {
      expect(await message(() => cours.creer(donnees(titre: ' '))), 'Indiquez le titre du cours.');
      expect(await message(() => cours.creer(donnees(places: 0))), 'Il faut au moins une place.');
      expect(await message(() => cours.creer(donnees(prix: -1))), 'Le prix ne peut pas être négatif.');
      expect(await db.select(db.cours).get(), isEmpty);
    });

    test('modifie le cours ; les inscrits déjà pris gardent leur prix', () async {
      final CoursFiche c = await unCours();
      final Inscription i = (await cours.inscrire(coursId: c.id, clientId: await unClient())).inscription;

      final CoursFiche modifie = await cours.modifier(
        c.id,
        donnees(titre: 'Initiation (2e session)', prix: 5000, places: 6, photo: 'photo_1.jpg'),
      );

      expect(modifie.titre, 'Initiation (2e session)');
      expect(modifie.prixCentimes, 5000);
      expect(modifie.places, 6);
      expect(modifie.photoChemin, 'photo_1.jpg');
      final Inscription apres = (await db.select(db.inscriptionsCours).get()).single;
      expect(apres.id, i.id);
      expect(apres.prixCentimes, 4500);
    });

    test('ne descend pas sous le nombre de personnes confirmées', () async {
      final CoursFiche c = await unCours(places: 3);
      for (int n = 0; n < 3; n++) {
        await cours.inscrire(coursId: c.id, clientId: await unClient());
      }
      expect(
        await message(() => cours.modifier(c.id, donnees(places: 2))),
        'Ce cours compte déjà 3 personnes confirmées : le nombre de places ne peut pas être plus petit.',
      );
      expect((await cours.obtenir(c.id))!.places, 3);
      await cours.modifier(c.id, donnees(places: 3));
    });

    test('un cours inconnu est refusé avec un message clair', () async {
      expect(await message(() => cours.modifier(999, donnees())), 'Ce cours n’existe plus.');
      expect(await message(() => cours.annulerCours(999)), 'Ce cours n’existe plus.');
    });
  });

  group('annuler, rétablir, archiver un cours', () {
    test('annuler puis rétablir ; chaque action impossible à refaire', () async {
      final CoursFiche c = await unCours();
      expect(await message(() => cours.retablirCours(c.id)), 'Ce cours n’est pas annulé.');

      await cours.annulerCours(c.id);
      expect((await cours.obtenir(c.id))!.statut, StatutCours.annule);
      expect(await message(() => cours.annulerCours(c.id)), 'Ce cours est déjà annulé.');

      await cours.retablirCours(c.id);
      expect((await cours.obtenir(c.id))!.statut, StatutCours.planifie);
    });

    test('annuler un cours laisse les inscriptions et les ventes telles quelles', () async {
      final CoursFiche c = await unCours();
      final ResultatInscription r = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient(),
        paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 4500),
      );

      await cours.annulerCours(c.id);

      final Inscription i = (await db.select(db.inscriptionsCours).get()).single;
      expect(i.statut, StatutInscription.confirmee);
      expect((await ventes.obtenir(r.vente!.id))!.statut, StatutVente.validee);
    });

    test('seul un cours terminé ou annulé s’archive ; on peut le restaurer', () async {
      final CoursFiche c = await unCours();
      expect(await message(() => cours.archiver(c.id)), 'Seul un cours terminé ou annulé peut être archivé.');

      await cours.archiver(c.id, maintenant: DateTime.now().add(const Duration(days: 30)));
      expect((await cours.obtenir(c.id))!.archiveLe, isNotNull);

      await cours.restaurer(c.id);
      expect((await cours.obtenir(c.id))!.archiveLe, isNull);

      await cours.annulerCours(c.id);
      await cours.archiver(c.id);
      expect((await cours.obtenir(c.id))!.archiveLe, isNotNull);
    });
  });

  group('inscrire', () {
    test('une place libre : inscription confirmée et vente d’une ligne « cours », sans effet sur le stock', () async {
      final int produitId = await db.insererProduit(stock: 5);
      final CoursFiche c = await unCours();
      final int clientId = await unClient();

      final ResultatInscription r = await cours.inscrire(coursId: c.id, clientId: clientId, notes: '  Apporte sa laine ');

      expect(r.inscription.statut, StatutInscription.confirmee);
      expect(r.inscription.prixCentimes, 4500);
      expect(r.inscription.notes, 'Apporte sa laine');
      expect(r.inscription.venteId, r.vente!.id);
      final Vente v = (await ventes.obtenir(r.vente!.id))!;
      expect(v.clientId, clientId);
      expect(v.totalCentimes, 4500);
      expect(v.statut, StatutVente.validee);
      expect(v.statutPaiement, StatutPaiement.impayee);
      expect(v.notes, 'Inscription au cours « Initiation au crochet »');

      final LigneVente ligne = (await db.select(db.lignesVente).get()).single;
      expect(ligne.coursId, c.id);
      expect(ligne.produitId, isNull);
      expect(ligne.nature, NatureLigne.service);
      expect(ligne.designation, 'Cours : Initiation au crochet');
      expect(ligne.quantite, 1);
      expect(ligne.prixUnitaireCentimes, 4500);
      expect(ligne.description, contains('2 h 30'));
      expect(ligne.description, contains('Atelier de Camille'));
      expect((await (db.select(db.produits)..where((t) => t.id.equals(produitId))).getSingle()).quantiteStock, 5);
    });

    test('avec un acompte ou le paiement complet', () async {
      final CoursFiche c = await unCours();
      final ResultatInscription acompte = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient(),
        paiement: const PaiementSaisi(mode: ModePaiement.virement, montantCentimes: 1500),
      );
      expect((await ventes.obtenir(acompte.vente!.id))!.statutPaiement, StatutPaiement.partiellementPayee);
      expect((await paiementsDe(acompte.vente!.id)).single.montantCentimes, 1500);

      final ResultatInscription tout = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient(),
        paiement: const PaiementSaisi(mode: ModePaiement.carte, montantCentimes: 4500),
      );
      expect((await ventes.obtenir(tout.vente!.id))!.statutPaiement, StatutPaiement.payee);
    });

    test('un prix convenu remplace le prix du cours pour cette personne seulement', () async {
      final CoursFiche c = await unCours();
      final ResultatInscription remise = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient(),
        prixCentimes: 3000,
      );
      final ResultatInscription normal = await cours.inscrire(coursId: c.id, clientId: await unClient());

      expect(remise.inscription.prixCentimes, 3000);
      expect(remise.vente!.totalCentimes, 3000);
      expect(normal.inscription.prixCentimes, 4500);
    });

    test('un cours gratuit : vente à 0 €, considérée comme payée', () async {
      final CoursFiche c = await unCours(prix: 0);
      final ResultatInscription r = await cours.inscrire(coursId: c.id, clientId: await unClient());
      expect(r.vente!.totalCentimes, 0);
      expect((await ventes.obtenir(r.vente!.id))!.statutPaiement, StatutPaiement.payee);
    });

    test('cours complet : liste d’attente, sans vente, et un paiement est refusé', () async {
      final CoursFiche c = await unCours(places: 1);
      await cours.inscrire(coursId: c.id, clientId: await unClient());

      expect(
        await message(
          () async => cours.inscrire(
            coursId: c.id,
            clientId: await unClient(),
            paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 1000),
          ),
        ),
        'Le cours est complet : la personne passe en liste d’attente, sans paiement pour le moment.',
      );
      expect(await db.select(db.inscriptionsCours).get(), hasLength(1));

      final ResultatInscription attente = await cours.inscrire(coursId: c.id, clientId: await unClient());
      expect(attente.inscription.statut, StatutInscription.listeAttente);
      expect(attente.inscription.venteId, isNull);
      expect(attente.vente, isNull);
      expect(await db.select(db.ventes).get(), hasLength(1));
    });

    test('refuse une deuxième inscription de la même personne', () async {
      final CoursFiche c = await unCours(places: 1);
      final int camille = await unClient();
      final int lea = await unClient();
      await cours.inscrire(coursId: c.id, clientId: camille);
      await cours.inscrire(coursId: c.id, clientId: lea);

      expect(
        await message(() => cours.inscrire(coursId: c.id, clientId: camille)),
        'Cette personne est déjà inscrite à ce cours.',
      );
      expect(
        await message(() => cours.inscrire(coursId: c.id, clientId: lea)),
        'Cette personne est déjà sur la liste d’attente de ce cours.',
      );
    });

    test('refuse un cours annulé ou archivé, un client inconnu ou archivé', () async {
      final CoursFiche c = await unCours();
      final int clientId = await unClient();

      expect(await message(() => cours.inscrire(coursId: 999, clientId: clientId)), 'Ce cours n’existe plus.');
      expect(await message(() => cours.inscrire(coursId: c.id, clientId: 999)), 'Ce client n’existe plus.');

      await (db.update(db.clients)..where((t) => t.id.equals(clientId))).write(
        ClientsCompanion(archiveLe: Value(DateTime.now())),
      );
      expect(
        await message(() => cours.inscrire(coursId: c.id, clientId: clientId)),
        'Ce client est archivé : restaurez sa fiche pour l’inscrire.',
      );

      await cours.annulerCours(c.id);
      expect(
        await message(() async => cours.inscrire(coursId: c.id, clientId: await unClient())),
        'Ce cours est annulé : on ne peut plus y inscrire personne.',
      );
      await cours.retablirCours(c.id);
      // Un cours n'est archivable qu'une fois terminé (ou annulé) : on se place après sa fin.
      await cours.archiver(c.id, maintenant: c.debutLe.add(const Duration(days: 1)));
      expect(
        await message(() async => cours.inscrire(coursId: c.id, clientId: await unClient())),
        'Ce cours est archivé : restaurez-le pour y inscrire quelqu’un.',
      );
      expect(await db.select(db.ventes).get(), isEmpty);
    });

    test('tout ou rien : un paiement trop élevé n’enregistre ni vente ni inscription', () async {
      final CoursFiche c = await unCours();
      expect(
        await message(
          () async => cours.inscrire(
            coursId: c.id,
            clientId: await unClient(),
            paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 9999),
          ),
        ),
        'Le montant encaissé ne peut pas dépasser le total de la vente.',
      );
      expect(await db.select(db.inscriptionsCours).get(), isEmpty);
      expect(await db.select(db.ventes).get(), isEmpty);
    });
  });

  group('liste d’attente : confirmer', () {
    test('une place se libère : la première personne en attente est confirmée, avec sa vente et son paiement', () async {
      final CoursFiche c = await unCours(places: 1);
      final int camille = await unClient();
      final ResultatInscription premiere = await cours.inscrire(coursId: c.id, clientId: camille);
      final ResultatInscription lea = await cours.inscrire(coursId: c.id, clientId: await unClient(), prixCentimes: 4000);
      await cours.inscrire(coursId: c.id, clientId: await unClient());

      await cours.annulerInscription(premiere.inscription.id);
      final ResultatInscription confirmee = await cours.confirmer(
        lea.inscription.id,
        paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 1000),
      );

      expect(confirmee.inscription.statut, StatutInscription.confirmee);
      expect(confirmee.vente!.totalCentimes, 4000);
      expect((await ventes.obtenir(confirmee.vente!.id))!.statutPaiement, StatutPaiement.partiellementPayee);
      expect(confirmee.inscription.venteId, confirmee.vente!.id);
    });

    test('refuse : pas de place, pas la première, pas en attente', () async {
      final CoursFiche c = await unCours(places: 1);
      final ResultatInscription premiere = await cours.inscrire(coursId: c.id, clientId: await unClient());
      final ResultatInscription deuxieme = await cours.inscrire(coursId: c.id, clientId: await unClient());
      final ResultatInscription troisieme = await cours.inscrire(coursId: c.id, clientId: await unClient());

      expect(
        await message(() => cours.confirmer(deuxieme.inscription.id)),
        'Le cours est complet : aucune place n’est libre pour le moment.',
      );

      await cours.annulerInscription(premiere.inscription.id);
      expect(
        await message(() => cours.confirmer(troisieme.inscription.id)),
        'Seule la première personne de la liste d’attente peut être confirmée.',
      );
      expect(
        await message(() => cours.confirmer(premiere.inscription.id)),
        'Cette personne n’est pas sur la liste d’attente.',
      );
      expect((await db.select(db.ventes).get()), hasLength(1));
    });

    test('refuse pour un cours annulé', () async {
      final CoursFiche c = await unCours(places: 1);
      final ResultatInscription premiere = await cours.inscrire(coursId: c.id, clientId: await unClient());
      final ResultatInscription attente = await cours.inscrire(coursId: c.id, clientId: await unClient());
      await cours.annulerInscription(premiere.inscription.id);
      await cours.annulerCours(c.id);

      expect(
        await message(() => cours.confirmer(attente.inscription.id)),
        'Ce cours est annulé : on ne peut plus y inscrire personne.',
      );
    });
  });

  group('annuler une inscription', () {
    test('sans paiement : l’inscription et la vente sont annulées, la place est libérée', () async {
      final CoursFiche c = await unCours(places: 1);
      final ResultatInscription r = await cours.inscrire(coursId: c.id, clientId: await unClient());

      await cours.annulerInscription(r.inscription.id, rembourser: false);

      expect((await db.select(db.inscriptionsCours).get()).single.statut, StatutInscription.annulee);
      expect((await ventes.obtenir(r.vente!.id))!.statut, StatutVente.annulee);
      expect((await cours.lister()).single.placesLibres, 1);
    });

    test('avec paiement, en remboursant : la vente est annulée et le net encaissé remboursé', () async {
      final CoursFiche c = await unCours();
      final ResultatInscription r = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient(),
        paiement: const PaiementSaisi(mode: ModePaiement.virement, montantCentimes: 4500),
      );

      await cours.annulerInscription(r.inscription.id);

      final Vente v = (await ventes.obtenir(r.vente!.id))!;
      expect(v.statut, StatutVente.annulee);
      expect(v.statutPaiement, StatutPaiement.remboursee);
      expect((await paiementsDe(v.id)).map((Paiement p) => p.montantCentimes), <int>[4500, -4500]);
    });

    test('avec paiement, en le gardant : la vente et le paiement restent tels quels', () async {
      final CoursFiche c = await unCours();
      final ResultatInscription r = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient(),
        paiement: const PaiementSaisi(mode: ModePaiement.virement, montantCentimes: 1500),
      );

      await cours.annulerInscription(r.inscription.id, rembourser: false);

      expect((await db.select(db.inscriptionsCours).get()).single.statut, StatutInscription.annulee);
      final Vente v = (await ventes.obtenir(r.vente!.id))!;
      expect(v.statut, StatutVente.validee);
      expect(v.statutPaiement, StatutPaiement.partiellementPayee);
      expect((await paiementsDe(v.id)).map((Paiement p) => p.montantCentimes), <int>[1500]);
    });

    test('une personne en attente s’annule sans vente ; une inscription annulée ne s’annule pas deux fois', () async {
      final CoursFiche c = await unCours(places: 1);
      await cours.inscrire(coursId: c.id, clientId: await unClient());
      final ResultatInscription attente = await cours.inscrire(coursId: c.id, clientId: await unClient());

      await cours.annulerInscription(attente.inscription.id);

      expect(
        (await db.select(db.inscriptionsCours).get()).map((Inscription i) => i.statut),
        <StatutInscription>[StatutInscription.confirmee, StatutInscription.annulee],
      );
      expect(await db.select(db.ventes).get(), hasLength(1));
      expect(
        await message(() => cours.annulerInscription(attente.inscription.id)),
        'Cette inscription est déjà annulée.',
      );
    });

    test('une personne dont l’inscription est annulée peut se réinscrire : même fiche, nouvelle vente', () async {
      final CoursFiche c = await unCours();
      final int camille = await unClient();
      final ResultatInscription premiere = await cours.inscrire(coursId: c.id, clientId: camille);
      await cours.annulerInscription(premiere.inscription.id);

      final ResultatInscription encore = await cours.inscrire(
        coursId: c.id,
        clientId: camille,
        prixCentimes: 4000,
      );

      expect(encore.inscription.id, premiere.inscription.id);
      expect(encore.inscription.statut, StatutInscription.confirmee);
      expect(encore.inscription.venteId, isNot(premiere.vente!.id));
      expect(encore.inscription.prixCentimes, 4000);
      expect(await db.select(db.inscriptionsCours).get(), hasLength(1));
      expect(await db.select(db.ventes).get(), hasLength(2));
    });
  });

  group('consulter', () {
    test('la liste : à venir (du plus proche au plus lointain), passés et archivés, avec les places', () async {
      final DateTime maintenant = DateTime(2026, 11, 1, 12);
      final CoursFiche lointain = await cours.creer(donnees(titre: 'Lointain', debut: DateTime(2026, 12, 20, 14)));
      final CoursFiche proche = await cours.creer(donnees(titre: 'Proche', debut: DateTime(2026, 11, 14, 14), places: 2));
      final CoursFiche passe = await cours.creer(donnees(titre: 'Passé', debut: DateTime(2026, 10, 3, 14)));
      final CoursFiche archive = await cours.creer(donnees(titre: 'Archivé', debut: DateTime(2026, 9, 5, 14)));
      await cours.archiver(archive.id, maintenant: maintenant);

      await cours.inscrire(coursId: proche.id, clientId: await unClient());
      await cours.inscrire(coursId: proche.id, clientId: await unClient());
      await cours.inscrire(coursId: proche.id, clientId: await unClient());

      final List<CoursResume> aVenir = await cours.lister(maintenant: maintenant);
      expect(aVenir.map((CoursResume r) => r.cours.titre), <String>['Proche', 'Lointain']);
      expect(aVenir.first.confirmes, 2);
      expect(aVenir.first.enAttente, 1);
      expect(aVenir.first.placesLibres, 0);
      expect(aVenir.first.complet, isTrue);
      expect(aVenir.last.placesLibres, 4);

      expect(
        (await cours.lister(filtre: FiltreCours.passes, maintenant: maintenant)).map((CoursResume r) => r.cours.id),
        <int>[passe.id],
      );
      expect(
        (await cours.lister(filtre: FiltreCours.archives, maintenant: maintenant)).map((CoursResume r) => r.cours.id),
        <int>[archive.id],
      );
      expect(lointain.id, isNot(proche.id));
    });

    test('la fiche : inscrits, liste d’attente dans l’ordre, inscriptions annulées, paiements', () async {
      final CoursFiche c = await unCours(places: 2);
      final DateTime t = DateTime(2026, 10, 1, 9);
      final ResultatInscription payee = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient('Martin'),
        paiement: const PaiementSaisi(mode: ModePaiement.carte, montantCentimes: 4500),
        date: t,
      );
      final ResultatInscription acompte = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient('Bernard'),
        paiement: const PaiementSaisi(mode: ModePaiement.especes, montantCentimes: 1000),
        date: t.add(const Duration(hours: 1)),
      );
      final ResultatInscription attente1 = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient('Durand'),
        date: t.add(const Duration(hours: 3)),
      );
      final ResultatInscription attente2 = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient('Petit'),
        date: t.add(const Duration(hours: 2)),
      );
      await cours.annulerInscription(acompte.inscription.id);
      final ResultatInscription lea = await cours.inscrire(
        coursId: c.id,
        clientId: await unClient('Moreau'),
        date: t.add(const Duration(hours: 4)),
      );
      expect(lea.inscription.statut, StatutInscription.confirmee);

      final CoursDetail d = (await cours.detail(c.id))!;

      expect(d.confirmees.map((InscriptionDetail i) => i.client.nom), <String?>['Martin', 'Moreau']);
      expect(d.confirmees.first.statutPaiement, StatutPaiement.payee);
      expect(d.confirmees.first.encaisseCentimes, 4500);
      expect(d.confirmees.first.soldeCentimes, 0);
      expect(d.confirmees.last.statutPaiement, StatutPaiement.impayee);
      expect(d.confirmees.last.soldeCentimes, 4500);
      expect(d.enAttente.map((InscriptionDetail i) => i.inscription.id), <int>[
        attente2.inscription.id,
        attente1.inscription.id,
      ]);
      expect(d.enAttente.map((InscriptionDetail i) => i.rangAttente), <int?>[1, 2]);
      expect(d.enAttente.first.vente, isNull);
      expect(d.annulees.single.inscription.id, acompte.inscription.id);
      expect(d.annulees.single.soldeCentimes, 0);
      expect(d.placesLibres, 0);
      expect(d.complet, isTrue);
      expect(d.refusInscriptionCours, isNull);
      expect(d.refusConfirmationDe(d.enAttente.first), 'Le cours est complet : aucune place n’est libre pour le moment.');
      expect(payee.inscription.statut, StatutInscription.confirmee);
      expect(await cours.detail(999), isNull);
    });

    test('la fiche signale les possibilités : confirmer la première personne dès qu’une place est libre', () async {
      final CoursFiche c = await unCours(places: 1);
      final ResultatInscription premiere = await cours.inscrire(coursId: c.id, clientId: await unClient());
      await cours.inscrire(coursId: c.id, clientId: await unClient());
      await cours.inscrire(coursId: c.id, clientId: await unClient());
      await cours.annulerInscription(premiere.inscription.id);

      final CoursDetail d = (await cours.detail(c.id))!;

      expect(d.refusConfirmationDe(d.enAttente.first), isNull);
      expect(
        d.refusConfirmationDe(d.enAttente.last),
        'Seule la première personne de la liste d’attente peut être confirmée.',
      );
    });

    test('la fiche se met à jour toute seule quand on s’inscrit', () async {
      final CoursFiche c = await unCours();
      final List<int> nombres = <int>[];
      Completer<void> prochain = Completer<void>();
      final StreamSubscription<CoursDetail?> abonnement = cours.observerDetail(c.id).listen((CoursDetail? d) {
        nombres.add(d!.confirmees.length);
        if (!prochain.isCompleted) prochain.complete();
      });

      await prochain.future.timeout(const Duration(seconds: 5));
      expect(nombres, <int>[0]);

      prochain = Completer<void>();
      await cours.inscrire(coursId: c.id, clientId: await unClient());
      await prochain.future.timeout(const Duration(seconds: 5));
      expect(nombres.last, 1);

      await abonnement.cancel();
    });
  });
}
