/// Règles des devis : validité, acompte, statuts, expiration automatique.
///
/// Tout est exprimé en fonctions pures (aucune base de données, aucun écran) : le dépôt de données
/// et les écrans appliquent exactement les mêmes règles, et elles se testent sans rien d'autre.
library;

import '../core/utils/money.dart';
import 'enums.dart';
import 'erreurs.dart';

/// Durée de validité proposée à la création d'un devis (modifiable).
const int validiteParDefautEnJours = 30;

/// Minuit (heure locale) du jour de [date] : les dates d'un devis se comptent en jours entiers.
DateTime debutDeJour(DateTime date) {
  final DateTime locale = date.toLocal();
  return DateTime(locale.year, locale.month, locale.day);
}

/// Date de validité proposée pour un devis établi le [emission] : 30 jours plus tard.
DateTime dateValiditeParDefaut(DateTime emission) {
  final DateTime jour = debutDeJour(emission);
  return DateTime(jour.year, jour.month, jour.day + validiteParDefautEnJours);
}

/// Vrai si la date limite est dépassée à la date [maintenant]. Un devis reste valable **toute la journée**
/// de sa date de validité : il n'est périmé qu'à partir du lendemain. Pas de date limite = jamais périmé.
bool validiteDepassee(DateTime? dateValidite, DateTime maintenant) {
  if (dateValidite == null) return false;
  return debutDeJour(dateValidite).isBefore(debutDeJour(maintenant));
}

/// Statut à afficher : un brouillon ou un devis envoyé dont la validité est dépassée est « Expiré ».
/// Les devis acceptés ou refusés ne changent jamais d'eux-mêmes.
StatutDevis statutAffiche(StatutDevis statut, DateTime? dateValidite, DateTime maintenant) {
  final bool encoreOuvert = statut == StatutDevis.brouillon || statut == StatutDevis.envoye;
  if (encoreOuvert && validiteDepassee(dateValidite, maintenant)) return StatutDevis.expire;
  return statut;
}

/// Statuts que l'utilisatrice peut choisir à partir de [actuel] (hors conversion, qui accepte le devis
/// elle-même) :
///
/// - brouillon → envoyé, accepté ou refusé ;
/// - envoyé → accepté ou refusé ;
/// - accepté (pas encore converti) → refusé ;
/// - refusé, expiré ou converti : plus de changement possible. Un devis expiré redevient un brouillon
///   quand on prolonge sa validité (voir [peutEtreModifie]).
Set<StatutDevis> statutsPossibles(StatutDevis actuel, {required bool converti}) {
  if (converti) return const <StatutDevis>{};
  return switch (actuel) {
    StatutDevis.brouillon => const <StatutDevis>{StatutDevis.envoye, StatutDevis.accepte, StatutDevis.refuse},
    StatutDevis.envoye => const <StatutDevis>{StatutDevis.accepte, StatutDevis.refuse},
    StatutDevis.accepte => const <StatutDevis>{StatutDevis.refuse},
    StatutDevis.refuse || StatutDevis.expire => const <StatutDevis>{},
  };
}

/// Un devis se modifie tant qu'il n'est ni accepté, ni refusé, ni converti. Un devis expiré se modifie
/// pour prolonger sa validité.
bool peutEtreModifie(StatutDevis statut, {required bool converti}) {
  if (converti) return false;
  return statut == StatutDevis.brouillon || statut == StatutDevis.envoye || statut == StatutDevis.expire;
}

/// Un devis se convertit en commande tant qu'il est un brouillon, envoyé ou accepté, et qu'il n'a pas déjà
/// été converti. Un devis expiré doit d'abord voir sa validité prolongée.
bool peutEtreConverti(StatutDevis statut, {required bool converti}) {
  if (converti) return false;
  return statut == StatutDevis.brouillon || statut == StatutDevis.envoye || statut == StatutDevis.accepte;
}

/// Contrôle les dates et l'acompte d'un devis. Lance [DonneeInvalide] (message en français).
///
/// - la validité ne peut pas précéder la date du devis, ni être déjà passée à la date [maintenant] ;
/// - l'acompte ne peut être ni négatif, ni supérieur au total du devis.
void verifierDevis({
  required DateTime dateEmission,
  DateTime? dateValidite,
  required int acompteCentimes,
  required int totalCentimes,
  required DateTime maintenant,
}) {
  if (dateValidite != null) {
    if (debutDeJour(dateValidite).isBefore(debutDeJour(dateEmission))) {
      throw const DonneeInvalide('La date de validité ne peut pas être avant la date du devis.');
    }
    if (validiteDepassee(dateValidite, maintenant)) {
      throw const DonneeInvalide('La date de validité est déjà passée : choisissez une date à venir.');
    }
  }
  if (acompteCentimes < 0) {
    throw const DonneeInvalide('L’acompte ne peut pas être négatif.');
  }
  if (acompteCentimes > totalCentimes) {
    throw DonneeInvalide('L’acompte ne peut pas dépasser le total du devis (${formatEuros(totalCentimes)}).');
  }
}
