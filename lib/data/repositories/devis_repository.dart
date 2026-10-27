import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../core/utils/texte.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/calculs/totaux.dart';
import '../../domain/document_devis.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_devis.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';
import '../pdf/construire_document.dart';
import '../stockage/stockage_pdf.dart';
import 'devis_vues.dart';
import 'facture_repository.dart';
import 'numerotation_repository.dart';
import 'parametres_repository.dart';
import 'vente_repository.dart';

/// Fabrique le PDF d'un [DocumentDevis]. En production : `genererDevisPdf` avec les polices et le logo de
/// l'application ; les tests fournissent un faux générateur, rapide et sans ressources.
typedef GenerateurDevisPdf = Future<Uint8List> Function(DocumentDevis document);

/// Ce que l'utilisatrice saisit pour un devis. Les lignes, la remise et les frais de port sont ceux d'un
/// [Panier] (lignes libres : description, quantité, prix) : les règles de calcul sont donc celles des ventes.
class DevisSaisi {
  const DevisSaisi({
    this.clientId,
    required this.panier,
    this.dateEmission,
    this.dateValidite,
    this.delaiRealisation,
    this.acompteCentimes = 0,
    this.notes,
  });

  /// `null` : devis sans client.
  final int? clientId;
  final Panier panier;

  /// Date du devis (aujourd'hui par défaut). Ignorée à la modification : un devis garde sa date.
  final DateTime? dateEmission;

  /// Dernier jour de validité ; `null` : pas de limite.
  final DateTime? dateValidite;

  /// Délai de réalisation, en texte libre (« 3 semaines »).
  final String? delaiRealisation;
  final int acompteCentimes;

  /// Notes pour soi, non imprimées sur le devis (recopiées sur la commande à la conversion).
  final String? notes;
}

/// Devis : création, modification, statuts, expiration, conversion en commande (et facture) et PDF.
///
/// Un devis prend son numéro (`DEVIS-2026-0001`) dès sa création, dans la même transaction que son
/// enregistrement. Il se modifie tant qu'il n'est ni accepté, ni refusé, ni converti. Il ne se supprime pas :
/// un devis dont on ne veut plus se marque « refusé ».
class DevisRepository {
  DevisRepository(
    this._db,
    this._numerotation,
    this._ventes,
    this._factures,
    this._parametres,
    this._stockage,
    this._generateur,
  );

  final AppDatabase _db;
  final NumerotationRepository _numerotation;
  final VenteRepository _ventes;
  final FactureRepository _factures;
  final ParametresRepository _parametres;
  final StockagePdf _stockage;
  final GenerateurDevisPdf _generateur;

  // --- Création et modification ---------------------------------------------

  /// Crée un devis « brouillon » et lui attribue son numéro. Lance [DonneeInvalide], [ElementIntrouvable]
  /// ou [RemiseInvalide] (message en français) ; rien n'est alors enregistré et aucun numéro n'est consommé.
  Future<DevisFiche> creer(DevisSaisi saisie, {DateTime? maintenant}) {
    return _db.transaction(() async {
      final DateTime aujourdhui = maintenant ?? DateTime.now();
      final DateTime emission = debutDeJour(saisie.dateEmission ?? aujourdhui);
      final TotauxDocument totaux = await _controler(saisie, emission: emission, maintenant: aujourdhui);

      final String numero = await _numerotation.prochainNumeroDevis(emission);
      final int id = await _db
          .into(_db.devis)
          .insert(
            DevisCompanion.insert(
              numero: numero,
              sousTotalCentimes: totaux.sousTotalCentimes,
              totalCentimes: totaux.totalCentimes,
              clientId: Value(saisie.clientId),
              dateEmission: Value(emission),
              dateValidite: Value(saisie.dateValidite == null ? null : debutDeJour(saisie.dateValidite!)),
              delaiRealisation: Value(nullSiVide(saisie.delaiRealisation)),
              acompteCentimes: Value(saisie.acompteCentimes),
              remiseType: Value(saisie.panier.remiseType),
              remiseValeur: Value(
                saisie.panier.remiseType == RemiseType.aucune ? 0 : saisie.panier.remiseValeur,
              ),
              remiseCentimes: Value(totaux.remiseCentimes),
              fraisPortCentimes: Value(totaux.fraisPortCentimes),
              notes: Value(nullSiVide(saisie.notes)),
            ),
          );
      await _ecrireLignes(id, saisie.panier);
      return _devis(id);
    });
  }

  /// Modifie un devis : contenu, client, dates, acompte. Lance [DonneeInvalide] s'il est accepté, refusé ou
  /// converti, ou si la saisie est impossible ; le devis est alors inchangé.
  ///
  /// Un devis expiré se modifie pour **prolonger sa validité** : il redevient alors un brouillon.
  Future<DevisFiche> modifier(int id, DevisSaisi saisie, {DateTime? maintenant}) async {
    final DateTime aujourdhui = maintenant ?? DateTime.now();
    // Avant la transaction : un refus (saisie impossible...) ne doit pas annuler le passage en « Expiré ».
    await actualiserExpirations(maintenant: aujourdhui);
    return _db.transaction(() async {
      final DevisFiche actuel = await _devis(id);
      final bool converti = actuel.venteId != null;
      if (!peutEtreModifie(actuel.statut, converti: converti)) {
        throw DonneeInvalide(
          converti
              ? 'Ce devis a déjà été converti en commande : on ne peut plus le modifier.'
              : 'Un devis ${actuel.statut.libelle.toLowerCase()} ne peut plus être modifié.',
        );
      }

      final TotauxDocument totaux = await _controler(
        saisie,
        emission: actuel.dateEmission,
        maintenant: aujourdhui,
        clientActuelId: actuel.clientId,
      );

      await (_db.update(_db.devis)..where((t) => t.id.equals(id))).write(
        DevisCompanion(
          clientId: Value(saisie.clientId),
          dateValidite: Value(saisie.dateValidite == null ? null : debutDeJour(saisie.dateValidite!)),
          delaiRealisation: Value(nullSiVide(saisie.delaiRealisation)),
          acompteCentimes: Value(saisie.acompteCentimes),
          statut: Value(actuel.statut == StatutDevis.expire ? StatutDevis.brouillon : actuel.statut),
          sousTotalCentimes: Value(totaux.sousTotalCentimes),
          remiseType: Value(saisie.panier.remiseType),
          remiseValeur: Value(saisie.panier.remiseType == RemiseType.aucune ? 0 : saisie.panier.remiseValeur),
          remiseCentimes: Value(totaux.remiseCentimes),
          fraisPortCentimes: Value(totaux.fraisPortCentimes),
          totalCentimes: Value(totaux.totalCentimes),
          notes: Value(nullSiVide(saisie.notes)),
          modifieLe: Value(DateTime.now()),
        ),
      );
      await (_db.delete(_db.lignesDevis)..where((t) => t.devisId.equals(id))).go();
      await _ecrireLignes(id, saisie.panier);
      return _devis(id);
    });
  }

  // --- Statuts ----------------------------------------------------------------

  /// Change le statut à la main : envoyé, accepté ou refusé (voir `statutsPossibles`). Lance [DonneeInvalide]
  /// si ce changement n'est pas permis depuis le statut actuel (un devis refusé ne revient pas en arrière, un
  /// devis expiré doit d'abord voir sa validité prolongée...).
  Future<DevisFiche> changerStatut(int id, StatutDevis nouveau, {DateTime? maintenant}) async {
    // Avant la transaction : un refus ne doit pas annuler le passage en « Expiré ».
    await actualiserExpirations(maintenant: maintenant);
    return _db.transaction(() async {
      final DevisFiche devis = await _devis(id);
      final bool converti = devis.venteId != null;
      if (!statutsPossibles(devis.statut, converti: converti).contains(nouveau)) {
        throw DonneeInvalide(_refusDeStatut(devis, nouveau, converti: converti));
      }
      await (_db.update(_db.devis)..where((t) => t.id.equals(id))).write(
        DevisCompanion(statut: Value(nouveau), modifieLe: Value(DateTime.now())),
      );
      return _devis(id);
    });
  }

  /// Passe en « Expiré » les brouillons et les devis envoyés dont la date de validité est dépassée.
  /// Retourne le nombre de devis concernés. Appelée à l'ouverture des écrans de devis et avant chaque
  /// changement de statut ou conversion.
  Future<int> actualiserExpirations({DateTime? maintenant}) {
    final DateTime aujourdhui = debutDeJour(maintenant ?? DateTime.now());
    return (_db.update(_db.devis)..where(
          (t) =>
              (t.statut.equalsValue(StatutDevis.brouillon) | t.statut.equalsValue(StatutDevis.envoye)) &
              t.dateValidite.isSmallerThanValue(aujourdhui),
        ))
        .write(DevisCompanion(statut: const Value(StatutDevis.expire), modifieLe: Value(DateTime.now())));
  }

  // --- Conversion -----------------------------------------------------------

  /// Convertit le devis en **commande** (une vente validée, aux lignes, remise et frais de port du devis),
  /// le marque « accepté » et le relie à la commande.
  ///
  /// - [modeAcompte] renseigné : l'acompte demandé par le devis est enregistré comme premier paiement de la
  ///   commande, par ce mode de paiement (la commande est alors « partiellement payée ») ; sinon elle reste
  ///   impayée ;
  /// - [avecFacture] : établit aussi la facture de la commande. Le profil « Mon entreprise » est contrôlé
  ///   **avant** toute écriture ([ProfilIncomplet]) : rien n'est alors à moitié fait.
  ///
  /// Les lignes d'un devis sont libres : la commande n'a aucun effet sur le stock. Lance [DonneeInvalide] si
  /// le devis est refusé, expiré, déjà converti, ou si un acompte est demandé alors que le devis n'en prévoit pas.
  /// Si la commande est créée mais pas sa facture (cas très rare), [ResultatConversion.problemeFacture] dit
  /// pourquoi : la facture se crée ensuite depuis la commande.
  Future<ResultatConversion> convertir(
    int devisId, {
    bool avecFacture = false,
    ModePaiement? modeAcompte,
    DateTime? date,
  }) async {
    if (avecFacture) await _factures.verifierProfil();
    // Avant la transaction : un refus (devis expiré...) ne doit pas annuler le passage en « Expiré ».
    await actualiserExpirations(maintenant: date);

    final DevisFiche converti = await _db.transaction(() async {
      final DevisFiche devis = await _devis(devisId);
      if (devis.venteId != null) throw const DonneeInvalide('Ce devis a déjà été converti en commande.');
      if (devis.statut == StatutDevis.expire) {
        throw const DonneeInvalide(
          'Ce devis est expiré : prolongez sa validité (« Modifier ») avant de le convertir.',
        );
      }
      if (!peutEtreConverti(devis.statut, converti: false)) {
        throw DonneeInvalide('Un devis ${devis.statut.libelle.toLowerCase()} ne peut pas être converti.');
      }
      if (modeAcompte != null && devis.acompteCentimes <= 0) {
        throw const DonneeInvalide('Ce devis ne demande pas d’acompte.');
      }

      final List<LigneDevis> lignes = await _lignes(devisId);
      Panier panier = const Panier();
      for (final LigneDevis l in lignes) {
        panier = panier.ajouter(
          designation: l.designation,
          description: l.description,
          nature: l.nature,
          prixUnitaireCentimes: l.prixUnitaireCentimes,
          quantite: l.quantite,
        );
      }
      panier = panier.avecRemise(devis.remiseType, devis.remiseValeur).avecFraisPort(devis.fraisPortCentimes);

      final Vente vente = await _ventes.valider(
        clientId: devis.clientId,
        panier: panier,
        paiement: modeAcompte == null
            ? null
            : PaiementSaisi(mode: modeAcompte, montantCentimes: devis.acompteCentimes),
        notes: <String?>['Commande issue du devis ${devis.numero}', nullSiVide(devis.notes)]
            .whereType<String>()
            .join('\n'),
        date: date,
      );

      await (_db.update(_db.devis)..where((t) => t.id.equals(devisId))).write(
        DevisCompanion(
          statut: const Value(StatutDevis.accepte),
          venteId: Value(vente.id),
          modifieLe: Value(DateTime.now()),
        ),
      );
      return _devis(devisId);
    });

    final int venteId = converti.venteId!;
    Facture? facture;
    String? probleme;
    if (avecFacture) {
      try {
        facture = await _factures.creer(venteId, date: date);
      } on ErreurMetier catch (erreur) {
        probleme = erreur.message;
      } catch (_) {
        probleme = 'La facture n’a pas pu être établie.';
      }
    }
    final Vente vente = (await _ventes.obtenir(venteId))!;
    return ResultatConversion(devis: converti, vente: vente, facture: facture, problemeFacture: probleme);
  }

  // --- Consultation -----------------------------------------------------------

  Future<DevisFiche?> obtenir(int id) =>
      (_db.select(_db.devis)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Tous les devis avec leur client, le plus récent d'abord.
  Future<List<DevisResume>> lister() async {
    final List<DevisFiche> devis =
        await (_db.select(_db.devis)..orderBy([
              (t) => OrderingTerm(expression: t.dateEmission, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ]))
            .get();
    final List<Client> clients = await _db.select(_db.clients).get();
    final Map<int, Client> parId = <int, Client>{for (final Client c in clients) c.id: c};
    return <DevisResume>[
      for (final DevisFiche d in devis) DevisResume(devis: d, client: d.clientId == null ? null : parId[d.clientId]),
    ];
  }

  /// Liste des devis, mise à jour automatiquement (création, modification, statut, client modifié).
  Stream<List<DevisResume>> observerListe() =>
      observerTables(_db, <ResultSetImplementation>{_db.devis, _db.clients}, lister);

  /// Détail complet d'un devis (`null` s'il n'existe pas).
  Future<DevisDetail?> detail(int id) async {
    final DevisFiche? devis = await obtenir(id);
    if (devis == null) return null;
    final int? clientId = devis.clientId;
    final int? venteId = devis.venteId;
    return DevisDetail(
      devis: devis,
      lignes: await _lignes(id),
      client: clientId == null
          ? null
          : await (_db.select(_db.clients)..where((t) => t.id.equals(clientId))).getSingleOrNull(),
      vente: venteId == null ? null : await _ventes.obtenir(venteId),
    );
  }

  /// Détail d'un devis, mis à jour automatiquement.
  Stream<DevisDetail?> observerDetail(int id) => observerTables(
    _db,
    <ResultSetImplementation>{_db.devis, _db.lignesDevis, _db.clients, _db.ventes},
    () => detail(id),
  );

  // --- PDF --------------------------------------------------------------------

  /// Le PDF du devis, fabriqué à partir de son état actuel (un devis peut être modifié : le PDF n'est jamais
  /// une copie périmée) et rangé sur le téléphone sous `DEVIS-2026-0001.pdf`.
  Future<Uint8List> obtenirPdf(int devisId) async {
    final DevisDetail? fiche = await detail(devisId);
    if (fiche == null) throw const ElementIntrouvable('Ce devis n’existe plus.');
    final DocumentDevis document = construireDocumentDevis(
      devis: fiche.devis,
      lignes: fiche.lignes,
      client: fiche.client,
      entreprise: await _parametres.lire(),
    );
    final Uint8List octets = await _generateur(document);
    await _stockage.enregistrer(fiche.devis.numero, octets);
    return octets;
  }

  /// Fichier PDF du devis sur le téléphone (pour le partager), après l'avoir fabriqué.
  Future<String> cheminPdf(int devisId) async {
    await obtenirPdf(devisId);
    final DevisFiche devis = await _devis(devisId);
    return _stockage.fichier('${devis.numero}.pdf').path;
  }

  // --- Interne --------------------------------------------------------------

  Future<DevisFiche> _devis(int id) async {
    final DevisFiche? devis = await obtenir(id);
    if (devis == null) throw const ElementIntrouvable('Ce devis n’existe plus.');
    return devis;
  }

  Future<List<LigneDevis>> _lignes(int devisId) {
    return (_db.select(_db.lignesDevis)
          ..where((t) => t.devisId.equals(devisId))
          ..orderBy([(t) => OrderingTerm(expression: t.position), (t) => OrderingTerm(expression: t.id)]))
        .get();
  }

  Future<void> _ecrireLignes(int devisId, Panier panier) async {
    for (int i = 0; i < panier.lignes.length; i++) {
      final LignePanier ligne = panier.lignes[i];
      await _db
          .into(_db.lignesDevis)
          .insert(
            LignesDevisCompanion.insert(
              devisId: devisId,
              designation: ligne.designation,
              quantite: ligne.quantite,
              prixUnitaireCentimes: ligne.prixUnitaireCentimes,
              totalLigneCentimes: ligne.totalCentimes,
              position: Value(i),
              nature: Value(ligne.nature),
              description: Value(ligne.description),
            ),
          );
    }
  }

  /// Vérifie la saisie d'un devis et retourne ses totaux. Lance [DonneeInvalide], [ElementIntrouvable] ou
  /// [RemiseInvalide].
  Future<TotauxDocument> _controler(
    DevisSaisi saisie, {
    required DateTime emission,
    required DateTime maintenant,
    int? clientActuelId,
  }) async {
    final Panier panier = saisie.panier;
    if (panier.estVide) throw const DonneeInvalide('Ajoutez au moins une ligne au devis.');
    for (final LignePanier ligne in panier.lignes) {
      if (ligne.designation.length > 300) {
        throw const DonneeInvalide('Le nom d’un article est limité à 300 caractères.');
      }
    }
    final String? delai = nullSiVide(saisie.delaiRealisation);
    if (delai != null && delai.length > 200) {
      throw const DonneeInvalide('Le délai de réalisation est limité à 200 caractères.');
    }

    final int? clientId = saisie.clientId;
    if (clientId != null) {
      final Client? client = await (_db.select(_db.clients)..where((t) => t.id.equals(clientId))).getSingleOrNull();
      if (client == null) throw const ElementIntrouvable('Ce client n’existe plus.');
      if (client.archiveLe != null && clientId != clientActuelId) {
        throw const DonneeInvalide('Ce client est archivé : restaurez sa fiche pour lui faire un devis.');
      }
    }

    final TotauxDocument totaux = panier.totaux;
    verifierDevis(
      dateEmission: emission,
      dateValidite: saisie.dateValidite,
      acompteCentimes: saisie.acompteCentimes,
      totalCentimes: totaux.totalCentimes,
      maintenant: maintenant,
    );
    return totaux;
  }

  String _refusDeStatut(DevisFiche devis, StatutDevis nouveau, {required bool converti}) {
    if (converti) return 'Ce devis a déjà été converti en commande : son statut ne change plus.';
    return switch (devis.statut) {
      StatutDevis.expire =>
        'Ce devis est expiré : prolongez sa validité (« Modifier ») avant de changer son statut.',
      StatutDevis.refuse => 'Un devis refusé ne change plus de statut.',
      _ => 'Un devis ${devis.statut.libelle.toLowerCase()} ne peut pas passer à « ${nouveau.libelle} ».',
    };
  }
}
