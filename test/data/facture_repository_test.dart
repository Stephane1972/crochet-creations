import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crochet_creations/core/constants/app_constants.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/facture_repository.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/data/repositories/vente_vues.dart';
import 'package:crochet_creations/data/stockage/stockage_pdf.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/document_facture.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late Directory dossier;
  late ParametresRepository parametres;
  late ClientRepository clients;
  late VenteRepository ventes;
  late FactureRepository factures;
  late StockagePdf stockage;
  late List<DocumentFacture> documents;
  late bool generateurEnPanne;

  setUp(() async {
    db = creerBaseEnMemoire();
    dossier = await Directory.systemTemp.createTemp('crochet_factures_');
    stockage = StockagePdf(Directory('${dossier.path}/factures'));
    parametres = ParametresRepository(db);
    clients = ClientRepository(db);
    ventes = VenteRepository(db, ProduitRepository(db, NumerotationRepository(db)));
    documents = <DocumentFacture>[];
    generateurEnPanne = false;
    factures = FactureRepository(db, NumerotationRepository(db), parametres, stockage, (
      DocumentFacture document,
    ) async {
      documents.add(document);
      if (generateurEnPanne) throw StateError('PDF impossible');
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
    telephone: '06 12 34 56 78',
    email: 'contact@exemple.fr',
    siren: '123 456 789',
    conditionsPaiement: 'Paiement sous 15 jours.',
    iban: 'FR14 2004 1010 0505 0001 3M02 606',
    messageRemerciement: 'Merci et à bientôt !',
  );

  final DateTime le15Juin = DateTime(2026, 6, 15, 10, 30);

  /// Une vente de deux articles, avec 10 % de remise et 4,90 € de frais de port.
  Future<Vente> uneVente({int? clientId, DateTime? date}) {
    return ventes.valider(
      clientId: clientId,
      date: date ?? DateTime(2026, 6, 10, 15),
      panier: const Panier()
          .ajouter(
            designation: 'Doudou lapin',
            description: 'Beige, 25 cm',
            prixUnitaireCentimes: 2500,
            quantite: 2,
          )
          .ajouter(designation: 'Boucles d’oreilles', prixUnitaireCentimes: 1800)
          .avecRemise(RemiseType.pourcentage, 1000)
          .avecFraisPort(490),
    );
  }

  Future<Client> unClient() => clients.creer(
    const DonneesClient(
      typeClient: TypeClient.professionnel,
      raisonSociale: 'Atelier Soleil',
      prenom: 'Léa',
      nom: 'Bernard',
      adresse: '3 place du Marché',
      codePostal: '34000',
      ville: 'Montpellier',
      siret: '98765432100012',
    ),
  );

  Future<int> nombreDeFactures() async => (await db.select(db.factures).get()).length;

  group('creer', () {
    test('profil incomplet : refusé, avec ce qui manque, sans consommer de numéro', () async {
      final Vente vente = await uneVente();
      await parametres.enregistrerProfil(const DonneesEntreprise(nomCommercial: 'Crochet & Créations'));

      await expectLater(
        factures.creer(vente.id, date: le15Juin),
        throwsA(
          isA<ProfilIncomplet>()
              .having((ProfilIncomplet e) => e.manque, 'manque', <String>[
                'l’adresse',
                'le code postal et la ville',
                'le numéro SIREN',
              ])
              .having((ProfilIncomplet e) => e.message, 'message', contains('« Mon entreprise »')),
        ),
      );
      expect(await nombreDeFactures(), 0);
      expect(documents, isEmpty);

      // Une fois le profil complété, la première facture porte bien le numéro 1.
      await parametres.enregistrerProfil(profilComplet);
      expect((await factures.creer(vente.id, date: le15Juin)).numero, 'FACT-2026-0001');
    });

    test('recopie le client, les mentions et les dates, et range le PDF', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Client client = await unClient();
      final Vente vente = await uneVente(clientId: client.id);

      final Facture f = await factures.creer(vente.id, date: le15Juin);

      expect(f.numero, 'FACT-2026-0001');
      expect(f.venteId, vente.id);
      expect(f.clientId, client.id);
      expect(f.clientNom, 'Atelier Soleil');
      expect(f.clientAdresse, '3 place du Marché\n34000 Montpellier');
      expect(f.clientSiret, '98765432100012');
      expect(f.dateEmission, le15Juin);
      expect(f.dateVentePrestation, vente.dateVente);
      expect(f.totalCentimes, vente.totalCentimes);
      expect(f.mentionTva, 'TVA non applicable, article 293 B du CGI');
      expect(f.mentionTva, AppConstants.mentionTvaFranchise);
      expect(f.conditionsPaiement, 'Paiement sous 15 jours.');
      expect(f.iban, 'FR14 2004 1010 0505 0001 3M02 606');
      expect(f.messageRemerciement, 'Merci et à bientôt !');
      expect(f.statut, StatutFacture.emise);
      expect(f.pdfChemin, 'FACT-2026-0001.pdf');
      expect(utf8.decode((await stockage.lire('FACT-2026-0001.pdf'))!), '%PDF-FAUX FACT-2026-0001');
    });

    test('le document imprimé reprend les lignes, la remise, les frais de port et l’entreprise', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Client client = await unClient();
      final Vente vente = await uneVente(clientId: client.id);

      await factures.creer(vente.id, date: le15Juin);

      final DocumentFacture d = documents.single;
      expect(d.numero, 'FACT-2026-0001');
      expect(d.emetteur.nom, 'Crochet & Créations');
      expect(d.emetteur.responsable, 'Camille Martin');
      expect(d.emetteur.adresse, <String>['12 rue des Lilas', '31000 Toulouse']);
      expect(d.emetteur.siren, '123456789');
      expect(d.client.nom, 'Atelier Soleil');
      expect(d.client.adresse, <String>['3 place du Marché', '34000 Montpellier']);
      expect(d.lignes.map((LigneDocument l) => l.designation), <String>['Doudou lapin', 'Boucles d’oreilles']);
      expect(d.lignes.first.description, 'Beige, 25 cm');
      expect(d.lignes.first.quantite, 2);
      expect(d.lignes.first.totalCentimes, 5000);
      expect(d.sousTotalCentimes, 6800);
      expect(d.remiseCentimes, 680);
      expect(d.libelleRemise, 'Remise (10 %)');
      expect(d.fraisPortCentimes, 490);
      expect(d.totalCentimes, 6610);
      expect(d.mentionTva, 'TVA non applicable, article 293 B du CGI');
      expect(d.messageRemerciement, 'Merci et à bientôt !');
    });

    test('client de passage : aucune coordonnée client', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();

      final Facture f = await factures.creer(vente.id, date: le15Juin);

      expect(f.clientId, isNull);
      expect(f.clientNom, isNull);
      expect(f.clientAdresse, isNull);
      expect(documents.single.client.nom, isNull);
      expect(documents.single.client.adresse, isEmpty);
    });

    test('numérotation chronologique, une suite par année', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente a = await uneVente();
      final Vente b = await uneVente();
      final Vente c = await uneVente();

      expect((await factures.creer(a.id, date: DateTime(2026, 12, 30))).numero, 'FACT-2026-0001');
      expect((await factures.creer(b.id, date: DateTime(2026, 12, 31))).numero, 'FACT-2026-0002');
      expect((await factures.creer(c.id, date: DateTime(2027, 1, 2))).numero, 'FACT-2027-0001');
    });

    test('une vente déjà facturée est refusée, sans consommer de numéro', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      final Vente autre = await uneVente();
      await factures.creer(vente.id, date: le15Juin);

      await expectLater(
        factures.creer(vente.id, date: le15Juin),
        throwsA(
          isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('FACT-2026-0001')),
        ),
      );
      expect(await nombreDeFactures(), 1);
      expect((await factures.creer(autre.id, date: le15Juin)).numero, 'FACT-2026-0002');
    });

    test('une vente annulée ne se facture pas', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      await ventes.annuler(vente.id);

      await expectLater(
        factures.creer(vente.id, date: le15Juin),
        throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains('annulée'))),
      );
      expect(await nombreDeFactures(), 0);
    });

    test('une vente inexistante est signalée', () async {
      await parametres.enregistrerProfil(profilComplet);

      await expectLater(factures.creer(999, date: le15Juin), throwsA(isA<ElementIntrouvable>()));
      expect(await nombreDeFactures(), 0);
    });

    test('la facture est figée : modifier ensuite le client ou l’entreprise ne la change pas', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Client client = await unClient();
      final Vente vente = await uneVente(clientId: client.id);
      final Facture f = await factures.creer(vente.id, date: le15Juin);

      await clients.modifier(
        client.id,
        const DonneesClient(
          typeClient: TypeClient.professionnel,
          raisonSociale: 'Autre nom',
          adresse: 'Ailleurs',
          codePostal: '75001',
          ville: 'Paris',
        ),
      );
      await parametres.enregistrerProfil(
        const DonneesEntreprise(
          nomCommercial: 'Nouveau nom',
          adresse: 'Nouvelle adresse',
          codePostal: '75001',
          ville: 'Paris',
          siren: '732829320',
          conditionsPaiement: 'Comptant.',
          iban: 'FR1420041010050500013M02606',
        ),
      );

      final Facture relue = (await factures.obtenir(f.id))!;
      expect(relue.clientNom, 'Atelier Soleil');
      expect(relue.clientAdresse, '3 place du Marché\n34000 Montpellier');
      expect(relue.conditionsPaiement, 'Paiement sous 15 jours.');
      expect(relue.iban, 'FR14 2004 1010 0505 0001 3M02 606');
      expect(relue.messageRemerciement, 'Merci et à bientôt !');
    });

    test('profil sans IBAN ni remerciement : la facture n’en porte pas', () async {
      await parametres.enregistrerProfil(
        const DonneesEntreprise(
          nomCommercial: 'Crochet & Créations',
          adresse: '12 rue des Lilas',
          codePostal: '31000',
          ville: 'Toulouse',
          siren: '123456789',
        ),
      );
      final Vente vente = await uneVente();

      final Facture f = await factures.creer(vente.id, date: le15Juin);

      expect(f.iban, isNull);
      expect(f.messageRemerciement, isNull);
      expect(f.conditionsPaiement, 'Paiement à réception de la facture.');
      expect(documents.single.iban, isNull);
      expect(documents.single.messageRemerciement, isNull);
    });

    test('si le PDF ne peut pas être fabriqué, la facture existe quand même et son PDF sera refait', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      generateurEnPanne = true;

      final Facture f = await factures.creer(vente.id, date: le15Juin);

      expect(f.numero, 'FACT-2026-0001');
      expect(f.pdfChemin, isNull);
      expect(await stockage.lire('FACT-2026-0001.pdf'), isNull);

      generateurEnPanne = false;
      final Uint8List octets = await factures.obtenirPdf(f.id);
      expect(utf8.decode(octets), '%PDF-FAUX FACT-2026-0001');
      expect((await factures.obtenir(f.id))!.pdfChemin, 'FACT-2026-0001.pdf');
    });
  });

  group('annuler', () {
    test('marque la facture annulée sans toucher à la vente', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      final Facture f = await factures.creer(vente.id, date: le15Juin);

      await factures.annuler(f.id);

      expect((await factures.obtenir(f.id))!.statut, StatutFacture.annulee);
      final Vente apres = (await ventes.obtenir(vente.id))!;
      expect(apres.statut, StatutVente.validee);
      expect(apres.statutPaiement, vente.statutPaiement);
      expect(apres.totalCentimes, vente.totalCentimes);
    });

    test('le numéro reste utilisé : une nouvelle facture de la même vente porte le suivant', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      final Facture premiere = await factures.creer(vente.id, date: le15Juin);
      await factures.annuler(premiere.id);

      final Facture seconde = await factures.creer(vente.id, date: le15Juin);

      expect(premiere.numero, 'FACT-2026-0001');
      expect(seconde.numero, 'FACT-2026-0002');
      expect(await nombreDeFactures(), 2);
      expect((await factures.obtenir(premiere.id))!.statut, StatutFacture.annulee);
      expect((await factures.obtenir(seconde.id))!.statut, StatutFacture.emise);
    });

    test('une facture déjà annulée ne s’annule pas deux fois', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      final Facture f = await factures.creer(vente.id, date: le15Juin);
      await factures.annuler(f.id);

      await expectLater(factures.annuler(f.id), throwsA(isA<DonneeInvalide>()));
    });

    test('une facture inexistante est signalée', () async {
      await expectLater(factures.annuler(42), throwsA(isA<ElementIntrouvable>()));
    });

    test('annuler la vente annule aussi sa facture', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      final Facture f = await factures.creer(vente.id, date: le15Juin);

      await ventes.annuler(vente.id);

      expect((await factures.obtenir(f.id))!.statut, StatutFacture.annulee);
    });
  });

  group('consultation', () {
    test('lister : la plus récente d’abord', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Facture a = await factures.creer((await uneVente()).id, date: DateTime(2026, 6, 1));
      final Facture b = await factures.creer((await uneVente()).id, date: DateTime(2026, 6, 20));
      final Facture c = await factures.creer((await uneVente()).id, date: DateTime(2026, 6, 20));

      final List<Facture> liste = await factures.lister();

      expect(liste.map((Facture f) => f.id), <int>[c.id, b.id, a.id]);
    });

    test('observerListe se met à jour à la création et à l’annulation', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();

      final List<List<String>> vus = <List<String>>[];
      final sub = factures.observerListe().listen(
        (List<Facture> l) => vus.add(l.map((Facture f) => '${f.numero}:${f.statut.name}').toList()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final Facture f = await factures.creer(vente.id, date: le15Juin);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await factures.annuler(f.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(vus.first, isEmpty);
      expect(vus, contains(equals(<String>['FACT-2026-0001:emise'])));
      expect(vus.last, <String>['FACT-2026-0001:annulee']);
    });

    test('le détail d’une vente connaît ses factures, la valide en premier', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Vente vente = await uneVente();
      expect((await ventes.detail(vente.id))!.factureEmise, isNull);

      final Facture premiere = await factures.creer(vente.id, date: le15Juin);
      expect((await ventes.detail(vente.id))!.factureEmise?.id, premiere.id);

      await factures.annuler(premiere.id);
      final VenteDetail apresAnnulation = (await ventes.detail(vente.id))!;
      expect(apresAnnulation.factureEmise, isNull);
      expect(apresAnnulation.factures.map((Facture f) => f.numero), <String>['FACT-2026-0001']);

      final Facture seconde = await factures.creer(vente.id, date: le15Juin);
      final VenteDetail detail = (await ventes.detail(vente.id))!;
      expect(detail.factureEmise?.id, seconde.id);
      expect(detail.factures.map((Facture f) => f.numero), <String>['FACT-2026-0002', 'FACT-2026-0001']);
    });
  });

  group('obtenirPdf', () {
    test('relit le fichier rangé sans refabriquer le PDF', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Facture f = await factures.creer((await uneVente()).id, date: le15Juin);
      expect(documents, hasLength(1));

      final Uint8List octets = await factures.obtenirPdf(f.id);

      expect(utf8.decode(octets), '%PDF-FAUX FACT-2026-0001');
      expect(documents, hasLength(1));
    });

    test('refabrique le PDF s’il n’est plus sur le téléphone', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Facture f = await factures.creer((await uneVente()).id, date: le15Juin);
      await stockage.supprimer(f.pdfChemin!);

      final Uint8List octets = await factures.obtenirPdf(f.id);

      expect(utf8.decode(octets), '%PDF-FAUX FACT-2026-0001');
      expect(documents, hasLength(2));
      expect(await stockage.lire('FACT-2026-0001.pdf'), isNotNull);
    });

    test('cheminPdf donne le fichier à partager', () async {
      await parametres.enregistrerProfil(profilComplet);
      final Facture f = await factures.creer((await uneVente()).id, date: le15Juin);

      final String chemin = await factures.cheminPdf(f.id);

      expect(chemin, endsWith('FACT-2026-0001.pdf'));
      expect(await File(chemin).exists(), isTrue);
    });

    test('une facture inexistante est signalée', () async {
      await expectLater(factures.obtenirPdf(7), throwsA(isA<ElementIntrouvable>()));
    });
  });
}
