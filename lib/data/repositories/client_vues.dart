import '../../domain/enums.dart';
import '../database/app_database.dart';

String _personne(Client c) => <String?>[
  c.prenom,
  c.nom,
].whereType<String>().map((String s) => s.trim()).where((String s) => s.isNotEmpty).join(' ');

/// Nom affiché d'un client : la raison sociale pour un professionnel, sinon « Prénom Nom ».
String libelleClient(Client c) {
  final String personne = _personne(c);
  final String raison = c.raisonSociale?.trim() ?? '';
  if (c.typeClient == TypeClient.professionnel && raison.isNotEmpty) return raison;
  if (personne.isNotEmpty) return personne;
  return raison;
}

/// Personne à contacter chez un professionnel (affichée sous le nom de l'entreprise).
String? contactClient(Client c) {
  final String personne = _personne(c);
  final String raison = c.raisonSociale?.trim() ?? '';
  if (c.typeClient == TypeClient.professionnel && raison.isNotEmpty && personne.isNotEmpty) {
    return personne;
  }
  return null;
}

/// Une ou deux initiales pour la pastille du client (« CM » pour Camille Martin).
String initialesClient(Client c) {
  final List<String> mots = libelleClient(c).split(RegExp(r'\s+')).where((String m) => m.isNotEmpty).toList();
  if (mots.isEmpty) return '?';
  final String premiere = String.fromCharCode(mots.first.runes.first);
  if (mots.length == 1) return premiere.toUpperCase();
  return (premiere + String.fromCharCode(mots.last.runes.first)).toUpperCase();
}

/// Les textes dans lesquels on cherche un client. Le téléphone est aussi cherché sans espaces
/// (« 0612 » trouve « 06 12 34 56 78 »).
List<String?> champsRechercheClient(Client c) => <String?>[
  c.prenom,
  c.nom,
  c.raisonSociale,
  c.telephone,
  c.telephone?.replaceAll(RegExp(r'\D'), ''),
  c.email,
  c.adresse,
  c.codePostal,
  c.ville,
  c.siret,
  c.siret?.replaceAll(RegExp(r'\D'), ''),
  c.notes,
];

/// Une vente d'un client, dans son historique.
class VenteClient {
  const VenteClient({
    required this.venteId,
    required this.dateVente,
    required this.totalCentimes,
    required this.statut,
    required this.statutPaiement,
  });

  final int venteId;
  final DateTime dateVente;
  final int totalCentimes;
  final StatutVente statut;
  final StatutPaiement statutPaiement;
}

/// Un paiement (ou remboursement, de montant négatif) d'une vente du client.
class PaiementClient {
  const PaiementClient({
    required this.paiementId,
    required this.venteId,
    required this.datePaiement,
    required this.mode,
    required this.montantCentimes,
  });

  final int paiementId;
  final int venteId;
  final DateTime datePaiement;
  final ModePaiement mode;
  final int montantCentimes;
}

/// Une inscription du client à un cours.
class InscriptionClient {
  const InscriptionClient({
    required this.inscriptionId,
    required this.coursId,
    required this.titreCours,
    required this.debutCours,
    required this.statut,
    required this.prixCentimes,
  });

  final int inscriptionId;
  final int coursId;
  final String titreCours;
  final DateTime debutCours;
  final StatutInscription statut;
  final int prixCentimes;
}

/// Tout l'historique d'un client : devis, ventes, factures, paiements et cours.
class HistoriqueClient {
  const HistoriqueClient({
    this.devis = const <DevisFiche>[],
    this.ventes = const <VenteClient>[],
    this.factures = const <Facture>[],
    this.paiements = const <PaiementClient>[],
    this.inscriptions = const <InscriptionClient>[],
  });

  final List<DevisFiche> devis;
  final List<VenteClient> ventes;
  final List<Facture> factures;
  final List<PaiementClient> paiements;
  final List<InscriptionClient> inscriptions;

  /// Total des ventes validées (les ventes annulées ne comptent pas).
  int get totalAchatsCentimes => ventes
      .where((VenteClient v) => v.statut == StatutVente.validee)
      .fold(0, (int somme, VenteClient v) => somme + v.totalCentimes);

  int get nombreVentesValidees => ventes.where((VenteClient v) => v.statut == StatutVente.validee).length;

  bool get estVide =>
      devis.isEmpty && ventes.isEmpty && factures.isEmpty && paiements.isEmpty && inscriptions.isEmpty;
}
