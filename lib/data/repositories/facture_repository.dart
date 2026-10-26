import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/texte.dart';
import '../../domain/document_facture.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_entreprise.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import '../pdf/construire_document.dart';
import '../stockage/stockage_pdf.dart';
import 'client_vues.dart';
import 'numerotation_repository.dart';
import 'parametres_repository.dart';

/// Fabrique le PDF d'un [DocumentFacture]. En production : `genererFacturePdf` avec les polices et le logo
/// de l'application ; les tests fournissent un faux générateur, rapide et sans ressources.
typedef GenerateurFacturePdf = Future<Uint8List> Function(DocumentFacture document);

/// Factures : création à partir d'une vente, annulation, consultation et PDF.
///
/// Une facture émise ne se modifie ni ne se supprime. Son numéro (`FACT-2026-0001`) est unique et
/// chronologique. On peut l'**annuler** : elle reste dans la liste, marquée « annulée », son numéro reste
/// utilisé, et la vente n'est pas touchée (on peut alors établir une nouvelle facture pour cette vente).
class FactureRepository {
  FactureRepository(this._db, this._numerotation, this._parametres, this._stockage, this._generateur);

  final AppDatabase _db;
  final NumerotationRepository _numerotation;
  final ParametresRepository _parametres;
  final StockagePdf _stockage;
  final GenerateurFacturePdf _generateur;

  /// Établit la facture de la vente [venteId] et enregistre son PDF.
  ///
  /// Lance [ProfilIncomplet] si « Mon entreprise » ne permet pas encore de facturer (aucun numéro n'est alors
  /// consommé), [ElementIntrouvable] si la vente n'existe plus, ou [DonneeInvalide] si elle est annulée ou
  /// déjà facturée. Le numéro est attribué dans la même transaction que l'enregistrement de la facture :
  /// si celui-ci échoue, le numéro n'est pas consommé.
  ///
  /// Le PDF est fabriqué une fois la facture enregistrée. Si cette étape échoue (disque plein...), la facture
  /// existe quand même : le PDF est refabriqué à la prochaine consultation (voir [obtenirPdf]).
  Future<Facture> creer(int venteId, {DateTime? date}) async {
    final Entreprise entreprise = await verifierProfil();

    final Facture facture = await _db.transaction(() async {
      final Vente? vente = await (_db.select(_db.ventes)..where((t) => t.id.equals(venteId))).getSingleOrNull();
      if (vente == null) throw const ElementIntrouvable('Cette vente n’existe plus.');
      if (vente.statut == StatutVente.annulee) {
        throw const DonneeInvalide('Cette vente est annulée : on ne peut pas la facturer.');
      }
      final Facture? existante =
          await (_db.select(_db.factures)..where((t) => t.venteId.equals(venteId) & t.statut.equalsValue(StatutFacture.emise)))
              .getSingleOrNull();
      if (existante != null) {
        throw DonneeInvalide('Cette vente a déjà une facture : ${existante.numero}.');
      }

      final int? clientId = vente.clientId;
      final Client? client = clientId == null
          ? null
          : await (_db.select(_db.clients)..where((t) => t.id.equals(clientId))).getSingleOrNull();

      final DateTime emission = date ?? DateTime.now();
      final String numero = await _numerotation.prochainNumeroFacture(emission);
      final int id = await _db
          .into(_db.factures)
          .insert(
            FacturesCompanion.insert(
              numero: numero,
              venteId: venteId,
              dateVentePrestation: vente.dateVente,
              totalCentimes: vente.totalCentimes,
              clientId: Value(clientId),
              clientNom: Value(client == null ? null : nullSiVide(libelleClient(client))),
              clientAdresse: Value(client == null ? null : adresseClientPourFacture(client)),
              clientSiret: Value(client == null ? null : nullSiVide(client.siret)),
              dateEmission: Value(emission),
              mentionTva: const Value(AppConstants.mentionTvaFranchise),
              conditionsPaiement: Value(nullSiVide(entreprise.conditionsPaiement) ?? conditionsPaiementParDefaut),
              iban: Value(nullSiVide(entreprise.iban)),
              messageRemerciement: Value(nullSiVide(entreprise.messageRemerciement)),
            ),
          );
      return _facture(id);
    });

    try {
      await _fabriquerPdf(facture, entreprise);
    } catch (_) {
      // La facture est enregistrée ; son PDF sera refabriqué à la demande.
    }
    return _facture(facture.id);
  }

  /// Vérifie que « Mon entreprise » permet de facturer et retourne le profil. Lance [ProfilIncomplet] sinon.
  /// Sert aussi à tout contrôler **avant** une opération qui créerait une facture en plus d'autre chose
  /// (la conversion d'un devis en commande et facture) : rien n'est alors à moitié fait.
  Future<Entreprise> verifierProfil() async {
    final Entreprise entreprise = await _parametres.lire();
    final List<String> manque = informationsManquantes(
      nomCommercial: entreprise.nomCommercial,
      nomResponsable: entreprise.nomResponsable,
      adresse: entreprise.adresse,
      codePostal: entreprise.codePostal,
      ville: entreprise.ville,
      siren: entreprise.siren,
    );
    if (manque.isNotEmpty) throw ProfilIncomplet(manque);
    return entreprise;
  }

  /// Annule la facture : elle reste dans la liste, marquée « annulée ». Son numéro reste utilisé et la vente
  /// n'est pas modifiée. Lance [DonneeInvalide] si elle est déjà annulée.
  Future<void> annuler(int factureId) {
    return _db.transaction(() async {
      final Facture facture = await _facture(factureId);
      if (facture.statut == StatutFacture.annulee) {
        throw const DonneeInvalide('Cette facture est déjà annulée.');
      }
      await (_db.update(_db.factures)..where((t) => t.id.equals(factureId))).write(
        FacturesCompanion(statut: const Value(StatutFacture.annulee), modifieLe: Value(DateTime.now())),
      );
    });
  }

  Future<Facture?> obtenir(int id) =>
      (_db.select(_db.factures)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Toutes les factures, la plus récente d'abord (numéro le plus élevé en premier à date égale).
  Future<List<Facture>> lister() {
    return (_db.select(_db.factures)..orderBy([
          (t) => OrderingTerm(expression: t.dateEmission, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ]))
        .get();
  }

  /// Liste des factures, mise à jour automatiquement (création, annulation).
  Stream<List<Facture>> observerListe() =>
      observerTables(_db, <ResultSetImplementation>{_db.factures}, lister);

  /// Une facture, mise à jour automatiquement (`null` si elle n'existe pas).
  Stream<Facture?> observerFacture(int id) =>
      observerTables(_db, <ResultSetImplementation>{_db.factures}, () => obtenir(id));

  /// Le PDF de la facture. S'il n'est plus sur le téléphone (fichier effacé, sauvegarde restaurée sans les
  /// PDF), il est refabriqué à partir de la facture et des coordonnées actuelles de l'entreprise.
  Future<Uint8List> obtenirPdf(int factureId) async {
    final Facture facture = await _facture(factureId);
    final String? nom = facture.pdfChemin;
    if (nom != null) {
      final Uint8List? octets = await _stockage.lire(nom);
      if (octets != null) return octets;
    }
    return _fabriquerPdf(facture, await _parametres.lire());
  }

  /// Fichier PDF de la facture sur le téléphone (pour le partager), après l'avoir refabriqué si besoin.
  Future<String> cheminPdf(int factureId) async {
    await obtenirPdf(factureId);
    final Facture facture = await _facture(factureId);
    return _stockage.fichier(facture.pdfChemin!).path;
  }

  // --- Interne --------------------------------------------------------------

  Future<Facture> _facture(int id) async {
    final Facture? facture = await obtenir(id);
    if (facture == null) throw const ElementIntrouvable('Cette facture n’existe plus.');
    return facture;
  }

  /// Fabrique le PDF, le range sur le téléphone et note son nom dans la facture.
  Future<Uint8List> _fabriquerPdf(Facture facture, Entreprise entreprise) async {
    final Vente vente = await (_db.select(_db.ventes)..where((t) => t.id.equals(facture.venteId))).getSingle();
    final List<LigneVente> lignes =
        await (_db.select(_db.lignesVente)
              ..where((t) => t.venteId.equals(facture.venteId))
              ..orderBy([(t) => OrderingTerm(expression: t.position), (t) => OrderingTerm(expression: t.id)]))
            .get();
    final DocumentFacture document = construireDocumentFacture(
      facture: facture,
      vente: vente,
      lignes: lignes,
      entreprise: entreprise,
    );
    final Uint8List octets = await _generateur(document);
    final String nom = await _stockage.enregistrer(facture.numero, octets);
    if (facture.pdfChemin != nom) {
      await (_db.update(_db.factures)..where((t) => t.id.equals(facture.id))).write(
        FacturesCompanion(pdfChemin: Value(nom), modifieLe: Value(DateTime.now())),
      );
    }
    return octets;
  }
}
