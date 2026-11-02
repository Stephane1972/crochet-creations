import 'dart:io';

import 'package:crochet_creations/data/database/app_database.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mise à jour d'une base créée par une version plus ancienne de l'application : rien ne se perd.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = await Directory.systemTemp.createTemp('migration_');
    fichier = File('${dossier.path}/base.sqlite');
  });

  tearDown(() async {
    if (await dossier.exists()) await dossier.delete(recursive: true);
  });

  test('du schéma 1 au schéma 2 : les données restent, les colonnes « client_nom » apparaissent', () async {
    // 1. Une base créée avec le schéma actuel, remplie de quelques lignes.
    final AppDatabase neuve = AppDatabase(NativeDatabase(fichier));
    final int clientId = await neuve.into(neuve.clients).insert(ClientsCompanion.insert(nom: const Value('Dupont')));
    final int venteId = await neuve
        .into(neuve.ventes)
        .insert(VentesCompanion.insert(sousTotalCentimes: 1000, totalCentimes: 1000, clientId: Value(clientId)));
    await neuve
        .into(neuve.devis)
        .insert(
          DevisCompanion.insert(
            numero: 'DEVIS-2026-0001',
            sousTotalCentimes: 6000,
            totalCentimes: 6000,
            clientId: Value(clientId),
          ),
        );
    await neuve.close();

    // 2. On la ramène à l'état d'une base du schéma 1 : sans les deux colonnes, version 1.
    final AppDatabase rouverte = AppDatabase(
      NativeDatabase(
        fichier,
        setup: (raw) {
          raw.execute('ALTER TABLE ventes DROP COLUMN client_nom');
          raw.execute('ALTER TABLE devis DROP COLUMN client_nom');
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    // La première requête déclenche la mise à jour, puis le test relit le résultat.
    final int version = (await rouverte.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
    expect(version, 2);
    for (final String table in <String>['ventes', 'devis']) {
      final Set<String> colonnes = (await rouverte.customSelect('PRAGMA table_info("$table")').get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(colonnes, contains('client_nom'), reason: table);
    }

    // 3. Les données sont intactes, et le nouveau champ est vide.
    final Vente vente = (await rouverte.select(rouverte.ventes).get()).single;
    expect(vente.id, venteId);
    expect(vente.clientId, clientId);
    expect(vente.totalCentimes, 1000);
    expect(vente.clientNom, isNull);
    final DevisFiche devis = (await rouverte.select(rouverte.devis).get()).single;
    expect(devis.numero, 'DEVIS-2026-0001');
    expect(devis.clientNom, isNull);
    expect((await rouverte.select(rouverte.clients).get()).single.nom, 'Dupont');

    // 4. Et l'application sait s'en servir : supprimer le client copie son nom.
    await rouverte.update(rouverte.ventes).write(const VentesCompanion(clientNom: Value('Dupont')));
    expect((await rouverte.select(rouverte.ventes).get()).single.clientNom, 'Dupont');
    await rouverte.close();
  });
}
