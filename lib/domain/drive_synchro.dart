// Google Drive, partie 3 : reprise d'un appareil à l'autre (le téléphone et l'ordinateur).
//
// Des règles pures, testées sans réseau. Un seul appareil est actif à la fois : chacun envoie ses données sur Drive (une
// sauvegarde « données seules », voir `drive_sauvegardes.dart`), et l'autre propose de les **reprendre** à son ouverture.
// Il n'y a **pas de fusion** de modifications faites en même temps sur les deux appareils : dans ce cas, c'est la personne
// qui choisit, et rien n'est jamais écrasé en silence (la version qu'on ne garde pas reste sur Drive, l'application ne
// supprime rien).
//
// Chaque appareil retient la **dernière version de Drive qu'il a envoyée ou reprise** (une [ReferenceSynchro]) et
// l'**empreinte de ses données à ce moment-là**. En les comparant à ce que Drive contient et à ses données du moment, il sait
// deux choses :
//   - Drive a-t-il une version plus récente que celle-là (envoyée d'un autre appareil) ?
//   - cet appareil a-t-il changé depuis ?

import 'drive_sauvegardes.dart';

/// Où en est cet appareil par rapport à Drive.
enum SituationSynchro {
  /// Rien de plus récent sur Drive, et rien de neuf ici : tout est à jour.
  aJour,

  /// Rien de plus récent sur Drive, mais cet appareil a du neuf : à envoyer.
  aEnvoyer,

  /// Drive a une version plus récente, envoyée d'un autre appareil, et cet appareil n'a rien de neuf : on propose de la
  /// **reprendre**.
  aReprendre,

  /// Drive a une version plus récente **et** cet appareil a du neuf (ou on ne peut pas le savoir) : la personne choisit,
  /// il n'y a pas de fusion.
  aChoisir,
}

/// Ce que la comparaison de cet appareil et de Drive a donné.
class ConstatSynchro {
  const ConstatSynchro({
    required this.situation,
    required this.empreinteLocale,
    this.distante,
    this.reference,
    this.modifieIci,
  });

  final SituationSynchro situation;

  /// La sauvegarde la plus récente sur Drive (`null` : il n'y en a aucune).
  final SauvegardeDrive? distante;

  /// Ce que cet appareil a envoyé ou repris la dernière fois (`null` : jamais).
  final ReferenceSynchro? reference;

  /// Empreinte des données de cet appareil au moment de la comparaison.
  final String empreinteLocale;

  /// Cet appareil a-t-il changé depuis sa référence ? `null` : on ne peut pas le dire (aucune référence, ou référence
  /// d'avant la synchronisation).
  final bool? modifieIci;

  /// Une version plus récente est sur Drive : la personne doit décider (reprendre, ou garder cet appareil).
  bool get demandeUneDecision => situation == SituationSynchro.aReprendre || situation == SituationSynchro.aChoisir;
}

/// Compare cet appareil et Drive.
///
/// - [reference] : la dernière version de Drive que cet appareil a envoyée ou reprise (`null` : jamais).
/// - [distante] : la sauvegarde la plus récente sur Drive (`null` : aucune).
/// - [empreinteLocale] : l'empreinte des données de cet appareil, maintenant.
/// - [donneesVierges] : cet appareil n'a encore rien de saisi (une installation toute neuve) ; ne sert que s'il n'a jamais
///   été synchronisé.
/// - [fichiersEnAttente] : des photos ou documents n'ont pas pu partir la dernière fois : il reste à les envoyer.
ConstatSynchro constaterSynchro({
  required ReferenceSynchro? reference,
  required SauvegardeDrive? distante,
  required String empreinteLocale,
  bool donneesVierges = false,
  bool fichiersEnAttente = false,
}) {
  final String? connue = reference?.empreinteLocale;
  final bool? modifieIci = connue == null ? null : connue != empreinteLocale;

  // Plus récente que ce que cet appareil a envoyé ou repris. Une sauvegarde plus ancienne que la référence (celle qu'on avait
  // a disparu de Drive) n'est pas une nouveauté.
  final bool plusRecente =
      distante != null && (reference == null || (distante.nom != reference.nom && distante.date.isAfter(reference.date)));

  final SituationSynchro situation;
  if (plusRecente) {
    if (modifieIci == false || (reference == null && donneesVierges)) {
      situation = SituationSynchro.aReprendre;
    } else {
      situation = SituationSynchro.aChoisir;
    }
  } else if (reference == null) {
    // Jamais synchronisé, et rien d'autre sur Drive : on envoie, sauf si cet appareil n'a rien à envoyer.
    situation = donneesVierges ? SituationSynchro.aJour : SituationSynchro.aEnvoyer;
  } else if (modifieIci != false || fichiersEnAttente) {
    situation = SituationSynchro.aEnvoyer;
  } else {
    situation = SituationSynchro.aJour;
  }

  return ConstatSynchro(
    situation: situation,
    empreinteLocale: empreinteLocale,
    distante: distante,
    reference: reference,
    modifieIci: modifieIci,
  );
}

/// Les envois faits en passant l'application en arrière-plan (Android) sont espacés d'au moins cette durée : on n'ajoute pas
/// une sauvegarde sur Drive à chaque fois qu'on change d'application.
const Duration delaiEntreEnvoisEnArrierePlan = Duration(minutes: 10);

/// L'envoi en arrière-plan peut-il partir maintenant ? [dernierEnvoi] : la dernière fois qu'il a été tenté (`null` : jamais).
bool envoiEnArrierePlanPermis(DateTime? dernierEnvoi, DateTime maintenant) {
  if (dernierEnvoi == null) return true;
  final Duration ecoule = maintenant.difference(dernierEnvoi);
  return ecoule.isNegative || ecoule >= delaiEntreEnvoisEnArrierePlan;
}
