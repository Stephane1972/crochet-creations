import 'package:crochet_creations/domain/declaration.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les rappels à partir de [maintenant] (le lundi 23 novembre 2026, 10 h, par défaut).
List<RappelDeclaration> _rappels({DateTime? maintenant, int mois = moisProgrammesDeclaration}) =>
    prochainsRappelsDeclaration(maintenant ?? DateTime(2026, 11, 23, 10), mois: mois);

void main() {
  group('les réglages du rappel', () {
    test('3 jours avant la fin du mois, puis le dernier jour, à 9 h, pour les 12 prochains mois', () {
      expect(joursAvantDeclaration, 3);
      expect(heureRappelDeclaration, 9);
      expect(moisProgrammesDeclaration, 12);
      expect(titreRappelDeclaration, 'Déclaration des recettes');
    });
  });

  group('les rappels d’un mois', () {
    test('novembre 2026 : le vendredi 27 (3 jours avant) et le lundi 30 (dernier jour), à 9 h', () {
      final List<RappelDeclaration> r = _rappels(mois: 1);

      expect(r, hasLength(2));
      expect(r[0].type, TypeRappelDeclaration.avance);
      expect(r[0].quand, DateTime(2026, 11, 27, 9));
      expect(r[0].dernierJour, DateTime(2026, 11, 30));
      expect(r[1].type, TypeRappelDeclaration.dernierJour);
      expect(r[1].quand, DateTime(2026, 11, 30, 9));
      expect(r[1].dernierJour, DateTime(2026, 11, 30));
    });

    test('chaque rappel porte le titre et le texte de son type', () {
      final List<RappelDeclaration> r = _rappels(mois: 1);

      expect(r[0].titre, 'Déclaration des recettes');
      expect(
        r[0].texte,
        'Fin de mois lundi 30 novembre (dans 3 jours) : pensez à préparer la déclaration de vos recettes.',
      );
      expect(r[1].titre, 'Déclaration des recettes');
      expect(
        r[1].texte,
        'Fin de mois aujourd’hui (lundi 30 novembre) : pensez à déclarer vos recettes à l’organisme.',
      );
      expect(texteRappelDeclaration(DateTime(2026, 12, 31), TypeRappelDeclaration.dernierJour), contains('jeudi 31 décembre'));
    });

    test('le mois de 31 jours, de 30 jours, février de 28 et de 29 jours', () {
      // (maintenant, dernier jour du mois, jour du rappel d'avance)
      final List<(DateTime, DateTime, DateTime)> cas = <(DateTime, DateTime, DateTime)>[
        (DateTime(2026, 12, 1, 8), DateTime(2026, 12, 31), DateTime(2026, 12, 28, 9)),
        (DateTime(2026, 4, 1, 8), DateTime(2026, 4, 30), DateTime(2026, 4, 27, 9)),
        (DateTime(2027, 2, 1, 8), DateTime(2027, 2, 28), DateTime(2027, 2, 25, 9)),
        (DateTime(2028, 2, 1, 8), DateTime(2028, 2, 29), DateTime(2028, 2, 26, 9)),
      ];
      for (final (DateTime maintenant, DateTime dernier, DateTime avance) in cas) {
        final List<RappelDeclaration> r = _rappels(maintenant: maintenant, mois: 1);
        expect(r, hasLength(2), reason: '$dernier');
        expect(r[0].quand, avance, reason: '$dernier');
        expect(r[1].quand, DateTime(dernier.year, dernier.month, dernier.day, 9), reason: '$dernier');
        expect(r[1].dernierJour, dernier, reason: '$dernier');
      }
    });

    test('le rappel de 3 jours avant n’est jamais dans le mois précédent', () {
      for (final RappelDeclaration rappel in _rappels(maintenant: DateTime(2026, 1, 1), mois: 36)) {
        expect(rappel.quand.month, rappel.dernierJour.month, reason: '${rappel.quand}');
        expect(rappel.quand.year, rappel.dernierJour.year, reason: '${rappel.quand}');
      }
    });
  });

  group('ce qui est déjà passé n’est pas programmé', () {
    test('à 9 h pile le jour du premier rappel, il est passé ; une minute avant, il est encore à venir', () {
      final List<RappelDeclaration> passe = _rappels(maintenant: DateTime(2026, 11, 27, 9), mois: 1);
      expect(passe, hasLength(1));
      expect(passe.single.type, TypeRappelDeclaration.dernierJour);

      final List<RappelDeclaration> avant = _rappels(maintenant: DateTime(2026, 11, 27, 8, 59), mois: 1);
      expect(avant, hasLength(2));
    });

    test('le dernier jour avant 9 h : il reste le rappel du jour ; après 9 h : plus rien pour ce mois', () {
      final List<RappelDeclaration> matin = _rappels(maintenant: DateTime(2026, 11, 30, 8), mois: 1);
      expect(matin.map((RappelDeclaration r) => r.type), <TypeRappelDeclaration>[TypeRappelDeclaration.dernierJour]);

      expect(_rappels(maintenant: DateTime(2026, 11, 30, 10), mois: 1), isEmpty);
    });

    test('après la fin du mois, le premier rappel est celui du mois suivant', () {
      final List<RappelDeclaration> r = _rappels(maintenant: DateTime(2026, 11, 30, 10));

      expect(r.first.type, TypeRappelDeclaration.avance);
      expect(r.first.quand, DateTime(2026, 12, 28, 9));
    });
  });

  group('la liste des rappels programmés', () {
    test('12 mois à partir de novembre 2026 : de novembre 2026 à octobre 2027, 24 rappels', () {
      final List<RappelDeclaration> r = _rappels();

      expect(r, hasLength(24));
      expect(r.first.quand, DateTime(2026, 11, 27, 9));
      expect(r.last.quand, DateTime(2027, 10, 31, 9));
      expect(r.last.dernierJour, DateTime(2027, 10, 31));
    });

    test('à partir de la fin du mois, le premier mois est déjà passé : 22 rappels, jusqu’en novembre 2027', () {
      final List<RappelDeclaration> r = _rappels(maintenant: DateTime(2026, 11, 30, 10));

      // Le mois en cours compte parmi les 12 : de novembre 2026 à octobre 2027, sans les deux rappels de novembre.
      expect(r, hasLength(22));
      expect(r.last.dernierJour, DateTime(2027, 10, 31));
    });

    test('le passage à l’année suivante : décembre 2026 puis janvier 2027', () {
      final List<RappelDeclaration> r = _rappels(maintenant: DateTime(2026, 12, 20, 10), mois: 2);

      expect(r.map((RappelDeclaration x) => x.quand), <DateTime>[
        DateTime(2026, 12, 28, 9),
        DateTime(2026, 12, 31, 9),
        DateTime(2027, 1, 28, 9),
        DateTime(2027, 1, 31, 9),
      ]);
    });

    test('rangés du plus proche au plus lointain, sans identifiant en double', () {
      final List<RappelDeclaration> r = _rappels(mois: 36);

      for (int i = 1; i < r.length; i++) {
        expect(r[i].quand.isAfter(r[i - 1].quand), isTrue, reason: '${r[i - 1].quand} puis ${r[i].quand}');
      }
      expect(r.map((RappelDeclaration x) => x.id).toSet(), hasLength(r.length));
    });

    test('toujours à 9 h pile, y compris les jours de changement d’heure (fin mars, fin octobre)', () {
      for (final RappelDeclaration rappel in _rappels(maintenant: DateTime(2026, 1, 1), mois: 36)) {
        expect(rappel.quand.hour, 9, reason: '${rappel.quand}');
        expect(rappel.quand.minute, 0, reason: '${rappel.quand}');
      }
    });

    test('un mois, ou aucun', () {
      expect(_rappels(mois: 1), hasLength(2));
      expect(_rappels(mois: 0), isEmpty);
    });
  });

  group('les identifiants', () {
    test('l’année, le mois et le type : 2026110 pour 3 jours avant, 2026111 pour le dernier jour', () {
      expect(identifiantRappel(DateTime(2026, 11, 30), TypeRappelDeclaration.avance), 2026110);
      expect(identifiantRappel(DateTime(2026, 11, 30), TypeRappelDeclaration.dernierJour), 2026111);
      expect(identifiantRappel(DateTime(2027, 1, 31), TypeRappelDeclaration.avance), 2027010);
      expect(identifiantRappel(DateTime(2027, 12, 31), TypeRappelDeclaration.dernierJour), 2027121);
    });

    test('le même rappel reprogrammé garde le même identifiant, et il remplace donc l’ancien', () {
      final RappelDeclaration tot = _rappels(maintenant: DateTime(2026, 11, 1)).first;
      final RappelDeclaration tard = _rappels(maintenant: DateTime(2026, 11, 20)).first;

      expect(tot.id, tard.id);
      expect(tot, tard);
    });

    test('estIdentifiantRappel ne reconnaît que les identifiants de rappel, pas ceux d’autres notifications', () {
      expect(estIdentifiantRappel(2026110), isTrue);
      expect(estIdentifiantRappel(1000000), isTrue);
      expect(estIdentifiantRappel(9999999), isTrue);
      expect(estIdentifiantRappel(1), isFalse); // la notification d'essai
      expect(estIdentifiantRappel(0), isFalse);
      expect(estIdentifiantRappel(999999), isFalse);
      expect(estIdentifiantRappel(10000000), isFalse);
      expect(estIdentifiantRappel(-2026110), isFalse);
    });

    test('tous les identifiants programmés sont reconnus comme des rappels, sur 100 ans', () {
      for (final RappelDeclaration rappel in _rappels(mois: 1200)) {
        expect(estIdentifiantRappel(rappel.id), isTrue, reason: '${rappel.id}');
      }
    });
  });

  group('RappelDeclaration', () {
    test('deux rappels identiques sont égaux ; un détail de différence les distingue', () {
      RappelDeclaration rappel({DateTime? quand}) => RappelDeclaration(
        id: 2026110,
        quand: quand ?? DateTime(2026, 11, 27, 9),
        type: TypeRappelDeclaration.avance,
        dernierJour: DateTime(2026, 11, 30),
        titre: 'Déclaration des recettes',
        texte: 'Texte',
      );

      expect(rappel(), rappel());
      expect(rappel().hashCode, rappel().hashCode);
      expect(rappel(), isNot(rappel(quand: DateTime(2026, 11, 27, 10))));
    });
  });
}
