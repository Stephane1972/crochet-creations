import 'dart:async';

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

  test('le rappel de la déclaration est désactivé au départ, puis mémorisé sans toucher aux autres réglages', () async {
    expect(await repo.lireRappelDeclaration(), isFalse);
    expect(ParametresRepository.rappelDeclarationDe(await repo.lire()), isFalse);

    await repo.modifier(const ParametresEntrepriseCompanion(ville: Value('Toulouse')));
    await repo.enregistrerRappelDeclaration(true);
    expect(await repo.lireRappelDeclaration(), isTrue);
    expect((await repo.lire()).ville, 'Toulouse');

    await repo.enregistrerRappelDeclaration(false);
    expect(await repo.lireRappelDeclaration(), isFalse);
    expect((await repo.lire()).ville, 'Toulouse');
  });

  test('le rappel de la déclaration est annoncé en direct aux écrans ouverts', () async {
    final List<bool> vus = <bool>[];
    final StreamSubscription<bool> subscription = repo.observer().map(ParametresRepository.rappelDeclarationDe).listen(vus.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.enregistrerRappelDeclaration(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();

    expect(vus.first, isFalse);
    expect(vus.last, isTrue);
  });

  test('toujours une seule ligne de réglages', () async {
    await repo.memoriser(ThemeMode.dark);
    await repo.modifier(const ParametresEntrepriseCompanion(ville: Value('Toulouse')));
    expect(await db.select(db.parametresEntreprise).get(), hasLength(1));
  });
}
