import 'package:drift/drift.dart';

import 'app_database.dart';

/// Flux « en direct » : relit les données avec [lire] au départ, puis à chaque écriture dans
/// l'une des [tables]. `asyncMap` traite les relectures une par une, dans l'ordre.
///
/// ⚠️ Drift partage un même flux entre toutes les requêtes qui ont le même texte SQL, **sans
/// regarder les tables surveillées**. Avec un `SELECT 1` identique partout, le premier flux
/// ouvert « volait » les suivants : l'historique d'un client ne se rafraîchissait pas tant que
/// la liste des produits (ouverte avant) était affichée. Les noms des tables sont donc écrits
/// dans le texte SQL (en commentaire), pour que deux flux sur des tables différentes ne se
/// confondent jamais.
Stream<T> observerTables<T>(
  AppDatabase db,
  Set<ResultSetImplementation> tables,
  Future<T> Function() lire,
) {
  final List<String> noms = tables.map((ResultSetImplementation t) => t.entityName).toList()..sort();
  return db
      .customSelect('SELECT 1 /* ${noms.join(', ')} */', readsFrom: tables)
      .watch()
      .asyncMap((_) => lire());
}
