import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/recherche.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/client_vues.dart';
import '../../domain/enums.dart';

/// Recherche et filtres de la liste des clients.
class FiltresClients {
  const FiltresClients({this.recherche = '', this.type, this.archives = false});

  final String recherche;

  /// `null` = tous les types de clients.
  final TypeClient? type;

  /// Afficher aussi les clients archivés.
  final bool archives;

  /// Vrai si un critère limite la liste (la case « archivés » élargit la liste, elle ne la limite pas).
  bool get limiteLaListe => recherche.trim().isNotEmpty || type != null;

  FiltresClients avecRecherche(String valeur) =>
      FiltresClients(recherche: valeur, type: type, archives: archives);

  FiltresClients avecType(TypeClient? valeur) =>
      FiltresClients(recherche: recherche, type: valeur, archives: archives);

  FiltresClients avecArchives({required bool valeur}) =>
      FiltresClients(recherche: recherche, type: type, archives: valeur);
}

class FiltresClientsNotifier extends Notifier<FiltresClients> {
  @override
  FiltresClients build() => const FiltresClients();

  void rechercher(String valeur) => state = state.avecRecherche(valeur);

  void choisirType(TypeClient? valeur) => state = state.avecType(valeur);

  void basculerArchives() => state = state.avecArchives(valeur: !state.archives);

  void reinitialiser() => state = const FiltresClients();
}

final filtresClientsProvider = NotifierProvider<FiltresClientsNotifier, FiltresClients>(
  FiltresClientsNotifier.new,
);

/// Applique la recherche et les filtres, puis trie par nom affiché (sans tenir compte des
/// accents ni des majuscules), à égalité par ordre de création.
List<Client> filtrerClients(List<Client> clients, FiltresClients filtres) {
  final List<Client> retenus = clients.where((Client c) {
    if (!filtres.archives && c.archiveLe != null) return false;
    if (filtres.type != null && c.typeClient != filtres.type) return false;
    return correspondALaRecherche(filtres.recherche, champsRechercheClient(c));
  }).toList();

  final Map<int, String> cles = <int, String>{
    for (final Client c in retenus) c.id: normaliserPourRecherche(libelleClient(c)),
  };
  retenus.sort((Client a, Client b) {
    final int ordre = cles[a.id]!.compareTo(cles[b.id]!);
    return ordre != 0 ? ordre : a.id.compareTo(b.id);
  });
  return retenus;
}
