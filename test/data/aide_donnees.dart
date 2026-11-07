import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/sauvegarde/format_sauvegarde.dart';
import 'package:crochet_creations/domain/categories_produit.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart' show Value;

/// Photos et PDF cités par [remplirBase] (noms des fichiers, tels qu'ils sont rangés en base).
const String photoPrincipale = 'photo_1.jpg';
const String photoSecondaire = 'photo_2.jpg';
const String pdfFacture = 'FACT-2026-0001.pdf';
const String pdfDevis = 'DEVIS-2026-0001.pdf';

/// Une petite boutique : **au moins une ligne dans chacune des 15 tables**, avec des accents, des points-virgules
/// et des guillemets dans les textes (ce qui casse un CSV ou un JSON mal fabriqué).
///
/// Les dates sont à la seconde près : c'est la précision de la base.
Future<void> remplirBase(AppDatabase db) async {
  await db
      .update(db.parametresEntreprise)
      .write(
        ParametresEntrepriseCompanion(
          nomCommercial: const Value('Atelier de Camille'),
          modeTheme: const Value(ModeTheme.nuit),
          siren: const Value('123456789'),
        ),
      );

  await db
      .into(db.numerotationDocuments)
      .insert(
        NumerotationDocumentsCompanion.insert(
          typeCompteur: TypeCompteur.facture,
          annee: 2026,
          dernierNumero: const Value(1),
        ),
      );
  await db
      .into(db.numerotationDocuments)
      .insert(
        NumerotationDocumentsCompanion.insert(
          typeCompteur: TypeCompteur.devis,
          annee: 2026,
          dernierNumero: const Value(1),
        ),
      );
  await db
      .into(db.numerotationDocuments)
      .insert(
        NumerotationDocumentsCompanion.insert(
          typeCompteur: TypeCompteur.produit,
          annee: 0,
          dernierNumero: const Value(1),
        ),
      );

  final int produitId = await db
      .into(db.produits)
      .insert(
        ProduitsCompanion.insert(
          reference: 'PRD-0001',
          nom: 'Doudou lapin « Noisette »',
          categorie: CleCategorie.doudou,
          prixVenteCentimes: 2500,
          quantiteStock: const Value(4),
          matieres: const Value('Coton; laine mérinos'),
          personnalisable: const Value(true),
          photoPrincipaleChemin: const Value(photoPrincipale),
        ),
      );
  await db
      .into(db.variantesProduit)
      .insert(
        VariantesProduitCompanion.insert(
          produitId: produitId,
          libelle: 'Rose – taille M',
          quantiteStock: const Value(2),
        ),
      );
  await db
      .into(db.photosProduit)
      .insert(
        PhotosProduitCompanion.insert(
          produitId: produitId,
          chemin: photoSecondaire,
          position: const Value(1),
        ),
      );

  final int clientId = await db
      .into(db.clients)
      .insert(
        ClientsCompanion.insert(
          prenom: const Value('Marie'),
          nom: const Value('Dupont'),
          email: const Value('marie@example.fr'),
          notes: const Value('Préfère les couleurs "pastel"'),
        ),
      );

  // Un lieu de départ (« Marché ») : la vente de la boutique y est rattachée.
  final int lieuId = (await (db.select(db.lieuxVente)..where((t) => t.nom.equals('Marché'))).getSingle()).id;

  final int venteId = await db
      .into(db.ventes)
      .insert(
        VentesCompanion.insert(
          sousTotalCentimes: 5000,
          totalCentimes: 5000,
          clientId: Value(clientId),
          lieuId: Value(lieuId),
          dateVente: Value(DateTime(2026, 10, 20, 14, 30)),
          statutPaiement: const Value(StatutPaiement.payee),
        ),
      );
  await db
      .into(db.lignesVente)
      .insert(
        LignesVenteCompanion.insert(
          venteId: venteId,
          designation: 'Doudou lapin « Noisette »',
          quantite: 2,
          prixUnitaireCentimes: 2500,
          totalLigneCentimes: 5000,
          produitId: Value(produitId),
        ),
      );
  await db
      .into(db.paiements)
      .insert(
        PaiementsCompanion.insert(
          venteId: venteId,
          montantCentimes: 5000,
          modePaiement: ModePaiement.carte,
          datePaiement: Value(DateTime(2026, 10, 20, 14, 35)),
        ),
      );
  await db
      .into(db.factures)
      .insert(
        FacturesCompanion.insert(
          numero: 'FACT-2026-0001',
          venteId: venteId,
          dateVentePrestation: DateTime(2026, 10, 20, 14, 30),
          totalCentimes: 5000,
          clientId: Value(clientId),
          clientNom: const Value('Marie Dupont'),
          dateEmission: Value(DateTime(2026, 10, 20, 15)),
          pdfChemin: const Value(pdfFacture),
        ),
      );

  // Une vente « client de passage », sans client, payée en partie.
  final int ventePassageId = await db
      .into(db.ventes)
      .insert(
        VentesCompanion.insert(
          sousTotalCentimes: 1200,
          totalCentimes: 1200,
          dateVente: Value(DateTime(2026, 10, 25, 10)),
          statutPaiement: const Value(StatutPaiement.partiellementPayee),
          notes: const Value('Marché; stand 3'),
        ),
      );
  await db
      .into(db.paiements)
      .insert(
        PaiementsCompanion.insert(
          venteId: ventePassageId,
          montantCentimes: 500,
          modePaiement: ModePaiement.especes,
          datePaiement: Value(DateTime(2026, 10, 25, 10, 5)),
        ),
      );

  final int devisId = await db
      .into(db.devis)
      .insert(
        DevisCompanion.insert(
          numero: 'DEVIS-2026-0001',
          sousTotalCentimes: 6000,
          totalCentimes: 6000,
          clientId: Value(clientId),
          dateEmission: Value(DateTime(2026, 10, 22, 9)),
          dateValidite: Value(DateTime(2026, 11, 22, 9)),
          statut: const Value(StatutDevis.envoye),
          delaiRealisation: const Value('3 semaines'),
        ),
      );
  await db
      .into(db.lignesDevis)
      .insert(
        LignesDevisCompanion.insert(
          devisId: devisId,
          designation: 'Couverture bébé sur mesure',
          quantite: 1,
          prixUnitaireCentimes: 6000,
          totalLigneCentimes: 6000,
          nature: const Value(NatureLigne.service),
        ),
      );

  final int coursId = await db
      .into(db.cours)
      .insert(
        CoursCompanion.insert(
          titre: 'Initiation au crochet',
          debutLe: DateTime(2026, 11, 14, 14),
          dureeMinutes: 150,
          prixCentimes: 4500,
          places: 4,
          lieu: const Value('Atelier de Camille'),
        ),
      );
  await db
      .into(db.inscriptionsCours)
      .insert(
        InscriptionsCoursCompanion.insert(
          coursId: coursId,
          clientId: clientId,
          prixCentimes: 4500,
          dateInscription: Value(DateTime(2026, 10, 26, 18)),
        ),
      );

  await db
      .into(db.depenses)
      .insert(
        DepensesCompanion.insert(
          dateDepense: DateTime(2026, 10, 5),
          categorie: CategorieDepense.laineFil,
          montantCentimes: 2490,
          fournisseur: const Value('Mercerie du Port'),
          produitId: Value(produitId),
        ),
      );
}

/// Toutes les lignes de toutes les tables, telles que la base les contient : sert à vérifier qu'une
/// sauvegarde puis une restauration redonnent **exactement** les mêmes données.
Future<Map<String, List<Map<String, Object?>>>> instantane(AppDatabase db) async {
  final Map<String, List<Map<String, Object?>>> resultat = <String, List<Map<String, Object?>>>{};
  for (final String table in FormatSauvegarde.tables) {
    final lignes = await db.customSelect('SELECT * FROM "$table" ORDER BY id').get();
    resultat[table] = lignes.map((ligne) => Map<String, Object?>.from(ligne.data)).toList();
  }
  return resultat;
}
