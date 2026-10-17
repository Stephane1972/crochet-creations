import 'package:crochet_creations/domain/calculs/numero_document.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formaterNumero', () {
    test('facture : FACT-AAAA-NNNN', () {
      expect(formaterNumero(TypeCompteur.facture, annee: 2026, numero: 1), 'FACT-2026-0001');
      expect(formaterNumero(TypeCompteur.facture, annee: 2026, numero: 42), 'FACT-2026-0042');
    });

    test('devis : DEVIS-AAAA-NNNN', () {
      expect(formaterNumero(TypeCompteur.devis, annee: 2026, numero: 12), 'DEVIS-2026-0012');
    });

    test('référence produit : PRD-NNNN, sans année', () {
      expect(formaterNumero(TypeCompteur.produit, annee: 0, numero: 7), 'PRD-0007');
    });

    test('au-delà de 9 999 le numéro s’allonge sans se répéter', () {
      expect(formaterNumero(TypeCompteur.facture, annee: 2026, numero: 10000), 'FACT-2026-10000');
    });
  });
}
