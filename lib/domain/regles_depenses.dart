import 'erreurs.dart';

/// Règles des dépenses, sans base de données ni interface. Les messages sont ceux affichés à l'utilisatrice.

/// Le jour (sans l'heure) d'une date, à minuit, en heure locale.
DateTime jourDe(DateTime date) => DateTime(date.year, date.month, date.day);

/// Vrai si [date] tombe un jour après celui de [maintenant] (on ne note pas une dépense à l'avance).
bool dateDansLeFutur(DateTime date, DateTime maintenant) => jourDe(date).isAfter(jourDe(maintenant));

/// Premier jour du mois [mois] (1 à 12) de l'année [annee], à minuit.
DateTime debutDuMois(int annee, int mois) => DateTime(annee, mois, 1);

/// Premier jour du mois suivant : borne (exclue) d'un mois. `mois: 13` donne janvier de l'année suivante.
DateTime debutDuMoisSuivant(int annee, int mois) => DateTime(annee, mois + 1, 1);

/// Vrai si [date] appartient au mois [mois] de l'année [annee].
bool estDansLeMois(DateTime date, int annee, int mois) => date.year == annee && date.month == mois;

/// Somme de montants en centimes.
int totalCentimes(Iterable<int> montants) => montants.fold(0, (int somme, int m) => somme + m);

/// Contrôle les informations d'une dépense. [maintenant] sert à refuser une date dans le futur.
/// Lance [DonneeInvalide] (message en français).
void verifierDepense({
  required int montantCentimes,
  required DateTime date,
  required DateTime maintenant,
  String? fournisseur,
  String? description,
}) {
  if (montantCentimes <= 0) {
    throw const DonneeInvalide('Le montant de la dépense doit être supérieur à 0 €.');
  }
  if (dateDansLeFutur(date, maintenant)) {
    throw const DonneeInvalide('La date d’une dépense ne peut pas être dans le futur.');
  }
  if ((fournisseur?.trim().length ?? 0) > 200) {
    throw const DonneeInvalide('Le nom du fournisseur est trop long (200 caractères maximum).');
  }
  if ((description?.trim().length ?? 0) > 2000) {
    throw const DonneeInvalide('La description est trop longue (2 000 caractères maximum).');
  }
}
