import 'package:drift/drift.dart';

import '../../domain/calculs/numero_document.dart';
import '../../domain/enums.dart';
import '../database/app_database.dart';

/// Attribue les numéros de factures, de devis et les références produit.
///
/// Règle importante : appeler ces méthodes **à l'intérieur de la transaction qui enregistre
/// le document** (`db.transaction`). Si l'enregistrement échoue, la transaction est annulée
/// et le numéro n'est pas consommé : la numérotation reste continue, sans trou.
class NumerotationRepository {
  NumerotationRepository(this._db);

  final AppDatabase _db;

  /// Numéro de la prochaine facture : `FACT-2026-0001`, `FACT-2026-0002`...
  /// La suite repart à 1 chaque année, selon l'année de [dateEmission].
  Future<String> prochainNumeroFacture(DateTime dateEmission) =>
      _prochainNumero(TypeCompteur.facture, dateEmission.toLocal().year);

  /// Numéro du prochain devis : `DEVIS-2026-0001`...
  Future<String> prochainNumeroDevis(DateTime dateEmission) =>
      _prochainNumero(TypeCompteur.devis, dateEmission.toLocal().year);

  /// Référence automatique du prochain produit : `PRD-0001`...
  Future<String> prochaineReferenceProduit() => _prochainNumero(TypeCompteur.produit, 0);

  Future<String> _prochainNumero(TypeCompteur type, int annee) async {
    final int numero = await _db.transaction(() async {
      final Compteur? existant =
          await (_db.select(_db.numerotationDocuments)..where(
                (t) => t.typeCompteur.equalsValue(type) & t.annee.equals(annee),
              ))
              .getSingleOrNull();

      if (existant == null) {
        await _db
            .into(_db.numerotationDocuments)
            .insert(
              NumerotationDocumentsCompanion.insert(
                typeCompteur: type,
                annee: annee,
                dernierNumero: const Value(1),
              ),
            );
        return 1;
      }

      final int suivant = existant.dernierNumero + 1;
      await (_db.update(_db.numerotationDocuments)..where((t) => t.id.equals(existant.id))).write(
        NumerotationDocumentsCompanion(dernierNumero: Value(suivant)),
      );
      return suivant;
    });

    return formaterNumero(type, annee: annee, numero: numero);
  }
}
