/// Schéma de la base de données (SQLite, via Drift) : 15 tables.
///
/// Conventions (détail dans ARCHITECTURE.md) :
/// - **Montants** : nombres entiers de centimes (`1250` = 12,50 €). Jamais de décimaux.
/// - **Dates** : Drift enregistre les `DateTime` en secondes depuis 1970 (UTC), donc sans
///   ambiguïté de fuseau horaire ; elles sont relues en heure locale.
/// - **Suppression douce** : `archive_le` renseigné = élément archivé (masqué mais conservé).
///   Les ventes, factures et devis ne s'archivent pas : ils changent de statut.
/// - **Clés étrangères** : activées à l'ouverture (`PRAGMA foreign_keys = ON`), par défaut
///   en `RESTRICT` : on ne peut pas supprimer ce qui est encore utilisé par une vente, une facture...
/// - **Contraintes** : noms non vides, quantités et montants positifs, totaux cohérents,
///   numéros uniques... La base refuse un enregistrement incohérent même si le code se trompe.
///   (`withLength` de Drift ne contrôle que côté Dart : la base reçoit donc aussi un `CHECK`.)
/// - Les valeurs des listes de choix (`enums.dart`) sont enregistrées sous leur nom Dart ;
///   certaines sont citées dans les contraintes SQL ci-dessous.
///
/// Toute modification de ce fichier demande une **nouvelle version de schéma** et une
/// migration (voir `app_database.dart`).
library;

import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/enums.dart';

// -----------------------------------------------------------------------------
// Colonnes communes
// -----------------------------------------------------------------------------

/// Date de création et de dernière modification (mise à jour par les repositories).
mixin Tracabilite on Table {
  DateTimeColumn get creeLe => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifieLe => dateTime().withDefault(currentDateAndTime)();
}

/// Suppression douce : `archive_le` est vide tant que l'élément est actif.
mixin Archivable on Table {
  DateTimeColumn get archiveLe => dateTime().nullable()();
}

// -----------------------------------------------------------------------------
// Réglages et compteurs
// -----------------------------------------------------------------------------

/// Profil « Mon entreprise » et réglages : **une seule ligne** (`id = 1`), créée
/// automatiquement à l'ouverture de la base.
@DataClassName('Entreprise')
class ParametresEntreprise extends Table with Tracabilite {
  IntColumn get id => integer().withDefault(const Constant(1)).check(id.equals(1))();

  TextColumn get nomCommercial => text().withDefault(const Constant(''))();

  /// Nom et prénom de l'entrepreneuse (à afficher sur les factures).
  TextColumn get nomResponsable => text().nullable()();
  TextColumn get adresse => text().nullable()();
  TextColumn get codePostal => text().nullable()();
  TextColumn get ville => text().nullable()();
  TextColumn get telephone => text().nullable()();
  TextColumn get email => text().nullable()();

  /// Numéro SIREN (9 chiffres).
  TextColumn get siren => text().nullable()();

  /// Chemin du logo personnalisé ; vide = logo de l'application.
  TextColumn get logoChemin => text().nullable()();

  TextColumn get conditionsPaiement =>
      text().withDefault(const Constant('Paiement à réception de la facture.'))();

  /// IBAN facultatif, imprimé sur les factures s'il est renseigné.
  TextColumn get iban => text().nullable()();
  TextColumn get messageRemerciement =>
      text().withDefault(const Constant('Merci pour votre confiance !'))();

  /// Mode jour / nuit / automatique choisi dans les réglages.
  TextColumn get modeTheme => textEnum<ModeTheme>().withDefault(const Constant('systeme'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Dernier numéro attribué pour chaque suite : factures et devis (une suite par année),
/// références produit (une seule suite, année = 0).
///
/// Un numéro n'est attribué qu'à l'intérieur de la transaction qui enregistre le document :
/// si l'enregistrement échoue, le numéro n'est pas consommé (pas de « trou »).
@DataClassName('Compteur')
class NumerotationDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get typeCompteur => textEnum<TypeCompteur>()();
  IntColumn get annee => integer().check(annee.isBiggerOrEqualValue(0))();
  IntColumn get dernierNumero =>
      integer().withDefault(const Constant(0)).check(dernierNumero.isBiggerOrEqualValue(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {typeCompteur, annee},
  ];
}

// -----------------------------------------------------------------------------
// Catalogue
// -----------------------------------------------------------------------------

@DataClassName('Produit')
@TableIndex(name: 'idx_produits_nom', columns: {#nom})
@TableIndex(name: 'idx_produits_categorie', columns: {#categorie})
@TableIndex(name: 'idx_produits_statut', columns: {#statut})
@TableIndex(name: 'idx_produits_archive_le', columns: {#archiveLe})
class Produits extends Table with Tracabilite, Archivable {
  IntColumn get id => integer().autoIncrement()();

  /// Référence automatique (PRD-0001...), unique.
  TextColumn get reference => text().unique()();
  TextColumn get nom => text().withLength(min: 1, max: 200)();
  TextColumn get categorie => textEnum<CategorieProduit>()();
  TextColumn get description => text().nullable()();
  TextColumn get matieres => text().nullable()();

  /// Couleur d'un produit sans variantes (sinon, voir `variantes_produit`).
  TextColumn get couleur => text().nullable()();

  /// Taille ou dimensions d'un produit sans variantes.
  TextColumn get dimensions => text().nullable()();
  IntColumn get tempsFabricationMinutes =>
      integer().nullable().check(tempsFabricationMinutes.isBiggerOrEqualValue(0))();

  /// Coût des matières, pour estimer la marge.
  IntColumn get coutMatiereCentimes =>
      integer().withDefault(const Constant(0)).check(coutMatiereCentimes.isBiggerOrEqualValue(0))();
  IntColumn get prixVenteCentimes => integer().check(prixVenteCentimes.isBiggerOrEqualValue(0))();

  /// Stock d'un produit **sans variantes**. Si le produit a des variantes, le stock
  /// est porté par chaque variante et cette colonne n'est pas utilisée.
  IntColumn get quantiteStock =>
      integer().withDefault(const Constant(0)).check(quantiteStock.isBiggerOrEqualValue(0))();
  IntColumn get seuilAlerteStock =>
      integer().withDefault(const Constant(0)).check(seuilAlerteStock.isBiggerOrEqualValue(0))();
  TextColumn get statut =>
      textEnum<StatutProduit>().withDefault(const Constant('disponible'))();
  BoolColumn get personnalisable => boolean().withDefault(const Constant(false))();

  /// Chemin de la photo principale (les autres photos sont dans `photos_produit`).
  TextColumn get photoPrincipaleChemin => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(nom)) > 0)',
    'CHECK (length(trim(reference)) > 0)',
  ];
}

/// Variante d'un produit (couleur, taille...) avec son propre stock.
@DataClassName('VarianteProduit')
class VariantesProduit extends Table with Tracabilite, Archivable {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get produitId =>
      integer().references(Produits, #id, onDelete: KeyAction.restrict)();

  /// Nom affiché, par exemple « Rose – taille M ». Unique pour un même produit.
  TextColumn get libelle => text().withLength(min: 1, max: 120)();
  TextColumn get couleur => text().nullable()();
  TextColumn get taille => text().nullable()();

  /// Prix propre à la variante ; vide = prix du produit.
  IntColumn get prixCentimes => integer().nullable().check(prixCentimes.isBiggerOrEqualValue(0))();
  IntColumn get quantiteStock =>
      integer().withDefault(const Constant(0)).check(quantiteStock.isBiggerOrEqualValue(0))();

  /// Seuil d'alerte propre à la variante ; vide = seuil du produit.
  IntColumn get seuilAlerteStock =>
      integer().nullable().check(seuilAlerteStock.isBiggerOrEqualValue(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {produitId, libelle},
  ];

  @override
  List<String> get customConstraints => ['CHECK (length(trim(libelle)) > 0)'];
}

/// Photos secondaires d'un produit (la principale est dans `produits`).
@DataClassName('PhotoProduit')
@TableIndex(name: 'idx_photos_produit_produit_id', columns: {#produitId})
class PhotosProduit extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get produitId =>
      integer().references(Produits, #id, onDelete: KeyAction.cascade)();
  TextColumn get chemin => text().withLength(min: 1)();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => ['CHECK (length(trim(chemin)) > 0)'];
}

// -----------------------------------------------------------------------------
// Clients
// -----------------------------------------------------------------------------

/// Les ventes « client de passage » n'ont pas de fiche : `ventes.client_id` reste vide.
@DataClassName('Client')
@TableIndex(name: 'idx_clients_nom', columns: {#nom, #prenom})
@TableIndex(name: 'idx_clients_telephone', columns: {#telephone})
@TableIndex(name: 'idx_clients_email', columns: {#email})
@TableIndex(name: 'idx_clients_archive_le', columns: {#archiveLe})
class Clients extends Table with Tracabilite, Archivable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get typeClient =>
      textEnum<TypeClient>().withDefault(const Constant('particulier'))();
  TextColumn get civilite => textEnum<Civilite>().nullable()();
  TextColumn get prenom => text().nullable()();
  TextColumn get nom => text().nullable()();

  /// Nom de l'entreprise (clients professionnels).
  TextColumn get raisonSociale => text().nullable()();
  TextColumn get telephone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get adresse => text().nullable()();
  TextColumn get codePostal => text().nullable()();
  TextColumn get ville => text().nullable()();

  /// SIREN ou SIRET (clients professionnels).
  TextColumn get siret => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK (length(trim(coalesce(prenom, '') || coalesce(nom, '') || coalesce(raison_sociale, ''))) > 0)",
  ];
}

// -----------------------------------------------------------------------------
// Ventes, lignes et paiements
// -----------------------------------------------------------------------------

/// Une vente. Le total est toujours : sous-total − remise + frais de port.
/// Le statut de paiement est recalculé à chaque paiement (voir `calculerStatutPaiement`).
@DataClassName('Vente')
@TableIndex(name: 'idx_ventes_client_id', columns: {#clientId})
@TableIndex(name: 'idx_ventes_date_vente', columns: {#dateVente})
@TableIndex(name: 'idx_ventes_statut_paiement', columns: {#statutPaiement})
class Ventes extends Table with Tracabilite {
  IntColumn get id => integer().autoIncrement()();

  /// Vide = « client de passage ».
  IntColumn get clientId =>
      integer().nullable().references(Clients, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get dateVente => dateTime().withDefault(currentDateAndTime)();
  TextColumn get statut => textEnum<StatutVente>().withDefault(const Constant('validee'))();

  IntColumn get sousTotalCentimes => integer().check(sousTotalCentimes.isBiggerOrEqualValue(0))();
  TextColumn get remiseType => textEnum<RemiseType>().withDefault(const Constant('aucune'))();

  /// Pourcentage : centièmes de pour cent (1500 = 15 %). Montant : centimes.
  IntColumn get remiseValeur =>
      integer().withDefault(const Constant(0)).check(remiseValeur.isBiggerOrEqualValue(0))();

  /// Montant effectif de la remise, en centimes.
  IntColumn get remiseCentimes =>
      integer().withDefault(const Constant(0)).check(remiseCentimes.isBiggerOrEqualValue(0))();
  IntColumn get fraisPortCentimes =>
      integer().withDefault(const Constant(0)).check(fraisPortCentimes.isBiggerOrEqualValue(0))();
  IntColumn get totalCentimes => integer().check(totalCentimes.isBiggerOrEqualValue(0))();
  TextColumn get statutPaiement =>
      textEnum<StatutPaiement>().withDefault(const Constant('impayee'))();
  TextColumn get notes => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (remise_centimes <= sous_total_centimes)',
    'CHECK (total_centimes = sous_total_centimes - remise_centimes + frais_port_centimes)',
    "CHECK (remise_type <> 'aucune' OR (remise_valeur = 0 AND remise_centimes = 0))",
    "CHECK (remise_type <> 'pourcentage' OR remise_valeur <= 10000)",
    "CHECK (remise_type <> 'pourcentage' OR remise_centimes = (sous_total_centimes * remise_valeur + 5000) / 10000)",
    "CHECK (remise_type <> 'montant' OR remise_valeur = remise_centimes)",
  ];
}

/// Une ligne de vente : un produit (éventuellement une variante), un cours, ou une ligne libre.
/// Désignation et prix sont recopiés au moment de la vente : modifier le catalogue
/// plus tard ne change jamais une vente passée.
@DataClassName('LigneVente')
@TableIndex(name: 'idx_lignes_vente_vente_id', columns: {#venteId})
@TableIndex(name: 'idx_lignes_vente_produit_id', columns: {#produitId})
@TableIndex(name: 'idx_lignes_vente_cours_id', columns: {#coursId})
class LignesVente extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get venteId => integer().references(Ventes, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer().withDefault(const Constant(0))();

  /// Alimente le bon compteur de chiffre d'affaires (objets / prestations).
  TextColumn get nature => textEnum<NatureLigne>().withDefault(const Constant('bien'))();
  IntColumn get produitId =>
      integer().nullable().references(Produits, #id, onDelete: KeyAction.restrict)();
  IntColumn get varianteId =>
      integer().nullable().references(VariantesProduit, #id, onDelete: KeyAction.restrict)();
  IntColumn get coursId =>
      integer().nullable().references(Cours, #id, onDelete: KeyAction.restrict)();
  TextColumn get designation => text().withLength(min: 1, max: 300)();
  TextColumn get description => text().nullable()();
  IntColumn get quantite => integer().check(quantite.isBiggerOrEqualValue(1))();
  IntColumn get prixUnitaireCentimes =>
      integer().check(prixUnitaireCentimes.isBiggerOrEqualValue(0))();

  /// Coût matière unitaire au moment de la vente, pour la marge estimée.
  IntColumn get coutUnitaireCentimes =>
      integer().withDefault(const Constant(0)).check(coutUnitaireCentimes.isBiggerOrEqualValue(0))();
  IntColumn get totalLigneCentimes => integer().check(totalLigneCentimes.isBiggerOrEqualValue(0))();

  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(designation)) > 0)',
    'CHECK (total_ligne_centimes = quantite * prix_unitaire_centimes)',
    'CHECK (variante_id IS NULL OR produit_id IS NOT NULL)',
    "CHECK (produit_id IS NULL OR nature = 'bien')",
    "CHECK (cours_id IS NULL OR (produit_id IS NULL AND nature = 'service'))",
  ];
}

/// Encaissements et remboursements d'une vente.
/// Un remboursement est un paiement de **montant négatif** ; le montant 0 est refusé.
@DataClassName('Paiement')
@TableIndex(name: 'idx_paiements_vente_id', columns: {#venteId})
@TableIndex(name: 'idx_paiements_date_paiement', columns: {#datePaiement})
class Paiements extends Table with Tracabilite {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get venteId => integer().references(Ventes, #id, onDelete: KeyAction.restrict)();
  IntColumn get montantCentimes => integer().check(montantCentimes.equals(0).not())();
  TextColumn get modePaiement => textEnum<ModePaiement>()();
  DateTimeColumn get datePaiement => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
}

// -----------------------------------------------------------------------------
// Factures
// -----------------------------------------------------------------------------

/// Une facture émise à partir d'une vente. Numéro unique et chronologique (FACT-2026-0001).
/// Les informations légales sont **recopiées** à l'émission (client, mention TVA, conditions,
/// IBAN, remerciement) : modifier ensuite un client ou les réglages ne change pas la facture.
/// Les lignes et montants se lisent dans la vente liée, qui n'est plus modifiable.
@DataClassName('Facture')
@TableIndex(name: 'idx_factures_date_emission', columns: {#dateEmission})
@TableIndex(name: 'idx_factures_client_id', columns: {#clientId})
@TableIndex.sql(
  "CREATE UNIQUE INDEX idx_factures_vente_emise ON factures (vente_id) WHERE statut = 'emise'",
)
class Factures extends Table with Tracabilite {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get numero => text().unique()();

  /// Une seule facture « émise » par vente (index ci-dessus) ; une facture annulée
  /// n'empêche pas d'en émettre une nouvelle.
  IntColumn get venteId => integer().references(Ventes, #id, onDelete: KeyAction.restrict)();
  IntColumn get clientId =>
      integer().nullable().references(Clients, #id, onDelete: KeyAction.restrict)();

  /// Coordonnées du client au moment de l'émission.
  TextColumn get clientNom => text().nullable()();
  TextColumn get clientAdresse => text().nullable()();
  TextColumn get clientSiret => text().nullable()();

  DateTimeColumn get dateEmission => dateTime().withDefault(currentDateAndTime)();

  /// Date de la vente ou de la prestation.
  DateTimeColumn get dateVentePrestation => dateTime()();
  DateTimeColumn get dateEcheance => dateTime().nullable()();
  IntColumn get totalCentimes => integer().check(totalCentimes.isBiggerOrEqualValue(0))();

  /// « TVA non applicable, article 293 B du CGI » (recopiée sur chaque facture).
  TextColumn get mentionTva =>
      text().withDefault(const Constant(AppConstants.mentionTvaFranchise))();
  TextColumn get conditionsPaiement => text().nullable()();
  TextColumn get iban => text().nullable()();
  TextColumn get messageRemerciement => text().nullable()();
  TextColumn get statut => textEnum<StatutFacture>().withDefault(const Constant('emise'))();

  /// Chemin du PDF enregistré sur le téléphone.
  TextColumn get pdfChemin => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (date_echeance IS NULL OR date_echeance >= date_emission)',
  ];
}

// -----------------------------------------------------------------------------
// Devis
// -----------------------------------------------------------------------------

/// Un devis (DEVIS-2026-0001). Converti, il pointe vers la vente créée (`vente_id`).
@DataClassName('DevisFiche')
@TableIndex(name: 'idx_devis_client_id', columns: {#clientId})
@TableIndex(name: 'idx_devis_statut', columns: {#statut})
@TableIndex(name: 'idx_devis_date_emission', columns: {#dateEmission})
class Devis extends Table with Tracabilite {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get numero => text().unique()();
  IntColumn get clientId =>
      integer().nullable().references(Clients, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get dateEmission => dateTime().withDefault(currentDateAndTime)();

  /// Date limite de validité du devis.
  DateTimeColumn get dateValidite => dateTime().nullable()();

  /// Délai de réalisation, en texte libre (« 3 semaines »).
  TextColumn get delaiRealisation => text().nullable()();

  /// Acompte demandé, en centimes.
  IntColumn get acompteCentimes =>
      integer().withDefault(const Constant(0)).check(acompteCentimes.isBiggerOrEqualValue(0))();
  TextColumn get statut => textEnum<StatutDevis>().withDefault(const Constant('brouillon'))();

  IntColumn get sousTotalCentimes => integer().check(sousTotalCentimes.isBiggerOrEqualValue(0))();
  TextColumn get remiseType => textEnum<RemiseType>().withDefault(const Constant('aucune'))();
  IntColumn get remiseValeur =>
      integer().withDefault(const Constant(0)).check(remiseValeur.isBiggerOrEqualValue(0))();
  IntColumn get remiseCentimes =>
      integer().withDefault(const Constant(0)).check(remiseCentimes.isBiggerOrEqualValue(0))();
  IntColumn get fraisPortCentimes =>
      integer().withDefault(const Constant(0)).check(fraisPortCentimes.isBiggerOrEqualValue(0))();
  IntColumn get totalCentimes => integer().check(totalCentimes.isBiggerOrEqualValue(0))();
  TextColumn get notes => text().nullable()();

  /// Vente créée lors de la conversion du devis (vide tant qu'il n'est pas converti).
  IntColumn get venteId =>
      integer().nullable().references(Ventes, #id, onDelete: KeyAction.restrict)();

  @override
  List<String> get customConstraints => [
    'CHECK (date_validite IS NULL OR date_validite >= date_emission)',
    'CHECK (acompte_centimes <= total_centimes)',
    'CHECK (remise_centimes <= sous_total_centimes)',
    'CHECK (total_centimes = sous_total_centimes - remise_centimes + frais_port_centimes)',
    "CHECK (remise_type <> 'aucune' OR (remise_valeur = 0 AND remise_centimes = 0))",
    "CHECK (remise_type <> 'pourcentage' OR remise_valeur <= 10000)",
    "CHECK (remise_type <> 'pourcentage' OR remise_centimes = (sous_total_centimes * remise_valeur + 5000) / 10000)",
    "CHECK (remise_type <> 'montant' OR remise_valeur = remise_centimes)",
  ];
}

/// Ligne d'un devis : ligne libre, produit ou cours.
@DataClassName('LigneDevis')
@TableIndex(name: 'idx_lignes_devis_devis_id', columns: {#devisId})
class LignesDevis extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get devisId => integer().references(Devis, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get nature => textEnum<NatureLigne>().withDefault(const Constant('bien'))();
  IntColumn get produitId =>
      integer().nullable().references(Produits, #id, onDelete: KeyAction.restrict)();
  IntColumn get varianteId =>
      integer().nullable().references(VariantesProduit, #id, onDelete: KeyAction.restrict)();
  IntColumn get coursId =>
      integer().nullable().references(Cours, #id, onDelete: KeyAction.restrict)();
  TextColumn get designation => text().withLength(min: 1, max: 300)();

  /// Description détaillée (ligne libre).
  TextColumn get description => text().nullable()();
  IntColumn get quantite => integer().check(quantite.isBiggerOrEqualValue(1))();
  IntColumn get prixUnitaireCentimes =>
      integer().check(prixUnitaireCentimes.isBiggerOrEqualValue(0))();
  IntColumn get totalLigneCentimes => integer().check(totalLigneCentimes.isBiggerOrEqualValue(0))();

  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(designation)) > 0)',
    'CHECK (total_ligne_centimes = quantite * prix_unitaire_centimes)',
    'CHECK (variante_id IS NULL OR produit_id IS NOT NULL)',
    "CHECK (produit_id IS NULL OR nature = 'bien')",
    "CHECK (cours_id IS NULL OR (produit_id IS NULL AND nature = 'service'))",
  ];
}

// -----------------------------------------------------------------------------
// Cours
// -----------------------------------------------------------------------------

@DataClassName('CoursFiche')
@TableIndex(name: 'idx_cours_debut_le', columns: {#debutLe})
@TableIndex(name: 'idx_cours_titre', columns: {#titre})
@TableIndex(name: 'idx_cours_archive_le', columns: {#archiveLe})
class Cours extends Table with Tracabilite, Archivable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get titre => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();

  /// Date et heure de début.
  DateTimeColumn get debutLe => dateTime()();
  IntColumn get dureeMinutes => integer().check(dureeMinutes.isBiggerOrEqualValue(1))();
  TextColumn get lieu => text().nullable()();
  IntColumn get prixCentimes => integer().check(prixCentimes.isBiggerOrEqualValue(0))();

  /// Nombre de places ; au-delà, les inscriptions vont en liste d'attente.
  IntColumn get places => integer().check(places.isBiggerOrEqualValue(1))();
  TextColumn get niveau => textEnum<NiveauCours>().withDefault(const Constant('tousNiveaux'))();
  BoolColumn get materielInclus => boolean().withDefault(const Constant(false))();
  TextColumn get photoChemin => text().nullable()();
  TextColumn get statut => textEnum<StatutCours>().withDefault(const Constant('planifie'))();

  @override
  List<String> get customConstraints => ['CHECK (length(trim(titre)) > 0)'];
}

/// Inscription d'un client à un cours. Une seule ligne par couple (cours, client) :
/// se réinscrire réactive la ligne existante. La liste d'attente se lit dans l'ordre
/// de `date_inscription`. Paiement, facture et reçu passent par la vente liée.
@DataClassName('Inscription')
@TableIndex(name: 'idx_inscriptions_cours_id', columns: {#coursId})
@TableIndex(name: 'idx_inscriptions_client_id', columns: {#clientId})
@TableIndex(name: 'idx_inscriptions_vente_id', columns: {#venteId})
class InscriptionsCours extends Table with Tracabilite {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get coursId => integer().references(Cours, #id, onDelete: KeyAction.restrict)();
  IntColumn get clientId => integer().references(Clients, #id, onDelete: KeyAction.restrict)();
  TextColumn get statut =>
      textEnum<StatutInscription>().withDefault(const Constant('confirmee'))();
  DateTimeColumn get dateInscription => dateTime().withDefault(currentDateAndTime)();

  /// Prix convenu pour cette personne (par défaut, le prix du cours).
  IntColumn get prixCentimes => integer().check(prixCentimes.isBiggerOrEqualValue(0))();

  /// Vente qui encaisse cette inscription.
  IntColumn get venteId =>
      integer().nullable().references(Ventes, #id, onDelete: KeyAction.restrict)();
  TextColumn get notes => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {coursId, clientId},
  ];
}

// -----------------------------------------------------------------------------
// Dépenses
// -----------------------------------------------------------------------------

@DataClassName('Depense')
@TableIndex(name: 'idx_depenses_date_depense', columns: {#dateDepense})
@TableIndex(name: 'idx_depenses_categorie', columns: {#categorie})
@TableIndex(name: 'idx_depenses_produit_id', columns: {#produitId})
@TableIndex(name: 'idx_depenses_archive_le', columns: {#archiveLe})
class Depenses extends Table with Tracabilite, Archivable {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get dateDepense => dateTime()();
  TextColumn get categorie => textEnum<CategorieDepense>()();
  IntColumn get montantCentimes => integer().check(montantCentimes.isBiggerThanValue(0))();
  TextColumn get fournisseur => text().nullable()();
  TextColumn get description => text().nullable()();

  /// Chemin de la photo du ticket.
  TextColumn get photoTicketChemin => text().nullable()();

  /// Produit concerné par la dépense, s'il y en a un.
  IntColumn get produitId =>
      integer().nullable().references(Produits, #id, onDelete: KeyAction.restrict)();
}
