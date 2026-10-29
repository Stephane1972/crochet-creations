import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:crochet_creations/domain/regles_cours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('durée et fin d’un cours', () {
    test('la fin est le début plus la durée', () {
      expect(finDuCours(DateTime(2026, 11, 14, 14), 150), DateTime(2026, 11, 14, 16, 30));
    });

    test('un cours est terminé une fois sa fin passée', () {
      final DateTime debut = DateTime(2026, 11, 14, 14);
      expect(coursTermine(debut, 120, DateTime(2026, 11, 14, 15, 59)), isFalse);
      expect(coursTermine(debut, 120, DateTime(2026, 11, 14, 16, 1)), isTrue);
      expect(coursTermine(debut, 120, DateTime(2026, 11, 13)), isFalse);
    });
  });

  group('places', () {
    test('places restantes : jamais négatives', () {
      expect(placesRestantes(places: 6, confirmes: 4), 2);
      expect(placesRestantes(places: 6, confirmes: 6), 0);
      expect(placesRestantes(places: 4, confirmes: 6), 0);
    });

    test('une inscription est confirmée s’il reste une place, sinon en liste d’attente', () {
      expect(statutNouvelleInscription(1), StatutInscription.confirmee);
      expect(statutNouvelleInscription(0), StatutInscription.listeAttente);
    });
  });

  group('liste d’attente', () {
    final DateTime t = DateTime(2026, 11, 1, 10);

    test('dans l’ordre d’arrivée, puis de création', () {
      final List<EnAttente> ordre = ordreAttente(<EnAttente>[
        EnAttente(inscriptionId: 7, dateInscription: t.add(const Duration(hours: 2))),
        EnAttente(inscriptionId: 9, dateInscription: t),
        EnAttente(inscriptionId: 8, dateInscription: t),
      ]);
      expect(ordre.map((EnAttente e) => e.inscriptionId), <int>[8, 9, 7]);
    });

    test('le premier en attente, ou personne', () {
      expect(premierEnAttente(const <EnAttente>[]), isNull);
      expect(
        premierEnAttente(<EnAttente>[
          EnAttente(inscriptionId: 2, dateInscription: t.add(const Duration(days: 1))),
          EnAttente(inscriptionId: 5, dateInscription: t),
        ]),
        5,
      );
    });
  });

  group('verifierCours', () {
    void valide({String titre = 'Initiation', int duree = 120, int prix = 4500, int places = 6, int confirmes = 0}) =>
        verifierCours(titre: titre, dureeMinutes: duree, prixCentimes: prix, places: places, confirmes: confirmes);

    String? refus(void Function() action) {
      try {
        action();
        return null;
      } on DonneeInvalide catch (e) {
        return e.message;
      }
    }

    test('accepte un cours correct, gratuit ou non', () {
      expect(refus(() => valide()), isNull);
      expect(refus(() => valide(prix: 0)), isNull);
      expect(refus(() => valide(places: 1)), isNull);
    });

    test('refuse un titre vide, une durée nulle, un prix négatif, aucune place', () {
      expect(refus(() => valide(titre: '   ')), 'Indiquez le titre du cours.');
      expect(refus(() => valide(duree: 0)), 'La durée doit être d’au moins 1 minute.');
      expect(refus(() => valide(prix: -1)), 'Le prix ne peut pas être négatif.');
      expect(refus(() => valide(places: 0)), 'Il faut au moins une place.');
    });

    test('refuse moins de places que de personnes confirmées', () {
      expect(
        refus(() => valide(places: 3, confirmes: 4)),
        'Ce cours compte déjà 4 personnes confirmées : le nombre de places ne peut pas être plus petit.',
      );
      expect(refus(() => valide(places: 4, confirmes: 4)), isNull);
      expect(refus(() => valide(places: 1, confirmes: 1)), isNull);
    });
  });

  group('refusInscription', () {
    test('un cours prévu et non archivé accepte les inscriptions', () {
      expect(refusInscription(statut: StatutCours.planifie, archive: false), isNull);
    });

    test('un cours annulé ou archivé les refuse, avec un message', () {
      expect(
        refusInscription(statut: StatutCours.annule, archive: false),
        'Ce cours est annulé : on ne peut plus y inscrire personne.',
      );
      expect(
        refusInscription(statut: StatutCours.planifie, archive: true),
        'Ce cours est archivé : restaurez-le pour y inscrire quelqu’un.',
      );
    });
  });

  group('refusConfirmation', () {
    String? refus({
      StatutInscription inscription = StatutInscription.listeAttente,
      StatutCours cours = StatutCours.planifie,
      bool archive = false,
      int libres = 1,
      bool premiere = true,
    }) => refusConfirmation(
      statutInscription: inscription,
      statutCours: cours,
      archive: archive,
      placesLibres: libres,
      estPremiere: premiere,
    );

    test('possible : en attente, première, une place libre', () {
      expect(refus(), isNull);
    });

    test('refuse une personne qui n’est pas en attente', () {
      expect(refus(inscription: StatutInscription.confirmee), 'Cette personne n’est pas sur la liste d’attente.');
      expect(refus(inscription: StatutInscription.annulee), 'Cette personne n’est pas sur la liste d’attente.');
    });

    test('refuse sans place libre', () {
      expect(refus(libres: 0), 'Le cours est complet : aucune place n’est libre pour le moment.');
    });

    test('refuse une personne qui n’est pas la première', () {
      expect(
        refus(premiere: false),
        'Seule la première personne de la liste d’attente peut être confirmée.',
      );
    });

    test('refuse pour un cours annulé ou archivé', () {
      expect(refus(cours: StatutCours.annule), contains('annulé'));
      expect(refus(archive: true), contains('archivé'));
    });
  });

  test('peutAnnulerInscription : tout sauf une inscription déjà annulée', () {
    expect(peutAnnulerInscription(StatutInscription.confirmee), isTrue);
    expect(peutAnnulerInscription(StatutInscription.listeAttente), isTrue);
    expect(peutAnnulerInscription(StatutInscription.annulee), isFalse);
  });

  group('refusArchivage', () {
    test('un cours terminé ou annulé peut être archivé', () {
      expect(refusArchivage(statut: StatutCours.planifie, termine: true), isNull);
      expect(refusArchivage(statut: StatutCours.annule, termine: false), isNull);
    });

    test('un cours à venir et maintenu ne s’archive pas', () {
      expect(
        refusArchivage(statut: StatutCours.planifie, termine: false),
        'Seul un cours terminé ou annulé peut être archivé.',
      );
    });
  });
}
