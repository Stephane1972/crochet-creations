import 'dart:typed_data';

import 'package:crochet_creations/data/pdf/devis_pdf.dart';
import 'package:crochet_creations/data/pdf/ressources_pdf.dart';
import 'package:crochet_creations/domain/document_devis.dart';
import 'package:crochet_creations/domain/document_facture.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_pdf.dart';

DocumentDevis _devis({
  int nombreDeLignes = 2,
  bool complet = true,
  String numero = 'DEVIS-2026-0001',
}) {
  final List<LigneDocument> lignes = <LigneDocument>[
    for (int i = 1; i <= nombreDeLignes; i++)
      LigneDocument(
        designation: i == 1 ? 'Couverture bébé sur mesure' : 'Doudou assorti n° $i',
        description: i.isOdd ? 'Coton bio, rose poudré et écru, 80 × 100 cm — lavable en machine à 30 °C' : null,
        quantite: i % 3 + 1,
        prixUnitaireCentimes: 2400 + i * 100,
        totalCentimes: (i % 3 + 1) * (2400 + i * 100),
      ),
  ];
  final int sousTotal = lignes.fold(0, (int s, LigneDocument l) => s + l.totalCentimes);
  final int remise = complet ? sousTotal ~/ 10 : 0;
  final int port = complet ? 490 : 0;
  final int total = sousTotal - remise + port;
  return DocumentDevis(
    numero: numero,
    dateEmission: DateTime(2026, 6, 15),
    dateValidite: complet ? DateTime(2026, 7, 15) : null,
    delaiRealisation: complet ? '3 semaines à partir de l’acceptation' : null,
    acompteCentimes: complet ? total ~/ 3 : 0,
    emetteur: emetteurDeTest,
    client: complet
        ? const DestinataireDocument(
            nom: 'Léa Bernard',
            adresse: <String>['3 place du Marché', '34000 Montpellier'],
          )
        : const DestinataireDocument(),
    lignes: lignes,
    sousTotalCentimes: sousTotal,
    remiseCentimes: remise,
    libelleRemise: libelleRemiseDocument(RemiseType.pourcentage, 1000),
    fraisPortCentimes: port,
    totalCentimes: total,
    mentionTva: 'TVA non applicable, article 293 B du CGI',
    iban: complet ? 'FR14 2004 1010 0505 0001 3M02 606' : null,
  );
}

void main() {
  late RessourcesPdf ressources;

  setUpAll(() => ressources = ressourcesPdfDeTest());

  group('genererDevisPdf', () {
    test('fabrique un PDF valide d’une page pour un devis complet', () async {
      final Uint8List pdf = await genererDevisPdf(_devis(), ressources);
      ecrireExemplePdf('devis-complet', pdf);

      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(String.fromCharCodes(pdf.sublist(pdf.length - 6)).trim(), endsWith('%%EOF'));
      expect(pdf.length, greaterThan(10000));
      expect(nombreDePages(pdf), 1);
    });

    test('un devis minimal : sans client, validité, délai ni acompte', () async {
      final Uint8List pdf = await genererDevisPdf(
        _devis(nombreDeLignes: 1, complet: false, numero: 'DEVIS-2026-0002'),
        ressources,
      );
      ecrireExemplePdf('devis-simple', pdf);

      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(nombreDePages(pdf), 1);
    });

    test('un devis long continue sur plusieurs pages, avec ses conditions et son bon pour accord', () async {
      final Uint8List pdf = await genererDevisPdf(
        _devis(nombreDeLignes: 45, numero: 'DEVIS-2026-0003'),
        ressources,
      );
      ecrireExemplePdf('devis-long', pdf);

      expect(nombreDePages(pdf), greaterThan(1));
    });
  });
}
