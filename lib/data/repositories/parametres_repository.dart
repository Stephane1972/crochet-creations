import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../core/theme/theme_mode_provider.dart';
import '../../domain/enums.dart';
import '../database/app_database.dart';

/// Profil « Mon entreprise » et réglages (une seule ligne, `id = 1`).
class ParametresRepository implements ModeThemeStore {
  ParametresRepository(this._db);

  final AppDatabase _db;

  Future<Entreprise> lire() =>
      (_db.select(_db.parametresEntreprise)..where((t) => t.id.equals(1))).getSingle();

  Stream<Entreprise> observer() =>
      (_db.select(_db.parametresEntreprise)..where((t) => t.id.equals(1))).watchSingle();

  /// Modifie uniquement les champs renseignés dans [changements].
  Future<void> modifier(ParametresEntrepriseCompanion changements) async {
    await (_db.update(_db.parametresEntreprise)..where((t) => t.id.equals(1))).write(
      changements.copyWith(modifieLe: Value(DateTime.now())),
    );
  }

  /// Mode d'affichage mémorisé (automatique tant que rien n'a été choisi).
  Future<ThemeMode> lireModeTheme() async => _versThemeMode((await lire()).modeTheme);

  @override
  Future<void> memoriser(ThemeMode mode) =>
      modifier(ParametresEntrepriseCompanion(modeTheme: Value(_depuisThemeMode(mode))));

  static ThemeMode _versThemeMode(ModeTheme mode) => switch (mode) {
    ModeTheme.systeme => ThemeMode.system,
    ModeTheme.jour => ThemeMode.light,
    ModeTheme.nuit => ThemeMode.dark,
  };

  static ModeTheme _depuisThemeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.system => ModeTheme.systeme,
    ThemeMode.light => ModeTheme.jour,
    ThemeMode.dark => ModeTheme.nuit,
  };
}
