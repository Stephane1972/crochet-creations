import 'package:drift/drift.dart';

import '../../core/utils/texte.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_depenses.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import 'depense_vues.dart';

/// Ce que l'utilisatrice saisit pour une dépense.
class DonneesDepense {
  const DonneesDepense({
    required this.date,
    required this.categorie,
    required this.montantCentimes,
    this.fournisseur,
    this.description,
    this.photoTicketChemin,
    this.produitId,
  });

  /// Jour de la dépense (l'heure est ignorée).
  final DateTime date;
  final CategorieDepense categorie;
  final int montantCentimes;
  final String? fournisseur;
  final String? description;

  /// Nom du fichier de la photo du ticket (voir `StockagePhotos`) ; `null` = pas de photo.
  final String? photoTicketChemin;

  /// Produit concerné (information seulement : rien d'autre n'est modifié) ; `null` = aucun.
  final int? produitId;
}

/// Dépenses de l'entreprise : laine, fournitures, emballage, frais de marché...
///
/// - Un montant est toujours positif, la date n'est jamais dans le futur.
/// - Le produit concerné est une simple information : il ne change ni le coût matière ni le stock.
/// - Une dépense ne se supprime pas : elle s'**archive** (elle quitte la liste et les totaux) et se restaure.
class DepenseRepository {
  DepenseRepository(this._db);

  final AppDatabase _db;

  Future<Depense> creer(DonneesDepense d, {DateTime? maintenant}) async {
    _verifier(d, maintenant ?? DateTime.now());
    return _db.transaction(() async {
      await _verifierProduit(d.produitId);
      final int id = await _db
          .into(_db.depenses)
          .insert(
            DepensesCompanion.insert(
              dateDepense: jourDe(d.date),
              categorie: d.categorie,
              montantCentimes: d.montantCentimes,
              fournisseur: Value(nullSiVide(d.fournisseur)),
              description: Value(nullSiVide(d.description)),
              photoTicketChemin: Value(d.photoTicketChemin),
              produitId: Value(d.produitId),
            ),
          );
      return _depense(id);
    });
  }

  Future<Depense> modifier(int id, DonneesDepense d, {DateTime? maintenant}) async {
    _verifier(d, maintenant ?? DateTime.now());
    return _db.transaction(() async {
      await _depense(id);
      await _verifierProduit(d.produitId);
      await (_db.update(_db.depenses)..where((t) => t.id.equals(id))).write(
        DepensesCompanion(
          dateDepense: Value(jourDe(d.date)),
          categorie: Value(d.categorie),
          montantCentimes: Value(d.montantCentimes),
          fournisseur: Value(nullSiVide(d.fournisseur)),
          description: Value(nullSiVide(d.description)),
          photoTicketChemin: Value(d.photoTicketChemin),
          produitId: Value(d.produitId),
          modifieLe: Value(DateTime.now()),
        ),
      );
      return _depense(id);
    });
  }

  /// Archive la dépense : elle quitte la liste et les totaux, mais reste récupérable.
  Future<void> archiver(int id) async {
    await _depense(id);
    await _marquerArchive(id, DateTime.now());
  }

  Future<void> restaurer(int id) async {
    await _depense(id);
    await _marquerArchive(id, null);
  }

  Future<Depense?> obtenir(int id) =>
      (_db.select(_db.depenses)..where((t) => t.id.equals(id))).getSingleOrNull();

  // --- Consultation -----------------------------------------------------------

  /// Les dépenses du mois [mois] de l'année [annee] : la plus récente d'abord. Par défaut les dépenses actives ;
  /// avec [archivees], celles qui ont été archivées. [categorie] ne garde que cette catégorie.
  /// Le total est celui des lignes retournées.
  Future<ListeDepenses> lister({
    required int annee,
    required int mois,
    CategorieDepense? categorie,
    bool archivees = false,
  }) async {
    final List<TypedResult> resultats =
        await (_db.select(_db.depenses).join(<Join>[
                leftOuterJoin(_db.produits, _db.produits.id.equalsExp(_db.depenses.produitId)),
              ])
              ..orderBy(<OrderingTerm>[
                OrderingTerm.desc(_db.depenses.dateDepense),
                OrderingTerm.desc(_db.depenses.id),
              ]))
            .get();

    final List<DepenseLigne> lignes = <DepenseLigne>[];
    for (final TypedResult r in resultats) {
      final Depense depense = r.readTable(_db.depenses);
      if (!estDansLeMois(depense.dateDepense, annee, mois)) continue;
      if ((depense.archiveLe != null) != archivees) continue;
      if (categorie != null && depense.categorie != categorie) continue;
      lignes.add(DepenseLigne(depense: depense, produit: r.readTableOrNull(_db.produits)));
    }
    return ListeDepenses(
      lignes: lignes,
      totalCentimes: totalCentimes(lignes.map((DepenseLigne l) => l.depense.montantCentimes)),
    );
  }

  /// Liste des dépenses, mise à jour automatiquement (dépense ajoutée, modifiée ou archivée, produit renommé).
  Stream<ListeDepenses> observerListe({
    required int annee,
    required int mois,
    CategorieDepense? categorie,
    bool archivees = false,
  }) => observerTables(
    _db,
    <ResultSetImplementation>{_db.depenses, _db.produits},
    () => lister(annee: annee, mois: mois, categorie: categorie, archivees: archivees),
  );

  // --- Interne ----------------------------------------------------------------

  void _verifier(DonneesDepense d, DateTime maintenant) {
    verifierDepense(
      montantCentimes: d.montantCentimes,
      date: d.date,
      maintenant: maintenant,
      fournisseur: d.fournisseur,
      description: d.description,
    );
  }

  Future<void> _verifierProduit(int? produitId) async {
    if (produitId == null) return;
    final Produit? produit = await (_db.select(_db.produits)..where((t) => t.id.equals(produitId))).getSingleOrNull();
    if (produit == null) throw const ElementIntrouvable('Ce produit n’existe plus.');
  }

  Future<Depense> _depense(int id) async {
    final Depense? depense = await obtenir(id);
    if (depense == null) throw const ElementIntrouvable('Cette dépense n’existe plus.');
    return depense;
  }

  Future<void> _marquerArchive(int id, DateTime? quand) async {
    await (_db.update(_db.depenses)..where((t) => t.id.equals(id))).write(
      DepensesCompanion(archiveLe: Value(quand), modifieLe: Value(DateTime.now())),
    );
  }
}
