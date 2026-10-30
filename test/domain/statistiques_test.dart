import 'package:crochet_creations/domain/calculs/statistiques.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Octobre 2026 : du 1er octobre (inclus) au 1er novembre (exclu).
  final DateTime debut = DateTime(2026, 10);
  final DateTime fin = DateTime(2026, 11);

  LigneCompta objet({
    int total = 5000,
    int quantite = 1,
    int cout = 0,
    int produitId = 1,
    CategorieProduit categorie = CategorieProduit.doudou,
    String designation = 'Doudou lapin',
  }) => LigneCompta(
    nature: NatureLigne.bien,
    designation: designation,
    quantite: quantite,
    totalCentimes: total,
    coutUnitaireCentimes: cout,
    produitId: produitId,
    categorie: categorie,
  );

  LigneCompta prestation({int total = 1000, String designation = 'Retouche'}) =>
      LigneCompta(nature: NatureLigne.service, designation: designation, quantite: 1, totalCentimes: total);

  LigneCompta cours({int total = 4500, int coursId = 7}) => LigneCompta(
    nature: NatureLigne.service,
    designation: 'Cours : Initiation',
    quantite: 1,
    totalCentimes: total,
    coursId: coursId,
  );

  PaiementCompta paiement(DateTime date, int montant) => PaiementCompta(date: date, montantCentimes: montant);

  VenteCompta vente({
    required DateTime date,
    required List<LigneCompta> lignes,
    List<PaiementCompta> paiements = const <PaiementCompta>[],
    bool annulee = false,
    int remise = 0,
    int port = 0,
  }) => VenteCompta(
    date: date,
    annulee: annulee,
    lignes: lignes,
    paiements: paiements,
    remiseCentimes: remise,
    fraisPortCentimes: port,
  );

  StatsPeriode stats(List<VenteCompta> ventes, {List<DepenseCompta> depenses = const <DepenseCompta>[]}) =>
      calculerStatsPeriode(
        periode: PeriodeStats.mois,
        debut: debut,
        fin: fin,
        ventes: ventes,
        depenses: depenses,
      );

  final DateTime le5 = DateTime(2026, 10, 5, 10);

  group('arithmétique en centimes', () {
    test('diviserArrondi arrondit au plus proche, la moitié s’éloigne de zéro', () {
      expect(diviserArrondi(5, 2), 3);
      expect(diviserArrondi(-5, 2), -3);
      expect(diviserArrondi(4, 3), 1);
      expect(diviserArrondi(7, 3), 2);
      expect(diviserArrondi(0, 5), 0);
      expect(diviserArrondi(-7, 3), -2);
    });

    test('repartirProportionnellement : la somme des parts est exactement le montant', () {
      expect(repartirProportionnellement(1000, <int>[2500, 7500]), <int>[250, 750]);
      expect(repartirProportionnellement(100, <int>[1, 1, 1]), <int>[34, 33, 33]);
      expect(repartirProportionnellement(999, <int>[333, 333, 334]), <int>[333, 333, 333]);
      for (final int montant in <int>[1, 7, 99, 1001, 12345]) {
        final List<int> parts = repartirProportionnellement(montant, <int>[333, 1, 2999, 17]);
        expect(parts.fold(0, (int s, int p) => s + p), montant, reason: '$montant');
      }
    });

    test('un montant négatif (remboursement) est réparti de la même façon, au signe près', () {
      expect(repartirProportionnellement(-100, <int>[1, 1, 1]), <int>[-34, -33, -33]);
      expect(repartirProportionnellement(-1000, <int>[2500, 7500]), <int>[-250, -750]);
    });

    test('cas limites : aucune part, montant nul, poids tous nuls', () {
      expect(repartirProportionnellement(100, <int>[]), isEmpty);
      expect(repartirProportionnellement(0, <int>[3, 4]), <int>[0, 0]);
      expect(repartirProportionnellement(50, <int>[0, 0]), <int>[50, 0]);
    });
  });

  group('éléments d’une vente', () {
    final VenteCompta uneVente = vente(
      date: le5,
      lignes: <LigneCompta>[objet(total: 3000, quantite: 2, cout: 400), prestation()],
      remise: 400,
      port: 500,
    );

    test('la remise est répartie au prorata des lignes, les frais de port forment un élément à part', () {
      final List<ComposantVente> composants = composantsDeVente(uneVente);
      expect(composants.map((ComposantVente c) => c.poidsCentimes), <int>[2700, 900, 500]);
      expect(composants.map((ComposantVente c) => c.nature), <NatureLigne>[
        NatureLigne.bien,
        NatureLigne.service,
        NatureLigne.bien,
      ]);
    });

    test('le coût matière est celui de la quantité vendue (jamais celui des frais de port)', () {
      final List<ComposantVente> composants = composantsDeVente(uneVente);
      expect(composants.map((ComposantVente c) => c.coutCentimes), <int>[800, 0, 0]);
    });

    test('la somme des éléments est le total de la vente (sous-total − remise + frais de port)', () {
      expect(totalDeVente(uneVente), 4100);
    });

    test('une ligne de cours est reconnue comme telle', () {
      final List<ComposantVente> composants = composantsDeVente(vente(date: le5, lignes: <LigneCompta>[cours()]));
      expect(composants.single.estCours, isTrue);
      expect(composants.single.nature, NatureLigne.service);
    });
  });

  group('périodes', () {
    // Le mercredi 28 octobre 2026.
    final DateTime mercredi = DateTime(2026, 10, 28, 15, 30);

    test('jour : de minuit à minuit', () {
      final b = bornesPeriode(PeriodeStats.jour, mercredi);
      expect(b.debut, DateTime(2026, 10, 28));
      expect(b.fin, DateTime(2026, 10, 29));
    });

    test('semaine : du lundi (inclus) au lundi suivant (exclu)', () {
      final b = bornesPeriode(PeriodeStats.semaine, mercredi);
      expect(b.debut, DateTime(2026, 10, 26));
      expect(b.fin, DateTime(2026, 11, 2));
    });

    test('un dimanche appartient à la semaine qui finit ce jour-là', () {
      final b = bornesPeriode(PeriodeStats.semaine, DateTime(2026, 11, 1, 20));
      expect(b.debut, DateTime(2026, 10, 26));
      expect(b.fin, DateTime(2026, 11, 2));
    });

    test('une semaine peut chevaucher deux années', () {
      final b = bornesPeriode(PeriodeStats.semaine, DateTime(2027, 1, 1));
      expect(b.debut, DateTime(2026, 12, 28));
      expect(b.fin, DateTime(2027, 1, 4));
    });

    test('mois et année', () {
      final m = bornesPeriode(PeriodeStats.mois, mercredi);
      expect(m.debut, DateTime(2026, 10));
      expect(m.fin, DateTime(2026, 11));
      final a = bornesPeriode(PeriodeStats.annee, mercredi);
      expect(a.debut, DateTime(2026));
      expect(a.fin, DateTime(2027));
      final decembre = bornesPeriode(PeriodeStats.mois, DateTime(2026, 12, 31, 23, 59));
      expect(decembre.fin, DateTime(2027));
    });

    test('le début est dans la période, la fin n’y est plus', () {
      final DateTime d = DateTime(2026, 10);
      final DateTime f = DateTime(2026, 11);
      expect(dansLaPeriode(d, d, f), isTrue);
      expect(dansLaPeriode(DateTime(2026, 10, 31, 23, 59, 59), d, f), isTrue);
      expect(dansLaPeriode(f, d, f), isFalse);
      expect(dansLaPeriode(DateTime(2026, 9, 30, 23, 59), d, f), isFalse);
    });
  });

  group('argent encaissé, objets et prestations', () {
    test('une vente payée en entier : chaque nature reçoit ce qui lui revient', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[objet(total: 5000, quantite: 2, cout: 1000), cours()],
          paiements: <PaiementCompta>[paiement(le5, 9500)],
        ),
      ]);
      expect(s.encaisseObjetsCentimes, 5000);
      expect(s.encaissePrestationsCentimes, 4500);
      expect(s.encaisseCoursCentimes, 4500);
      expect(s.encaisseTotalCentimes, 9500);
      expect(s.ventesHorsCoursCentimes, 5000);
      expect(s.coutCentimes, 2000);
      expect(s.margeCentimes, 7500);
    });

    test('un acompte compte pour sa part de chaque ligne, le solde plus tard dans sa propre période', () {
      final VenteCompta v = vente(
        date: le5,
        lignes: <LigneCompta>[objet(total: 10000, cout: 3000)],
        paiements: <PaiementCompta>[paiement(le5, 4000), paiement(DateTime(2026, 11, 3), 6000)],
      );
      final StatsPeriode octobre = stats(<VenteCompta>[v]);
      expect(octobre.encaisseTotalCentimes, 4000);
      expect(octobre.coutCentimes, 1200);
      expect(octobre.margeCentimes, 2800);

      final StatsPeriode novembre = calculerStatsPeriode(
        periode: PeriodeStats.mois,
        debut: DateTime(2026, 11),
        fin: DateTime(2026, 12),
        ventes: <VenteCompta>[v],
        depenses: const <DepenseCompta>[],
      );
      expect(novembre.encaisseTotalCentimes, 6000);
      expect(novembre.coutCentimes, 1800);
      // Sur la vie de la vente, tout le coût est retrouvé.
      expect(octobre.coutCentimes + novembre.coutCentimes, 3000);
    });

    test('la remise et les frais de port sont comptés : les frais de port avec les objets', () {
      final VenteCompta v = vente(
        date: le5,
        lignes: <LigneCompta>[objet(total: 3000, quantite: 2, cout: 400), prestation()],
        remise: 400,
        port: 500,
        paiements: <PaiementCompta>[paiement(le5, 4100)],
      );
      final StatsPeriode s = stats(<VenteCompta>[v]);
      expect(s.encaisseObjetsCentimes, 3200); // 2 700 d'objets après remise + 500 de port
      expect(s.encaissePrestationsCentimes, 900);
      expect(s.coutCentimes, 800);
    });

    test('un paiement partiel est réparti au prorata, sans perdre un centime', () {
      final VenteCompta v = vente(
        date: le5,
        lignes: <LigneCompta>[objet(total: 3000, quantite: 2, cout: 400), prestation()],
        remise: 400,
        port: 500,
        paiements: <PaiementCompta>[paiement(le5, 2050)],
      );
      final StatsPeriode s = stats(<VenteCompta>[v]);
      expect(s.encaisseObjetsCentimes, 1600);
      expect(s.encaissePrestationsCentimes, 450);
      expect(s.coutCentimes, 400);
    });

    test('la somme des natures est toujours exactement ce qui a été encaissé', () {
      final VenteCompta v = vente(
        date: le5,
        lignes: <LigneCompta>[objet(total: 333), prestation(total: 333), objet(total: 334, produitId: 2)],
        paiements: <PaiementCompta>[paiement(le5, 777)],
      );
      final StatsPeriode s = stats(<VenteCompta>[v]);
      expect(s.encaisseTotalCentimes, 777);
    });

    test('une vente sans paiement ne rapporte rien (mais compte comme une vente)', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(date: le5, lignes: <LigneCompta>[objet(total: 5000, cout: 1000)]),
      ]);
      expect(s.encaisseTotalCentimes, 0);
      expect(s.coutCentimes, 0);
      expect(s.nombreVentes, 1);
    });

    test('une vente d’un autre mois payée ce mois-ci compte dans l’argent encaissé, pas dans les ventes', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: DateTime(2026, 9, 28),
          lignes: <LigneCompta>[objet(total: 5000)],
          paiements: <PaiementCompta>[paiement(DateTime(2026, 10, 2), 5000)],
        ),
      ]);
      expect(s.encaisseTotalCentimes, 5000);
      expect(s.nombreVentes, 0);
      expect(s.meilleuresVentes, isEmpty);
    });

    test('un remboursement retire l’argent (et le coût) dans la période où il est fait', () {
      final VenteCompta annulee = vente(
        date: le5,
        annulee: true,
        lignes: <LigneCompta>[objet(total: 5000, cout: 1500)],
        paiements: <PaiementCompta>[paiement(le5, 5000), paiement(DateTime(2026, 11, 5), -5000)],
      );
      final StatsPeriode octobre = stats(<VenteCompta>[annulee]);
      expect(octobre.encaisseTotalCentimes, 5000);
      expect(octobre.coutCentimes, 1500);

      final StatsPeriode novembre = calculerStatsPeriode(
        periode: PeriodeStats.mois,
        debut: DateTime(2026, 11),
        fin: DateTime(2026, 12),
        ventes: <VenteCompta>[annulee],
        depenses: const <DepenseCompta>[],
      );
      expect(novembre.encaisseTotalCentimes, -5000);
      expect(novembre.coutCentimes, -1500);
      expect(novembre.margeCentimes, -3500);
      expect(novembre.nombreVentes, 0);
    });

    test('une vente annulée et remboursée le même mois ne laisse rien', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          annulee: true,
          lignes: <LigneCompta>[objet(total: 5000, cout: 1500)],
          paiements: <PaiementCompta>[paiement(le5, 5000), paiement(DateTime(2026, 10, 6), -5000)],
        ),
      ]);
      expect(s.encaisseTotalCentimes, 0);
      expect(s.coutCentimes, 0);
      expect(s.nombreVentes, 0);
      expect(s.meilleuresVentes, isEmpty);
      expect(s.categories, isEmpty);
    });

    test('une vente à 0 € (cours gratuit) ne compte ni dans les ventes ni dans l’argent encaissé', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(date: le5, lignes: <LigneCompta>[cours(total: 0)]),
      ]);
      expect(s.nombreVentes, 0);
      expect(s.encaisseTotalCentimes, 0);
    });
  });

  group('panier moyen', () {
    test('moyenne des totaux des ventes validées de la période', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(date: le5, lignes: <LigneCompta>[objet(total: 1000)]),
        vente(date: le5, lignes: <LigneCompta>[objet(total: 1000)]),
        vente(date: le5, lignes: <LigneCompta>[objet(total: 1002)]),
        vente(date: DateTime(2026, 9, 1), lignes: <LigneCompta>[objet(total: 9999)]),
        vente(date: le5, annulee: true, lignes: <LigneCompta>[objet(total: 9999)]),
      ]);
      expect(s.nombreVentes, 3);
      expect(s.totalVentesCentimes, 3002);
      expect(s.panierMoyenCentimes, 1001); // 1 000,67 arrondi
    });

    test('la remise et les frais de port sont dans le total d’une vente', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(date: le5, lignes: <LigneCompta>[objet(total: 3000)], remise: 500, port: 400),
      ]);
      expect(s.panierMoyenCentimes, 2900);
    });

    test('aucune vente : pas de panier moyen', () {
      expect(stats(<VenteCompta>[]).panierMoyenCentimes, isNull);
    });
  });

  group('meilleures ventes', () {
    test('classées par quantité, puis par montant ; les ventes d’un même produit sont additionnées', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[
            objet(produitId: 1, designation: 'Bonnet', quantite: 2, total: 2000),
            objet(produitId: 2, designation: 'Écharpe', quantite: 3, total: 4500),
          ],
        ),
        vente(date: le5, lignes: <LigneCompta>[objet(produitId: 1, designation: 'Bonnet', quantite: 1, total: 1000)]),
      ]);
      expect(s.meilleuresVentes.map((VenteProduit v) => v.designation), <String>['Écharpe', 'Bonnet']);
      expect(s.meilleuresVentes.first.quantite, 3);
      expect(s.meilleuresVentes.first.totalCentimes, 4500);
      expect(s.meilleuresVentes.last.quantite, 3);
      expect(s.meilleuresVentes.last.totalCentimes, 3000);
    });

    test('les lignes libres sont regroupées par désignation ; les cours et les ventes annulées sont exclus', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[
            LigneCompta(
              nature: NatureLigne.bien,
              designation: 'Couverture sur mesure',
              quantite: 1,
              totalCentimes: 6000,
            ),
            cours(),
          ],
        ),
        vente(
          date: le5,
          lignes: <LigneCompta>[
            LigneCompta(
              nature: NatureLigne.bien,
              designation: ' couverture SUR mesure ',
              quantite: 1,
              totalCentimes: 6500,
            ),
          ],
        ),
        vente(date: le5, annulee: true, lignes: <LigneCompta>[objet(produitId: 9, designation: 'Annulé')]),
      ]);
      expect(s.meilleuresVentes, hasLength(1));
      expect(s.meilleuresVentes.single.designation, 'Couverture sur mesure');
      expect(s.meilleuresVentes.single.quantite, 2);
      expect(s.meilleuresVentes.single.totalCentimes, 12500);
    });

    test('on garde les cinq premières', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[
            for (int i = 1; i <= 7; i++) objet(produitId: i, designation: 'Produit $i', quantite: i, total: 1000 * i),
          ],
        ),
      ]);
      expect(s.meilleuresVentes, hasLength(nombreMeilleuresVentes));
      expect(s.meilleuresVentes.first.designation, 'Produit 7');
      expect(s.meilleuresVentes.last.designation, 'Produit 3');
    });
  });

  group('catégories les plus rentables et cours', () {
    test('classées par marge (argent encaissé moins coût matière), sans les catégories inactives', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[
            objet(produitId: 1, categorie: CategorieProduit.doudou, total: 5000, quantite: 2, cout: 1000),
            objet(produitId: 2, categorie: CategorieProduit.crochet, total: 10000, cout: 3000, designation: 'Plaid'),
            objet(produitId: 3, categorie: CategorieProduit.accessoire, total: 800, cout: 100, designation: 'Pince'),
          ],
          paiements: <PaiementCompta>[paiement(le5, 15800)],
        ),
      ]);
      expect(s.categories.map((CategorieRentable c) => c.categorie), <CategorieProduit>[
        CategorieProduit.crochet, // marge 7 000
        CategorieProduit.doudou, // marge 3 000
        CategorieProduit.accessoire, // marge 700
      ]);
      expect(s.categories.first.encaisseCentimes, 10000);
      expect(s.categories.first.coutCentimes, 3000);
      expect(s.categories.first.margeCentimes, 7000);
    });

    test('un paiement partiel ne compte que sa part de chaque catégorie', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[
            objet(produitId: 1, categorie: CategorieProduit.doudou, total: 6000, cout: 2000),
            objet(produitId: 2, categorie: CategorieProduit.crochet, total: 4000, cout: 1000, designation: 'Plaid'),
          ],
          paiements: <PaiementCompta>[paiement(le5, 5000)],
        ),
      ]);
      final CategorieRentable doudou = s.categories.firstWhere(
        (CategorieRentable c) => c.categorie == CategorieProduit.doudou,
      );
      expect(doudou.encaisseCentimes, 3000);
      expect(doudou.coutCentimes, 1000);
      expect(s.categories.fold(0, (int somme, CategorieRentable c) => somme + c.encaisseCentimes), 5000);
    });

    test('les lignes libres, les cours et les frais de port ne sont dans aucune catégorie', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[cours(), prestation()],
          port: 300,
          paiements: <PaiementCompta>[paiement(le5, 5800)],
        ),
      ]);
      expect(s.categories, isEmpty);
      expect(s.encaisseCoursCentimes, 4500);
      expect(s.encaissePrestationsCentimes, 5500);
      expect(s.encaisseObjetsCentimes, 300);
    });

    test('revenus des cours : un remboursement les diminue', () {
      final StatsPeriode s = stats(<VenteCompta>[
        vente(
          date: le5,
          lignes: <LigneCompta>[cours()],
          paiements: <PaiementCompta>[paiement(le5, 4500), paiement(DateTime(2026, 10, 12), -4500)],
        ),
        vente(date: le5, lignes: <LigneCompta>[cours(coursId: 8)], paiements: <PaiementCompta>[paiement(le5, 4500)]),
      ]);
      expect(s.encaisseCoursCentimes, 4500);
    });
  });

  group('dépenses par catégorie', () {
    test('totaux par catégorie pour la période, la plus lourde d’abord', () {
      final StatsPeriode s = stats(
        <VenteCompta>[],
        depenses: <DepenseCompta>[
          DepenseCompta(date: DateTime(2026, 10), categorie: CategorieDepense.laineFil, montantCentimes: 2490),
          DepenseCompta(date: DateTime(2026, 10, 15), categorie: CategorieDepense.laineFil, montantCentimes: 1000),
          DepenseCompta(date: DateTime(2026, 10, 31), categorie: CategorieDepense.standMarche, montantCentimes: 5000),
          DepenseCompta(date: DateTime(2026, 11), categorie: CategorieDepense.transport, montantCentimes: 900),
          DepenseCompta(date: DateTime(2026, 9, 30), categorie: CategorieDepense.emballage, montantCentimes: 450),
        ],
      );
      expect(s.depenses.map((DepenseParCategorie d) => d.categorie), <CategorieDepense>[
        CategorieDepense.standMarche,
        CategorieDepense.laineFil,
      ]);
      expect(s.depenses.last.totalCentimes, 3490);
      expect(s.depensesTotalCentimes, 8490);
    });

    test('aucune dépense : rien', () {
      final StatsPeriode s = stats(<VenteCompta>[]);
      expect(s.depenses, isEmpty);
      expect(s.depensesTotalCentimes, 0);
    });
  });

  group('franchise de TVA', () {
    const int seuil = 8500000; // 85 000 €

    test('loin du seuil : rien à signaler', () {
      expect(niveauFranchise(0, seuil), NiveauFranchise.ok);
      expect(niveauFranchise(6799999, seuil), NiveauFranchise.ok);
    });

    test('à partir de 80 % du seuil : le seuil approche', () {
      expect(niveauFranchise(6800000, seuil), NiveauFranchise.approche);
      expect(niveauFranchise(8000000, seuil), NiveauFranchise.approche);
    });

    test('le seuil lui-même n’est pas dépassé ; un centime de plus, si', () {
      expect(niveauFranchise(8500000, seuil), NiveauFranchise.approche);
      expect(niveauFranchise(8500001, seuil), NiveauFranchise.depasse);
    });

    test('seuil des prestations : 37 500 €', () {
      const int seuilServices = 3750000;
      expect(niveauFranchise(2999999, seuilServices), NiveauFranchise.ok);
      expect(niveauFranchise(3000000, seuilServices), NiveauFranchise.approche);
      expect(niveauFranchise(3750001, seuilServices), NiveauFranchise.depasse);
    });

    test('part du seuil : entre 0 et 1', () {
      expect(partDuSeuil(0, seuil), 0);
      expect(partDuSeuil(4250000, seuil), 0.5);
      expect(partDuSeuil(9000000, seuil), 1);
      expect(partDuSeuil(-100, seuil), 0);
      expect(partDuSeuil(100, 0), 0);
    });
  });
}
