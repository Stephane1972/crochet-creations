import 'package:drift/drift.dart';

import '../../domain/erreurs.dart';
import '../../domain/lieux_vente.dart';
import '../database/app_database.dart';
import '../database/flux_en_direct.dart';

/// Où vont les ventes d'un lieu qu'on supprime : vers un autre lieu, ou vers « Non renseigné » (sans lieu).
class DestinationVentes {
  /// Les ventes passent dans le lieu [lieuId].
  const DestinationVentes.lieu(int this.lieuId);

  /// Les ventes n'ont plus de lieu : « Non renseigné ».
  const DestinationVentes.nonRenseigne() : lieuId = null;

  /// `null` = « Non renseigné ».
  final int? lieuId;
}

/// Lieux de vente : lister, créer, renommer, supprimer (en déplaçant les ventes qu'ils contiennent).
///
/// Une vente enregistre l'**identifiant** de son lieu, jamais son nom : renommer ne touche à aucune vente.
/// Supprimer un lieu ne supprime jamais une vente : elles passent dans un autre lieu ou dans « Non renseigné ».
class LieuVenteRepository {
  LieuVenteRepository(this._db);

  final AppDatabase _db;

  // --- Lecture -----------------------------------------------------------------

  /// Tous les lieux, dans l'ordre d'affichage (création, sauf changement).
  Future<List<LieuVente>> lister() => _requete().get();

  /// Les lieux, mis à jour automatiquement.
  Stream<List<LieuVente>> observer() => _requete().watch();

  Future<LieuVente?> obtenir(int id) =>
      (_db.select(_db.lieuxVente)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Nombre de ventes de chaque lieu (annulées comprises), par identifiant. Les lieux sans vente n'y figurent pas.
  Future<Map<int, int>> nombreVentesParLieu() async {
    final List<QueryRow> lignes = await _db
        .customSelect(
          'SELECT lieu_id AS lieu, COUNT(*) AS n FROM ventes WHERE lieu_id IS NOT NULL GROUP BY lieu_id',
          readsFrom: <ResultSetImplementation>{_db.ventes},
        )
        .get();
    return <int, int>{for (final QueryRow l in lignes) l.read<int>('lieu'): l.read<int>('n')};
  }

  Future<int> nombreVentes(int lieuId) async => (await nombreVentesParLieu())[lieuId] ?? 0;

  /// Le nombre de ventes de chaque lieu, mis à jour automatiquement (vente enregistrée, lieu modifié, lieu supprimé).
  Stream<Map<int, int>> observerNombreVentesParLieu() => observerTables(
    _db,
    <ResultSetImplementation>{_db.ventes, _db.lieuxVente},
    nombreVentesParLieu,
  );

  // --- Écriture ----------------------------------------------------------------

  /// Crée un lieu, à la fin de la liste. Lance [DonneeInvalide] si le nom est vide, trop long, réservé ou déjà pris
  /// (sans tenir compte des majuscules, des accents ni des espaces).
  Future<LieuVente> creer(String nom) {
    return _db.transaction(() async {
      final String propre = await _nomValide(nom);
      final List<LieuVente> existants = await lister();
      final int position = existants.isEmpty
          ? 0
          : existants.map((LieuVente l) => l.position).reduce((int a, int b) => a > b ? a : b) + 1;
      final int id = await _db
          .into(_db.lieuxVente)
          .insert(LieuxVenteCompanion.insert(nom: propre, position: Value(position)));
      return (await obtenir(id))!;
    });
  }

  /// Change le nom d'un lieu ; son identifiant, et donc ses ventes, ne bougent pas.
  Future<LieuVente> renommer(int id, String nom) {
    return _db.transaction(() async {
      final LieuVente lieu = await _lieu(id);
      final String propre = await _nomValide(nom, sauf: id);
      if (propre != lieu.nom) {
        await (_db.update(_db.lieuxVente)..where((t) => t.id.equals(id))).write(
          LieuxVenteCompanion(nom: Value(propre), modifieLe: Value(DateTime.now())),
        );
      }
      return (await obtenir(id))!;
    });
  }

  /// Supprime un lieu. S'il a des ventes (annulées comprises), [deplacerVers] est obligatoire : le lieu qui les reçoit,
  /// ou [DestinationVentes.nonRenseigne]. Retourne le nombre de ventes déplacées.
  ///
  /// Lance [ElementIntrouvable] si le lieu (ou celui qui reçoit) n'existe pas, [DonneeInvalide] si les ventes n'ont
  /// nulle part où aller. Tout ou rien : en cas de refus, rien n'est déplacé ni supprimé. Aucune vente n'est jamais
  /// supprimée ni modifiée autrement que par son lieu.
  Future<int> supprimer(int id, {DestinationVentes? deplacerVers}) {
    return _db.transaction(() async {
      final LieuVente lieu = await _lieu(id);
      final int nombre = await nombreVentes(id);

      if (nombre > 0) {
        if (deplacerVers == null) {
          throw DonneeInvalide(
            'Ce lieu contient ${nombre > 1 ? '$nombre ventes' : '1 vente'} : '
            'choisissez où ${nombre > 1 ? 'les' : 'la'} déplacer.',
          );
        }
        final int? destination = deplacerVers.lieuId;
        if (destination == id) {
          throw const DonneeInvalide('Choisissez un autre lieu que celui qu’on supprime.');
        }
        if (destination != null && await obtenir(destination) == null) {
          throw const ElementIntrouvable('Le lieu choisi n’existe plus.');
        }
        await (_db.update(_db.ventes)..where((t) => t.lieuId.equals(lieu.id))).write(
          VentesCompanion(lieuId: Value(destination), modifieLe: Value(DateTime.now())),
        );
      }

      await (_db.delete(_db.lieuxVente)..where((t) => t.id.equals(id))).go();
      return nombre;
    });
  }

  // --- Aides -------------------------------------------------------------------

  SimpleSelectStatement<$LieuxVenteTable, LieuVente> _requete() => _db.select(_db.lieuxVente)
    ..orderBy([(t) => OrderingTerm.asc(t.position), (t) => OrderingTerm.asc(t.id)]);

  Future<LieuVente> _lieu(int id) async {
    final LieuVente? lieu = await obtenir(id);
    if (lieu == null) throw const ElementIntrouvable('Ce lieu de vente n’existe plus.');
    return lieu;
  }

  /// Le nom nettoyé, ou [DonneeInvalide]. [sauf] : le lieu qu'on renomme, qui peut garder son propre nom.
  Future<String> _nomValide(String nom, {int? sauf}) async {
    final String? probleme = erreurNomLieu(nom);
    if (probleme != null) throw DonneeInvalide(probleme);
    final String propre = nettoyerNomLieu(nom);
    for (final LieuVente autre in await lister()) {
      if (autre.id != sauf && memeNomLieu(autre.nom, propre)) {
        throw DonneeInvalide('Un lieu « ${autre.nom} » existe déjà.');
      }
    }
    return propre;
  }
}
