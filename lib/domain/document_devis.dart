import 'document_facture.dart';

/// Tout ce qui est imprimé sur un devis, prêt à mettre en page. Comme [DocumentFacture], il ne dépend ni du
/// PDF ni de la base : le même document sert à fabriquer le PDF et à le tester. Les lignes, l'émetteur et le
/// destinataire sont ceux de la facture ([LigneDocument], [EmetteurDocument], [DestinataireDocument]).
class DocumentDevis {
  const DocumentDevis({
    required this.numero,
    required this.dateEmission,
    this.dateValidite,
    this.delaiRealisation,
    this.acompteCentimes = 0,
    required this.emetteur,
    required this.client,
    required this.lignes,
    required this.sousTotalCentimes,
    this.remiseCentimes = 0,
    this.libelleRemise = 'Remise',
    this.fraisPortCentimes = 0,
    required this.totalCentimes,
    required this.mentionTva,
    this.iban,
  });

  /// `DEVIS-2026-0001`.
  final String numero;
  final DateTime dateEmission;

  /// Dernier jour où le devis est valable (vide : pas de limite).
  final DateTime? dateValidite;

  /// Délai de réalisation, en texte libre (« 3 semaines »).
  final String? delaiRealisation;

  /// Acompte demandé à l'acceptation, en centimes (0 : pas d'acompte).
  final int acompteCentimes;
  final EmetteurDocument emetteur;

  /// Vide (sans nom) quand le devis n'a pas de client.
  final DestinataireDocument client;
  final List<LigneDocument> lignes;
  final int sousTotalCentimes;
  final int remiseCentimes;

  /// « Remise » ou « Remise (10 %) » (voir `libelleRemiseDocument`).
  final String libelleRemise;
  final int fraisPortCentimes;
  final int totalCentimes;

  /// « TVA non applicable, article 293 B du CGI ».
  final String mentionTva;

  /// Imprimé sous l'acompte pour qu'on puisse le régler par virement (facultatif).
  final String? iban;
}
