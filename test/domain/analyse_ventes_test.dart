import 'package:crochet_creations/domain/calculs/analyse_ventes.dart';
import 'package:crochet_creations/domain/calculs/statistiques.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LigneCompta objet({
    int total = 5000,
    int cout = 0,
    String categorie = CleCategorie.doudou,
    int produitId = 1,
  }) => LigneCompta(
    nature: NatureLigne.bien,
    designation: 'Article',
    quantite: 1,
    totalCentimes: total,
    coutUnitaireCentimes: cout,
    produitId: produitId,
    categorie: categorie,
  );

  LigneCompta cours({int total = 4500}) => LigneCompta(
    nature: NatureLigne.service,
    designation: 'Cours : Initiation',
    quantite: 1,
    totalCentimes: total,
    coursId: 7,
  );

  PaiementCompta paiement(DateTime date, int montant) => PaiementCompta(date: date, montantCentimes: montant);

  VenteCompta vente({
    required DateTime date,
    required List<LigneCompta> lignes,
    required List<PaiementCompta> paiements,
    int? lieuId,
    int remise = 0,
    int port = 0,
    bool annulee = false,
  }) => VenteCompta(
    date: date,
    annulee: annulee,
    lignes: lignes,
    paiements: paiements,
    remiseCentimes: remise,
    fraisPortCentimes: port,
    lieuId: lieuId,
  );

  // Les lieux : 1 = Marché, 2 = Salon, sans lieu = « Non renseigné ».
  // Quatre ventes, un remboursement.
  final DateTime le5Oct = DateTime(2026, 10, 5, 10);
  final DateTime le12Oct = DateTime(2026, 10, 12, 15);
  final DateTime le3Nov = DateTime(2026, 11, 3, 9);
  final DateTime le20Nov = DateTime(2026, 11, 20, 18);
  final DateTime le15Mars2025 = DateTime(2025, 3, 15, 11);

  final List<VenteCompta> ventes = <VenteCompta>[
    // Marché : un doudou à 50 € (matière 10 €), payé le 5 octobre, puis 10 € remboursés le 20 novembre.
    vente(
      date: le5Oct,
      lieuId: 1,
      lignes: <LigneCompta>[objet(total: 5000, cout: 1000)],
      paiements: <PaiementCompta>[paiement(le5Oct, 5000), paiement(le20Nov, -1000)],
    ),
    // Salon : un article de crochet à 30 € (matière 5 €).
    vente(
      date: le12Oct,
      lieuId: 2,
      lignes: <LigneCompta>[objet(total: 3000, cout: 500, categorie: CleCategorie.crochet, produitId: 2)],
      paiements: <PaiementCompta>[paiement(le12Oct, 3000)],
    ),
    // Sans lieu : un doudou à 25 € (matière 6 €).
    vente(
      date: le3Nov,
      lignes: <LigneCompta>[objet(total: 2500, cout: 600)],
      paiements: <PaiementCompta>[paiement(le3Nov, 2500)],
    ),
    // L'an dernier, au Marché : un article de crochet à 40 € (matière 10 €).
    vente(
      date: le15Mars2025,
      lieuId: 1,
      lignes: <LigneCompta>[objet(total: 4000, cout: 1000, categorie: CleCategorie.crochet, produitId: 2)],
      paiements: <PaiementCompta>[paiement(le15Mars2025, 4000)],
    ),
  ];

  List<int> encaisses(AnalyseVentes a) => <int>[for (final LigneAnalyse l in a.lignes) l.encaisseCentimes];
  List<int> couts(AnalyseVentes a) => <int>[for (final LigneAnalyse l in a.lignes) l.coutCentimes];

  group('choix d’un filtre', () {
    test('« tous » accepte tout, « valeur » n’accepte qu’elle, « sans » n’accepte que le vide', () {
      const ChoixFiltre<int> tous = ChoixFiltre<int>.tous();
      const ChoixFiltre<int> un = ChoixFiltre<int>.valeur(1);
      const ChoixFiltre<int> sans = ChoixFiltre<int>.sans();
      expect(<bool>[tous.accepte(1), tous.accepte(null)], <bool>[true, true]);
      expect(<bool>[un.accepte(1), un.accepte(2), un.accepte(null)], <bool>[true, false, false]);
      expect(<bool>[sans.accepte(null), sans.accepte(1)], <bool>[true, false]);
    });

    test('deux choix identiques sont égaux (nécessaire pour une liste déroulante)', () {
      expect(const ChoixFiltre<int>.tous(), const ChoixFiltre<int>.tous());
      expect(const ChoixFiltre<int>.valeur(3), const ChoixFiltre<int>.valeur(3));
      expect(const ChoixFiltre<int>.tous() == const ChoixFiltre<int>.sans(), isFalse);
      expect(const ChoixFiltre<int>.sans() == const ChoixFiltre<int>.valeur(3), isFalse);
      expect(const ChoixFiltre<String>.valeur('a').hashCode, const ChoixFiltre<String>.valeur('a').hashCode);
    });

    test('le filtre de date croise année et mois', () {
      expect(const FiltreAnalyse().accepteDate(DateTime(2020, 5, 5)), isTrue);
      expect(const FiltreAnalyse(annee: 2026).accepteDate(DateTime(2026, 5, 5)), isTrue);
      expect(const FiltreAnalyse(annee: 2026).accepteDate(DateTime(2025, 5, 5)), isFalse);
      expect(const FiltreAnalyse(mois: 5).accepteDate(DateTime(2020, 5, 5)), isTrue);
      expect(const FiltreAnalyse(mois: 5).accepteDate(DateTime(2020, 6, 5)), isFalse);
      expect(const FiltreAnalyse(annee: 2026, mois: 5).accepteDate(DateTime(2025, 5, 5)), isFalse);
    });
  });

  test('anneesAvecEncaissements : les années où de l’argent a bougé, de la plus récente à la plus ancienne', () {
    expect(anneesAvecEncaissements(ventes), <int>[2026, 2025]);
    expect(anneesAvecEncaissements(const <VenteCompta>[]), isEmpty);
    // Un paiement de 0 € ne compte pas, et la date de la vente n'y change rien.
    final VenteCompta sansArgent = vente(
      date: DateTime(2020, 1, 1),
      lignes: <LigneCompta>[objet()],
      paiements: <PaiementCompta>[paiement(DateTime(2021, 1, 1), 0)],
    );
    expect(anneesAvecEncaissements(<VenteCompta>[sansArgent]), isEmpty);
  });

  group('par lieu', () {
    test('toutes années : du plus rentable au moins rentable, remboursements déduits', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.lieu,
        ordreLieux: <int>[1, 2],
      );
      expect(a.lignes.map((LigneAnalyse l) => l.lieuId), <int?>[1, 2, null]);
      // Marché : 50 € − 10 € + 40 € ; matière : 8 € (4 000 sur 5 000) + 10 €.
      expect(encaisses(a), <int>[8000, 3000, 2500]);
      expect(couts(a), <int>[1800, 500, 600]);
      expect(a.lignes.first.margeCentimes, 6200);
      expect(a.encaisseTotalCentimes, 13500);
      expect(a.coutTotalCentimes, 2900);
      expect(a.margeTotalCentimes, 10600);
      expect(a.vide, isFalse);
    });

    test('limité à une année', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.lieu,
        filtre: const FiltreAnalyse(annee: 2026),
        ordreLieux: <int>[1, 2],
      );
      expect(a.lignes.map((LigneAnalyse l) => l.lieuId), <int?>[1, 2, null]);
      expect(encaisses(a), <int>[4000, 3000, 2500]);
      expect(couts(a), <int>[800, 500, 600]);
    });

    test('à montant égal, l’ordre habituel des lieux est conservé ; « Non renseigné » passe en dernier', () {
      final List<VenteCompta> egales = <VenteCompta>[
        vente(
          date: le5Oct,
          lignes: <LigneCompta>[objet(total: 1000)],
          paiements: <PaiementCompta>[paiement(le5Oct, 1000)],
        ),
        vente(
          date: le5Oct,
          lieuId: 1,
          lignes: <LigneCompta>[objet(total: 1000)],
          paiements: <PaiementCompta>[paiement(le5Oct, 1000)],
        ),
        vente(
          date: le5Oct,
          lieuId: 2,
          lignes: <LigneCompta>[objet(total: 1000)],
          paiements: <PaiementCompta>[paiement(le5Oct, 1000)],
        ),
        vente(
          date: le5Oct,
          lieuId: 9,
          lignes: <LigneCompta>[objet(total: 1000)],
          paiements: <PaiementCompta>[paiement(le5Oct, 1000)],
        ),
      ];
      final AnalyseVentes a = calculerAnalyse(
        ventes: egales,
        dimension: DimensionAnalyse.lieu,
        ordreLieux: <int>[2, 1],
      );
      // 2 et 1 selon l'ordre habituel, puis le lieu inconnu (9), puis « Non renseigné ».
      expect(a.lignes.map((LigneAnalyse l) => l.lieuId), <int?>[2, 1, 9, null]);
    });

    test('le filtre « Non renseigné » ne garde que les ventes sans lieu', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.lieu,
        filtre: const FiltreAnalyse(lieu: ChoixFiltre<int>.sans()),
      );
      expect(a.lignes.map((LigneAnalyse l) => l.lieuId), <int?>[null]);
      expect(encaisses(a), <int>[2500]);
    });

    test('un lieu sans aucun argent n’apparaît pas', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.lieu,
        filtre: const FiltreAnalyse(annee: 2025),
        ordreLieux: <int>[1, 2],
      );
      expect(a.lignes.map((LigneAnalyse l) => l.lieuId), <int?>[1]);
    });
  });

  group('par catégorie', () {
    test('une année : l’argent et la matière de chaque catégorie', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.categorie,
        filtre: const FiltreAnalyse(annee: 2026),
        ordreCategories: <String>[CleCategorie.doudou, CleCategorie.crochet],
      );
      expect(a.lignes.map((LigneAnalyse l) => l.categorie), <String?>[CleCategorie.doudou, CleCategorie.crochet]);
      // Doudous : 40 € (50 € − 10 €) + 25 € ; matière 8 € + 6 €.
      expect(encaisses(a), <int>[6500, 3000]);
      expect(couts(a), <int>[1400, 500]);
    });

    test('lignes libres, cours et frais de port forment « sans catégorie »', () {
      final VenteCompta melangee = vente(
        date: le5Oct,
        lignes: <LigneCompta>[
          objet(total: 4000, cout: 800),
          cours(total: 1000),
          const LigneCompta(
            nature: NatureLigne.service,
            designation: 'Retouche',
            quantite: 1,
            totalCentimes: 1000,
          ),
        ],
        port: 500,
        paiements: <PaiementCompta>[paiement(le5Oct, 6500)],
      );
      final AnalyseVentes a = calculerAnalyse(ventes: <VenteCompta>[melangee], dimension: DimensionAnalyse.categorie);
      expect(a.lignes.map((LigneAnalyse l) => l.categorie), <String?>[CleCategorie.doudou, null]);
      expect(encaisses(a), <int>[4000, 2500]);
      expect(couts(a), <int>[800, 0]);
      expect(a.encaisseTotalCentimes, 6500);

      final AnalyseVentes sans = calculerAnalyse(
        ventes: <VenteCompta>[melangee],
        dimension: DimensionAnalyse.lieu,
        filtre: const FiltreAnalyse(categorie: ChoixFiltre<String>.sans()),
      );
      expect(encaisses(sans), <int>[2500]);
    });

    test('la remise est répartie entre les lignes avant de classer par catégorie', () {
      final VenteCompta remisee = vente(
        date: le5Oct,
        lignes: <LigneCompta>[
          objet(total: 3000),
          objet(total: 1000, categorie: CleCategorie.crochet, produitId: 2),
        ],
        remise: 400,
        paiements: <PaiementCompta>[paiement(le5Oct, 3600)],
      );
      final AnalyseVentes a = calculerAnalyse(ventes: <VenteCompta>[remisee], dimension: DimensionAnalyse.categorie);
      // 3 000 − 300 = 2 700 et 1 000 − 100 = 900.
      expect(encaisses(a), <int>[2700, 900]);
      expect(a.encaisseTotalCentimes, 3600);
    });

    test('une catégorie supprimée passe après celles de la liste, puis « sans catégorie »', () {
      final List<VenteCompta> egales = <VenteCompta>[
        for (final String cle in <String>['zzz', 'aaa', CleCategorie.crochet])
          vente(
            date: le5Oct,
            lignes: <LigneCompta>[objet(total: 1000, categorie: cle)],
            paiements: <PaiementCompta>[paiement(le5Oct, 1000)],
          ),
        vente(
          date: le5Oct,
          lignes: const <LigneCompta>[
            LigneCompta(nature: NatureLigne.bien, designation: 'Libre', quantite: 1, totalCentimes: 1000),
          ],
          paiements: <PaiementCompta>[paiement(le5Oct, 1000)],
        ),
      ];
      final AnalyseVentes a = calculerAnalyse(
        ventes: egales,
        dimension: DimensionAnalyse.categorie,
        ordreCategories: <String>[CleCategorie.crochet],
      );
      expect(a.lignes.map((LigneAnalyse l) => l.categorie), <String?>[CleCategorie.crochet, 'aaa', 'zzz', null]);
    });

    test('le filtre garde une seule catégorie, croisée avec le lieu', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.lieu,
        filtre: const FiltreAnalyse(categorie: ChoixFiltre<String>.valeur(CleCategorie.crochet)),
        ordreLieux: <int>[1, 2],
      );
      // Crochet : 40 € au Marché (l'an dernier), 30 € au Salon.
      expect(a.lignes.map((LigneAnalyse l) => l.lieuId), <int?>[1, 2]);
      expect(encaisses(a), <int>[4000, 3000]);
    });

    test('partager un petit paiement entre trois catégories ne perd aucun centime', () {
      final VenteCompta trois = vente(
        date: le5Oct,
        lignes: <LigneCompta>[
          objet(total: 1000, categorie: 'a'),
          objet(total: 1000, categorie: 'b'),
          objet(total: 1000, categorie: 'c'),
        ],
        paiements: <PaiementCompta>[paiement(le5Oct, 100)],
      );
      final AnalyseVentes a = calculerAnalyse(ventes: <VenteCompta>[trois], dimension: DimensionAnalyse.categorie);
      expect(a.encaisseTotalCentimes, 100);
      expect(encaisses(a)..sort(), <int>[33, 33, 34]);
    });
  });

  group('par mois', () {
    test('avec une année : les douze mois, dans l’ordre, les mois vides à zéro', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(annee: 2026),
      );
      expect(a.lignes, hasLength(12));
      expect(a.lignes.map((LigneAnalyse l) => l.mois), <int?>[for (int m = 1; m <= 12; m++) m]);
      expect(a.lignes.every((LigneAnalyse l) => l.annee == 2026), isTrue);
      // Octobre : 50 € + 30 € ; novembre : 25 € − 10 € remboursés.
      expect(a.lignes[9].encaisseCentimes, 8000);
      expect(a.lignes[9].coutCentimes, 1500);
      expect(a.lignes[10].encaisseCentimes, 1500);
      expect(a.lignes[10].coutCentimes, 400);
      expect(a.lignes.where((LigneAnalyse l) => l.encaisseCentimes == 0), hasLength(10));
      expect(a.encaisseTotalCentimes, 9500);
    });

    test('sans année : du premier au dernier mois qui a de l’argent, les mois du milieu à zéro', () {
      final AnalyseVentes a = calculerAnalyse(ventes: ventes, dimension: DimensionAnalyse.mois);
      // De mars 2025 à novembre 2026 : 10 + 11 mois.
      expect(a.lignes, hasLength(21));
      expect((a.lignes.first.annee, a.lignes.first.mois), (2025, 3));
      expect((a.lignes.last.annee, a.lignes.last.mois), (2026, 11));
      expect(a.lignes.first.encaisseCentimes, 4000);
      expect(a.encaisseTotalCentimes, 13500);
    });

    test('un mois choisi : ce mois-là de chaque année, même quand une année n’a rien', () {
      final List<VenteCompta> plusieursAnnees = <VenteCompta>[
        for (final int annee in <int>[2024, 2026])
          vente(
            date: DateTime(annee, 10, 5),
            lignes: <LigneCompta>[objet(total: 2000)],
            paiements: <PaiementCompta>[paiement(DateTime(annee, 10, 5), 2000)],
          ),
        // Un autre mois : ne compte pas.
        vente(
          date: DateTime(2025, 6, 5),
          lignes: <LigneCompta>[objet(total: 9900)],
          paiements: <PaiementCompta>[paiement(DateTime(2025, 6, 5), 9900)],
        ),
      ];
      final AnalyseVentes a = calculerAnalyse(
        ventes: plusieursAnnees,
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(mois: 10),
      );
      expect(a.lignes.map((LigneAnalyse l) => (l.annee, l.mois)), <(int?, int?)>[(2024, 10), (2025, 10), (2026, 10)]);
      expect(encaisses(a), <int>[2000, 0, 2000]);
    });

    test('croisé avec un lieu et une catégorie', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(
          annee: 2026,
          lieu: ChoixFiltre<int>.valeur(1),
          categorie: ChoixFiltre<String>.valeur(CleCategorie.doudou),
        ),
      );
      // Doudou du Marché : 50 € en octobre, −10 € en novembre.
      expect(a.lignes[9].encaisseCentimes, 5000);
      expect(a.lignes[10].encaisseCentimes, -1000);
      expect(a.encaisseTotalCentimes, 4000);
    });
  });

  group('par année', () {
    test('une ligne par année, de la première à la dernière', () {
      final AnalyseVentes a = calculerAnalyse(ventes: ventes, dimension: DimensionAnalyse.annee);
      expect(a.lignes.map((LigneAnalyse l) => l.annee), <int?>[2025, 2026]);
      expect(encaisses(a), <int>[4000, 9500]);
      expect(couts(a), <int>[1000, 1900]);
    });

    test('une année sans rien entre deux années à zéro reste visible', () {
      final List<VenteCompta> espacees = <VenteCompta>[
        for (final int annee in <int>[2023, 2025])
          vente(
            date: DateTime(annee, 2, 2),
            lignes: <LigneCompta>[objet(total: 1000)],
            paiements: <PaiementCompta>[paiement(DateTime(annee, 2, 2), 1000)],
          ),
      ];
      final AnalyseVentes a = calculerAnalyse(ventes: espacees, dimension: DimensionAnalyse.annee);
      expect(a.lignes.map((LigneAnalyse l) => l.annee), <int?>[2023, 2024, 2025]);
      expect(encaisses(a), <int>[1000, 0, 1000]);
    });
  });

  group('cohérence', () {
    test('la somme des lignes est l’argent encaissé, quelle que soit la façon de regrouper', () {
      for (final DimensionAnalyse d in DimensionAnalyse.values) {
        final AnalyseVentes a = calculerAnalyse(ventes: ventes, dimension: d);
        expect(a.encaisseTotalCentimes, 13500, reason: d.name);
        expect(a.coutTotalCentimes, 2900, reason: d.name);
      }
    });

    test('mêmes chiffres, au centime près, que l’écran Statistiques pour une même période', () {
      // Une vente remisée, en deux catégories, payée en trois fois (dont un paiement en novembre).
      final VenteCompta compliquee = vente(
        date: DateTime(2026, 10, 3),
        lieuId: 1,
        lignes: <LigneCompta>[
          objet(total: 3333, cout: 700),
          objet(total: 1777, cout: 450, categorie: CleCategorie.crochet, produitId: 2),
          cours(total: 1234),
        ],
        remise: 701,
        port: 333,
        paiements: <PaiementCompta>[
          paiement(DateTime(2026, 10, 3), 1111),
          paiement(DateTime(2026, 10, 20), 1234),
          paiement(DateTime(2026, 11, 2), 999),
        ],
      );
      final List<VenteCompta> toutes = <VenteCompta>[compliquee, ...ventes];

      final Map<String, ({DateTime debut, DateTime fin})> periodes = <String, ({DateTime debut, DateTime fin})>{
        'octobre': (debut: DateTime(2026, 10), fin: DateTime(2026, 11)),
        'novembre': (debut: DateTime(2026, 11), fin: DateTime(2026, 12)),
        '2026': (debut: DateTime(2026), fin: DateTime(2027)),
      };
      final Map<String, FiltreAnalyse> filtres = <String, FiltreAnalyse>{
        'octobre': const FiltreAnalyse(annee: 2026, mois: 10),
        'novembre': const FiltreAnalyse(annee: 2026, mois: 11),
        '2026': const FiltreAnalyse(annee: 2026),
      };
      for (final String nom in periodes.keys) {
        final StatsPeriode stats = calculerStatsPeriode(
          periode: PeriodeStats.mois,
          debut: periodes[nom]!.debut,
          fin: periodes[nom]!.fin,
          ventes: toutes,
          depenses: const <DepenseCompta>[],
        );
        final AnalyseVentes parCategorie = calculerAnalyse(
          ventes: toutes,
          dimension: DimensionAnalyse.categorie,
          filtre: filtres[nom]!,
        );
        expect(parCategorie.encaisseTotalCentimes, stats.encaisseTotalCentimes, reason: nom);
        expect(parCategorie.coutTotalCentimes, stats.coutCentimes, reason: nom);
        for (final CategorieRentable c in stats.categories) {
          final LigneAnalyse ligne = parCategorie.lignes.firstWhere((LigneAnalyse l) => l.categorie == c.categorie);
          expect(ligne.encaisseCentimes, c.encaisseCentimes, reason: '$nom / ${c.categorie}');
          expect(ligne.coutCentimes, c.coutCentimes, reason: '$nom / ${c.categorie}');
        }
        final AnalyseVentes parLieu = calculerAnalyse(
          ventes: toutes,
          dimension: DimensionAnalyse.lieu,
          filtre: filtres[nom]!,
        );
        expect(parLieu.encaisseTotalCentimes, stats.encaisseTotalCentimes, reason: nom);
      }
    });

    test('regrouper par mois donne le même total que l’année, même avec un paiement partiel chaque mois', () {
      final VenteCompta etalee = vente(
        date: DateTime(2026, 1, 10),
        lignes: <LigneCompta>[
          objet(total: 1000, cout: 100, categorie: 'a'),
          objet(total: 1000, cout: 200, categorie: 'b'),
          objet(total: 1000, cout: 300, categorie: 'c'),
        ],
        paiements: <PaiementCompta>[
          for (int m = 1; m <= 6; m++) paiement(DateTime(2026, m, 10), 101),
        ],
      );
      final AnalyseVentes parMois = calculerAnalyse(
        ventes: <VenteCompta>[etalee],
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(annee: 2026),
      );
      final AnalyseVentes parAnnee = calculerAnalyse(
        ventes: <VenteCompta>[etalee],
        dimension: DimensionAnalyse.annee,
      );
      // L'argent est exact ; la matière peut différer de quelques centimes d'arrondi entre les deux regroupements.
      expect(parMois.encaisseTotalCentimes, 606);
      expect(parAnnee.encaisseTotalCentimes, 606);
      expect((parMois.coutTotalCentimes - parAnnee.coutTotalCentimes).abs(), lessThanOrEqualTo(3));
    });
  });

  group('cas limites', () {
    test('aucune vente : rien à montrer', () {
      for (final DimensionAnalyse d in DimensionAnalyse.values) {
        final AnalyseVentes a = calculerAnalyse(ventes: const <VenteCompta>[], dimension: d);
        expect(a.vide, isTrue, reason: d.name);
        expect(a.encaisseTotalCentimes, 0);
        expect(a.margeTotalCentimes, 0);
      }
    });

    test('des critères qui ne correspondent à rien : rien à montrer', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(annee: 2019),
      );
      expect(a.vide, isTrue);
    });

    test('une vente sans paiement ou d’un total nul n’apporte rien', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: <VenteCompta>[
          vente(date: le5Oct, lignes: <LigneCompta>[objet(total: 1000)], paiements: const <PaiementCompta>[]),
          vente(
            date: le5Oct,
            lignes: <LigneCompta>[objet(total: 0)],
            paiements: <PaiementCompta>[paiement(le5Oct, 500)],
          ),
        ],
        dimension: DimensionAnalyse.lieu,
      );
      expect(a.vide, isTrue);
    });

    test('une vente annulée et entièrement remboursée n’apporte rien, ni par lieu ni par mois', () {
      final VenteCompta annulee = vente(
        date: le5Oct,
        lieuId: 1,
        annulee: true,
        lignes: <LigneCompta>[objet(total: 5000, cout: 1000)],
        paiements: <PaiementCompta>[paiement(le5Oct, 5000), paiement(le12Oct, -5000)],
      );
      final AnalyseVentes a = calculerAnalyse(ventes: <VenteCompta>[annulee], dimension: DimensionAnalyse.lieu);
      expect(a.vide, isTrue);
      final AnalyseVentes parMois = calculerAnalyse(
        ventes: <VenteCompta>[annulee],
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(annee: 2026),
      );
      expect(parMois.vide, isTrue);
      expect(parMois.encaisseTotalCentimes, 0);
    });

    test('un remboursement dans un mois plus tard donne un mois négatif', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(annee: 2026, lieu: ChoixFiltre<int>.valeur(1)),
      );
      expect(a.lignes[10].encaisseCentimes, -1000);
      expect(a.lignes[10].coutCentimes, -200);
      expect(a.lignes[10].margeCentimes, -800);
    });

    test('partEnPourcent : arrondi, et rien quand le total n’est pas positif', () {
      final AnalyseVentes a = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.lieu,
        ordreLieux: <int>[1, 2],
      );
      expect(a.lignes.map(a.partEnPourcent), <int?>[59, 22, 19]);

      final AnalyseVentes negatif = calculerAnalyse(
        ventes: ventes,
        dimension: DimensionAnalyse.mois,
        filtre: const FiltreAnalyse(annee: 2026, mois: 11, lieu: ChoixFiltre<int>.valeur(1)),
      );
      expect(negatif.encaisseTotalCentimes, -1000);
      expect(negatif.lignes.map(negatif.partEnPourcent), everyElement(isNull));
    });
  });
}
