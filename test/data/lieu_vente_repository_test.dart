import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/lieu_vente_repository.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/vente_repository.dart';
import 'package:crochet_creations/domain/calculs/panier.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/erreurs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late LieuVenteRepository lieux;
  late ProduitRepository produits;
  late VenteRepository ventes;

  setUp(() {
    db = creerBaseEnMemoire();
    lieux = LieuVenteRepository(db);
    produits = ProduitRepository(db, NumerotationRepository(db));
    ventes = VenteRepository(db, produits);
  });
  tearDown(() => db.close());

  Matcher refus(String morceau) =>
      throwsA(isA<DonneeInvalide>().having((DonneeInvalide e) => e.message, 'message', contains(morceau)));

  Future<List<String>> noms() async => (await lieux.lister()).map((LieuVente l) => l.nom).toList();

  Future<LieuVente> parNom(String nom) async => (await lieux.lister()).firstWhere((LieuVente l) => l.nom == nom);

  /// Une vente validée par le dépôt, dans le lieu [lieuId] (ou sans lieu).
  Future<Vente> vendre({int? lieuId}) async {
    final Produit p = await produits.creer(
      DonneesProduit(
        nom: 'Doudou ${DateTime.now().microsecondsSinceEpoch}',
        categorie: CleCategorie.doudou,
        prixVenteCentimes: 2000,
        quantiteStock: 50,
      ),
    );
    return ventes.valider(
      lieuId: lieuId,
      panier: const Panier().ajouter(
        produitId: p.id,
        designation: p.nom,
        prixUnitaireCentimes: p.prixVenteCentimes,
        quantite: 1,
        stockDisponible: p.quantiteStock,
      ),
    );
  }

  group('lister', () {
    test('une base neuve a les quatre lieux de départ, dans l’ordre', () async {
      expect(await noms(), <String>['Marché', 'Salon', 'Boutique', 'Vente en ligne']);
    });

    test('obtenir retrouve un lieu, ou rien', () async {
      final LieuVente salon = await parNom('Salon');
      expect((await lieux.obtenir(salon.id))!.nom, 'Salon');
      expect(await lieux.obtenir(999), isNull);
    });

    test('le nombre de ventes par lieu compte aussi les ventes annulées, et ignore les ventes sans lieu', () async {
      final LieuVente marche = await parNom('Marché');
      final LieuVente salon = await parNom('Salon');
      await vendre(lieuId: marche.id);
      final Vente annulee = await vendre(lieuId: marche.id);
      await ventes.annuler(annulee.id);
      await vendre(lieuId: salon.id);
      await vendre(); // sans lieu : n'est dans aucun lieu

      expect(await lieux.nombreVentesParLieu(), <int, int>{marche.id: 2, salon.id: 1});
      expect(await lieux.nombreVentes(marche.id), 2);
      expect(await lieux.nombreVentes((await parNom('Boutique')).id), 0);
    });

    test('observer envoie la liste mise à jour après un ajout', () async {
      final Stream<List<LieuVente>> flux = lieux.observer();
      final Future<void> verification = expectLater(flux.map((List<LieuVente> l) => l.length), emitsThrough(5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await lieux.creer('Fête du village');
      await verification;
    });

    test('observerNombreVentesParLieu suit les ventes en direct', () async {
      final LieuVente marche = await parNom('Marché');
      final Stream<Map<int, int>> flux = lieux.observerNombreVentesParLieu();
      final Future<void> verification = expectLater(
        flux.map((Map<int, int> m) => m[marche.id] ?? 0),
        emitsThrough(1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await vendre(lieuId: marche.id);
      await verification;
    });
  });

  group('créer', () {
    test('le nouveau lieu passe en dernier', () async {
      final LieuVente fete = await lieux.creer('  Fête   du village ');
      expect(fete.nom, 'Fête du village');
      expect(await noms(), <String>['Marché', 'Salon', 'Boutique', 'Vente en ligne', 'Fête du village']);
      expect(fete.position, greaterThan((await parNom('Vente en ligne')).position));
    });

    test('refuse un nom vide, trop long ou réservé', () async {
      await expectLater(lieux.creer('   '), refus('Donnez un nom'));
      await expectLater(lieux.creer('a' * 61), refus('limité à 60'));
      await expectLater(lieux.creer('Non renseigné'), refus('vente sans lieu'));
      expect(await noms(), hasLength(4));
    });

    test('refuse un nom déjà pris, sans tenir compte des majuscules, des accents ni des espaces', () async {
      await expectLater(lieux.creer('marché'), refus('« Marché » existe déjà'));
      await expectLater(lieux.creer(' VENTE  EN LIGNE '), refus('existe déjà'));
      expect(await noms(), hasLength(4));
    });

    test('après avoir supprimé tous les lieux, on repart de zéro', () async {
      for (final LieuVente l in await lieux.lister()) {
        await lieux.supprimer(l.id);
      }
      expect(await lieux.lister(), isEmpty);
      final LieuVente premier = await lieux.creer('Atelier');
      expect(premier.position, 0);
    });
  });

  group('renommer', () {
    test('change le nom sans toucher aux ventes : elles gardent le même lieu', () async {
      final LieuVente marche = await parNom('Marché');
      final Vente v = await vendre(lieuId: marche.id);

      final LieuVente renomme = await lieux.renommer(marche.id, '  Marché du samedi ');
      expect(renomme.id, marche.id);
      expect(renomme.nom, 'Marché du samedi');
      expect((await ventes.obtenir(v.id))!.lieuId, marche.id);
      expect((await ventes.detail(v.id))!.lieu!.nom, 'Marché du samedi');
    });

    test('un lieu peut garder son nom, ou le changer de casse', () async {
      final LieuVente salon = await parNom('Salon');
      expect((await lieux.renommer(salon.id, 'Salon')).nom, 'Salon');
      expect((await lieux.renommer(salon.id, 'SALON')).nom, 'SALON');
    });

    test('refuse le nom d’un autre lieu, un nom invalide ou un lieu inconnu', () async {
      final LieuVente salon = await parNom('Salon');
      await expectLater(lieux.renommer(salon.id, 'Boutique'), refus('existe déjà'));
      await expectLater(lieux.renommer(salon.id, ''), refus('Donnez un nom'));
      await expectLater(lieux.renommer(999, 'Autre'), throwsA(isA<ElementIntrouvable>()));
      expect((await parNom('Salon')).nom, 'Salon');
    });
  });

  group('supprimer', () {
    test('un lieu sans vente se supprime directement', () async {
      final LieuVente boutique = await parNom('Boutique');
      expect(await lieux.supprimer(boutique.id), 0);
      expect(await noms(), <String>['Marché', 'Salon', 'Vente en ligne']);
    });

    test('un lieu qui a des ventes ne se supprime pas sans destination, et rien ne bouge', () async {
      final LieuVente marche = await parNom('Marché');
      await vendre(lieuId: marche.id);
      await vendre(lieuId: marche.id);

      await expectLater(lieux.supprimer(marche.id), refus('contient 2 ventes'));
      expect(await noms(), contains('Marché'));
      expect(await lieux.nombreVentes(marche.id), 2);
    });

    test('les ventes passent dans le lieu choisi, annulées comprises, et rien d’autre ne change', () async {
      final LieuVente marche = await parNom('Marché');
      final LieuVente salon = await parNom('Salon');
      final Vente a = await vendre(lieuId: marche.id);
      final Vente b = await vendre(lieuId: marche.id);
      await ventes.annuler(b.id);
      final Vente autre = await vendre(lieuId: salon.id);
      final int totalA = a.totalCentimes;

      expect(await lieux.supprimer(marche.id, deplacerVers: DestinationVentes.lieu(salon.id)), 2);

      expect((await ventes.obtenir(a.id))!.lieuId, salon.id);
      expect((await ventes.obtenir(b.id))!.lieuId, salon.id);
      expect((await ventes.obtenir(autre.id))!.lieuId, salon.id);
      expect((await ventes.obtenir(a.id))!.totalCentimes, totalA);
      expect((await ventes.obtenir(b.id))!.statut.name, 'annulee');
      expect(await noms(), isNot(contains('Marché')));
      expect(await lieux.nombreVentes(salon.id), 3);
    });

    test('ou dans « Non renseigné » : les ventes n’ont plus de lieu mais existent toujours', () async {
      final LieuVente marche = await parNom('Marché');
      final Vente v = await vendre(lieuId: marche.id);

      expect(await lieux.supprimer(marche.id, deplacerVers: const DestinationVentes.nonRenseigne()), 1);

      expect((await ventes.obtenir(v.id))!.lieuId, isNull);
      expect((await ventes.detail(v.id))!.lieu, isNull);
      expect(await db.select(db.ventes).get(), hasLength(1));
    });

    test('refuse de déplacer les ventes vers le lieu qu’on supprime ou vers un lieu qui n’existe pas : rien ne bouge', () async {
      final LieuVente marche = await parNom('Marché');
      final Vente v = await vendre(lieuId: marche.id);

      await expectLater(
        lieux.supprimer(marche.id, deplacerVers: DestinationVentes.lieu(marche.id)),
        refus('autre lieu'),
      );
      await expectLater(
        lieux.supprimer(marche.id, deplacerVers: DestinationVentes.lieu(999)),
        throwsA(isA<ElementIntrouvable>()),
      );
      expect((await ventes.obtenir(v.id))!.lieuId, marche.id);
      expect(await noms(), contains('Marché'));
    });

    test('un lieu inconnu est signalé', () async {
      await expectLater(lieux.supprimer(999), throwsA(isA<ElementIntrouvable>()));
    });
  });
}
