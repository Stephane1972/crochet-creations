import 'package:crochet_creations/domain/agenda.dart';
import 'package:flutter_test/flutter_test.dart';

EntreeAgenda _entree(
  String titre,
  DateTime debut, {
  TypeEntreeAgenda type = TypeEntreeAgenda.evenement,
  bool journeeEntiere = false,
  DateTime? fin,
  String? detail,
  String? lieu,
}) => EntreeAgenda(
  type: type,
  titre: titre,
  debut: debut,
  fin: fin,
  journeeEntiere: journeeEntiere,
  detail: detail,
  lieu: lieu,
);

void main() {
  group('jours du mois', () {
    test('le dernier jour du mois : 30 novembre, 28 ou 29 février, 31 décembre', () {
      expect(dernierJourDuMois(2026, 11), DateTime(2026, 11, 30));
      expect(dernierJourDuMois(2026, 2), DateTime(2026, 2, 28));
      expect(dernierJourDuMois(2028, 2), DateTime(2028, 2, 29));
      expect(dernierJourDuMois(2026, 12), DateTime(2026, 12, 31));
    });

    test('le début du mois suivant passe à l’année suivante en décembre', () {
      expect(debutMoisSuivant(2026, 11), DateTime(2026, 12, 1));
      expect(debutMoisSuivant(2026, 12), DateTime(2027, 1, 1));
    });

    test('jourDe garde le jour et retire l’heure', () {
      expect(jourDe(DateTime(2026, 11, 23, 17, 45, 12)), DateTime(2026, 11, 23));
    });

    test('novembre 2026 (il commence un dimanche) : six semaines, du lundi 26 octobre au dimanche 6 décembre', () {
      final List<DateTime> jours = joursAffiches(2026, 11);
      expect(jours, hasLength(42));
      expect(jours.first, DateTime(2026, 10, 26));
      expect(jours.last, DateTime(2026, 12, 6));
    });

    test('février 2027 (il commence un lundi et dure 28 jours) : exactement quatre semaines', () {
      final List<DateTime> jours = joursAffiches(2027, 2);
      expect(jours, hasLength(28));
      expect(jours.first, DateTime(2027, 2, 1));
      expect(jours.last, DateTime(2027, 2, 28));
    });

    test('la grille commence toujours un lundi, finit un dimanche, et ne saute aucun jour (changements d’heure compris)', () {
      for (int annee = 2026; annee <= 2028; annee++) {
        for (int mois = 1; mois <= 12; mois++) {
          final List<DateTime> jours = joursAffiches(annee, mois);
          reason() => '$mois/$annee';
          expect(jours.length % 7, 0, reason: reason());
          expect(jours.length, inInclusiveRange(28, 42), reason: reason());
          expect(jours.first.weekday, DateTime.monday, reason: reason());
          expect(jours.last.weekday, DateTime.sunday, reason: reason());
          expect(jours.contains(DateTime(annee, mois, 1)), isTrue, reason: reason());
          expect(jours.contains(dernierJourDuMois(annee, mois)), isTrue, reason: reason());
          for (int i = 0; i + 1 < jours.length; i++) {
            expect(jours[i + 1], DateTime(jours[i].year, jours[i].month, jours[i].day + 1), reason: reason());
          }
        }
      }
    });
  });

  group('ordre et regroupement', () {
    test('un jour : d’abord « toute la journée », puis par heure, puis par type, puis par titre', () {
      final DateTime jour = DateTime(2026, 11, 23);
      final EntreeAgenda atelier = _entree('Atelier', DateTime(2026, 11, 23, 14), type: TypeEntreeAgenda.cours);
      final EntreeAgenda rendezVous = _entree('Rendez-vous', DateTime(2026, 11, 23, 9));
      final EntreeAgenda declaration = _entree(
        titreDeclaration,
        jour,
        type: TypeEntreeAgenda.declaration,
        journeeEntiere: true,
      );
      final EntreeAgenda devis = _entree('Fin du devis', jour, type: TypeEntreeAgenda.devis, journeeEntiere: true);
      final EntreeAgenda marche = _entree('Marché', jour, journeeEntiere: true);
      final EntreeAgenda autreMarche = _entree('Brocante', jour, journeeEntiere: true);

      final Map<DateTime, List<EntreeAgenda>> parJour = regrouperParJour(<EntreeAgenda>[
        atelier,
        marche,
        rendezVous,
        declaration,
        autreMarche,
        devis,
      ]);

      expect(parJour.keys, <DateTime>[jour]);
      // Toute la journée : par type (cours, devis, déclaration, événement), puis par titre ; puis 9 h, puis 14 h.
      expect(parJour[jour], <EntreeAgenda>[devis, declaration, autreMarche, marche, rendezVous, atelier]);
    });

    test('les entrées de jours différents sont rangées chacune à leur jour', () {
      final EntreeAgenda a = _entree('A', DateTime(2026, 11, 23, 9));
      final EntreeAgenda b = _entree('B', DateTime(2026, 11, 24, 9));
      final EntreeAgenda c = _entree('C', DateTime(2026, 11, 23, 18));

      final Map<DateTime, List<EntreeAgenda>> parJour = regrouperParJour(<EntreeAgenda>[b, c, a]);

      expect(parJour[DateTime(2026, 11, 23)], <EntreeAgenda>[a, c]);
      expect(parJour[DateTime(2026, 11, 24)], <EntreeAgenda>[b]);
      expect(parJour[DateTime(2026, 11, 25)], isNull);
    });
  });

  group('filtres', () {
    test('au départ, tout est affiché', () {
      const FiltresAgenda filtres = FiltresAgenda();
      for (final TypeEntreeAgenda type in TypeEntreeAgenda.values) {
        expect(filtres.accepte(type), isTrue, reason: type.name);
      }
    });

    test('masquer ou afficher un type ne change que celui-là', () {
      for (final TypeEntreeAgenda type in TypeEntreeAgenda.values) {
        final FiltresAgenda masque = const FiltresAgenda().avec(type, affiche: false);
        for (final TypeEntreeAgenda autre in TypeEntreeAgenda.values) {
          expect(masque.accepte(autre), autre != type, reason: '${type.name} masqué, ${autre.name}');
        }
        expect(masque.avec(type, affiche: true), const FiltresAgenda());
      }
    });

    test('deux filtres identiques sont égaux', () {
      expect(const FiltresAgenda(devis: false), const FiltresAgenda(devis: false));
      expect(const FiltresAgenda(devis: false).hashCode, const FiltresAgenda(devis: false).hashCode);
      expect(const FiltresAgenda(devis: false), isNot(const FiltresAgenda(cours: false)));
    });

    test('chaque type a son nom, tel qu’il est écrit sur l’écran', () {
      expect(TypeEntreeAgenda.values.map((TypeEntreeAgenda t) => t.libelle), <String>[
        'Cours',
        'Devis',
        'Déclaration',
        'Mes événements',
      ]);
    });
  });

  group('déclaration des recettes : le dernier jour de chaque mois', () {
    test('sur deux mois, un jour par mois', () {
      final List<EntreeAgenda> echeances = echeancesDeclaration(DateTime(2026, 11, 1), DateTime(2027, 1, 1));
      expect(echeances.map((EntreeAgenda e) => e.debut), <DateTime>[DateTime(2026, 11, 30), DateTime(2026, 12, 31)]);
      for (final EntreeAgenda e in echeances) {
        expect(e.type, TypeEntreeAgenda.declaration);
        expect(e.titre, titreDeclaration);
        expect(e.journeeEntiere, isTrue);
        expect(e.identifiant, isNull);
      }
    });

    test('la grille de novembre 2026 montre aussi le 31 octobre', () {
      final List<DateTime> jours = joursAffiches(2026, 11);
      final List<EntreeAgenda> echeances = echeancesDeclaration(jours.first, DateTime(jours.last.year, jours.last.month, jours.last.day + 1));
      expect(echeances.map((EntreeAgenda e) => e.debut), <DateTime>[DateTime(2026, 10, 31), DateTime(2026, 11, 30)]);
    });

    test('le début de l’intervalle est compris, la fin est exclue', () {
      expect(echeancesDeclaration(DateTime(2026, 11, 30), DateTime(2026, 12, 1)).map((EntreeAgenda e) => e.debut), <DateTime>[
        DateTime(2026, 11, 30),
      ]);
      expect(echeancesDeclaration(DateTime(2026, 11, 1), DateTime(2026, 11, 30)), isEmpty);
      expect(echeancesDeclaration(DateTime(2026, 12, 1), DateTime(2026, 12, 31)), isEmpty);
    });

    test('février : le 28, ou le 29 en année bissextile', () {
      expect(echeancesDeclaration(DateTime(2027, 2, 1), DateTime(2027, 3, 1)).single.debut, DateTime(2027, 2, 28));
      expect(echeancesDeclaration(DateTime(2028, 2, 1), DateTime(2028, 3, 1)).single.debut, DateTime(2028, 2, 29));
    });

    test('un intervalle vide ne donne rien', () {
      expect(echeancesDeclaration(DateTime(2026, 11, 10), DateTime(2026, 11, 10)), isEmpty);
    });
  });

  group('liens vers Google Agenda', () {
    test('« Ouvrir Google Agenda » : l’accueil de Google Agenda, ou le mois du jour choisi', () {
      expect(lienOuvrirGoogleAgenda().toString(), 'https://calendar.google.com/calendar/r');
      expect(
        lienOuvrirGoogleAgenda(jour: DateTime(2026, 11, 23)).toString(),
        'https://calendar.google.com/calendar/r/month/2026/11/23',
      );
    });

    test('le compte Google à utiliser, quand on le connaît, est transmis ; vide, il est ignoré', () {
      final Uri avec = lienOuvrirGoogleAgenda(compte: 'stef@exemple.fr');
      expect(avec.queryParameters, <String, String>{'authuser': 'stef@exemple.fr'});
      expect(lienOuvrirGoogleAgenda(compte: '  ').hasQuery, isFalse);
      expect(lienOuvrirGoogleAgenda(compte: null).hasQuery, isFalse);
    });

    test('toutes les adresses sont en https, sur calendar.google.com', () {
      final EntreeAgenda e = _entree('Marché', DateTime(2026, 12, 12), journeeEntiere: true);
      for (final Uri adresse in <Uri>[lienOuvrirGoogleAgenda(), lienAjouterAGoogleAgenda(e)]) {
        expect(adresse.scheme, 'https');
        expect(adresse.host, 'calendar.google.com');
      }
    });

    test('« Ajouter à Google Agenda » : un événement sur toute la journée (la fin de Google est le lendemain)', () {
      final Uri adresse = lienAjouterAGoogleAgenda(
        _entree('Marché de Noël', DateTime(2026, 12, 12), journeeEntiere: true, detail: 'Prévoir la nappe', lieu: 'Place du village'),
      );
      expect(adresse.path, '/calendar/render');
      expect(adresse.queryParameters, <String, String>{
        'action': 'TEMPLATE',
        'text': 'Marché de Noël',
        'dates': '20261212/20261213',
        'details': 'Prévoir la nappe',
        'location': 'Place du village',
      });
    });

    test('le dernier jour de l’année finit le 1er janvier', () {
      final Uri adresse = lienAjouterAGoogleAgenda(_entree('Bilan', DateTime(2026, 12, 31), journeeEntiere: true));
      expect(adresse.queryParameters['dates'], '20261231/20270101');
    });

    test('sans précision ni lieu, ces champs ne sont pas envoyés', () {
      final Uri adresse = lienAjouterAGoogleAgenda(
        _entree('Marché', DateTime(2026, 12, 12), journeeEntiere: true, detail: '  ', lieu: ''),
      );
      expect(adresse.queryParameters.keys, <String>['action', 'text', 'dates']);
    });

    test('un événement à heure fixe est écrit en heure universelle (UTC), avec sa fin', () {
      final DateTime debut = DateTime(2026, 12, 12, 9, 30);
      final DateTime fin = DateTime(2026, 12, 12, 11);
      final Uri adresse = lienAjouterAGoogleAgenda(_entree('Atelier', debut, fin: fin, type: TypeEntreeAgenda.cours));

      final List<String> dates = adresse.queryParameters['dates']!.split('/');
      expect(dates[0], matches(RegExp(r'^\d{8}T\d{6}Z$')));
      expect(dates[1], matches(RegExp(r'^\d{8}T\d{6}Z$')));
      expect(DateTime.parse(dates[0]), debut.toUtc());
      expect(DateTime.parse(dates[1]), fin.toUtc());
    });

    test('un événement à heure fixe sans heure de fin dure une heure', () {
      final DateTime debut = DateTime(2026, 12, 12, 14);
      final Uri adresse = lienAjouterAGoogleAgenda(_entree('Rendez-vous', debut));

      final List<String> dates = adresse.queryParameters['dates']!.split('/');
      expect(DateTime.parse(dates[0]), debut.toUtc());
      expect(DateTime.parse(dates[1]), debut.add(const Duration(hours: 1)).toUtc());
    });

    test('la déclaration des recettes revient chaque mois, le dernier jour', () {
      final Uri adresse = lienAjouterAGoogleAgenda(echeancesDeclaration(DateTime(2026, 11, 1), DateTime(2026, 12, 1)).single);
      expect(adresse.queryParameters['text'], titreDeclaration);
      expect(adresse.queryParameters['dates'], '20261130/20261201');
      expect(adresse.queryParameters['recur'], 'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1');
    });

    test('un cours, un devis ou un événement ne se répètent pas', () {
      for (final TypeEntreeAgenda type in <TypeEntreeAgenda>[
        TypeEntreeAgenda.cours,
        TypeEntreeAgenda.devis,
        TypeEntreeAgenda.evenement,
      ]) {
        final Uri adresse = lienAjouterAGoogleAgenda(_entree('Un', DateTime(2026, 12, 12), journeeEntiere: true, type: type));
        expect(adresse.queryParameters.containsKey('recur'), isFalse, reason: type.name);
      }
    });

    test('le compte Google est transmis aussi pour l’ajout', () {
      final Uri adresse = lienAjouterAGoogleAgenda(
        _entree('Marché', DateTime(2026, 12, 12), journeeEntiere: true),
        compte: 'stef@exemple.fr',
      );
      expect(adresse.queryParameters['authuser'], 'stef@exemple.fr');
    });
  });
}
