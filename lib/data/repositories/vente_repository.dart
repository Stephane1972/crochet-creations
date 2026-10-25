import 'package:drift/drift.dart';

import '../../core/utils/money.dart';
import '../../core/utils/texte.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/calculs/statut_paiement.dart';
import '../../domain/calculs/stock.dart';
import '../../domain/calculs/totaux.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import 'produit_repository.dart';
import 'vente_vues.dart';

/// Ventes : validation d'un panier, annulation, encaissements.
///
/// Une vente validée est définitive : on ne la modifie pas et on ne la supprime jamais.
/// Une erreur se corrige en l'**annulant** (le stock est remis et un remboursement est
/// enregistré si elle était payée).
class VenteRepository {
  VenteRepository(this._db, this._produits);

  final AppDatabase _db;
  final ProduitRepository _produits;

  /// Valide le [panier] en une seule opération « tout ou rien » : la vente, ses lignes, la
  /// décrémentation du stock et l'encaissement éventuel sont enregistrés ensemble, ou rien du tout.
  ///
  /// - [clientId] vide = « client de passage » ;
  /// - [paiement] vide = vente impayée (paiement différé) ;
  /// - désignations et prix des lignes sont ceux du panier ; le coût matière est relevé au catalogue.
  ///
  /// Lance [DonneeInvalide], [ElementIntrouvable], [RemiseInvalide] ou [StockInsuffisant]
  /// (message en français) ; la base n'est alors pas modifiée.
  Future<Vente> valider({
    int? clientId,
    required Panier panier,
    PaiementSaisi? paiement,
    String? notes,
    DateTime? date,
  }) {
    return _db.transaction(() async {
      if (panier.estVide) throw const DonneeInvalide('Le panier est vide.');

      if (clientId != null) {
        final Client? client = await (_db.select(
          _db.clients,
        )..where((t) => t.id.equals(clientId))).getSingleOrNull();
        if (client == null) throw const ElementIntrouvable('Ce client n’existe plus.');
        if (client.archiveLe != null) {
          throw const DonneeInvalide('Ce client est archivé : restaurez sa fiche pour lui vendre.');
        }
      }

      final TotauxDocument totaux = panier.totaux;
      paiement?.verifier(totaux.totalCentimes);

      // Contrôle de chaque article du catalogue, puis sortie de stock.
      final Map<int, int> couts = <int, int>{};
      for (final LignePanier ligne in panier.lignes) {
        final int? produitId = ligne.produitId;
        if (produitId == null) continue;
        couts[ligne.idLigne] = await _controlerArticle(ligne, produitId);
      }
      for (final LignePanier ligne in panier.lignes) {
        final int? produitId = ligne.produitId;
        if (produitId == null) continue;
        await _produits.consommerStock(
          produitId: produitId,
          varianteId: ligne.varianteId,
          quantite: ligne.quantite,
        );
      }

      final int venteId = await _db
          .into(_db.ventes)
          .insert(
            VentesCompanion.insert(
              sousTotalCentimes: totaux.sousTotalCentimes,
              totalCentimes: totaux.totalCentimes,
              clientId: Value(clientId),
              dateVente: date == null ? const Value.absent() : Value(date),
              remiseType: Value(panier.remiseType),
              remiseValeur: Value(panier.remiseType == RemiseType.aucune ? 0 : panier.remiseValeur),
              remiseCentimes: Value(totaux.remiseCentimes),
              fraisPortCentimes: Value(totaux.fraisPortCentimes),
              notes: Value(nullSiVide(notes)),
            ),
          );

      for (int i = 0; i < panier.lignes.length; i++) {
        final LignePanier ligne = panier.lignes[i];
        await _db
            .into(_db.lignesVente)
            .insert(
              LignesVenteCompanion.insert(
                venteId: venteId,
                designation: ligne.designation,
                quantite: ligne.quantite,
                prixUnitaireCentimes: ligne.prixUnitaireCentimes,
                totalLigneCentimes: ligne.totalCentimes,
                position: Value(i),
                nature: Value(ligne.nature),
                produitId: Value(ligne.produitId),
                varianteId: Value(ligne.varianteId),
                description: Value(ligne.description),
                coutUnitaireCentimes: Value(couts[ligne.idLigne] ?? 0),
              ),
            );
      }

      if (paiement != null) {
        await _db
            .into(_db.paiements)
            .insert(
              PaiementsCompanion.insert(
                venteId: venteId,
                montantCentimes: paiement.montantCentimes,
                modePaiement: paiement.mode,
                datePaiement: date == null ? const Value.absent() : Value(date),
              ),
            );
      }
      await _recalculerStatutPaiement(venteId);
      return _vente(venteId);
    });
  }

  /// Annule une vente validée : le stock des articles suivis est remis, un remboursement égal au
  /// net encaissé est enregistré (même mode que le dernier paiement), et les factures émises pour
  /// cette vente sont marquées annulées. Lance [DonneeInvalide] si elle est déjà annulée.
  Future<void> annuler(int venteId) {
    return _db.transaction(() async {
      final Vente vente = await _vente(venteId);
      if (vente.statut == StatutVente.annulee) {
        throw const DonneeInvalide('Cette vente est déjà annulée.');
      }

      final List<LigneVente> lignes = await (_db.select(
        _db.lignesVente,
      )..where((t) => t.venteId.equals(venteId))).get();
      for (final LigneVente ligne in lignes) {
        final int? produitId = ligne.produitId;
        if (produitId == null) continue;
        final Produit? produit = await _produits.obtenir(produitId);
        if (produit == null || !suitLeStock(produit.statut)) continue;
        await _produits.ajusterStock(
          produitId: produitId,
          varianteId: ligne.varianteId,
          delta: ligne.quantite,
        );
      }

      final List<Paiement> paiements = await _paiements(venteId);
      final int net = paiements.fold(0, (int somme, Paiement p) => somme + p.montantCentimes);
      if (net > 0) {
        await _db
            .into(_db.paiements)
            .insert(
              PaiementsCompanion.insert(
                venteId: venteId,
                montantCentimes: -net,
                modePaiement: paiements.last.modePaiement,
                note: const Value('Remboursement : vente annulée'),
              ),
            );
      }

      await (_db.update(_db.ventes)..where((t) => t.id.equals(venteId))).write(
        VentesCompanion(statut: const Value(StatutVente.annulee), modifieLe: Value(DateTime.now())),
      );
      await (_db.update(_db.factures)
            ..where((t) => t.venteId.equals(venteId) & t.statut.equalsValue(StatutFacture.emise)))
          .write(
            FacturesCompanion(
              statut: const Value(StatutFacture.annulee),
              modifieLe: Value(DateTime.now()),
            ),
          );
      await _recalculerStatutPaiement(venteId);
    });
  }

  /// Enregistre un encaissement sur une vente validée (acompte, solde, paiement différé).
  /// Lance [DonneeInvalide] si la vente est annulée ou déjà soldée, si le montant est nul
  /// ou s'il dépasse le solde dû.
  Future<Paiement> encaisser({
    required int venteId,
    required ModePaiement mode,
    required int montantCentimes,
    DateTime? date,
    String? note,
  }) {
    return _db.transaction(() async {
      final Vente vente = await _vente(venteId);
      if (vente.statut == StatutVente.annulee) {
        throw const DonneeInvalide('Cette vente est annulée : on ne peut plus l’encaisser.');
      }
      if (montantCentimes <= 0) {
        throw const DonneeInvalide('Le montant encaissé doit être supérieur à 0.');
      }
      final List<Paiement> paiements = await _paiements(venteId);
      final int net = paiements.fold(0, (int somme, Paiement p) => somme + p.montantCentimes);
      final int solde = vente.totalCentimes - net;
      if (solde <= 0) throw const DonneeInvalide('Cette vente est déjà entièrement payée.');
      if (montantCentimes > solde) {
        throw DonneeInvalide('Le montant dépasse le solde dû (${formatEuros(solde)}).');
      }

      final int id = await _db
          .into(_db.paiements)
          .insert(
            PaiementsCompanion.insert(
              venteId: venteId,
              montantCentimes: montantCentimes,
              modePaiement: mode,
              datePaiement: date == null ? const Value.absent() : Value(date),
              note: Value(nullSiVide(note)),
            ),
          );
      await _recalculerStatutPaiement(venteId);
      return (_db.select(_db.paiements)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  Future<Vente?> obtenir(int id) =>
      (_db.select(_db.ventes)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Détail complet d'une vente (`null` si elle n'existe pas).
  Future<VenteDetail?> detail(int id) async {
    final Vente? vente = await obtenir(id);
    if (vente == null) return null;
    final List<LigneVente> lignes =
        await (_db.select(_db.lignesVente)
              ..where((t) => t.venteId.equals(id))
              ..orderBy([(t) => OrderingTerm(expression: t.position), (t) => OrderingTerm(expression: t.id)]))
            .get();
    final int? clientId = vente.clientId;
    final Client? client = clientId == null
        ? null
        : await (_db.select(_db.clients)..where((t) => t.id.equals(clientId))).getSingleOrNull();
    final List<Facture> factures =
        await (_db.select(_db.factures)
              ..where((t) => t.venteId.equals(id))
              ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)]))
            .get();
    return VenteDetail(
      vente: vente,
      lignes: lignes,
      paiements: await _paiements(id),
      client: client,
      factures: factures,
    );
  }

  /// Détail d'une vente, mis à jour automatiquement (paiement, annulation, facture, modification du client).
  Stream<VenteDetail?> observerDetail(int id) => observerTables(
    _db,
    <ResultSetImplementation>{_db.ventes, _db.lignesVente, _db.paiements, _db.clients, _db.factures},
    () => detail(id),
  );

  // --- Interne --------------------------------------------------------------

  /// Vérifie qu'un article du catalogue peut être vendu et retourne son coût matière unitaire.
  Future<int> _controlerArticle(LignePanier ligne, int produitId) async {
    final Produit? produit = await _produits.obtenir(produitId);
    if (produit == null) {
      throw ElementIntrouvable('« ${ligne.designation} » n’existe plus au catalogue.');
    }
    if (produit.archiveLe != null || produit.statut == StatutProduit.epuise) {
      throw DonneeInvalide('« ${ligne.designation} » n’est plus en vente.');
    }

    final int? varianteId = ligne.varianteId;
    if (varianteId != null) {
      final VarianteProduit? variante = await (_db.select(
        _db.variantesProduit,
      )..where((t) => t.id.equals(varianteId))).getSingleOrNull();
      if (variante == null || variante.produitId != produitId || variante.archiveLe != null) {
        throw DonneeInvalide('Cette variante de « ${produit.nom} » n’est plus proposée à la vente.');
      }
    } else {
      // Un produit à variantes se vend par variante : son propre stock n'est pas utilisé.
      final List<VarianteProduit> actives = await (_db.select(
        _db.variantesProduit,
      )..where((t) => t.produitId.equals(produitId) & t.archiveLe.isNull())).get();
      if (actives.isNotEmpty) {
        throw DonneeInvalide('Choisissez une variante de « ${produit.nom} ».');
      }
    }
    return produit.coutMatiereCentimes;
  }

  Future<Vente> _vente(int id) async {
    final Vente? vente = await obtenir(id);
    if (vente == null) throw const ElementIntrouvable('Cette vente n’existe plus.');
    return vente;
  }

  /// Paiements d'une vente, du plus ancien au plus récent.
  Future<List<Paiement>> _paiements(int venteId) {
    return (_db.select(_db.paiements)
          ..where((t) => t.venteId.equals(venteId))
          ..orderBy([(t) => OrderingTerm(expression: t.datePaiement), (t) => OrderingTerm(expression: t.id)]))
        .get();
  }

  /// Recalcule le statut de paiement de la vente à partir de ses paiements.
  Future<void> _recalculerStatutPaiement(int venteId) async {
    final Vente vente = await _vente(venteId);
    final List<Paiement> paiements = await _paiements(venteId);
    final StatutPaiement statut = calculerStatutPaiement(
      totalCentimes: vente.totalCentimes,
      montantsPaiements: paiements.map((Paiement p) => p.montantCentimes),
    );
    await (_db.update(_db.ventes)..where((t) => t.id.equals(venteId))).write(
      VentesCompanion(statutPaiement: Value(statut), modifieLe: Value(DateTime.now())),
    );
  }
}
