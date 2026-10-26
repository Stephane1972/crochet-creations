import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

Panier _avecDoudou([int quantite = 1, int? stock = 5]) => const Panier().ajouter(
  produitId: 1,
  designation: 'Doudou lapin',
  prixUnitaireCentimes: 2500,
  quantite: quantite,
  stockDisponible: stock,
);

void main() {
  group('ajouter', () {
    test('un panier neuf est vide', () {
      const Panier panier = Panier();
      expect(panier.estVide, isTrue);
      expect(panier.nombreArticles, 0);
      expect(panier.totaux.totalCentimes, 0);
    });

    test('ajoute une ligne avec son total', () {
      final Panier panier = _avecDoudou(2);
      expect(panier.lignes, hasLength(1));
      expect(panier.lignes.single.designation, 'Doudou lapin');
      expect(panier.lignes.single.totalCentimes, 5000);
      expect(panier.nombreArticles, 2);
      expect(panier.totaux.totalCentimes, 5000);
    });

    test('le même produit augmente la quantité au lieu de créer une deuxième ligne', () {
      final Panier panier = _avecDoudou().ajouter(
        produitId: 1,
        designation: 'Doudou lapin',
        prixUnitaireCentimes: 2500,
        stockDisponible: 5,
      );
      expect(panier.lignes, hasLength(1));
      expect(panier.lignes.single.quantite, 2);
      expect(panier.quantiteDe(1), 2);
    });

    test('deux variantes du même produit restent deux lignes', () {
      final Panier panier = const Panier()
          .ajouter(produitId: 1, varianteId: 10, designation: 'Bonnet – Rose', prixUnitaireCentimes: 1800)
          .ajouter(produitId: 1, varianteId: 11, designation: 'Bonnet – Vert', prixUnitaireCentimes: 1800);
      expect(panier.lignes, hasLength(2));
      expect(panier.quantiteDe(1, varianteId: 10), 1);
      expect(panier.quantiteDe(1, varianteId: 11), 1);
      expect(panier.quantiteDe(1), 0);
    });

    test('les prestations libres ne sont jamais regroupées', () {
      final Panier panier = const Panier()
          .ajouter(designation: 'Retouche', nature: NatureLigne.service, prixUnitaireCentimes: 1000)
          .ajouter(designation: 'Retouche', nature: NatureLigne.service, prixUnitaireCentimes: 1000);
      expect(panier.lignes, hasLength(2));
      expect(panier.lignes.every((LignePanier l) => l.nature == NatureLigne.service), isTrue);
    });

    test('chaque ligne reçoit un identifiant différent', () {
      final Panier panier = const Panier()
          .ajouter(designation: 'A', prixUnitaireCentimes: 100)
          .ajouter(designation: 'B', prixUnitaireCentimes: 100);
      expect(panier.lignes.map((LignePanier l) => l.idLigne).toSet(), hasLength(2));
    });

    test('refuse un nom vide, une quantité nulle et un prix négatif', () {
      expect(
        () => const Panier().ajouter(designation: '  ', prixUnitaireCentimes: 100),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(
        () => const Panier().ajouter(designation: 'A', prixUnitaireCentimes: 100, quantite: 0),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(
        () => const Panier().ajouter(designation: 'A', prixUnitaireCentimes: -1),
        throwsA(isA<DonneeInvalide>()),
      );
    });

    test('un produit du catalogue est toujours un objet, une variante a besoin d’un produit', () {
      expect(
        () => const Panier().ajouter(
          produitId: 1,
          designation: 'A',
          nature: NatureLigne.service,
          prixUnitaireCentimes: 100,
        ),
        throwsA(isA<DonneeInvalide>()),
      );
      expect(
        () => const Panier().ajouter(varianteId: 3, designation: 'A', prixUnitaireCentimes: 100),
        throwsA(isA<DonneeInvalide>()),
      );
    });
  });

  group('stock', () {
    test('on ne peut pas dépasser le stock disponible', () {
      expect(
        () => _avecDoudou(6, 5),
        throwsA(
          isA<StockInsuffisant>()
              .having((StockInsuffisant e) => e.disponible, 'disponible', 5)
              .having((StockInsuffisant e) => e.demande, 'demande', 6),
        ),
      );
    });

    test('ajouter encore au-delà du stock est refusé et le panier ne change pas', () {
      final Panier panier = _avecDoudou(5, 5);
      expect(
        () => panier.ajouter(
          produitId: 1,
          designation: 'Doudou lapin',
          prixUnitaireCentimes: 2500,
          stockDisponible: 5,
        ),
        throwsA(isA<StockInsuffisant>()),
      );
      expect(panier.quantiteDe(1), 5);
    });

    test('sans limite de stock (produit sur commande), toute quantité est acceptée', () {
      final Panier panier = _avecDoudou(40, null);
      expect(panier.quantiteDe(1), 40);
    });

    test('un stock à jour remplace l’ancien lors d’un nouvel ajout', () {
      // Le stock est passé de 5 à 2 entre-temps : le plafond suit.
      final Panier panier = _avecDoudou(1, 5);
      expect(
        () => panier.ajouter(
          produitId: 1,
          designation: 'Doudou lapin',
          prixUnitaireCentimes: 2500,
          quantite: 2,
          stockDisponible: 2,
        ),
        throwsA(isA<StockInsuffisant>()),
      );
    });

    test('un stock à zéro interdit la vente', () {
      expect(() => _avecDoudou(1, 0), throwsA(isA<StockInsuffisant>()));
    });
  });

  group('quantité et retrait', () {
    test('avecQuantite change la quantité d’une ligne', () {
      final Panier panier = _avecDoudou();
      final Panier apres = panier.avecQuantite(panier.lignes.single.idLigne, 3);
      expect(apres.lignes.single.quantite, 3);
      expect(apres.totaux.totalCentimes, 7500);
    });

    test('avecQuantite respecte le stock et refuse moins de 1', () {
      final Panier panier = _avecDoudou(1, 3);
      final int id = panier.lignes.single.idLigne;
      expect(() => panier.avecQuantite(id, 4), throwsA(isA<StockInsuffisant>()));
      expect(() => panier.avecQuantite(id, 0), throwsA(isA<DonneeInvalide>()));
      expect(() => panier.avecQuantite(999, 1), throwsA(isA<DonneeInvalide>()));
    });

    test('sans retire la ligne', () {
      final Panier panier = _avecDoudou();
      expect(panier.sans(panier.lignes.single.idLigne).estVide, isTrue);
      expect(panier.sans(999).lignes, hasLength(1));
    });
  });

  group('remise et frais de port', () {
    test('remise en pourcentage et frais de port non remisés', () {
      final Panier panier = _avecDoudou(2).avecRemise(RemiseType.pourcentage, 1000).avecFraisPort(450);
      expect(panier.totaux.sousTotalCentimes, 5000);
      expect(panier.totaux.remiseCentimes, 500);
      expect(panier.totaux.fraisPortCentimes, 450);
      expect(panier.totaux.totalCentimes, 4950);
    });

    test('remise en montant', () {
      final Panier panier = _avecDoudou(2).avecRemise(RemiseType.montant, 300);
      expect(panier.totaux.totalCentimes, 4700);
    });

    test('« aucune » remet la valeur à zéro', () {
      final Panier panier = _avecDoudou().avecRemise(RemiseType.montant, 300).avecRemise(RemiseType.aucune, 300);
      expect(panier.remiseValeur, 0);
      expect(panier.totaux.remiseCentimes, 0);
    });

    test('une remise devenue trop grande après un retrait est signalée, sans casser le panier', () {
      final Panier panier = const Panier()
          .ajouter(designation: 'A', prixUnitaireCentimes: 1000)
          .ajouter(designation: 'B', prixUnitaireCentimes: 1000)
          .avecRemise(RemiseType.montant, 1500);
      expect(panier.problemeRemise, isNull);

      final Panier apres = panier.sans(panier.lignes.first.idLigne);
      expect(apres.problemeRemise, isNotNull);
      expect(() => apres.totaux, throwsA(isA<RemiseInvalide>()));
    });

    test('refuse des frais de port négatifs', () {
      expect(() => const Panier().avecFraisPort(-1), throwsA(isA<DonneeInvalide>()));
    });

    test('la remise et les frais survivent à l’ajout d’articles', () {
      final Panier panier = const Panier()
          .avecRemise(RemiseType.pourcentage, 500)
          .avecFraisPort(300)
          .ajouter(designation: 'A', prixUnitaireCentimes: 2000);
      expect(panier.remiseType, RemiseType.pourcentage);
      expect(panier.remiseValeur, 500);
      expect(panier.fraisPortCentimes, 300);
      expect(panier.totaux.totalCentimes, 2000 - 100 + 300);
    });
  });

  group('avecLigneModifiee', () {
    Panier deuxLignes() => const Panier()
        .ajouter(designation: 'Bonnet', prixUnitaireCentimes: 2000, quantite: 2)
        .ajouter(designation: 'Écharpe', prixUnitaireCentimes: 3500);

    test('remplace le contenu de la ligne, à la même place et avec le même identifiant', () {
      final Panier panier = deuxLignes();
      final int id = panier.lignes.first.idLigne;

      final Panier modifie = panier.avecLigneModifiee(
        id,
        designation: '  Bonnet « Hiver »  ',
        description: '  Laine mérinos  ',
        nature: NatureLigne.service,
        prixUnitaireCentimes: 2400,
        quantite: 3,
      );

      expect(modifie.lignes.map((LignePanier l) => l.idLigne), panier.lignes.map((LignePanier l) => l.idLigne));
      expect(modifie.lignes.first.designation, 'Bonnet « Hiver »');
      expect(modifie.lignes.first.description, 'Laine mérinos');
      expect(modifie.lignes.first.nature, NatureLigne.service);
      expect(modifie.lignes.first.totalCentimes, 7200);
      expect(modifie.lignes.last.designation, 'Écharpe');
      expect(modifie.totaux.sousTotalCentimes, 7200 + 3500);
    });

    test('la remise et les frais de port sont conservés', () {
      final Panier panier = deuxLignes().avecRemise(RemiseType.montant, 500).avecFraisPort(300);
      final Panier modifie = panier.avecLigneModifiee(
        panier.lignes.first.idLigne,
        designation: 'Bonnet',
        nature: NatureLigne.bien,
        prixUnitaireCentimes: 1000,
        quantite: 1,
      );
      expect(modifie.remiseType, RemiseType.montant);
      expect(modifie.remiseValeur, 500);
      expect(modifie.fraisPortCentimes, 300);
    });

    test('une description vide est retirée', () {
      final Panier panier = deuxLignes();
      final Panier modifie = panier.avecLigneModifiee(
        panier.lignes.first.idLigne,
        designation: 'Bonnet',
        description: '   ',
        nature: NatureLigne.bien,
        prixUnitaireCentimes: 1000,
        quantite: 1,
      );
      expect(modifie.lignes.first.description, isNull);
    });

    test('refuse un nom vide, une quantité nulle, un prix négatif ou une ligne absente', () {
      final Panier panier = deuxLignes();
      final int id = panier.lignes.first.idLigne;
      Panier essai({String nom = 'A', int prix = 100, int quantite = 1, int? ligne}) => panier.avecLigneModifiee(
        ligne ?? id,
        designation: nom,
        nature: NatureLigne.bien,
        prixUnitaireCentimes: prix,
        quantite: quantite,
      );
      expect(() => essai(nom: '  '), throwsA(isA<DonneeInvalide>()));
      expect(() => essai(quantite: 0), throwsA(isA<DonneeInvalide>()));
      expect(() => essai(prix: -1), throwsA(isA<DonneeInvalide>()));
      expect(() => essai(ligne: 999), throwsA(isA<DonneeInvalide>()));
    });

    test('ne modifie pas un produit du catalogue', () {
      final Panier panier = _avecDoudou();
      expect(
        () => panier.avecLigneModifiee(
          panier.lignes.single.idLigne,
          designation: 'Autre',
          nature: NatureLigne.bien,
          prixUnitaireCentimes: 100,
          quantite: 1,
        ),
        throwsA(isA<DonneeInvalide>()),
      );
    });
  });

  group('PaiementSaisi', () {
    test('accepte un montant entre 1 centime et le total', () {
      const PaiementSaisi(mode: ModePaiement.carte, montantCentimes: 1).verifier(5000);
      const PaiementSaisi(mode: ModePaiement.carte, montantCentimes: 5000).verifier(5000);
    });

    test('refuse un montant nul, négatif ou supérieur au total', () {
      for (final int montant in <int>[0, -100, 5001]) {
        expect(
          () => PaiementSaisi(mode: ModePaiement.especes, montantCentimes: montant).verifier(5000),
          throwsA(isA<DonneeInvalide>()),
          reason: '$montant',
        );
      }
    });
  });
}
