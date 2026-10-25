import 'enums.dart';

/// Une ligne imprimée sur la facture.
class LigneDocument {
  const LigneDocument({
    required this.designation,
    this.description,
    required this.quantite,
    required this.prixUnitaireCentimes,
    required this.totalCentimes,
  });

  final String designation;

  /// Précisions sous la désignation (facultatif).
  final String? description;
  final int quantite;
  final int prixUnitaireCentimes;
  final int totalCentimes;
}

/// Qui émet la facture : l'entreprise de l'entrepreneuse.
class EmetteurDocument {
  const EmetteurDocument({
    required this.nom,
    this.responsable,
    this.adresse = const <String>[],
    this.telephone,
    this.email,
    this.siren,
  });

  /// Nom commercial (à défaut, le nom de l'entrepreneuse).
  final String nom;

  /// Nom de l'entrepreneuse, affiché sous le nom commercial quand il est différent.
  final String? responsable;

  /// Lignes d'adresse : « 12 rue des Lilas », « 31000 Toulouse ».
  final List<String> adresse;
  final String? telephone;
  final String? email;

  /// 9 chiffres, sans espaces.
  final String? siren;
}

/// À qui la facture est adressée, tel qu'enregistré au moment de l'émission.
class DestinataireDocument {
  const DestinataireDocument({this.nom, this.adresse = const <String>[], this.siret});

  /// Vide pour un client de passage.
  final String? nom;
  final List<String> adresse;
  final String? siret;
}

/// Tout ce qui est imprimé sur une facture, prêt à mettre en page. Aucune dépendance au PDF ni à la
/// base : le même document sert à fabriquer le PDF et à le tester.
class DocumentFacture {
  const DocumentFacture({
    required this.numero,
    required this.dateEmission,
    required this.dateVentePrestation,
    required this.emetteur,
    required this.client,
    required this.lignes,
    required this.sousTotalCentimes,
    this.remiseCentimes = 0,
    this.libelleRemise = 'Remise',
    this.fraisPortCentimes = 0,
    required this.totalCentimes,
    required this.mentionTva,
    this.conditionsPaiement,
    this.iban,
    this.messageRemerciement,
  });

  /// `FACT-2026-0001`.
  final String numero;
  final DateTime dateEmission;

  /// Date de la vente ou de la prestation.
  final DateTime dateVentePrestation;
  final EmetteurDocument emetteur;
  final DestinataireDocument client;
  final List<LigneDocument> lignes;
  final int sousTotalCentimes;
  final int remiseCentimes;

  /// « Remise » ou « Remise (10 %) » (voir [libelleRemiseDocument]).
  final String libelleRemise;
  final int fraisPortCentimes;
  final int totalCentimes;

  /// « TVA non applicable, article 293 B du CGI ».
  final String mentionTva;
  final String? conditionsPaiement;
  final String? iban;
  final String? messageRemerciement;
}

/// « Remise » pour un montant, « Remise (10 %) » pour un pourcentage ([valeur] en centièmes de
/// pour cent : 1000 = 10 %, 1250 = 12,5 %). L'espace avant « % » est insécable.
String libelleRemiseDocument(RemiseType type, int valeur) {
  if (type != RemiseType.pourcentage) return 'Remise';
  final int entier = valeur ~/ 100;
  final int centiemes = valeur % 100;
  String nombre = '$entier';
  if (centiemes != 0) {
    final String decimales = centiemes.toString().padLeft(2, '0');
    nombre = '$entier,${decimales.endsWith('0') ? decimales.substring(0, 1) : decimales}';
  }
  return 'Remise ($nombre %)';
}
