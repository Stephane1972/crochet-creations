import 'package:crochet_creations/core/utils/recherche.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normaliserPourRecherche', () {
    test('minuscules et sans accents', () {
      expect(normaliserPourRecherche('Écharpe Été'), 'echarpe ete');
      expect(normaliserPourRecherche('Boucles d’oreilles'), "boucles d'oreilles");
      expect(normaliserPourRecherche('Cœur'), 'coeur');
      expect(normaliserPourRecherche('Façon'), 'facon');
    });

    test('espaces superflus supprimés', () {
      expect(normaliserPourRecherche('  doudou   lapin '), 'doudou lapin');
    });
  });

  group('correspondALaRecherche', () {
    test('une requête vide correspond à tout', () {
      expect(correspondALaRecherche('', <String?>['Doudou']), isTrue);
      expect(correspondALaRecherche('   ', <String?>[]), isTrue);
    });

    test('insensible à la casse et aux accents', () {
      expect(correspondALaRecherche('ECHARPE', <String?>['Écharpe en laine']), isTrue);
      expect(correspondALaRecherche('été', <String?>['echarpe ete']), isTrue);
    });

    test('tous les mots doivent se retrouver, dans n’importe quel champ', () {
      const List<String?> champs = <String?>['Doudou lapin', 'PRD-0003', null, 'coton bio'];
      expect(correspondALaRecherche('lapin coton', champs), isTrue);
      expect(correspondALaRecherche('prd-0003 lapin', champs), isTrue);
      expect(correspondALaRecherche('lapin laine', champs), isFalse);
    });

    test('les champs absents sont ignorés', () {
      expect(correspondALaRecherche('x', <String?>[null, null]), isFalse);
    });
  });
}
