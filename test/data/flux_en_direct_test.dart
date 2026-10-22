import 'dart:async';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/client_repository.dart';
import 'package:crochet_creations/data/repositories/client_vues.dart';
import 'package:crochet_creations/data/repositories/numerotation_repository.dart';
import 'package:crochet_creations/data/repositories/produit_repository.dart';
import 'package:crochet_creations/data/repositories/produit_vues.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

/// Drift partage un flux entre toutes les requêtes de même texte SQL, sans regarder les tables
/// surveillées : sans `observerTables`, le premier flux ouvert privait les suivants de mises à jour.
void main() {
  late AppDatabase db;

  setUp(() => db = creerBaseEnMemoire());
  tearDown(() => db.close());

  test('un flux ouvert avant ne prive pas l’historique d’un client de ses mises à jour', () async {
    final ProduitRepository produits = ProduitRepository(db, NumerotationRepository(db));
    final ClientRepository clients = ClientRepository(db);
    final int clientId = await db.insererClient();

    // Un premier flux, sur d'autres tables (produits et variantes), reste ouvert pendant tout le test.
    final StreamSubscription<Object?> flux = produits.observerResumes().listen((_) {});

    final List<int> nombresDeVentes = <int>[];
    Completer<void> prochain = Completer<void>();
    final StreamSubscription<HistoriqueClient> historique = clients.observerHistorique(clientId).listen((
      HistoriqueClient h,
    ) {
      nombresDeVentes.add(h.ventes.length);
      if (!prochain.isCompleted) prochain.complete();
    });

    await prochain.future.timeout(const Duration(seconds: 5));
    expect(nombresDeVentes, <int>[0]);

    prochain = Completer<void>();
    await db.insererVente(clientId: clientId);
    await prochain.future.timeout(const Duration(seconds: 5));
    expect(nombresDeVentes.last, 1);

    await historique.cancel();
    await flux.cancel();
  });

  test('l’historique des ventes d’un produit se met à jour même si la fiche du produit est ouverte', () async {
    final ProduitRepository produits = ProduitRepository(db, NumerotationRepository(db));
    final int clientId = await db.insererClient();
    final int produitId = await db.insererProduit();

    final StreamSubscription<Object?> fiche = produits.observerDetail(produitId).listen((_) {});

    final List<int> nombresDeLignes = <int>[];
    Completer<void> prochain = Completer<void>();
    final StreamSubscription<List<LigneHistoriqueVente>> historique = produits
        .observerHistorique(produitId)
        .listen((List<LigneHistoriqueVente> lignes) {
          nombresDeLignes.add(lignes.length);
          if (!prochain.isCompleted) prochain.complete();
        });

    await prochain.future.timeout(const Duration(seconds: 5));
    expect(nombresDeLignes, <int>[0]);

    prochain = Completer<void>();
    final int venteId = await db.insererVente(clientId: clientId);
    await db
        .into(db.lignesVente)
        .insert(
          LignesVenteCompanion.insert(
            venteId: venteId,
            designation: 'Doudou lapin',
            quantite: 1,
            prixUnitaireCentimes: 1000,
            totalLigneCentimes: 1000,
            produitId: Value(produitId),
          ),
        );
    await prochain.future.timeout(const Duration(seconds: 5));
    expect(nombresDeLignes.last, 1);

    await historique.cancel();
    await fiche.cancel();
  });
}
