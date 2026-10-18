import 'package:crochet_creations/domain/calculs/statut_paiement.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StatutPaiement statut(int total, List<int> paiements) =>
      calculerStatutPaiement(totalCentimes: total, montantsPaiements: paiements);

  group('calculerStatutPaiement', () {
    test('aucun paiement : impayée', () {
      expect(statut(5000, const <int>[]), StatutPaiement.impayee);
    });

    test('paiement partiel : partiellement payée', () {
      expect(statut(5000, const <int>[2000]), StatutPaiement.partiellementPayee);
      expect(statut(5000, const <int>[2000, 1000]), StatutPaiement.partiellementPayee);
    });

    test('total atteint ou dépassé : payée', () {
      expect(statut(5000, const <int>[5000]), StatutPaiement.payee);
      expect(statut(5000, const <int>[3000, 2000]), StatutPaiement.payee);
      expect(statut(5000, const <int>[6000]), StatutPaiement.payee);
    });

    test('une vente à 0 € est considérée comme payée', () {
      expect(statut(0, const <int>[]), StatutPaiement.payee);
    });

    test('encaissé puis intégralement remboursé : remboursée', () {
      expect(statut(5000, const <int>[5000, -5000]), StatutPaiement.remboursee);
    });

    test('remboursement partiel : le reste encaissé décide du statut', () {
      expect(statut(5000, const <int>[5000, -2000]), StatutPaiement.partiellementPayee);
    });
  });
}
