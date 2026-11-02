import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/usage_historique.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un élément : singulier dès 1, pluriel dès 2', () {
    expect(const ElementUsage(1, 'facture', 'factures').texte, '1 facture');
    expect(const ElementUsage(2, 'facture', 'factures').texte, '2 factures');
    expect(const ElementUsage(3, 'devis', 'devis').texte, '3 devis');
  });

  test('un client ou un produit sans historique n’est pas « utilisé »', () {
    final UsageHistorique usage = UsageHistorique(const <ElementUsage>[
      ElementUsage(0, 'vente', 'ventes'),
      ElementUsage(0, 'devis', 'devis'),
    ]);
    expect(usage.estUtilise, isFalse);
    expect(usage.elements, isEmpty);
    expect(usage.enumeration, '');
  });

  test('l’énumération passe sous silence ce qui est à zéro', () {
    expect(
      UsageHistorique(const <ElementUsage>[
        ElementUsage(3, 'vente', 'ventes'),
        ElementUsage(0, 'facture', 'factures'),
      ]).enumeration,
      '3 ventes',
    );
    expect(
      UsageHistorique(const <ElementUsage>[
        ElementUsage(1, 'vente', 'ventes'),
        ElementUsage(2, 'facture', 'factures'),
      ]).enumeration,
      '1 vente et 2 factures',
    );
    final UsageHistorique complet = UsageHistorique(const <ElementUsage>[
      ElementUsage(3, 'vente', 'ventes'),
      ElementUsage(1, 'facture', 'factures'),
      ElementUsage(2, 'devis', 'devis'),
      ElementUsage(1, 'inscription à un cours', 'inscriptions à des cours'),
    ]);
    expect(complet.estUtilise, isTrue);
    expect(complet.enumeration, '3 ventes, 1 facture, 2 devis et 1 inscription à un cours');
  });

  test('« suppression impossible » explique où le client apparaît et propose d’archiver', () {
    final SuppressionImpossible erreur = SuppressionImpossible(
      cible: 'client',
      usage: UsageHistorique(const <ElementUsage>[ElementUsage(2, 'inscription à un cours', 'inscriptions à des cours')]),
    );
    expect(
      erreur.message,
      'Ce client ne peut pas être supprimé : il apparaît dans 2 inscriptions à des cours. '
      'Archivez-le plutôt : il disparaît des listes, mais l’historique est conservé.',
    );
    expect(erreur, isA<ErreurMetier>());
  });
}
