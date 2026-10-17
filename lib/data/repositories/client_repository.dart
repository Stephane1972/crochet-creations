import 'package:drift/drift.dart';

import '../../core/utils/texte.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../database/app_database.dart';

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
    final String? courriel = nullSiVide(email);
    if (courriel != null && !courriel.contains('@')) {
      throw const DonneeInvalide('L’adresse e-mail n’est pas valide.');
    }
  }
}

/// Fiches clients. La recherche et l'historique arrivent à l'étape 4 (écrans clients).
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
