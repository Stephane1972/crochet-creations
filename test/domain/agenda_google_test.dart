import 'package:crochet_creations/domain/agenda.dart';
import 'package:crochet_creations/domain/agenda_google.dart';
import 'package:flutter_test/flutter_test.dart';

EntreeAgenda _entree(
  String titre,
  DateTime debut, {
  TypeEntreeAgenda type = TypeEntreeAgenda.evenement,
  bool journeeEntiere = false,
  DateTime? fin,
  String? detail,
  String? lieu,
  int? identifiant = 1,
}) => EntreeAgenda(
  type: type,
  titre: titre,
  debut: debut,
  fin: fin,
  journeeEntiere: journeeEntiere,
  detail: detail,
  lieu: lieu,
  identifiant: identifiant,
);

EvenementGoogle _evt(
  String id, {
  String titre = 'Atelier crochet',
  TypeEntreeAgenda? type = TypeEntreeAgenda.cours,
  DateTime? debut,
  DateTime? fin,
  bool journeeEntiere = false,
  String description = '',
  String lieu = '',
}) {
  final DateTime d = debut ?? DateTime.utc(2026, 12, 5, 13, 30);
  return EvenementGoogle(
    id: id,
    titre: titre,
    debut: d,
    fin: fin ?? d.add(const Duration(hours: 2)),
    journeeEntiere: journeeEntiere,
    description: description,
    lieu: lieu,
    type: type,
  );
}

void main() {
  group('la période synchronisée', () {
    test('du premier jour du mois précédent au premier jour du mois qui suit les 12 mois à venir', () {
      expect(moisPassesSynchronises, 1);
      expect(moisFutursSynchronises, 12);
      final ({DateTime debut, DateTime fin}) f = fenetreSynchro(DateTime(2026, 11, 25, 10));
      expect(f.debut, DateTime(2026, 10, 1));
      expect(f.fin, DateTime(2027, 12, 1)); // novembre 2027 compris
    });

    test('en janvier, le mois précédent est décembre de l’année d’avant', () {
      final ({DateTime debut, DateTime fin}) f = fenetreSynchro(DateTime(2027, 1, 15));
      expect(f.debut, DateTime(2026, 12, 1));
      expect(f.fin, DateTime(2028, 2, 1));
    });
  });

  group('les identifiants', () {
    test('cours, devis, événement : une lettre et le numéro ; déclaration : la date', () {
      expect(identifiantEvenementGoogle(_entree('x', DateTime(2026, 12, 5), type: TypeEntreeAgenda.cours, identifiant: 12)), 'ptitc12');
      expect(identifiantEvenementGoogle(_entree('x', DateTime(2026, 12, 5), type: TypeEntreeAgenda.devis, identifiant: 7)), 'ptitq7');
      expect(identifiantEvenementGoogle(_entree('x', DateTime(2026, 12, 5), identifiant: 3)), 'ptite3');
      expect(
        identifiantEvenementGoogle(
          _entree('x', DateTime(2026, 11, 30), type: TypeEntreeAgenda.declaration, journeeEntiere: true, identifiant: null),
        ),
        'ptitd20261130',
      );
      expect(
        identifiantEvenementGoogle(_entree('x', DateTime(2027, 1, 5), type: TypeEntreeAgenda.declaration, identifiant: null)),
        'ptitd20270105',
      );
    });

    test('un cours, un devis ou un événement sans numéro n’a pas d’identifiant', () {
      for (final TypeEntreeAgenda type in <TypeEntreeAgenda>[TypeEntreeAgenda.cours, TypeEntreeAgenda.devis, TypeEntreeAgenda.evenement]) {
        expect(identifiantEvenementGoogle(_entree('x', DateTime(2026, 12, 5), type: type, identifiant: null)), isNull, reason: '$type');
      }
    });

    test('Google n’accepte que a à v et 0 à 9, 5 caractères au moins : tous les identifiants produits le respectent', () {
      final RegExp admis = RegExp(r'^[a-v0-9]{5,1024}$');
      for (final int numero in <int>[1, 9, 10, 12345, 2000000]) {
        for (final TypeEntreeAgenda type in <TypeEntreeAgenda>[TypeEntreeAgenda.cours, TypeEntreeAgenda.devis, TypeEntreeAgenda.evenement]) {
          final String? id = identifiantEvenementGoogle(_entree('x', DateTime(2026, 12, 5), type: type, identifiant: numero));
          expect(id, matches(admis), reason: '$type $numero');
        }
      }
      expect(identifiantEvenementGoogle(_entree('x', DateTime(2026, 1, 1), type: TypeEntreeAgenda.declaration)), matches(admis));
    });

    test('un cours, un devis et un événement de même numéro n’ont pas le même identifiant', () {
      final Set<String?> ids = <String?>{
        for (final TypeEntreeAgenda type in TypeEntreeAgenda.values)
          identifiantEvenementGoogle(_entree('x', DateTime(2026, 12, 5), type: type, identifiant: 4)),
      };
      expect(ids, hasLength(TypeEntreeAgenda.values.length));
    });

    test('le même élément garde le même identifiant, même s’il change de titre ou de date', () {
      final String? avant = identifiantEvenementGoogle(_entree('Ancien titre', DateTime(2026, 12, 5), type: TypeEntreeAgenda.cours, identifiant: 9));
      final String? apres = identifiantEvenementGoogle(_entree('Nouveau titre', DateTime(2027, 2, 1), type: TypeEntreeAgenda.cours, identifiant: 9));
      expect(avant, apres);
    });
  });

  group('l’événement Google d’une entrée du calendrier', () {
    test('toute la journée : la date, et la fin (exclue) est le lendemain', () {
      final EvenementGoogle e = evenementDepuisEntree(
        _entree('Marché de Noël', DateTime(2026, 12, 12), journeeEntiere: true, identifiant: 4),
      )!;

      expect(e.id, 'ptite4');
      expect(e.journeeEntiere, isTrue);
      expect(e.debut, DateTime.utc(2026, 12, 12));
      expect(e.fin, DateTime.utc(2026, 12, 13));
      expect(e.type, TypeEntreeAgenda.evenement);
    });

    test('toute la journée, le 31 décembre : la fin est le 1er janvier suivant', () {
      final EvenementGoogle e = evenementDepuisEntree(
        _entree('Inventaire', DateTime(2026, 12, 31), journeeEntiere: true, identifiant: 5),
      )!;

      expect(e.debut, DateTime.utc(2026, 12, 31));
      expect(e.fin, DateTime.utc(2027, 1, 1));
    });

    test('à heure fixe : l’instant exact, début et fin, avec le lieu', () {
      final DateTime debut = DateTime(2026, 12, 5, 14, 30);
      final DateTime fin = debut.add(const Duration(hours: 2));
      final EvenementGoogle e = evenementDepuisEntree(
        _entree('Atelier crochet', debut, type: TypeEntreeAgenda.cours, fin: fin, lieu: '  Salle des fêtes ', identifiant: 12),
      )!;

      expect(e.id, 'ptitc12');
      expect(e.journeeEntiere, isFalse);
      expect(e.debut.isUtc, isTrue);
      expect(e.debut.isAtSameMomentAs(debut), isTrue);
      expect(e.fin.isAtSameMomentAs(fin), isTrue);
      expect(e.lieu, 'Salle des fêtes');
    });

    test('à heure fixe sans fin, ou avec une fin avant le début : une heure', () {
      final DateTime debut = DateTime(2026, 12, 5, 14, 30);
      final EvenementGoogle sansFin = evenementDepuisEntree(_entree('Rendez-vous', debut, identifiant: 1))!;
      final EvenementGoogle finAvant = evenementDepuisEntree(
        _entree('Rendez-vous', debut, fin: debut.subtract(const Duration(minutes: 30)), identifiant: 2),
      )!;
      final EvenementGoogle finEgale = evenementDepuisEntree(_entree('Rendez-vous', debut, fin: debut, identifiant: 3))!;

      for (final EvenementGoogle e in <EvenementGoogle>[sansFin, finAvant, finEgale]) {
        expect(e.fin.difference(e.debut), const Duration(hours: 1), reason: e.id);
      }
    });

    test('la description : la précision, puis la phrase de l’application ; sans précision, la phrase seule', () {
      final EvenementGoogle avec = evenementDepuisEntree(
        _entree('Fin de validité du devis D-12', DateTime(2026, 12, 20), type: TypeEntreeAgenda.devis, journeeEntiere: true, detail: ' Marie Dupont ', identifiant: 7),
      )!;
      final EvenementGoogle sans = evenementDepuisEntree(_entree('Rendez-vous', DateTime(2026, 12, 5, 9), identifiant: 1))!;
      final EvenementGoogle vide = evenementDepuisEntree(_entree('Rendez-vous', DateTime(2026, 12, 5, 9), detail: '   ', identifiant: 2))!;

      expect(avec.description, 'Marie Dupont\n\n$noteAgendaGoogle');
      expect(sans.description, noteAgendaGoogle);
      expect(vide.description, noteAgendaGoogle);
      expect(noteAgendaGoogle, contains('remplacée à la prochaine synchronisation'));
    });

    test('le titre est nettoyé ; un titre vide devient « (sans titre) »', () {
      expect(evenementDepuisEntree(_entree('  Marché  ', DateTime(2026, 12, 5, 9), identifiant: 1))!.titre, 'Marché');
      expect(evenementDepuisEntree(_entree('   ', DateTime(2026, 12, 5, 9), identifiant: 2))!.titre, titreSansNom);
    });

    test('une échéance de déclaration réelle : toute la journée, à sa date, de type « déclaration »', () {
      final List<EntreeAgenda> echeances = echeancesDeclaration(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
      final EvenementGoogle e = evenementDepuisEntree(echeances.single)!;

      expect(e.id, 'ptitd20261130');
      expect(e.titre, titreDeclaration);
      expect(e.journeeEntiere, isTrue);
      expect(e.debut, DateTime.utc(2026, 11, 30));
      expect(e.fin, DateTime.utc(2026, 12, 1));
      expect(e.type, TypeEntreeAgenda.declaration);
    });

    test('une entrée sans numéro n’a pas d’événement', () {
      expect(evenementDepuisEntree(_entree('x', DateTime(2026, 12, 5), identifiant: null)), isNull);
    });

    test('evenementsDepuisEntrees : celles sans identifiant sont ignorées, un doublon ne compte qu’une fois', () {
      final List<EvenementGoogle> liste = evenementsDepuisEntrees(<EntreeAgenda>[
        _entree('Premier', DateTime(2026, 12, 5, 9), identifiant: 1),
        _entree('Doublon', DateTime(2026, 12, 6, 9), identifiant: 1),
        _entree('Sans numéro', DateTime(2026, 12, 7, 9), identifiant: null),
        _entree('Autre', DateTime(2026, 12, 8, 9), identifiant: 2),
      ]);

      expect(liste.map((EvenementGoogle e) => e.titre), <String>['Premier', 'Autre']);
    });
  });

  group('EvenementGoogle', () {
    test('annule() ajoute « [Annulé] » au titre, une seule fois', () {
      final EvenementGoogle e = _evt('ptitc1', titre: 'Atelier crochet');

      expect(e.estAnnule, isFalse);
      expect(e.annule().titre, '[Annulé] Atelier crochet');
      expect(e.annule().estAnnule, isTrue);
      expect(e.annule().annule().titre, '[Annulé] Atelier crochet');
      // Tout le reste est conservé.
      expect(e.annule().id, e.id);
      expect(e.annule().debut, e.debut);
      expect(e.annule().lieu, e.lieu);
      expect(e.annule().type, e.type);
    });

    test('le préfixe est celui annoncé à la personne', () {
      expect(prefixeAnnule, '[Annulé] ');
    });

    test('memeContenu : identique, ou une seule différence à la fois', () {
      final EvenementGoogle base = _evt('ptitc1', description: 'Détail', lieu: 'Salle A');

      expect(base.memeContenu(_evt('ptitc1', description: 'Détail', lieu: 'Salle A')), isTrue);
      expect(base.memeContenu(_evt('ptitc2', description: 'Détail', lieu: 'Salle A')), isFalse);
      expect(base.memeContenu(_evt('ptitc1', titre: 'Autre', description: 'Détail', lieu: 'Salle A')), isFalse);
      expect(base.memeContenu(_evt('ptitc1', description: 'Autre', lieu: 'Salle A')), isFalse);
      expect(base.memeContenu(_evt('ptitc1', description: 'Détail', lieu: 'Salle B')), isFalse);
      expect(base.memeContenu(_evt('ptitc1', description: 'Détail', lieu: 'Salle A', debut: DateTime.utc(2026, 12, 6))), isFalse);
      expect(
        base.memeContenu(_evt('ptitc1', description: 'Détail', lieu: 'Salle A', fin: DateTime.utc(2026, 12, 5, 20))),
        isFalse,
      );
      expect(base.memeContenu(_evt('ptitc1', description: 'Détail', lieu: 'Salle A', journeeEntiere: true)), isFalse);
    });

    test('memeContenu ignore les espaces autour, le type de saut de ligne et le type d’élément', () {
      final EvenementGoogle base = _evt('ptitc1', titre: 'Atelier', description: 'Ligne 1\n\nLigne 2', lieu: 'Salle A');

      expect(
        base.memeContenu(_evt('ptitc1', titre: ' Atelier ', description: 'Ligne 1\r\n\r\nLigne 2\n', lieu: ' Salle A ')),
        isTrue,
      );
      // Le type vient de Google : une propriété absente ne doit pas faire réécrire l'événement.
      expect(base.memeContenu(_evt('ptitc1', titre: 'Atelier', description: 'Ligne 1\n\nLigne 2', lieu: 'Salle A', type: null)), isTrue);
    });

    test('memeContenu compare des instants, pas des fuseaux : 14 h 30 à Paris est 13 h 30 UTC', () {
      final EvenementGoogle utc = _evt('ptitc1', debut: DateTime.utc(2026, 12, 5, 13, 30), fin: DateTime.utc(2026, 12, 5, 15, 30));
      final EvenementGoogle decale = _evt(
        'ptitc1',
        debut: DateTime.parse('2026-12-05T14:30:00+01:00'),
        fin: DateTime.parse('2026-12-05T16:30:00+01:00'),
      );

      expect(utc.memeContenu(decale), isTrue);
    });
  });

  group('ce qu’il faut faire', () {
    test('rien de part ni d’autre : rien à faire', () {
      final PlanSynchro plan = planifierSynchro(souhaites: const <EvenementGoogle>[], existants: const <EvenementGoogle>[]);

      expect(plan.vide, isTrue);
      expect(plan.total, 0);
      expect(plan.inchanges, 0);
      expect(plan.dejaAnnules, 0);
    });

    test('un événement qui n’existe pas encore : à créer', () {
      final EvenementGoogle e = _evt('ptitc1');
      final PlanSynchro plan = planifierSynchro(souhaites: <EvenementGoogle>[e], existants: const <EvenementGoogle>[]);

      expect(plan.aCreer, <EvenementGoogle>[e]);
      expect(plan.aRemplacer, isEmpty);
      expect(plan.aAnnuler, isEmpty);
      expect(plan.total, 1);
    });

    test('un événement déjà à jour : rien, il est compté comme inchangé', () {
      final PlanSynchro plan = planifierSynchro(
        souhaites: <EvenementGoogle>[_evt('ptitc1')],
        existants: <EvenementGoogle>[_evt('ptitc1')],
      );

      expect(plan.vide, isTrue);
      expect(plan.inchanges, 1);
    });

    test('un événement dont la date, le titre ou le lieu a changé : à remplacer, par la version de l’application', () {
      final EvenementGoogle voulu = _evt('ptitc1', titre: 'Atelier du samedi', lieu: 'Salle B', debut: DateTime.utc(2026, 12, 12, 9));
      final PlanSynchro plan = planifierSynchro(
        souhaites: <EvenementGoogle>[voulu],
        existants: <EvenementGoogle>[_evt('ptitc1', titre: 'Atelier', lieu: 'Salle A')],
      );

      expect(plan.aRemplacer, <EvenementGoogle>[voulu]);
      expect(plan.aCreer, isEmpty);
      expect(plan.aAnnuler, isEmpty);
      expect(plan.inchanges, 0);
    });

    test('un événement modifié à la main dans Google Agenda est remis comme dans l’application', () {
      final EvenementGoogle voulu = _evt('ptitc1', titre: 'Atelier crochet');
      final PlanSynchro plan = planifierSynchro(
        souhaites: <EvenementGoogle>[voulu],
        existants: <EvenementGoogle>[_evt('ptitc1', titre: 'Atelier crochet (déplacé)', debut: DateTime.utc(2026, 12, 9, 8))],
      );

      expect(plan.aRemplacer, <EvenementGoogle>[voulu]);
    });

    test('un élément qui revient après avoir été marqué « [Annulé] » : l’événement est remplacé, il redevient normal', () {
      final EvenementGoogle voulu = _evt('ptitc1', titre: 'Atelier crochet');
      final PlanSynchro plan = planifierSynchro(
        souhaites: <EvenementGoogle>[voulu],
        existants: <EvenementGoogle>[voulu.annule()],
      );

      expect(plan.aRemplacer, <EvenementGoogle>[voulu]);
      expect(plan.aRemplacer.single.estAnnule, isFalse);
    });

    test('un élément disparu de l’application : l’événement est marqué « [Annulé] », jamais supprimé', () {
      final EvenementGoogle existant = _evt('ptitc1', titre: 'Atelier crochet');
      final PlanSynchro plan = planifierSynchro(souhaites: const <EvenementGoogle>[], existants: <EvenementGoogle>[existant]);

      expect(plan.aAnnuler, hasLength(1));
      expect(plan.aAnnuler.single.id, 'ptitc1');
      expect(plan.aAnnuler.single.titre, '[Annulé] Atelier crochet');
      expect(plan.aCreer, isEmpty);
      expect(plan.aRemplacer, isEmpty);
    });

    test('un événement déjà marqué « [Annulé] » dont l’élément n’est pas revenu : on n’y touche plus', () {
      final PlanSynchro plan = planifierSynchro(
        souhaites: const <EvenementGoogle>[],
        existants: <EvenementGoogle>[_evt('ptitc1').annule()],
      );

      expect(plan.vide, isTrue);
      expect(plan.dejaAnnules, 1);
    });

    test('un type masqué dans les filtres n’est pas touché : ses événements déjà envoyés restent tels quels', () {
      final PlanSynchro plan = planifierSynchro(
        souhaites: const <EvenementGoogle>[],
        existants: <EvenementGoogle>[
          _evt('ptitc1'),
          _evt('ptitq2', type: TypeEntreeAgenda.devis, journeeEntiere: true),
          _evt('ptite3', type: TypeEntreeAgenda.evenement),
          _evt('ptitd20261130', type: TypeEntreeAgenda.declaration, journeeEntiere: true),
        ],
        filtres: const FiltresAgenda(cours: false, devis: true, declaration: false, evenements: true),
      );

      // Les cours et la déclaration sont masqués : intacts. Le devis et l'événement ne sont plus demandés : marqués.
      expect(plan.aAnnuler.map((EvenementGoogle e) => e.id), unorderedEquals(<String>['ptitq2', 'ptite3']));
    });

    test('un événement de type inconnu qui n’est pas demandé n’est pas touché', () {
      final PlanSynchro plan = planifierSynchro(
        souhaites: const <EvenementGoogle>[],
        existants: <EvenementGoogle>[_evt('ptitc1', type: null)],
      );

      expect(plan.vide, isTrue);
      expect(plan.dejaAnnules, 0);
    });

    test('un événement de type inconnu qui est demandé est tout de même mis à jour', () {
      final EvenementGoogle voulu = _evt('ptitc1', titre: 'Nouveau titre');
      final PlanSynchro plan = planifierSynchro(
        souhaites: <EvenementGoogle>[voulu],
        existants: <EvenementGoogle>[_evt('ptitc1', type: null)],
      );

      expect(plan.aRemplacer, <EvenementGoogle>[voulu]);
    });

    test('un cas mélangé : chaque événement est rangé au bon endroit, dans l’ordre des dates', () {
      final EvenementGoogle neuf = _evt('ptitc10', debut: DateTime.utc(2026, 12, 20, 9));
      final EvenementGoogle neufPlusTot = _evt('ptitc11', debut: DateTime.utc(2026, 12, 2, 9));
      final EvenementGoogle inchange = _evt('ptitc1');
      final EvenementGoogle voulu2 = _evt('ptitc2', titre: 'Changé');
      final PlanSynchro plan = planifierSynchro(
        souhaites: <EvenementGoogle>[neuf, neufPlusTot, inchange, voulu2],
        existants: <EvenementGoogle>[inchange, _evt('ptitc2', titre: 'Avant'), _evt('ptitc3'), _evt('ptitc4').annule()],
      );

      expect(plan.aCreer.map((EvenementGoogle e) => e.id), <String>['ptitc11', 'ptitc10']);
      expect(plan.aRemplacer.map((EvenementGoogle e) => e.id), <String>['ptitc2']);
      expect(plan.aAnnuler.map((EvenementGoogle e) => e.id), <String>['ptitc3']);
      expect(plan.inchanges, 1);
      expect(plan.dejaAnnules, 1);
      expect(plan.total, 4);
    });

    test('une fois le plan appliqué, une nouvelle synchronisation n’a plus rien à faire', () {
      final List<EvenementGoogle> souhaites = <EvenementGoogle>[
        _evt('ptitc1'),
        _evt('ptitc2', titre: 'Changé'),
        _evt('ptitc10', debut: DateTime.utc(2026, 12, 20, 9)),
      ];
      final List<EvenementGoogle> existants = <EvenementGoogle>[_evt('ptitc2', titre: 'Avant'), _evt('ptitc3'), _evt('ptitc4').annule()];

      final PlanSynchro plan = planifierSynchro(souhaites: souhaites, existants: existants);
      final Map<String, EvenementGoogle> apres = <String, EvenementGoogle>{for (final EvenementGoogle e in existants) e.id: e};
      for (final EvenementGoogle e in <EvenementGoogle>[...plan.aCreer, ...plan.aRemplacer, ...plan.aAnnuler]) {
        apres[e.id] = e;
      }
      final PlanSynchro suivant = planifierSynchro(souhaites: souhaites, existants: apres.values);

      expect(plan.total, 4);
      expect(suivant.vide, isTrue);
      expect(suivant.inchanges, 3);
      expect(suivant.dejaAnnules, 2);
    });
  });

  group('le résultat en mots', () {
    ResultatSynchro r({int crees = 0, int modifies = 0, int annules = 0, int inchanges = 0, int echecs = 0}) => ResultatSynchro(
      quand: DateTime(2026, 11, 26, 9),
      crees: crees,
      modifies: modifies,
      annules: annules,
      inchanges: inchanges,
      echecs: echecs,
    );

    test('rien du tout, ou tout à jour', () {
      expect(resumeSynchro(r()), 'Rien à envoyer : aucun élément dans la période.');
      expect(resumeSynchro(r(inchanges: 1)), 'Tout est déjà à jour (1 élément).');
      expect(resumeSynchro(r(inchanges: 5)), 'Tout est déjà à jour (5 éléments).');
    });

    test('ajoutés, modifiés, marqués, déjà à jour : au singulier et au pluriel', () {
      expect(resumeSynchro(r(crees: 1)), '1 ajouté.');
      expect(resumeSynchro(r(crees: 3, modifies: 1, annules: 2, inchanges: 40)), '3 ajoutés, 1 modifié, 2 marqués « [Annulé] », 40 déjà à jour.');
      expect(resumeSynchro(r(annules: 1)), '1 marqué « [Annulé] ».');
      expect(resumeSynchro(r(modifies: 2)), '2 modifiés.');
    });

    test('les échecs sont dits', () {
      expect(resumeSynchro(r(crees: 2, echecs: 1)), '2 ajoutés, 1 en échec.');
      expect(r(echecs: 1).complet, isFalse);
      expect(r(crees: 1).complet, isTrue);
    });
  });
}
