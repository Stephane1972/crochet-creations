import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/devis_repository.dart';
import 'package:crochet_creations/data/repositories/devis_vues.dart';
import 'package:crochet_creations/data/repositories/facture_repository.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/data/repositories/vente_vues.dart';
import 'package:crochet_creations/data/stockage/stockage_pdf.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/document_devis.dart';
import 'package:crochet_creations/domain/document_facture.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/regles_devis.dart';
import 'package:drift/drift.dart' show HasResultSet, ResultSetImplementation;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

/// Le jour à [jours] jours de [date], à minuit : un calcul de calendrier, insensible aux changements d'heure.
DateTime decale(DateTime date, int jours) => DateTime(date.year, date.month, date.day + jours);

void main() {
  late AppDatabase db;
  late Directory dossier;
  late ParametresRepository parametres;
  late ClientRepository clients;
  late VenteRepository ventes;
  late FactureRepository factures;
  late DevisRepository devis;
  late StockagePdf stockage;
  late List<DocumentDevis> documents;

  setUp(() async {
    db = creerBaseEnMemoire();
    dossier = await Directory.systemTemp.createTemp('crochet_devis_');
    final NumerotationRepository numerotation = NumerotationRepository(db);
    parametres = ParametresRepository(db);
    clients = ClientRepository(db);
    ventes = VenteRepository(db, ProduitRepository(db, numerotation));
    factures = FactureRepository(
      db,
      numerotation,
      parametres,
      StockagePdf(Directory('${dossier.path}/factures')),
      (DocumentFacture document) async => Uint8List.fromList(utf8.encode('%PDF-FAUX ${document.numero}')),
    );
    stockage = StockagePdf(Directory('${dossier.path}/devis'));
    documents = <DocumentDevis>[];
    devis = DevisRepository(db, numerotation, ventes, factures, parametres, stockage, (
      DocumentDevis document,
    ) async {
      documents.add(document);
      return Uint8List.fromList(utf8.encode('%PDF-FAUX ${document.numero}'));
    });
  });

  tearDown(() async {
    await db.close();
    if (await dossier.exists()) await dossier.delete(recursive: true);
  });

  const DonneesEntreprise profilComplet = DonneesEntreprise(
    nomCommercial: 'Crochet & Créations',
    nomResponsable: 'Camille Martin',
    adresse: '12 rue des Lilas',
    codePostal: '31000',
    ville: 'Toulouse',
    siren: '123 456 789',
    iban: 'FR14 2004 1010 0505 0001 3M02 606',
  );

  final DateTime aujourdhui = debutDeJour(DateTime.now());
  final DateTime dans30Jours = decale(aujourdhui, 30);

  /// Une couverture sur mesure (60 €) et deux doudous (2 × 25 €) : 110 € ; 10 % de remise ; 4,90 € de port.
  Panier panierType() => const Panier()
      .ajouter(
        designation: 'Couverture bébé sur mesure',
        description: 'Coton bio, 80 × 100 cm',
        prixUnitaireCentimes: 6000,
        nature: NatureLigne.service,
      )
      .ajouter(designation: 'Doudou assorti', prixUnitaireCentimes: 2500, quantite: 2)
      .avecRemise(RemiseType.pourcentage, 1000)
      .avecFraisPort(490);

  const int totalType = 11000 - 1100 + 490;

  DevisSaisi saisie({
    int? clientId,
    Panier? panier,
    DateTime? validite,
    int acompte = 0,
    String? delai,
    String? notes,
    DateTime? emission,
  }) => DevisSaisi(
    clientId: clientId,
    panier: panier ?? panierType(),
    dateEmission: emission,
    dateValidite: validite ?? dans30Jours,
    delaiRealisation: delai,
    acompteCentimes: acompte,
    notes: notes,
  );

  Future<Client> unClient() => clients.creer(
    const DonneesClient(typeClient: TypeClient.particulier, prenom: 'Léa', nom: 'Bernard'),
  );

  Future<int> nombreDe<T extends HasResultSet, R>(ResultSetImplementation<T, R> table) async =>
      (await db.select(table).get()).length;

  String numero(int n) => 'DEVIS-${aujourdhui.year}-${n.toString().padLeft(4, '0')}';

  group('creer', () {
    test('crée un brouillon numéroté, avec ses lignes et ses totaux', () async {
      final Client client = await unClient();
      final DevisFiche d = await devis.creer(
        saisie(clientId: client.id, delai: '3 semaines', acompte: 3000, notes: 'Couleurs au choix'),
      );

      expect(d.numero, numero(1));
      expect(d.statut, StatutDevis.brouillon);
      expect(d.clientId, client.id);
      expect(d.dateEmission, aujourdhui);
      expect(d.dateValidite, dans30Jours);
      expect(d.delaiRealisation, '3 semaines');
      expect(d.acompteCentimes, 3000);
      expect(d.notes, 'Couleurs au choix');
      expect(d.sousTotalCentimes, 11000);
      expect(d.remiseType, RemiseType.pourcentage);
      expect(d.remiseValeur, 1000);
      expect(d.remiseCentimes, 1100);
      expect(d.fraisPortCentimes, 490);
      expect(d.totalCentimes, totalType);
      expect(d.venteId, isNull);

      final DevisDetail? detail = await devis.detail(d.id);
      expect(detail!.lignes.map((LigneDevis l) => l.designation), <String>[
        'Couverture bébé sur mesure',
        'Doudou assorti',
      ]);
      expect(detail.lignes.map((LigneDevis l) => l.position), <int>[0, 1]);
      expect(detail.lignes.first.description, 'Coton bio, 80 × 100 cm');
      expect(detail.lignes.first.nature, NatureLigne.service);
      expect(detail.lignes.last.quantite, 2);
      expect(detail.lignes.last.totalLigneCentimes, 5000);
      expect(detail.client!.id, client.id);
      expect(detail.vente, isNull);
    });

    test('les devis suivants prennent les numéros suivants', () async {
      expect((await devis.creer(saisie())).numero, numero(1));
      expect((await devis.creer(saisie())).numero, numero(2));
    });

    test('le numéro suit l’année de la date du devis', () async {
      final DevisFiche d = await devis.creer(saisie(emission: DateTime(2025, 12, 31, 18)));
      expect(d.numero, 'DEVIS-2025-0001');
      expect(d.dateEmission, DateTime(2025, 12, 31));
    });

    test('un devis sans client est possible', () async {
      final DevisFiche d = await devis.creer(saisie());
      expect(d.clientId, isNull);
      expect((await devis.detail(d.id))!.client, isNull);
    });

    test('une saisie refusée n’enregistre rien et ne consomme aucun numéro', () async {
      await expectLater(
        devis.creer(saisie(panier: const Panier())),
        throwsA(
          isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('au moins une ligne')),
        ),
      );
      await expectLater(devis.creer(saisie(acompte: totalType + 1)), throwsA(isA<DonneeInvalide>()));
      await expectLater(
        devis.creer(saisie(validite: decale(aujourdhui, -1))),
        throwsA(isA<DonneeInvalide>()),
      );
      await expectLater(
        devis.creer(saisie(emission: decale(aujourdhui, 2), validite: decale(aujourdhui, 1))),
        throwsA(isA<DonneeInvalide>()),
      );
      await expectLater(
        devis.creer(saisie(panier: panierType().avecRemise(RemiseType.montant, 999999))),
        throwsA(isA<RemiseInvalide>()),
      );

      expect(await nombreDe(db.devis), 0);
      expect(await nombreDe(db.lignesDevis), 0);
      expect((await devis.creer(saisie())).numero, numero(1));
    });

    test('refuse un client inexistant ou archivé', () async {
      await expectLater(devis.creer(saisie(clientId: 999)), throwsA(isA<ElementIntrouvable>()));

      final Client client = await unClient();
      await clients.archiver(client.id);
      await expectLater(devis.creer(saisie(clientId: client.id)), throwsA(isA<DonneeInvalide>()));
      expect(await nombreDe(db.devis), 0);
    });

    test('une validité aujourd’hui est acceptée, et un devis sans limite aussi', () async {
      await devis.creer(saisie(validite: aujourdhui));
      final DevisFiche sansLimite = await devis.creer(
        DevisSaisi(panier: panierType()),
      );
      expect(sansLimite.dateValidite, isNull);
    });
  });

  group('modifier', () {
    test('change le contenu et les conditions, mais garde le numéro, la date et le statut', () async {
      final Client client = await unClient();
      final DevisFiche d = await devis.creer(saisie(delai: '3 semaines'));
      await devis.changerStatut(d.id, StatutDevis.envoye);

      final Panier nouveau = const Panier().ajouter(designation: 'Bonnet', prixUnitaireCentimes: 1800);
      final DateTime autreValidite = decale(dans30Jours, 10);
      final DevisFiche modifie = await devis.modifier(
        d.id,
        saisie(
          clientId: client.id,
          panier: nouveau,
          validite: autreValidite,
          delai: '1 mois',
          acompte: 500,
          notes: 'Rose poudré',
        ),
      );

      expect(modifie.numero, d.numero);
      expect(modifie.dateEmission, d.dateEmission);
      expect(modifie.statut, StatutDevis.envoye);
      expect(modifie.clientId, client.id);
      expect(modifie.dateValidite, autreValidite);
      expect(modifie.delaiRealisation, '1 mois');
      expect(modifie.acompteCentimes, 500);
      expect(modifie.notes, 'Rose poudré');
      expect(modifie.sousTotalCentimes, 1800);
      expect(modifie.remiseType, RemiseType.aucune);
      expect(modifie.remiseCentimes, 0);
      expect(modifie.fraisPortCentimes, 0);
      expect(modifie.totalCentimes, 1800);

      final DevisDetail detail = (await devis.detail(d.id))!;
      expect(detail.lignes.map((LigneDevis l) => l.designation), <String>['Bonnet']);
      expect(await nombreDe(db.lignesDevis), 1);
      expect(await nombreDe(db.devis), 1);
    });

    test('une saisie refusée laisse le devis intact', () async {
      final DevisFiche d = await devis.creer(saisie());
      await expectLater(devis.modifier(d.id, saisie(acompte: totalType + 1)), throwsA(isA<DonneeInvalide>()));
      await expectLater(devis.modifier(d.id, saisie(panier: const Panier())), throwsA(isA<DonneeInvalide>()));

      final DevisDetail detail = (await devis.detail(d.id))!;
      expect(detail.devis.totalCentimes, totalType);
      expect(detail.lignes, hasLength(2));
    });

    test('un devis accepté, refusé ou converti ne se modifie plus', () async {
      final DevisFiche accepte = await devis.creer(saisie());
      await devis.changerStatut(accepte.id, StatutDevis.accepte);
      await expectLater(devis.modifier(accepte.id, saisie()), throwsA(isA<DonneeInvalide>()));

      final DevisFiche refuse = await devis.creer(saisie());
      await devis.changerStatut(refuse.id, StatutDevis.refuse);
      await expectLater(devis.modifier(refuse.id, saisie()), throwsA(isA<DonneeInvalide>()));

      final DevisFiche converti = await devis.creer(saisie());
      await devis.convertir(converti.id);
      await expectLater(
        devis.modifier(converti.id, saisie()),
        throwsA(
          isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('converti')),
        ),
      );
    });

    test('un devis expiré se modifie pour prolonger sa validité et redevient un brouillon', () async {
      final DevisFiche d = await devis.creer(saisie(validite: decale(aujourdhui, 2)));
      await devis.changerStatut(d.id, StatutDevis.envoye);
      final DateTime plusTard = decale(aujourdhui, 5);
      expect(await devis.actualiserExpirations(maintenant: plusTard), 1);
      expect((await devis.obtenir(d.id))!.statut, StatutDevis.expire);

      // Sans prolonger : refusé.
      await expectLater(
        devis.modifier(d.id, saisie(validite: decale(aujourdhui, 2)), maintenant: plusTard),
        throwsA(isA<DonneeInvalide>()),
      );

      final DevisFiche prolonge = await devis.modifier(
        d.id,
        saisie(validite: decale(plusTard, 20)),
        maintenant: plusTard,
      );
      expect(prolonge.statut, StatutDevis.brouillon);
      expect(prolonge.dateValidite, decale(plusTard, 20));
    });

    test('refuse un devis qui n’existe pas', () async {
      await expectLater(devis.modifier(999, saisie()), throwsA(isA<ElementIntrouvable>()));
    });
  });

  group('statuts', () {
    test('brouillon → envoyé → accepté → refusé', () async {
      final DevisFiche d = await devis.creer(saisie());
      expect((await devis.changerStatut(d.id, StatutDevis.envoye)).statut, StatutDevis.envoye);
      expect((await devis.changerStatut(d.id, StatutDevis.accepte)).statut, StatutDevis.accepte);
      expect((await devis.changerStatut(d.id, StatutDevis.refuse)).statut, StatutDevis.refuse);
    });

    test('un changement non permis est refusé et le statut ne bouge pas', () async {
      final DevisFiche d = await devis.creer(saisie());
      await devis.changerStatut(d.id, StatutDevis.refuse);
      for (final StatutDevis cible in <StatutDevis>[
        StatutDevis.brouillon,
        StatutDevis.envoye,
        StatutDevis.accepte,
        StatutDevis.expire,
      ]) {
        await expectLater(devis.changerStatut(d.id, cible), throwsA(isA<DonneeInvalide>()), reason: cible.name);
      }
      expect((await devis.obtenir(d.id))!.statut, StatutDevis.refuse);
    });

    test('un devis déjà converti ne change plus de statut', () async {
      final DevisFiche d = await devis.creer(saisie());
      await devis.convertir(d.id);
      await expectLater(devis.changerStatut(d.id, StatutDevis.refuse), throwsA(isA<DonneeInvalide>()));
    });

    test('refuse un devis qui n’existe pas', () async {
      await expectLater(devis.changerStatut(999, StatutDevis.envoye), throwsA(isA<ElementIntrouvable>()));
    });
  });

  group('expiration automatique', () {
    test('brouillons et devis envoyés périmés passent en « Expiré », les autres ne bougent pas', () async {
      final DateTime limite = decale(aujourdhui, 10);
      final DevisFiche brouillon = await devis.creer(saisie(validite: limite));
      final DevisFiche envoye = await devis.creer(saisie(validite: limite));
      await devis.changerStatut(envoye.id, StatutDevis.envoye);
      final DevisFiche accepte = await devis.creer(saisie(validite: limite));
      await devis.changerStatut(accepte.id, StatutDevis.accepte);
      final DevisFiche refuse = await devis.creer(saisie(validite: limite));
      await devis.changerStatut(refuse.id, StatutDevis.refuse);
      final DevisFiche valable = await devis.creer(saisie(validite: decale(limite, 30)));
      final DevisFiche sansLimite = await devis.creer(DevisSaisi(panier: panierType()));

      final int nombre = await devis.actualiserExpirations(maintenant: decale(limite, 1));

      expect(nombre, 2);
      Future<StatutDevis> statutDe(DevisFiche d) async => (await devis.obtenir(d.id))!.statut;
      expect(await statutDe(brouillon), StatutDevis.expire);
      expect(await statutDe(envoye), StatutDevis.expire);
      expect(await statutDe(accepte), StatutDevis.accepte);
      expect(await statutDe(refuse), StatutDevis.refuse);
      expect(await statutDe(valable), StatutDevis.brouillon);
      expect(await statutDe(sansLimite), StatutDevis.brouillon);
    });

    test('le devis reste valable toute la journée de sa date limite', () async {
      final DateTime limite = decale(aujourdhui, 10);
      final DevisFiche d = await devis.creer(saisie(validite: limite));

      expect(await devis.actualiserExpirations(maintenant: limite.add(const Duration(hours: 23, minutes: 59))), 0);
      expect((await devis.obtenir(d.id))!.statut, StatutDevis.brouillon);
      expect(await devis.actualiserExpirations(maintenant: decale(limite, 1)), 1);
    });

    test('un devis périmé ne peut plus changer de statut ni être converti', () async {
      final DateTime limite = decale(aujourdhui, 3);
      final DevisFiche d = await devis.creer(saisie(validite: limite));
      final DateTime apres = decale(limite, 1);

      await expectLater(
        devis.changerStatut(d.id, StatutDevis.accepte, maintenant: apres),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('expiré'))),
      );
      await expectLater(
        devis.convertir(d.id, date: apres),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('expiré'))),
      );
      expect((await devis.obtenir(d.id))!.statut, StatutDevis.expire);
      expect(await nombreDe(db.ventes), 0);
    });

    test('le résumé affiche « Expiré » même si la base n’a pas encore été mise à jour', () async {
      final DateTime limite = decale(aujourdhui, 3);
      await devis.creer(saisie(validite: limite));
      final DevisResume resume = (await devis.lister()).single;
      expect(resume.devis.statut, StatutDevis.brouillon);
      expect(resume.statut(limite), StatutDevis.brouillon);
      expect(resume.statut(decale(limite, 1)), StatutDevis.expire);
    });
  });

  group('convertir', () {
    test('en commande : les lignes, la remise et les frais passent dans une vente validée, sans facture', () async {
      final Client client = await unClient();
      final DevisFiche d = await devis.creer(saisie(clientId: client.id, acompte: 3000, notes: 'Rose poudré'));

      final ResultatConversion resultat = await devis.convertir(d.id);

      expect(resultat.facture, isNull);
      expect(resultat.problemeFacture, isNull);
      expect(resultat.devis.statut, StatutDevis.accepte);
      expect(resultat.devis.venteId, resultat.vente.id);

      final Vente vente = resultat.vente;
      expect(vente.clientId, client.id);
      expect(vente.statut, StatutVente.validee);
      expect(vente.statutPaiement, StatutPaiement.impayee);
      expect(vente.sousTotalCentimes, 11000);
      expect(vente.remiseType, RemiseType.pourcentage);
      expect(vente.remiseValeur, 1000);
      expect(vente.remiseCentimes, 1100);
      expect(vente.fraisPortCentimes, 490);
      expect(vente.totalCentimes, d.totalCentimes);
      expect(vente.notes, 'Commande issue du devis ${d.numero}\nRose poudré');

      final List<LigneVente> lignes = await (db.select(db.lignesVente)..where((t) => t.venteId.equals(vente.id))).get();
      expect(lignes.map((LigneVente l) => l.designation), <String>['Couverture bébé sur mesure', 'Doudou assorti']);
      expect(lignes.map((LigneVente l) => l.totalLigneCentimes), <int>[6000, 5000]);
      expect(lignes.first.description, 'Coton bio, 80 × 100 cm');
      expect(lignes.first.nature, NatureLigne.service);
      expect(lignes.every((LigneVente l) => l.produitId == null), isTrue);

      expect(await nombreDe(db.paiements), 0);
      expect(await nombreDe(db.factures), 0);

      final DevisDetail detail = (await devis.detail(d.id))!;
      expect(detail.estConverti, isTrue);
      expect(detail.vente!.id, vente.id);
    });

    test('avec l’acompte : il devient le premier paiement de la commande', () async {
      final DevisFiche d = await devis.creer(saisie(acompte: 3000));

      final ResultatConversion resultat = await devis.convertir(d.id, modeAcompte: ModePaiement.virement);

      final List<Paiement> paiements = await db.select(db.paiements).get();
      expect(paiements, hasLength(1));
      expect(paiements.single.venteId, resultat.vente.id);
      expect(paiements.single.montantCentimes, 3000);
      expect(paiements.single.modePaiement, ModePaiement.virement);
      expect(resultat.vente.statutPaiement, StatutPaiement.partiellementPayee);
      final VenteDetail? detail = await ventes.detail(resultat.vente.id);
      expect(detail!.soldeDuCentimes, totalType - 3000);
    });

    test('un acompte égal au total solde la commande', () async {
      final DevisFiche d = await devis.creer(saisie(acompte: totalType));
      final ResultatConversion resultat = await devis.convertir(d.id, modeAcompte: ModePaiement.carte);
      expect(resultat.vente.statutPaiement, StatutPaiement.payee);
    });

    test('sans acompte demandé par le devis, on ne peut pas en enregistrer un', () async {
      final DevisFiche d = await devis.creer(saisie());
      await expectLater(
        devis.convertir(d.id, modeAcompte: ModePaiement.especes),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(await nombreDe(db.ventes), 0);
      expect((await devis.obtenir(d.id))!.statut, StatutDevis.brouillon);
    });

    test('avec la facture : la commande et sa facture sont créées ensemble', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Client client = await unClient();
      final DevisFiche d = await devis.creer(saisie(clientId: client.id, acompte: 3000));

      final ResultatConversion resultat = await devis.convertir(
        d.id,
        avecFacture: true,
        modeAcompte: ModePaiement.virement,
      );

      expect(resultat.problemeFacture, isNull);
      final Facture facture = resultat.facture!;
      expect(facture.numero, 'FACT-${aujourdhui.year}-0001');
      expect(facture.venteId, resultat.vente.id);
      expect(facture.totalCentimes, d.totalCentimes);
      expect(facture.clientNom, 'Léa Bernard');
      expect(resultat.devis.statut, StatutDevis.accepte);
      expect(await nombreDe(db.paiements), 1);
    });

    test('profil incomplet : la conversion avec facture est refusée avant toute écriture', () async {
      final DevisFiche d = await devis.creer(saisie(acompte: 3000));

      await expectLater(
        devis.convertir(d.id, avecFacture: true, modeAcompte: ModePaiement.carte),
        throwsA(isA<ProfilIncomplet>()),
      );

      expect(await nombreDe(db.ventes), 0);
      expect(await nombreDe(db.paiements), 0);
      expect(await nombreDe(db.factures), 0);
      final DevisFiche intact = (await devis.obtenir(d.id))!;
      expect(intact.statut, StatutDevis.brouillon);
      expect(intact.venteId, isNull);

      // Le profil complété, la même conversion fonctionne, et la numérotation n'a pas de trou.
      await parametres.enregistrerProfil(profilComplet);
      final ResultatConversion resultat = await devis.convertir(d.id, avecFacture: true);
      expect(resultat.facture!.numero, 'FACT-${aujourdhui.year}-0001');
    });

    test('la facture peut ensuite être créée depuis la commande', () async {
      await parametres.enregistrerProfil(profilComplet);
      final DevisFiche d = await devis.creer(saisie());
      final ResultatConversion resultat = await devis.convertir(d.id);

      final Facture facture = await factures.creer(resultat.vente.id);
      expect(facture.totalCentimes, d.totalCentimes);
    });

    test('un client archivé entre-temps annule toute la conversion', () async {
      final Client client = await unClient();
      final DevisFiche d = await devis.creer(saisie(clientId: client.id, acompte: 3000));
      await clients.archiver(client.id);

      await expectLater(
        devis.convertir(d.id, modeAcompte: ModePaiement.carte),
        throwsA(isA<DonneeInvalide>()),
      );

      expect(await nombreDe(db.ventes), 0);
      expect(await nombreDe(db.lignesVente), 0);
      expect(await nombreDe(db.paiements), 0);
      final DevisFiche intact = (await devis.obtenir(d.id))!;
      expect(intact.statut, StatutDevis.brouillon);
      expect(intact.venteId, isNull);
    });

    test('se convertit depuis un brouillon, un devis envoyé ou un devis accepté, une seule fois', () async {
      for (final StatutDevis depart in <StatutDevis>[StatutDevis.brouillon, StatutDevis.envoye, StatutDevis.accepte]) {
        final DevisFiche d = await devis.creer(saisie());
        if (depart != StatutDevis.brouillon) await devis.changerStatut(d.id, depart);
        final ResultatConversion resultat = await devis.convertir(d.id);
        expect(resultat.devis.statut, StatutDevis.accepte, reason: depart.name);
        await expectLater(
          devis.convertir(d.id),
          throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('déjà'))),
          reason: depart.name,
        );
      }
      expect(await nombreDe(db.ventes), 3);
    });

    test('un devis refusé ne se convertit pas', () async {
      final DevisFiche d = await devis.creer(saisie());
      await devis.changerStatut(d.id, StatutDevis.refuse);
      await expectLater(devis.convertir(d.id), throwsA(isA<DonneeInvalide>()));
      expect(await nombreDe(db.ventes), 0);
    });

    test('un devis sans client donne une vente de passage', () async {
      final DevisFiche d = await devis.creer(saisie());
      final ResultatConversion resultat = await devis.convertir(d.id);
      expect(resultat.vente.clientId, isNull);
    });

    test('refuse un devis qui n’existe pas', () async {
      await expectLater(devis.convertir(999), throwsA(isA<ElementIntrouvable>()));
    });
  });

  group('consultation', () {
    test('lister : le plus récent d’abord, avec le client', () async {
      final Client client = await unClient();
      final DevisFiche ancien = await devis.creer(saisie(emission: decale(aujourdhui, -5)));
      final DevisFiche recent = await devis.creer(saisie(clientId: client.id));

      final List<DevisResume> liste = await devis.lister();

      expect(liste.map((DevisResume r) => r.devis.id), <int>[recent.id, ancien.id]);
      expect(liste.first.client!.id, client.id);
      expect(liste.last.client, isNull);
    });

    test('detail : null pour un devis inconnu', () async {
      expect(await devis.detail(999), isNull);
    });

    test('observerDetail se met à jour quand le statut change', () async {
      final DevisFiche d = await devis.creer(saisie());
      final List<StatutDevis> vus = <StatutDevis>[];
      Completer<void> prochain = Completer<void>();
      final StreamSubscription<DevisDetail?> abonnement = devis.observerDetail(d.id).listen((DevisDetail? detail) {
        vus.add(detail!.devis.statut);
        if (!prochain.isCompleted) prochain.complete();
      });

      await prochain.future.timeout(const Duration(seconds: 5));
      prochain = Completer<void>();
      await devis.changerStatut(d.id, StatutDevis.envoye);
      await prochain.future.timeout(const Duration(seconds: 5));

      expect(vus.first, StatutDevis.brouillon);
      expect(vus.last, StatutDevis.envoye);
      await abonnement.cancel();
    });
  });

  group('PDF', () {
    test('fabrique le document du devis et le range sous son numéro', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Client client = await unClient();
      final DevisFiche d = await devis.creer(saisie(clientId: client.id, delai: '3 semaines', acompte: 3000));

      final Uint8List pdf = await devis.obtenirPdf(d.id);

      expect(utf8.decode(pdf), '%PDF-FAUX ${d.numero}');
      final DocumentDevis document = documents.single;
      expect(document.numero, d.numero);
      expect(document.dateEmission, aujourdhui);
      expect(document.dateValidite, dans30Jours);
      expect(document.delaiRealisation, '3 semaines');
      expect(document.acompteCentimes, 3000);
      expect(document.client.nom, 'Léa Bernard');
      expect(document.emetteur.nom, 'Crochet & Créations');
      expect(document.emetteur.siren, '123456789');
      expect(document.iban, 'FR14 2004 1010 0505 0001 3M02 606');
      expect(document.mentionTva, 'TVA non applicable, article 293 B du CGI');
      expect(document.lignes.map((LigneDocument l) => l.designation), <String>[
        'Couverture bébé sur mesure',
        'Doudou assorti',
      ]);
      expect(document.sousTotalCentimes, 11000);
      expect(document.remiseCentimes, 1100);
      expect(document.libelleRemise, 'Remise (10\u00A0%)');
      expect(document.fraisPortCentimes, 490);
      expect(document.totalCentimes, totalType);

      final Uint8List? stocke = await stockage.lire('${d.numero}.pdf');
      expect(utf8.decode(stocke!), '%PDF-FAUX ${d.numero}');
    });

    test('le PDF reflète toujours l’état actuel du devis', () async {
      final DevisFiche d = await devis.creer(saisie());
      await devis.obtenirPdf(d.id);
      await devis.modifier(d.id, saisie(panier: const Panier().ajouter(designation: 'Bonnet', prixUnitaireCentimes: 1800)));

      await devis.obtenirPdf(d.id);

      expect(documents, hasLength(2));
      expect(documents.last.lignes.map((LigneDocument l) => l.designation), <String>['Bonnet']);
      expect(documents.last.totalCentimes, 1800);
    });

    test('un devis sans client s’imprime sans nom de destinataire', () async {
      final DevisFiche d = await devis.creer(saisie());
      await devis.obtenirPdf(d.id);
      expect(documents.single.client.nom, isNull);
    });

    test('cheminPdf donne le fichier à partager', () async {
      final DevisFiche d = await devis.creer(saisie());
      final String chemin = await devis.cheminPdf(d.id);
      expect(chemin, endsWith('${d.numero}.pdf'));
      expect(File(chemin).existsSync(), isTrue);
    });

    test('refuse un devis qui n’existe pas', () async {
      await expectLater(devis.obtenirPdf(999), throwsA(isA<ElementIntrouvable>()));
    });
  });
}
