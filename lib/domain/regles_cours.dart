import 'enums.dart';
import 'erreurs.dart';

/// Règles des cours et des inscriptions, sans base de données ni interface : places, liste d'attente,
/// ce qui est permis ou refusé. Les messages sont ceux affichés à l'utilisatrice.

/// Fin d'un cours : son début plus sa durée.
DateTime finDuCours(DateTime debutLe, int dureeMinutes) => debutLe.add(Duration(minutes: dureeMinutes));

/// Vrai si le cours est entièrement derrière nous à l'instant [maintenant].
bool coursTermine(DateTime debutLe, int dureeMinutes, DateTime maintenant) =>
    finDuCours(debutLe, dureeMinutes).isBefore(maintenant);

/// Nombre de places encore libres (jamais négatif, même si des places ont été retirées après coup).
int placesRestantes({required int places, required int confirmes}) {
  final int libres = places - confirmes;
  return libres < 0 ? 0 : libres;
}

/// Statut d'une nouvelle inscription : confirmée s'il reste une place, sinon en liste d'attente.
StatutInscription statutNouvelleInscription(int placesLibres) =>
    placesLibres > 0 ? StatutInscription.confirmee : StatutInscription.listeAttente;

/// Une personne de la liste d'attente : son inscription et la date à laquelle elle s'est inscrite.
class EnAttente {
  const EnAttente({required this.inscriptionId, required this.dateInscription});

  final int inscriptionId;
  final DateTime dateInscription;
}

/// La liste d'attente dans l'ordre d'arrivée (date d'inscription, puis ordre de création en cas d'égalité).
List<EnAttente> ordreAttente(Iterable<EnAttente> attente) {
  final List<EnAttente> liste = attente.toList();
  liste.sort((EnAttente a, EnAttente b) {
    final int parDate = a.dateInscription.compareTo(b.dateInscription);
    return parDate != 0 ? parDate : a.inscriptionId.compareTo(b.inscriptionId);
  });
  return liste;
}

/// Identifiant de l'inscription en tête de la liste d'attente ; `null` si personne n'attend.
int? premierEnAttente(Iterable<EnAttente> attente) {
  final List<EnAttente> ordre = ordreAttente(attente);
  return ordre.isEmpty ? null : ordre.first.inscriptionId;
}

/// Contrôle les informations d'un cours. [confirmes] : inscriptions confirmées actuelles (on ne peut pas
/// réduire le nombre de places en dessous). Lance [DonneeInvalide] (message en français).
void verifierCours({
  required String titre,
  required int dureeMinutes,
  required int prixCentimes,
  required int places,
  int confirmes = 0,
}) {
  if (titre.trim().isEmpty) throw const DonneeInvalide('Indiquez le titre du cours.');
  if (dureeMinutes < 1) throw const DonneeInvalide('La durée doit être d’au moins 1 minute.');
  if (prixCentimes < 0) throw const DonneeInvalide('Le prix ne peut pas être négatif.');
  if (places < 1) throw const DonneeInvalide('Il faut au moins une place.');
  if (places < confirmes) {
    // Ici « confirmes » vaut au moins 2 : avec une seule personne confirmée, « moins de places » veut dire zéro.
    throw DonneeInvalide(
      'Ce cours compte déjà $confirmes personnes confirmées : le nombre de places ne peut pas être plus petit.',
    );
  }
}

/// Pourquoi on ne peut pas inscrire quelqu'un à ce cours ; `null` si c'est possible.
String? refusInscription({required StatutCours statut, required bool archive}) {
  if (statut == StatutCours.annule) return 'Ce cours est annulé : on ne peut plus y inscrire personne.';
  if (archive) return 'Ce cours est archivé : restaurez-le pour y inscrire quelqu’un.';
  return null;
}

/// Pourquoi on ne peut pas confirmer cette personne de la liste d'attente ; `null` si c'est possible.
/// Il faut une place libre, et la personne doit être la première de la liste.
String? refusConfirmation({
  required StatutInscription statutInscription,
  required StatutCours statutCours,
  required bool archive,
  required int placesLibres,
  required bool estPremiere,
}) {
  if (statutInscription != StatutInscription.listeAttente) {
    return 'Cette personne n’est pas sur la liste d’attente.';
  }
  final String? refus = refusInscription(statut: statutCours, archive: archive);
  if (refus != null) return refus;
  if (placesLibres < 1) return 'Le cours est complet : aucune place n’est libre pour le moment.';
  if (!estPremiere) return 'Seule la première personne de la liste d’attente peut être confirmée.';
  return null;
}

/// Une inscription déjà annulée ne s'annule pas une seconde fois.
bool peutAnnulerInscription(StatutInscription statut) => statut != StatutInscription.annulee;
