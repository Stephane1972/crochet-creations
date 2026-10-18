import 'package:crochet_creations/core/constants/app_constants.dart';
import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/domain/calculs/totaux.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

/// Vérifie le schéma réel : tables, index, clés étrangères et contraintes de cohérence.
/// Les insertions « fautives » passent par du SQL brut pour contourner les garde-fous du code
/// et prouver que c'est bien la base de données qui refuse.
void main() {
  late AppDatabase db;

  setUp(() => db = creerBaseEnMemoire());
  tearDown(() => db.close());

  Future<List<String>> noms(String type) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = '$type' ORDER BY name")
        .get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<void> sql(String requete, [List<Object?> args = const <Object?>[]]) =>
      db.customStatement(requete, args);

  /// Insère une vente brute (clés étrangères et contraintes évaluées par SQLite).
  Future<void> venteBrute({int sousTotal = 1000, int total = 1000}) => sql(
    'INSERT INTO ventes (sous_total_centimes, total_centimes) VALUES (?, ?)',
    <Object?>[sousTotal, total],
  );

  group('structure', () {
    test('les 15 tables du schéma existent', () async {
      final List<String> tables = (await noms(
        'table',
      )).where((n) => !n.startsWith('sqlite_')).toList();
      expect(tables, <String>[
        'clients',
        'cours',
        'depenses',
        'devis',
        'factures',
        'inscriptions_cours',
        'lignes_devis',
        'lignes_vente',
        'numerotation_documents',
        'paiements',
        'parametres_entreprise',
        'photos_produit',
        'produits',
        'variantes_produit',
        'ventes',
      ]);
    });

    test('les index des champs fréquemment recherchés existent', () async {
      final List<String> index = await noms('index');
      expect(
        index,
        containsAll(<String>[
          'idx_produits_nom',
          'idx_produits_categorie',
          'idx_clients_nom',
          'idx_clients_telephone',
          'idx_ventes_date_vente',
          'idx_ventes_client_id',
          'idx_lignes_vente_vente_id',
          'idx_paiements_vente_id',
          'idx_factures_date_emission',
          'idx_factures_vente_emise',
          'idx_devis_statut',
          'idx_cours_debut_le',
          'idx_inscriptions_cours_id',
          'idx_depenses_date_depense',
        ]),
      );
    });

    test('la version du schéma est enregistrée dans le fichier', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), AppDatabase.versionSchema);
      expect(AppDatabase.versionSchema, 1);
    });

    test('les clés étrangères sont activées', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });

    test('la ligne unique des réglages existe dès la création, avec ses valeurs par défaut', () async {
      final List<Entreprise> lignes = await db.select(db.parametresEntreprise).get();
      expect(lignes, hasLength(1));
      expect(lignes.single.id, 1);
      expect(lignes.single.modeTheme, ModeTheme.systeme);
      expect(lignes.single.conditionsPaiement, isNotEmpty);
    });

    test('il ne peut y avoir qu’une seule ligne de réglages', () async {
      await expectLater(sql('INSERT INTO parametres_entreprise (id) VALUES (2)'), throwsException);
    });
  });

  group('clés étrangères', () {
    test('une ligne de vente doit pointer vers une vente existante', () async {
      await expectLater(
        sql(
          'INSERT INTO lignes_vente (vente_id, designation, quantite, prix_unitaire_centimes, '
          'total_ligne_centimes) VALUES (999, \'Fantôme\', 1, 100, 100)',
        ),
        throwsException,
      );
    });

    test('un produit utilisé par une vente ne peut pas être supprimé', () async {
      final int produit = await db.insererProduit();
      final int vente = await db.insererVente();
      await db.into(db.lignesVente).insert(
        LignesVenteCompanion.insert(
          venteId: vente,
          designation: 'Pochette',
          quantite: 1,
          prixUnitaireCentimes: 1000,
          totalLigneCentimes: 1000,
          produitId: Value(produit),
        ),
      );
      await expectLater(sql('DELETE FROM produits WHERE id = ?', <Object?>[produit]), throwsException);
    });

    test('une vente facturée ne peut pas être supprimée', () async {
      final int vente = await db.insererVente();
      await sql(
        'INSERT INTO factures (numero, vente_id, date_vente_prestation, total_centimes) '
        "VALUES ('FACT-2026-0001', ?, 1760000000, 1000)",
        <Object?>[vente],
      );
      await expectLater(sql('DELETE FROM ventes WHERE id = ?', <Object?>[vente]), throwsException);
    });

    test('supprimer une vente non facturée supprime ses lignes', () async {
      final int vente = await db.insererVente();
      await db.into(db.lignesVente).insert(
        LignesVenteCompanion.insert(
          venteId: vente,
          designation: 'Pochette',
          quantite: 1,
          prixUnitaireCentimes: 1000,
          totalLigneCentimes: 1000,
        ),
      );
      await sql('DELETE FROM ventes WHERE id = ?', <Object?>[vente]);
      expect(await db.select(db.lignesVente).get(), isEmpty);
    });
  });

  group('contraintes de cohérence', () {
    test('un stock négatif est refusé', () async {
      await expectLater(
        sql(
          'INSERT INTO produits (reference, nom, categorie, prix_vente_centimes, quantite_stock) '
          "VALUES ('PRD-0001', 'Doudou', 'doudou', 2500, -1)",
        ),
        throwsException,
      );
    });

    test('un nom de produit vide est refusé', () async {
      await expectLater(
        sql(
          'INSERT INTO produits (reference, nom, categorie, prix_vente_centimes) '
          "VALUES ('PRD-0001', '', 'doudou', 2500)",
        ),
        throwsException,
      );
    });

    test('les noms obligatoires ne peuvent pas être vides (variante, cours, ligne de vente)', () async {
      final int produit = await db.insererProduit();
      final int vente = await db.insererVente();
      await expectLater(
        sql("INSERT INTO variantes_produit (produit_id, libelle) VALUES (?, '  ')", <Object?>[produit]),
        throwsException,
      );
      await expectLater(
        sql(
          "INSERT INTO cours (titre, debut_le, duree_minutes, prix_centimes, places) VALUES ('', 1760000000, 60, 0, 1)",
        ),
        throwsException,
      );
      await expectLater(
        sql(
          'INSERT INTO lignes_vente (vente_id, designation, quantite, prix_unitaire_centimes, '
          "total_ligne_centimes) VALUES (?, ' ', 1, 100, 100)",
          <Object?>[vente],
        ),
        throwsException,
      );
    });

    test('une référence produit est unique', () async {
      await db.insererProduit(reference: 'PRD-0001');
      await expectLater(db.insererProduit(reference: 'PRD-0001'), throwsException);
    });

    test('un client doit avoir un prénom, un nom ou une raison sociale', () async {
      await expectLater(sql('INSERT INTO clients (email) VALUES (\'a@b.fr\')'), throwsException);
      await expectLater(sql("INSERT INTO clients (nom, prenom) VALUES ('   ', '')"), throwsException);
      await sql("INSERT INTO clients (raison_sociale) VALUES ('Atelier Laine & Co')");
    });

    test('le total d’une vente doit être : sous-total − remise + frais de port', () async {
      await expectLater(venteBrute(sousTotal: 1000, total: 900), throwsException);
      await venteBrute(sousTotal: 1000, total: 1000);
      await sql(
        'INSERT INTO ventes (sous_total_centimes, frais_port_centimes, total_centimes) '
        'VALUES (1000, 490, 1490)',
      );
    });

    test('une remise ne peut pas dépasser le sous-total', () async {
      await expectLater(
        sql(
          'INSERT INTO ventes (sous_total_centimes, remise_type, remise_valeur, remise_centimes, '
          "total_centimes) VALUES (1000, 'montant', 1500, 1500, 0)",
        ),
        throwsException,
      );
    });

    test('un type de remise « aucune » n’accepte aucune valeur de remise', () async {
      await expectLater(
        sql(
          'INSERT INTO ventes (sous_total_centimes, remise_valeur, remise_centimes, total_centimes) '
          'VALUES (1000, 500, 500, 500)',
        ),
        throwsException,
      );
    });

    test('la remise en pourcentage enregistrée suit exactement le calcul de l’application', () async {
      // Pour de nombreux montants et pourcentages, la base accepte la remise calculée par le code.
      for (final int sousTotal in <int>[1, 5, 99, 1004, 1005, 1006, 12345, 99999]) {
        for (final int pourCent in <int>[0, 1, 50, 333, 1000, 1500, 2575, 9999, 10000]) {
          final TotauxDocument t = calculerTotaux(
            lignes: <LigneACalculer>[LigneACalculer(quantite: 1, prixUnitaireCentimes: sousTotal)],
            remiseType: RemiseType.pourcentage,
            remiseValeur: pourCent,
          );
          await sql(
            'INSERT INTO ventes (sous_total_centimes, remise_type, remise_valeur, remise_centimes, '
            "total_centimes) VALUES (?, 'pourcentage', ?, ?, ?)",
            <Object?>[sousTotal, pourCent, t.remiseCentimes, t.totalCentimes],
          );
        }
      }
      // Et refuse une remise qui ne correspond pas au pourcentage annoncé.
      await expectLater(
        sql(
          'INSERT INTO ventes (sous_total_centimes, remise_type, remise_valeur, remise_centimes, '
          "total_centimes) VALUES (1000, 'pourcentage', 1000, 50, 950)",
        ),
        throwsException,
      );
    });

    test('le total d’une ligne doit être : quantité × prix unitaire', () async {
      final int vente = await db.insererVente();
      await expectLater(
        sql(
          'INSERT INTO lignes_vente (vente_id, designation, quantite, prix_unitaire_centimes, '
          "total_ligne_centimes) VALUES (?, 'Pochette', 2, 500, 999)",
          <Object?>[vente],
        ),
        throwsException,
      );
      await sql(
        'INSERT INTO lignes_vente (vente_id, designation, quantite, prix_unitaire_centimes, '
        "total_ligne_centimes) VALUES (?, 'Pochette', 2, 500, 1000)",
        <Object?>[vente],
      );
    });

    test('une quantité nulle est refusée', () async {
      final int vente = await db.insererVente();
      await expectLater(
        sql(
          'INSERT INTO lignes_vente (vente_id, designation, quantite, prix_unitaire_centimes, '
          "total_ligne_centimes) VALUES (?, 'Pochette', 0, 500, 0)",
          <Object?>[vente],
        ),
        throwsException,
      );
    });

    test('un produit est un objet, un cours est une prestation', () async {
      final int vente = await db.insererVente();
      final int produit = await db.insererProduit();
      await expectLater(
        sql(
          'INSERT INTO lignes_vente (vente_id, nature, produit_id, designation, quantite, '
          "prix_unitaire_centimes, total_ligne_centimes) VALUES (?, 'service', ?, 'X', 1, 100, 100)",
          <Object?>[vente, produit],
        ),
        throwsException,
      );
      final int cours = await db.into(db.cours).insert(
        CoursCompanion.insert(
          titre: 'Initiation',
          debutLe: DateTime(2026, 11, 7, 14),
          dureeMinutes: 120,
          prixCentimes: 4500,
          places: 6,
        ),
      );
      await expectLater(
        sql(
          'INSERT INTO lignes_vente (vente_id, nature, cours_id, designation, quantite, '
          "prix_unitaire_centimes, total_ligne_centimes) VALUES (?, 'bien', ?, 'Cours', 1, 4500, 4500)",
          <Object?>[vente, cours],
        ),
        throwsException,
      );
      await sql(
        'INSERT INTO lignes_vente (vente_id, nature, cours_id, designation, quantite, '
        "prix_unitaire_centimes, total_ligne_centimes) VALUES (?, 'service', ?, 'Cours', 1, 4500, 4500)",
        <Object?>[vente, cours],
      );
    });

    test('un paiement de 0 € est refusé ; un remboursement est un montant négatif', () async {
      final int vente = await db.insererVente();
      await expectLater(
        sql(
          "INSERT INTO paiements (vente_id, montant_centimes, mode_paiement) VALUES (?, 0, 'especes')",
          <Object?>[vente],
        ),
        throwsException,
      );
      await sql(
        "INSERT INTO paiements (vente_id, montant_centimes, mode_paiement) VALUES (?, 1000, 'carte')",
        <Object?>[vente],
      );
      await sql(
        "INSERT INTO paiements (vente_id, montant_centimes, mode_paiement) VALUES (?, -1000, 'carte')",
        <Object?>[vente],
      );
    });

    test('un numéro de facture est unique', () async {
      final int vente1 = await db.insererVente();
      final int vente2 = await db.insererVente();
      const String insertion =
          'INSERT INTO factures (numero, vente_id, date_vente_prestation, total_centimes) '
          "VALUES ('FACT-2026-0001', ?, 1760000000, 1000)";
      await sql(insertion, <Object?>[vente1]);
      await expectLater(sql(insertion, <Object?>[vente2]), throwsException);
    });

    test('une vente n’a qu’une facture émise, mais peut être refacturée après annulation', () async {
      final int vente = await db.insererVente();
      Future<void> emettre(String numero) => sql(
        'INSERT INTO factures (numero, vente_id, date_vente_prestation, total_centimes) '
        'VALUES (?, ?, 1760000000, 1000)',
        <Object?>[numero, vente],
      );

      await emettre('FACT-2026-0001');
      await expectLater(emettre('FACT-2026-0002'), throwsException);

      await sql("UPDATE factures SET statut = 'annulee' WHERE numero = 'FACT-2026-0001'");
      await emettre('FACT-2026-0002');
    });

    test('la mention de TVA est recopiée sur chaque facture, avec le texte exact', () async {
      final int vente = await db.insererVente();
      await sql(
        'INSERT INTO factures (numero, vente_id, date_vente_prestation, total_centimes) '
        "VALUES ('FACT-2026-0001', ?, 1760000000, 1000)",
        <Object?>[vente],
      );
      final Facture facture = await db.select(db.factures).getSingle();
      expect(facture.mentionTva, 'TVA non applicable, article 293 B du CGI');
      expect(facture.mentionTva, AppConstants.mentionTvaFranchise);
      expect(facture.statut, StatutFacture.emise);
    });

    test('un devis : acompte au plus égal au total, validité après l’émission', () async {
      await expectLater(
        sql(
          "INSERT INTO devis (numero, sous_total_centimes, total_centimes, acompte_centimes) VALUES ('DEVIS-2026-0001', 1000, 1000, 1500)",
        ),
        throwsException,
      );
      await expectLater(
        sql(
          "INSERT INTO devis (numero, sous_total_centimes, total_centimes, date_validite) VALUES ('DEVIS-2026-0001', 1000, 1000, 0)",
        ),
        throwsException,
      );
      await sql(
        "INSERT INTO devis (numero, sous_total_centimes, total_centimes, acompte_centimes) VALUES ('DEVIS-2026-0001', 1000, 1000, 300)",
      );
      final DevisFiche devis = await db.select(db.devis).getSingle();
      expect(devis.statut, StatutDevis.brouillon);
    });

    test('un cours a au moins une place ; un client ne s’inscrit qu’une fois au même cours', () async {
      await expectLater(
        sql(
          "INSERT INTO cours (titre, debut_le, duree_minutes, prix_centimes, places) VALUES ('Initiation', 1760000000, 120, 4500, 0)",
        ),
        throwsException,
      );
      final int cours = await db.into(db.cours).insert(
        CoursCompanion.insert(
          titre: 'Initiation',
          debutLe: DateTime(2026, 11, 7, 14),
          dureeMinutes: 120,
          prixCentimes: 4500,
          places: 6,
        ),
      );
      final int client = await db.insererClient();
      const String inscription =
          'INSERT INTO inscriptions_cours (cours_id, client_id, prix_centimes) VALUES (?, ?, 4500)';
      await sql(inscription, <Object?>[cours, client]);
      await expectLater(sql(inscription, <Object?>[cours, client]), throwsException);
    });

    test('une dépense a un montant strictement positif', () async {
      await expectLater(
        sql(
          "INSERT INTO depenses (date_depense, categorie, montant_centimes) VALUES (1760000000, 'laineFil', 0)",
        ),
        throwsException,
      );
      await sql(
        "INSERT INTO depenses (date_depense, categorie, montant_centimes) VALUES (1760000000, 'laineFil', 1850)",
      );
    });

    test('une variante : libellé unique pour un même produit', () async {
      final int produit = await db.insererProduit();
      const String insertion =
          "INSERT INTO variantes_produit (produit_id, libelle) VALUES (?, 'Rose')";
      await sql(insertion, <Object?>[produit]);
      await expectLater(sql(insertion, <Object?>[produit]), throwsException);
    });
  });
}
