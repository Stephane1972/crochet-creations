import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late NumerotationRepository numerotation;

  setUp(() {
    db = creerBaseEnMemoire();
    numerotation = NumerotationRepository(db);
  });
  tearDown(() => db.close());

  final DateTime juin2026 = DateTime(2026, 6, 15);

  group('numérotation des factures', () {
    test('unique et chronologique : FACT-2026-0001, 0002, 0003', () async {
      expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0001');
      expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0002');
      expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0003');
    });

    test('la suite repart à 1 au changement d’année, sans toucher à l’année précédente', () async {
      await numerotation.prochainNumeroFacture(DateTime(2026, 12, 31, 23, 59));
      await numerotation.prochainNumeroFacture(DateTime(2026, 12, 31, 23, 59));

      expect(await numerotation.prochainNumeroFacture(DateTime(2027, 1, 1)), 'FACT-2027-0001');
      expect(await numerotation.prochainNumeroFacture(DateTime(2026, 12, 31)), 'FACT-2026-0003');
    });

    test('les factures, les devis et les produits ont chacun leur suite', () async {
      expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0001');
      expect(await numerotation.prochainNumeroDevis(juin2026), 'DEVIS-2026-0001');
      expect(await numerotation.prochaineReferenceProduit(), 'PRD-0001');
      expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0002');
      expect(await numerotation.prochainNumeroDevis(juin2026), 'DEVIS-2026-0002');
      expect(await numerotation.prochaineReferenceProduit(), 'PRD-0002');
    });

    test('des demandes simultanées ne produisent jamais deux fois le même numéro', () async {
      final List<String> numeros = await Future.wait(
        List<Future<String>>.generate(30, (_) => numerotation.prochainNumeroFacture(juin2026)),
      );
      expect(numeros.toSet(), hasLength(30));
      expect(
        numeros.toSet(),
        List<String>.generate(30, (i) => 'FACT-2026-${(i + 1).toString().padLeft(4, '0')}').toSet(),
      );
    });

    test('si l’enregistrement du document échoue, le numéro n’est pas consommé', () async {
      await expectLater(
        db.transaction(() async {
          expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0001');
          throw StateError('échec de l’enregistrement');
        }),
        throwsStateError,
      );
      // Pas de « trou » : le numéro 0001 est toujours disponible.
      expect(await numerotation.prochainNumeroFacture(juin2026), 'FACT-2026-0001');
    });
  });
}
