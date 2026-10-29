import '../../domain/enums.dart';
import '../../domain/regles_cours.dart';
import '../database/app_database.dart';

/// Quels cours afficher dans la liste.
enum FiltreCours {
  aVenir('À venir'),
  passes('Passés'),
  archives('Archivés');

  const FiltreCours(this.libelle);
  final String libelle;
}

/// Une ligne de la liste des cours : le cours et l'état de ses inscriptions.
class CoursResume {
  const CoursResume({required this.cours, required this.confirmes, required this.enAttente});

  final CoursFiche cours;

  /// Personnes dont l'inscription est confirmée (elles occupent une place).
  final int confirmes;

  /// Personnes sur la liste d'attente.
  final int enAttente;

  int get placesLibres => placesRestantes(places: cours.places, confirmes: confirmes);
  bool get complet => placesLibres == 0;
  bool get annule => cours.statut == StatutCours.annule;
  bool get archive => cours.archiveLe != null;
}

/// Une personne inscrite (ou en attente, ou dont l'inscription est annulée) avec ce qu'il faut pour l'afficher :
/// son client, la vente qui encaisse sa place, ce qu'elle a payé et sa facture éventuelle.
class InscriptionDetail {
  const InscriptionDetail({
    required this.inscription,
    required this.client,
    this.vente,
    this.encaisseCentimes = 0,
    this.facture,
    this.rangAttente,
  });

  final Inscription inscription;
  final Client client;

  /// La vente créée à l'inscription (`null` pour une personne en liste d'attente : rien n'est vendu avant sa
  /// confirmation).
  final Vente? vente;

  /// Net encaissé sur la vente (paiements moins remboursements).
  final int encaisseCentimes;

  /// La facture émise pour cette vente, s'il y en a une.
  final Facture? facture;

  /// Place dans la liste d'attente (1 = la première) ; `null` si la personne n'attend pas.
  final int? rangAttente;

  StatutInscription get statut => inscription.statut;

  /// Statut de paiement de la vente ; `null` sans vente.
  StatutPaiement? get statutPaiement => vente?.statutPaiement;

  /// Reste à payer sur une vente en cours ; 0 si la vente est annulée ; `null` sans vente.
  int? get soldeCentimes {
    final Vente? v = vente;
    if (v == null) return null;
    if (v.statut == StatutVente.annulee) return 0;
    final int reste = v.totalCentimes - encaisseCentimes;
    return reste < 0 ? 0 : reste;
  }
}

/// Tout ce qu'affiche la fiche d'un cours : le cours, les inscrits, la liste d'attente, les inscriptions annulées.
class CoursDetail {
  const CoursDetail({
    required this.cours,
    this.confirmees = const <InscriptionDetail>[],
    this.enAttente = const <InscriptionDetail>[],
    this.annulees = const <InscriptionDetail>[],
  });

  final CoursFiche cours;

  /// Inscrits confirmés, dans l'ordre d'inscription.
  final List<InscriptionDetail> confirmees;

  /// Liste d'attente, dans l'ordre d'arrivée.
  final List<InscriptionDetail> enAttente;
  final List<InscriptionDetail> annulees;

  int get placesLibres => placesRestantes(places: cours.places, confirmes: confirmees.length);
  bool get complet => placesLibres == 0;
  bool get annule => cours.statut == StatutCours.annule;
  bool get archive => cours.archiveLe != null;

  bool termine(DateTime maintenant) => coursTermine(cours.debutLe, cours.dureeMinutes, maintenant);

  /// Pourquoi on ne peut pas inscrire quelqu'un ; `null` si c'est possible.
  String? get refusInscriptionCours => refusInscription(statut: cours.statut, archive: archive);

  /// Pourquoi on ne peut pas confirmer [personne] ; `null` si c'est possible.
  String? refusConfirmationDe(InscriptionDetail personne) => refusConfirmation(
    statutInscription: personne.statut,
    statutCours: cours.statut,
    archive: archive,
    placesLibres: placesLibres,
    estPremiere: enAttente.isNotEmpty && enAttente.first.inscription.id == personne.inscription.id,
  );

  /// Pourquoi on ne peut pas archiver le cours à l'instant [maintenant] ; `null` si c'est possible.
  String? refusArchivageCours(DateTime maintenant) =>
      refusArchivage(statut: cours.statut, termine: termine(maintenant));
}

/// Ce que renvoie une inscription ou une confirmation : l'inscription et la vente créée pour elle
/// (`null` pour une inscription en liste d'attente).
class ResultatInscription {
  const ResultatInscription({required this.inscription, this.vente});

  final Inscription inscription;
  final Vente? vente;
}
