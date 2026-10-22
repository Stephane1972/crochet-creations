import 'package:drift/drift.dart';

import '../../core/utils/texte.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_client.dart';
import '../database/app_database.dart';
import 'client_vues.dart';

/// Données saisies pour créer ou modifier un client.
class DonneesClient {
  const DonneesClient({
    this.typeClient = TypeClient.particulier,
    this.civilite,
    this.prenom,
    this.nom,
    this.raisonSociale,
    this.telephone,
    this.email,
    this.adresse,
    this.codePostal,
    this.ville,
    this.siret,
    this.notes,
  });

  final TypeClient typeClient;
  final Civilite? civilite;
  final String? prenom;
  final String? nom;

  /// Nom de l'entreprise (clients professionnels).
  final String? raisonSociale;
  final String? telephone;
  final String? email;
  final String? adresse;
  final String? codePostal;
  final String? ville;

  /// SIREN ou SIRET (clients professionnels).
  final String? siret;
  final String? notes;

  /// Lance [DonneeInvalide] (message en français) si la fiche est inutilisable.
  void valider() {
    final bool aUnNom =
        nullSiVide(prenom) != null || nullSiVide(nom) != null || nullSiVide(raisonSociale) != null;
    if (!aUnNom) {
      throw const DonneeInvalide('Indiquez au moins un prénom, un nom ou une raison sociale.');
    }
    // Mêmes règles et mêmes messages que le formulaire (voir `regles_client.dart`).
    final String? probleme =
        verifierEmail(email) ??
        verifierTelephone(telephone) ??
        verifierCodePostal(codePostal) ??
        verifierSiret(siret);
    if (probleme != null) throw DonneeInvalide(probleme);
  }
}

/// Fiches clients et historique (devis, ventes, factures, paiements, cours).
/// Une vente « client de passage » n'a pas de fiche (`client_id` vide).
class ClientRepository {
  ClientRepository(this._db);

  final AppDatabase _db;

  Future<Client> creer(DonneesClient donnees) async {
    donnees.valider();
    final int id = await _db
        .into(_db.clients)
        .insert(
          ClientsCompanion.insert(
            typeClient: Value(donnees.typeClient),
            civilite: Value(donnees.civilite),
            prenom: Value(nullSiVide(donnees.prenom)),
            nom: Value(nullSiVide(donnees.nom)),
            raisonSociale: Value(nullSiVide(donnees.raisonSociale)),
            telephone: Value(nullSiVide(donnees.telephone)),
            email: Value(nullSiVide(donnees.email)),
            adresse: Value(nullSiVide(donnees.adresse)),
            codePostal: Value(nullSiVide(donnees.codePostal)),
            ville: Value(nullSiVide(donnees.ville)),
            siret: Value(nullSiVide(donnees.siret)),
            notes: Value(nullSiVide(donnees.notes)),
          ),
        );
    return _client(id);
  }

  Future<Client> modifier(int id, DonneesClient donnees) async {
    donnees.valider();
    final int lignes = await (_db.update(_db.clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(
        typeClient: Value(donnees.typeClient),
        civilite: Value(donnees.civilite),
        prenom: Value(nullSiVide(donnees.prenom)),
        nom: Value(nullSiVide(donnees.nom)),
        raisonSociale: Value(nullSiVide(donnees.raisonSociale)),
        telephone: Value(nullSiVide(donnees.telephone)),
        email: Value(nullSiVide(donnees.email)),
        adresse: Value(nullSiVide(donnees.adresse)),
        codePostal: Value(nullSiVide(donnees.codePostal)),
        ville: Value(nullSiVide(donnees.ville)),
        siret: Value(nullSiVide(donnees.siret)),
        notes: Value(nullSiVide(donnees.notes)),
        modifieLe: Value(DateTime.now()),
      ),
    );
    if (lignes == 0) throw const ElementIntrouvable('Ce client n’existe plus.');
    return _client(id);
  }

  Future<Client?> obtenir(int id) =>
      (_db.select(_db.clients)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Clients triés par nom ; les clients archivés sont exclus sauf demande contraire.
  Future<List<Client>> lister({bool inclureArchives = false}) => _requeteListe(inclureArchives).get();

  Stream<List<Client>> observerClients({bool inclureArchives = false}) =>
      _requeteListe(inclureArchives).watch();

  /// Archive un client : sa fiche disparaît de la liste mais son historique est conservé.
  Future<void> archiver(int id) => _marquerArchive(id, DateTime.now());

  Future<void> restaurer(int id) => _marquerArchive(id, null);

  // --- Fiche et historique ---------------------------------------------------

  /// Fiche d'un client (`null` s'il n'existe pas), mise à jour automatiquement.
  Stream<Client?> observerClient(int id) =>
      (_db.select(_db.clients)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Devis, ventes, factures, paiements et inscriptions à des cours d'un client,
  /// du plus récent au plus ancien.
  Future<HistoriqueClient> historique(int clientId) async {
    final List<DevisFiche> devis =
        await (_db.select(_db.devis)
              ..where((t) => t.clientId.equals(clientId))
              ..orderBy([(t) => OrderingTerm.desc(t.dateEmission), (t) => OrderingTerm.desc(t.id)]))
            .get();

    final List<Vente> ventes =
        await (_db.select(_db.ventes)
              ..where((t) => t.clientId.equals(clientId))
              ..orderBy([(t) => OrderingTerm.desc(t.dateVente), (t) => OrderingTerm.desc(t.id)]))
            .get();

    final List<Facture> factures =
        await (_db.select(_db.factures)
              ..where((t) => t.clientId.equals(clientId))
              ..orderBy([(t) => OrderingTerm.desc(t.dateEmission), (t) => OrderingTerm.desc(t.id)]))
            .get();

    final JoinedSelectStatement<HasResultSet, dynamic> requetePaiements =
        _db.select(_db.paiements).join(<Join>[
            innerJoin(_db.ventes, _db.ventes.id.equalsExp(_db.paiements.venteId)),
          ])
          ..where(_db.ventes.clientId.equals(clientId))
          ..orderBy(<OrderingTerm>[
            OrderingTerm.desc(_db.paiements.datePaiement),
            OrderingTerm.desc(_db.paiements.id),
          ]);
    final List<TypedResult> lignesPaiements = await requetePaiements.get();

    final JoinedSelectStatement<HasResultSet, dynamic> requeteInscriptions =
        _db.select(_db.inscriptionsCours).join(<Join>[
            innerJoin(_db.cours, _db.cours.id.equalsExp(_db.inscriptionsCours.coursId)),
          ])
          ..where(_db.inscriptionsCours.clientId.equals(clientId))
          ..orderBy(<OrderingTerm>[
            OrderingTerm.desc(_db.cours.debutLe),
            OrderingTerm.desc(_db.inscriptionsCours.id),
          ]);
    final List<TypedResult> lignesInscriptions = await requeteInscriptions.get();

    return HistoriqueClient(
      devis: devis,
      ventes: <VenteClient>[
        for (final Vente v in ventes)
          VenteClient(
            venteId: v.id,
            dateVente: v.dateVente,
            totalCentimes: v.totalCentimes,
            statut: v.statut,
            statutPaiement: v.statutPaiement,
          ),
      ],
      factures: factures,
      paiements: <PaiementClient>[
        for (final TypedResult ligne in lignesPaiements)
          PaiementClient(
            paiementId: ligne.readTable(_db.paiements).id,
            venteId: ligne.readTable(_db.paiements).venteId,
            datePaiement: ligne.readTable(_db.paiements).datePaiement,
            mode: ligne.readTable(_db.paiements).modePaiement,
            montantCentimes: ligne.readTable(_db.paiements).montantCentimes,
          ),
      ],
      inscriptions: <InscriptionClient>[
        for (final TypedResult ligne in lignesInscriptions)
          InscriptionClient(
            inscriptionId: ligne.readTable(_db.inscriptionsCours).id,
            titreCours: ligne.readTable(_db.cours).titre,
            debutCours: ligne.readTable(_db.cours).debutLe,
            statut: ligne.readTable(_db.inscriptionsCours).statut,
            prixCentimes: ligne.readTable(_db.inscriptionsCours).prixCentimes,
          ),
      ],
    );
  }

  /// L'historique, relu automatiquement dès qu'une vente, un paiement, une facture, un devis
  /// ou une inscription change.
  Stream<HistoriqueClient> observerHistorique(int clientId) {
    final Set<ResultSetImplementation> tables = <ResultSetImplementation>{
      _db.devis,
      _db.ventes,
      _db.factures,
      _db.paiements,
      _db.inscriptionsCours,
      _db.cours,
    };
    return _db
        .customSelect('SELECT 1', readsFrom: tables)
        .watch()
        .asyncMap((_) => historique(clientId));
  }

  // --- Interne --------------------------------------------------------------

  SimpleSelectStatement<$ClientsTable, Client> _requeteListe(bool inclureArchives) {
    final SimpleSelectStatement<$ClientsTable, Client> requete = _db.select(_db.clients)
      ..orderBy([
        (t) => OrderingTerm(expression: t.nom.collate(Collate.noCase)),
        (t) => OrderingTerm(expression: t.prenom.collate(Collate.noCase)),
        (t) => OrderingTerm(expression: t.raisonSociale.collate(Collate.noCase)),
      ]);
    if (!inclureArchives) {
      requete.where((t) => t.archiveLe.isNull());
    }
    return requete;
  }

  Future<Client> _client(int id) async {
    final Client? client = await obtenir(id);
    if (client == null) throw const ElementIntrouvable('Ce client n’existe plus.');
    return client;
  }

  Future<void> _marquerArchive(int id, DateTime? date) async {
    final int lignes = await (_db.update(_db.clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(archiveLe: Value(date), modifieLe: Value(DateTime.now())),
    );
    if (lignes == 0) throw const ElementIntrouvable('Ce client n’existe plus.');
  }
}
