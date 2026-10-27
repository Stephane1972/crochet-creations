import 'dart:typed_data';

import 'package:crochet_creations/data/pdf/facture_pdf.dart';
import 'package:crochet_creations/data/pdf/ressources_pdf.dart';
import 'package:crochet_creations/domain/document_facture.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_pdf.dart';

DocumentFacture _facture({
  int nombreDeLignes = 2,
  bool complete = true,
  String numero = 'FACT-2026-0001',
}) {
  final List<LigneDocument> lignes = <LigneDocument>[
    for (int i = 1; i <= nombreDeLignes; i++)
      LigneDocument(
        designation: i == 1 ? 'Doudou lapin « Noisette »' : 'Boucles d’oreilles fleur n° $i',
        description: i.isOdd ? 'Coton bio, beige, 25 cm — lavable en machine à 30 °C' : null,
        quantite: i % 3 + 1,
        prixUnitaireCentimes: 1800 + i * 50,
        totalCentimes: (i % 3 + 1) * (1800 + i * 50),
      ),
  ];
  final int sousTotal = lignes.fold(0, (int s, LigneDocument l) => s + l.totalCentimes);
  final int remise = complete ? sousTotal ~/ 10 : 0;
  final int port = complete ? 490 : 0;
  return DocumentFacture(
    numero: numero,
    dateEmission: DateTime(2026, 6, 15),
    dateVentePrestation: DateTime(2026, 6, 10),
    emetteur: emetteurDeTest,
    client: complete
        ? const DestinataireDocument(
            nom: 'Atelier Soleil',
            adresse: <String>['3 place du Marché', '34000 Montpellier'],
            siret: '98765432100012',
          )
        : const DestinataireDocument(),
    lignes: lignes,
    sousTotalCentimes: sousTotal,
    remiseCentimes: remise,
    libelleRemise: libelleRemiseDocument(RemiseType.pourcentage, 1000),
    fraisPortCentimes: port,
    totalCentimes: sousTotal - remise + port,
    mentionTva: 'TVA non applicable, article 293 B du CGI',
    conditionsPaiement: complete ? 'Paiement sous 15 jours.' : null,
    iban: complete ? 'FR14 2004 1010 0505 0001 3M02 606' : null,
    messageRemerciement: complete ? 'Merci pour votre confiance !' : null,
  );
}

void main() {
  late RessourcesPdf ressources;

  setUpAll(() => ressources = ressourcesPdfDeTest());

  group('genererFacturePdf', () {
    test('fabrique un PDF valide d’une page pour une facture courte', () async {
      final Uint8List pdf = await genererFacturePdf(_facture(), ressources);

      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(String.fromCharCodes(pdf.sublist(pdf.length - 6)).trim(), endsWith('%%EOF'));
      expect(pdf.length, greaterThan(10000));
      expect(nombreDePages(pdf), 1);
      ecrireExemplePdf('facture-complete', pdf);
    });

    test('une facture de passage, sans remise, frais de port, IBAN ni remerciement', () async {
      final Uint8List pdf = await genererFacturePdf(
        _facture(nombreDeLignes: 1, complete: false, numero: 'FACT-2026-0002'),
        ressources,
      );

      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(nombreDePages(pdf), 1);
      ecrireExemplePdf('facture-simple', pdf);
    });

    test('une facture longue continue sur plusieurs pages', () async {
      final Uint8List pdf = await genererFacturePdf(
        _facture(nombreDeLignes: 45, numero: 'FACT-2026-0003'),
        ressources,
      );

      expect(nombreDePages(pdf), greaterThan(1));
      ecrireExemplePdf('facture-longue', pdf);
    });
  });
}
