import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ces noms sont écrits dans la base de données (valeurs par défaut et contraintes SQL
/// de `tables.dart`). Si ce test échoue, un nom a été changé : il faut une migration.
void main() {
  test('noms de valeurs cités dans les contraintes SQL', () {
    expect(NatureLigne.bien.name, 'bien');
    expect(NatureLigne.service.name, 'service');
    expect(RemiseType.aucune.name, 'aucune');
    expect(RemiseType.pourcentage.name, 'pourcentage');
    expect(RemiseType.montant.name, 'montant');
    expect(StatutFacture.emise.name, 'emise');
  });

  test('noms de valeurs utilisés par défaut dans les tables', () {
    expect(ModeTheme.systeme.name, 'systeme');
    expect(StatutProduit.disponible.name, 'disponible');
    expect(TypeClient.particulier.name, 'particulier');
    expect(StatutVente.validee.name, 'validee');
    expect(StatutPaiement.impayee.name, 'impayee');
    expect(StatutDevis.brouillon.name, 'brouillon');
    expect(NiveauCours.tousNiveaux.name, 'tousNiveaux');
    expect(StatutCours.planifie.name, 'planifie');
    expect(StatutInscription.confirmee.name, 'confirmee');
  });

  test('chaque valeur a un libellé en français affichable', () {
    for (final CategorieProduit v in CategorieProduit.values) {
      expect(v.libelle, isNotEmpty);
    }
    for (final ModePaiement v in ModePaiement.values) {
      expect(v.libelle, isNotEmpty);
    }
    for (final CategorieDepense v in CategorieDepense.values) {
      expect(v.libelle, isNotEmpty);
    }
  });

  test('les listes de choix reprennent le cahier des charges', () {
    expect(ModePaiement.values.map((v) => v.libelle), <String>[
      'Espèces',
      'Carte',
      'Virement',
      'PayPal',
      'Chèque',
      'Autre',
    ]);
    expect(CategorieProduit.values, hasLength(5));
    expect(CategorieDepense.values, hasLength(8));
    expect(StatutPaiement.values, hasLength(4));
    expect(StatutDevis.values, hasLength(5));
    expect(StatutProduit.values, hasLength(4));
  });
}
