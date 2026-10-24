import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/texte.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';
import '../../domain/regles_client.dart';
import '../../domain/regles_entreprise.dart';
import '../database/app_database.dart';

/// Ce que saisit l'entrepreneuse dans « Mon entreprise ». Tout est facultatif à l'enregistrement :
/// c'est au moment de facturer qu'on vérifie que le nécessaire est renseigné
/// (`informationsManquantes`).
class DonneesEntreprise {
  const DonneesEntreprise({
    this.nomCommercial,
    this.nomResponsable,
    this.adresse,
    this.codePostal,
    this.ville,
    this.telephone,
    this.email,
    this.siren,
    this.conditionsPaiement,
    this.iban,
    this.messageRemerciement,
  });

  /// Les valeurs actuelles du profil, pour préremplir le formulaire.
  factory DonneesEntreprise.depuis(Entreprise e) => DonneesEntreprise(
    nomCommercial: e.nomCommercial,
    nomResponsable: e.nomResponsable,
    adresse: e.adresse,
    codePostal: e.codePostal,
    ville: e.ville,
    telephone: e.telephone,
    email: e.email,
    siren: e.siren,
    conditionsPaiement: e.conditionsPaiement,
    iban: e.iban,
    messageRemerciement: e.messageRemerciement,
  );

  final String? nomCommercial;
  final String? nomResponsable;
  final String? adresse;
  final String? codePostal;
  final String? ville;
  final String? telephone;
  final String? email;
  final String? siren;

  /// Vide = les conditions par défaut (« Paiement à réception de la facture. »).
  final String? conditionsPaiement;
  final String? iban;

  /// Vide = pas de message de remerciement sur les factures.
  final String? messageRemerciement;

  /// Lance [DonneeInvalide] (message en français) si une valeur est impossible.
  void valider() {
    final String? probleme =
        _tropLong(nomCommercial, 100, 'Le nom de l’entreprise') ??
        _tropLong(nomResponsable, 100, 'Le nom de l’entrepreneuse') ??
        _tropLong(adresse, 200, 'L’adresse') ??
        _tropLong(ville, 100, 'La ville') ??
        verifierCodePostal(codePostal) ??
        verifierTelephone(telephone) ??
        verifierEmail(email) ??
        verifierSiren(siren) ??
        verifierIban(iban) ??
        _tropLong(conditionsPaiement, 300, 'Les conditions de paiement') ??
        _tropLong(messageRemerciement, 200, 'Le message de remerciement');
    if (probleme != null) throw DonneeInvalide(probleme);
  }

  static String? _tropLong(String? valeur, int max, String libelle) {
    if ((valeur?.trim().length ?? 0) <= max) return null;
    return '$libelle ne peut pas dépasser $max caractères.';
  }
}

/// Profil « Mon entreprise » et réglages (une seule ligne, `id = 1`).
class ParametresRepository implements ModeThemeStore {
  ParametresRepository(this._db);

  final AppDatabase _db;

  Future<Entreprise> lire() =>
      (_db.select(_db.parametresEntreprise)..where((t) => t.id.equals(1))).getSingle();

  Stream<Entreprise> observer() =>
      (_db.select(_db.parametresEntreprise)..where((t) => t.id.equals(1))).watchSingle();

  /// Enregistre le profil « Mon entreprise » après contrôle des valeurs (voir [DonneesEntreprise.valider]).
  Future<void> enregistrerProfil(DonneesEntreprise donnees) async {
    donnees.valider();
    final String? siren = nullSiVide(donnees.siren);
    final String? iban = nullSiVide(donnees.iban);
    await modifier(
      ParametresEntrepriseCompanion(
        nomCommercial: Value(nullSiVide(donnees.nomCommercial) ?? ''),
        nomResponsable: Value(nullSiVide(donnees.nomResponsable)),
        adresse: Value(nullSiVide(donnees.adresse)),
        codePostal: Value(nullSiVide(donnees.codePostal)),
        ville: Value(nullSiVide(donnees.ville)),
        telephone: Value(nullSiVide(donnees.telephone)),
        email: Value(nullSiVide(donnees.email)),
        siren: Value(siren == null ? null : normaliserSiren(siren)),
        conditionsPaiement: Value(nullSiVide(donnees.conditionsPaiement) ?? conditionsPaiementParDefaut),
        iban: Value(iban == null ? null : formaterIban(iban)),
        messageRemerciement: Value(nullSiVide(donnees.messageRemerciement) ?? ''),
      ),
    );
  }

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
