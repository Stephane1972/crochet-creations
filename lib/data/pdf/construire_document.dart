import '../../core/constants/app_constants.dart';
import '../../core/utils/texte.dart';
import '../../domain/document_devis.dart';
import '../../domain/document_facture.dart';
import '../database/app_database.dart';
import '../repositories/client_vues.dart';

/// Rassemble ce qui s'imprime sur une facture : l'identité de l'entreprise (profil « Mon entreprise »),
/// le client et les mentions recopiés à l'émission (ligne de la facture), puis les lignes et les montants
/// de la vente liée, qui n'est plus modifiable.
DocumentFacture construireDocumentFacture({
  required Facture facture,
  required Vente vente,
  required List<LigneVente> lignes,
  required Entreprise entreprise,
}) {
  return DocumentFacture(
    numero: facture.numero,
    dateEmission: facture.dateEmission,
    dateVentePrestation: facture.dateVentePrestation,
    emetteur: emetteurDepuis(entreprise),
    client: DestinataireDocument(
      nom: nullSiVide(facture.clientNom),
      adresse: lignesDAdresse(facture.clientAdresse),
      siret: nullSiVide(facture.clientSiret),
    ),
    lignes: <LigneDocument>[
      for (final LigneVente l in lignes)
        LigneDocument(
          designation: l.designation,
          description: nullSiVide(l.description),
          quantite: l.quantite,
          prixUnitaireCentimes: l.prixUnitaireCentimes,
          totalCentimes: l.totalLigneCentimes,
        ),
    ],
    sousTotalCentimes: vente.sousTotalCentimes,
    remiseCentimes: vente.remiseCentimes,
    libelleRemise: libelleRemiseDocument(vente.remiseType, vente.remiseValeur),
    fraisPortCentimes: vente.fraisPortCentimes,
    totalCentimes: facture.totalCentimes,
    mentionTva: facture.mentionTva,
    conditionsPaiement: nullSiVide(facture.conditionsPaiement),
    iban: nullSiVide(facture.iban),
    messageRemerciement: nullSiVide(facture.messageRemerciement),
  );
}

/// L'entreprise telle qu'elle s'imprime : le nom commercial (à défaut le nom de l'entrepreneuse), son
/// nom en dessous quand il est différent, l'adresse sur deux lignes, puis téléphone, e-mail et SIREN.
EmetteurDocument emetteurDepuis(Entreprise e) {
  final String? commercial = nullSiVide(e.nomCommercial);
  final String? responsable = nullSiVide(e.nomResponsable);
  final String? codePostalVille = nullSiVide(<String?>[
    nullSiVide(e.codePostal),
    nullSiVide(e.ville),
  ].whereType<String>().join(' '));
  return EmetteurDocument(
    nom: commercial ?? responsable ?? '',
    responsable: commercial != null && responsable != null && responsable != commercial ? responsable : null,
    adresse: <String>[
      if (nullSiVide(e.adresse) != null) nullSiVide(e.adresse)!,
      if (codePostalVille != null) codePostalVille,
    ],
    telephone: nullSiVide(e.telephone),
    email: nullSiVide(e.email),
    siren: nullSiVide(e.siren),
  );
}

/// Adresse enregistrée sur la facture (une ligne par retour à la ligne) → lignes imprimées.
List<String> lignesDAdresse(String? adresse) {
  if (adresse == null) return const <String>[];
  return adresse.split('\n').map((String l) => l.trim()).where((String l) => l.isNotEmpty).toList();
}

/// Adresse d'un client telle qu'elle est recopiée sur la facture : rue, puis code postal et ville.
String? adresseClientPourFacture(Client c) {
  final String? codePostalVille = nullSiVide(<String?>[
    nullSiVide(c.codePostal),
    nullSiVide(c.ville),
  ].whereType<String>().join(' '));
  final String texte = <String?>[
    nullSiVide(c.adresse),
    codePostalVille,
  ].whereType<String>().join('\n');
  return nullSiVide(texte);
}

/// Rassemble ce qui s'imprime sur un devis : l'identité de l'entreprise (profil « Mon entreprise »), le client
/// (sa fiche actuelle, un devis n'étant pas figé comme une facture), les lignes et les conditions du devis.
DocumentDevis construireDocumentDevis({
  required DevisFiche devis,
  required List<LigneDevis> lignes,
  Client? client,
  required Entreprise entreprise,
}) {
  return DocumentDevis(
    numero: devis.numero,
    dateEmission: devis.dateEmission,
    dateValidite: devis.dateValidite,
    delaiRealisation: nullSiVide(devis.delaiRealisation),
    acompteCentimes: devis.acompteCentimes,
    emetteur: emetteurDepuis(entreprise),
    client: client == null
        ? const DestinataireDocument()
        : DestinataireDocument(
            nom: nullSiVide(libelleClient(client)),
            adresse: lignesDAdresse(adresseClientPourFacture(client)),
            siret: nullSiVide(client.siret),
          ),
    lignes: <LigneDocument>[
      for (final LigneDevis l in lignes)
        LigneDocument(
          designation: l.designation,
          description: nullSiVide(l.description),
          quantite: l.quantite,
          prixUnitaireCentimes: l.prixUnitaireCentimes,
          totalCentimes: l.totalLigneCentimes,
        ),
    ],
    sousTotalCentimes: devis.sousTotalCentimes,
    remiseCentimes: devis.remiseCentimes,
    libelleRemise: libelleRemiseDocument(devis.remiseType, devis.remiseValeur),
    fraisPortCentimes: devis.fraisPortCentimes,
    totalCentimes: devis.totalCentimes,
    mentionTva: AppConstants.mentionTvaFranchise,
    iban: nullSiVide(entreprise.iban),
  );
}
