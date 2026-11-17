import 'package:crochet_creations/domain/drive_envoi.dart';
import 'package:crochet_creations/domain/drive_partage.dart';
import 'package:flutter_test/flutter_test.dart';

const AccesDrive _proprietaire = AccesDrive(
  id: 'p0',
  type: TypeAcces.proprietaire,
  email: 'stef@exemple.fr',
  nom: 'Stéphane',
);
const AccesDrive _marie = AccesDrive(id: 'p1', type: TypeAcces.personne, email: 'marie@exemple.fr', nom: 'Marie Dupont');
const AccesDrive _paul = AccesDrive(id: 'p2', type: TypeAcces.personne, email: 'paul@exemple.fr');
const AccesDrive _lien = AccesDrive(id: 'p3', type: TypeAcces.lienPublic);
const AccesDrive _groupe = AccesDrive(id: 'p4', type: TypeAcces.autre, email: 'equipe@exemple.fr');

void main() {
  group('rubriques', () {
    test('les noms des dossiers Drive sont ceux de l’envoi, et les sauvegardes n’y sont pas', () {
      expect(RubriquePartage.factures.nomDrive, DossierDrive.factures.nomDrive);
      expect(RubriquePartage.devis.nomDrive, DossierDrive.devis.nomDrive);
      expect(RubriquePartage.exports.nomDrive, nomDossierExportsDrive);
      expect(RubriquePartage.values, hasLength(3));
      final Set<String> noms = RubriquePartage.values.map((RubriquePartage r) => r.nomDrive).toSet();
      expect(noms, isNot(contains(DossierDrive.photos.nomDrive)));
      expect(noms, isNot(contains(DossierDrive.notes.nomDrive)));
      expect(noms.any((String n) => n.toLowerCase().contains('sauvegarde')), isFalse);
    });
  });

  group('typeAccesDrive', () {
    test('le propriétaire est reconnu par son rôle, avant tout', () {
      expect(typeAccesDrive(type: 'user', role: 'owner'), TypeAcces.proprietaire);
    });

    test('le lien public, une personne, le reste', () {
      expect(typeAccesDrive(type: 'anyone', role: 'reader'), TypeAcces.lienPublic);
      expect(typeAccesDrive(type: 'user', role: 'reader'), TypeAcces.personne);
      expect(typeAccesDrive(type: 'user', role: 'writer'), TypeAcces.personne);
      expect(typeAccesDrive(type: 'group', role: 'reader'), TypeAcces.autre);
      expect(typeAccesDrive(type: 'domain', role: 'reader'), TypeAcces.autre);
      expect(typeAccesDrive(type: null, role: null), TypeAcces.autre);
    });
  });

  group('AccesDrive.libelle', () {
    test('nom puis adresse, ou l’un des deux', () {
      expect(_marie.libelle, 'Marie Dupont (marie@exemple.fr)');
      expect(_paul.libelle, 'paul@exemple.fr');
      expect(const AccesDrive(id: 'x', type: TypeAcces.personne, nom: 'Léa').libelle, 'Léa');
      expect(const AccesDrive(id: 'x', type: TypeAcces.personne, email: 'a@b.fr', nom: 'a@b.fr').libelle, 'a@b.fr');
    });

    test('lien public, accès inconnus', () {
      expect(_lien.libelle, 'Toute personne ayant le lien');
      expect(const AccesDrive(id: 'x', type: TypeAcces.autre).libelle, 'Autre accès');
      expect(const AccesDrive(id: 'x', type: TypeAcces.proprietaire).libelle, 'Propriétaire');
    });
  });

  group('AccesFichier', () {
    test('un fichier sans autre accès que le propriétaire est privé', () {
      const AccesFichier acces = AccesFichier(<AccesDrive>[_proprietaire]);
      expect(acces.estPrive, isTrue);
      expect(acces.proprietaire, _proprietaire);
      expect(acces.personnes, isEmpty);
      expect(acces.lienPublic, isNull);
      expect(acces.resume, 'Privé : vous seul·e y avez accès.');
    });

    test('les personnes, le lien public et les autres accès sont séparés', () {
      const AccesFichier acces = AccesFichier(<AccesDrive>[_proprietaire, _marie, _lien, _paul, _groupe]);
      expect(acces.estPrive, isFalse);
      expect(acces.personnes, <AccesDrive>[_marie, _paul]);
      expect(acces.lienPublic, _lien);
      expect(acces.autres, <AccesDrive>[_groupe]);
    });

    test('le résumé dit ce qui est partagé', () {
      expect(const AccesFichier(<AccesDrive>[_proprietaire, _marie]).resume, 'Partagé avec 1 personne.');
      expect(const AccesFichier(<AccesDrive>[_proprietaire, _marie, _paul]).resume, 'Partagé avec 2 personnes.');
      expect(const AccesFichier(<AccesDrive>[_proprietaire, _lien]).resume, 'Lien public activé.');
      expect(
        const AccesFichier(<AccesDrive>[_proprietaire, _marie, _lien, _groupe]).resume,
        'Partagé avec 1 personne, lien public activé, autres accès.',
      );
    });
  });

  group('erreurCourrielPartage', () {
    test('une adresse correcte convient, quelle que soit la casse et les espaces', () {
      expect(erreurCourrielPartage('  Marie@Exemple.FR '), isNull);
      expect(normaliserCourriel('  Marie@Exemple.FR '), 'marie@exemple.fr');
    });

    test('vide ou mal écrite : un message', () {
      expect(erreurCourrielPartage('   '), 'Saisissez l’adresse e-mail de la personne.');
      expect(erreurCourrielPartage('marie'), isNotNull);
      expect(erreurCourrielPartage('marie@'), isNotNull);
    });

    test('pas de partage avec soi-même', () {
      expect(
        erreurCourrielPartage('STEF@exemple.fr', emailProprietaire: 'stef@exemple.fr'),
        'C’est votre propre adresse : ce fichier est déjà à vous.',
      );
    });

    test('pas de partage en double', () {
      expect(
        erreurCourrielPartage('Marie@exemple.fr', dejaPartagees: <String>['marie@exemple.fr']),
        'Ce fichier est déjà partagé avec cette adresse.',
      );
      expect(erreurCourrielPartage('paul@exemple.fr', dejaPartagees: <String>['marie@exemple.fr']), isNull);
    });
  });
}
