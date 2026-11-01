import 'package:crochet_creations/domain/csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('echapperCsv', () {
    test('une cellule simple reste telle quelle (accents compris)', () {
      expect(echapperCsv('Doudou lapin « Noisette »'), 'Doudou lapin « Noisette »');
      expect(echapperCsv(''), '');
      expect(echapperCsv('12,50'), '12,50'); // la virgule n'est pas le séparateur
    });

    test('un point-virgule, un guillemet ou un retour à la ligne protègent la cellule', () {
      expect(echapperCsv('Coton; laine'), '"Coton; laine"');
      expect(echapperCsv('ligne 1\nligne 2'), '"ligne 1\nligne 2"');
      expect(echapperCsv('ligne 1\r\nligne 2'), '"ligne 1\r\nligne 2"');
    });

    test('les guillemets d’une cellule protégée sont doublés', () {
      expect(echapperCsv('Couleurs "pastel"'), '"Couleurs ""pastel"""');
    });
  });

  group('construireCsv', () {
    test('une ligne d’en-têtes puis une ligne par élément, séparées par \\r\\n', () {
      final String csv = construireCsv(
        <String>['Nom', 'Prix (€)'],
        <List<String>>[
          <String>['Doudou', '25,00'],
          <String>['Bonnet; rose', '18,00'],
        ],
      );
      expect(csv, 'Nom;Prix (€)\r\nDoudou;25,00\r\n"Bonnet; rose";18,00\r\n');
    });

    test('sans élément : seulement les en-têtes', () {
      expect(construireCsv(<String>['A', 'B'], <List<String>>[]), 'A;B\r\n');
    });
  });

  group('montantCsv', () {
    test('toujours deux décimales, avec une virgule', () {
      expect(montantCsv(0), '0,00');
      expect(montantCsv(5), '0,05');
      expect(montantCsv(1250), '12,50');
      expect(montantCsv(100000), '1000,00'); // pas d'espace : le tableur doit pouvoir additionner
      expect(montantCsv(8500000), '85000,00');
    });

    test('un montant négatif (remboursement) garde son signe', () {
      expect(montantCsv(-300), '-3,00');
      expect(montantCsv(-5), '-0,05');
    });
  });
}
