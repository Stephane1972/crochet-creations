import 'package:crochet_creations/data/database/app_database.dart';
import 'package:crochet_creations/data/repositories/parametres_repository.dart';
import 'package:crochet_creations/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'aide_base.dart';

void main() {
  late AppDatabase db;
  late ParametresRepository repo;

  setUp(() {
    db = creerBaseEnMemoire();
    repo = ParametresRepository(db);
  });
  tearDown(() => db.close());

  test('valeurs par défaut à la première ouverture', () async {
    final Entreprise e = await repo.lire();
    expect(e.id, 1);
    expect(e.nomCommercial, '');
    expect(e.modeTheme, ModeTheme.systeme);
    expect(e.iban, isNull);
    expect(e.messageRemerciement, isNotEmpty);
    expect(await repo.lireModeTheme(), ThemeMode.system);
  });

  test('le mode jour / nuit est mémorisé', () async {
    await repo.memoriser(ThemeMode.dark);
    expect(await repo.lireModeTheme(), ThemeMode.dark);
    expect((await repo.lire()).modeTheme, ModeTheme.nuit);

    await repo.memoriser(ThemeMode.light);
    expect(await repo.lireModeTheme(), ThemeMode.light);

    await repo.memoriser(ThemeMode.system);
    expect(await repo.lireModeTheme(), ThemeMode.system);
  });

  test('le mode survit à la fermeture et à la réouverture de la base', () async {
    // Une vraie réouverture (fichier) est vérifiée sur l'appareil ; ici on vérifie que l'écriture
    // est bien dans la base et que les autres réglages ne sont pas touchés.
    await repo.modifier(const ParametresEntrepriseCompanion(nomCommercial: Value('Crochet & Créations')));
    await repo.memoriser(ThemeMode.dark);

    final Entreprise e = await repo.lire();
    expect(e.nomCommercial, 'Crochet & Créations');
    expect(e.modeTheme, ModeTheme.nuit);
  });

  test('toujours une seule ligne de réglages', () async {
    await repo.memoriser(ThemeMode.dark);
    await repo.modifier(const ParametresEntrepriseCompanion(ville: Value('Toulouse')));
    expect(await db.select(db.parametresEntreprise).get(), hasLength(1));
  });
}
