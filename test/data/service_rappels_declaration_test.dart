import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/notifications/service_rappels_declaration.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/declaration.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';
import 'aide_rappels.dart';

void main() {
  late AppDatabase db;
  late ParametresRepository parametres;
  late FauxPlanificateurRappels planificateur;
  late ServiceRappelsDeclaration service;
  late DateTime maintenant;

  setUp(() {
    db = creerBaseEnMemoire();
    parametres = ParametresRepository(db);
    planificateur = FauxPlanificateurRappels();
    maintenant = DateTime(2026, 11, 23, 10);
    service = ServiceRappelsDeclaration(
      parametres: parametres,
      planificateur: planificateur,
      horloge: () => maintenant,
    );
  });
  tearDown(() => db.close());

  group('activer', () {
    test('demande l’autorisation, programme les 12 prochains mois, puis mémorise le choix', () async {
      expect(await service.activer(), ResultatRappel.reussi);

      expect(planificateur.demandes, 1);
      expect(planificateur.remplacements, 1);
      expect(planificateur.programmes, prochainsRappelsDeclaration(maintenant));
      expect(planificateur.programmes, hasLength(24));
      expect(await parametres.lireRappelDeclaration(), isTrue);
    });

    test('si les notifications sont refusées, rien n’est programmé et le choix n’est pas mémorisé', () async {
      planificateur
        ..autorisation = false
        ..reponseALaDemande = false;

      expect(await service.activer(), ResultatRappel.autorisationRefusee);

      expect(planificateur.demandes, 1);
      expect(planificateur.remplacements, 0);
      expect(planificateur.programmes, isEmpty);
      expect(await parametres.lireRappelDeclaration(), isFalse);
    });

    test('si les notifications étaient bloquées mais que la personne accepte la demande, c’est activé', () async {
      planificateur
        ..autorisation = false
        ..reponseALaDemande = true;

      expect(await service.activer(), ResultatRappel.reussi);

      expect(planificateur.autorisation, isTrue);
      expect(await parametres.lireRappelDeclaration(), isTrue);
    });

    test('sur un appareil sans notifications : rien n’est demandé, rien n’est activé', () async {
      planificateur.disponible = false;

      expect(await service.activer(), ResultatRappel.indisponible);

      expect(planificateur.demandes, 0);
      expect(planificateur.remplacements, 0);
      expect(await parametres.lireRappelDeclaration(), isFalse);
    });

    test('si le système de notifications échoue, l’erreur remonte et le choix n’est pas mémorisé', () async {
      planificateur.erreurAuRemplacement = StateError('le système ne répond pas');

      await expectLater(service.activer(), throwsA(isA<StateError>()));

      expect(await parametres.lireRappelDeclaration(), isFalse);
    });

    test('réactiver remplace la programmation existante (les mêmes identifiants, pas de doublon)', () async {
      await service.activer();
      await service.activer();

      expect(planificateur.remplacements, 2);
      expect(planificateur.programmes, hasLength(24));
      expect(planificateur.programmes.map((RappelDeclaration r) => r.id).toSet(), hasLength(24));
    });
  });

  group('désactiver', () {
    test('annule les notifications programmées et mémorise le choix', () async {
      await service.activer();

      await service.desactiver();

      expect(planificateur.annulations, 1);
      expect(planificateur.programmes, isEmpty);
      expect(await parametres.lireRappelDeclaration(), isFalse);
    });

    test('sur un appareil sans notifications : le choix est tout de même mémorisé', () async {
      await parametres.enregistrerRappelDeclaration(true);
      planificateur.disponible = false;

      await service.desactiver();

      expect(planificateur.annulations, 0);
      expect(await parametres.lireRappelDeclaration(), isFalse);
    });
  });

  group('synchroniser (à chaque ouverture de l’application)', () {
    test('rappel désactivé : rien n’est programmé', () async {
      await service.synchroniser();

      expect(planificateur.remplacements, 0);
      expect(planificateur.annulations, 0);
      expect(planificateur.demandes, 0);
    });

    test('rappel activé : les mois à venir sont reprogrammés, sans demander quoi que ce soit', () async {
      await parametres.enregistrerRappelDeclaration(true);

      await service.synchroniser();

      expect(planificateur.demandes, 0);
      expect(planificateur.programmes, prochainsRappelsDeclaration(maintenant));
    });

    test('l’horizon avance avec le temps : un mois plus tard, le mois d’avant n’y est plus et un nouveau mois s’ajoute', () async {
      await parametres.enregistrerRappelDeclaration(true);
      await service.synchroniser();
      expect(planificateur.programmes.first.dernierJour, DateTime(2026, 11, 30));
      expect(planificateur.programmes.last.dernierJour, DateTime(2027, 10, 31));

      maintenant = DateTime(2026, 12, 2, 8);
      await service.synchroniser();

      expect(planificateur.programmes.first.dernierJour, DateTime(2026, 12, 31));
      expect(planificateur.programmes.last.dernierJour, DateTime(2027, 11, 30));
    });

    test('autorisation retirée dans les réglages de l’appareil : rien n’est reprogrammé', () async {
      await parametres.enregistrerRappelDeclaration(true);
      planificateur.autorisation = false;

      await service.synchroniser();

      expect(planificateur.remplacements, 0);
      expect(planificateur.demandes, 0);
    });

    test('appareil sans notifications : rien n’est fait', () async {
      await parametres.enregistrerRappelDeclaration(true);
      planificateur.disponible = false;

      await service.synchroniser();

      expect(planificateur.remplacements, 0);
    });

    test('une erreur du système de notifications ne gêne jamais l’ouverture de l’application', () async {
      await parametres.enregistrerRappelDeclaration(true);
      planificateur.erreurAuRemplacement = StateError('le système ne répond pas');

      await service.synchroniser(); // ne lance rien

      expect(await parametres.lireRappelDeclaration(), isTrue); // le choix est gardé
    });
  });

  group('tester', () {
    test('affiche une notification tout de suite, avec le titre du rappel', () async {
      expect(await service.tester(), ResultatRappel.reussi);

      expect(planificateur.affichees, hasLength(1));
      expect(planificateur.affichees.single.titre, 'Déclaration des recettes');
      expect(planificateur.affichees.single.texte, contains('rappel de fin de mois'));
      // Un essai ne programme rien et ne change pas le choix.
      expect(planificateur.remplacements, 0);
      expect(await parametres.lireRappelDeclaration(), isFalse);
    });

    test('notifications refusées : rien n’est affiché', () async {
      planificateur
        ..autorisation = false
        ..reponseALaDemande = false;

      expect(await service.tester(), ResultatRappel.autorisationRefusee);

      expect(planificateur.affichees, isEmpty);
    });

    test('appareil sans notifications : indisponible', () async {
      planificateur.disponible = false;

      expect(await service.tester(), ResultatRappel.indisponible);

      expect(planificateur.affichees, isEmpty);
    });
  });

  group('l’état des notifications', () {
    test('disponible et notificationsAutorisees reprennent ce que dit l’appareil', () async {
      expect(service.disponible, isTrue);
      expect(await service.notificationsAutorisees(), isTrue);

      planificateur
        ..disponible = false
        ..autorisation = false;

      expect(service.disponible, isFalse);
      expect(await service.notificationsAutorisees(), isFalse);
    });
  });
}
