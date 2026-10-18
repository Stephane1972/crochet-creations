import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late ClientRepository repo;

  setUp(() {
    db = creerBaseEnMemoire();
    repo = ClientRepository(db);
  });
  tearDown(() => db.close());

  test('création d’un particulier', () async {
    final Client c = await repo.creer(
      const DonneesClient(
        civilite: Civilite.madame,
        prenom: ' Camille ',
        nom: 'Martin',
        telephone: '06 12 34 56 78',
        email: 'camille@exemple.fr',
        codePostal: '31000',
        ville: 'Toulouse',
      ),
    );
    expect(c.typeClient, TypeClient.particulier);
    expect(c.civilite, Civilite.madame);
    expect(c.prenom, 'Camille');
    expect(c.nom, 'Martin');
    expect(c.adresse, isNull);
    expect(c.archiveLe, isNull);
  });

  test('un professionnel peut n’avoir qu’une raison sociale', () async {
    final Client c = await repo.creer(
      const DonneesClient(
        typeClient: TypeClient.professionnel,
        raisonSociale: 'Boutique La Pelote',
        siret: '123 456 789 00012',
      ),
    );
    expect(c.typeClient, TypeClient.professionnel);
    expect(c.raisonSociale, 'Boutique La Pelote');
  });

  test('une fiche sans nom, ou avec un e-mail invalide, est refusée', () async {
    await expectLater(repo.creer(const DonneesClient(telephone: '0600000000')), throwsA(isA<DonneeInvalide>()));
    await expectLater(repo.creer(const DonneesClient(nom: '   ')), throwsA(isA<DonneeInvalide>()));
    await expectLater(
      repo.creer(const DonneesClient(nom: 'Martin', email: 'pas-un-email')),
      throwsA(isA<DonneeInvalide>()),
    );
    expect(await repo.lister(), isEmpty);
  });

  test('modification et client introuvable', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    final Client modifie = await repo.modifier(c.id, const DonneesClient(nom: 'Martin', ville: 'Albi'));
    expect(modifie.ville, 'Albi');
    await expectLater(repo.modifier(999, const DonneesClient(nom: 'X')), throwsA(isA<ElementIntrouvable>()));
  });

  test('archivage : masqué de la liste mais conservé, puis restauration', () async {
    final Client c = await repo.creer(const DonneesClient(nom: 'Martin'));
    await repo.archiver(c.id);
    expect(await repo.lister(), isEmpty);
    expect(await repo.lister(inclureArchives: true), hasLength(1));
    await repo.restaurer(c.id);
    expect(await repo.lister(), hasLength(1));
  });

  test('la liste est triée par nom', () async {
    await repo.creer(const DonneesClient(nom: 'Roux', prenom: 'Léa'));
    await repo.creer(const DonneesClient(nom: 'Bernard', prenom: 'Zoé'));
    await repo.creer(const DonneesClient(nom: 'bernard', prenom: 'Alice'));

    final List<Client> liste = await repo.observerClients().first;
    expect(liste.map((c) => '${c.prenom} ${c.nom}'), <String>['Alice bernard', 'Zoé Bernard', 'Léa Roux']);
  });
}
