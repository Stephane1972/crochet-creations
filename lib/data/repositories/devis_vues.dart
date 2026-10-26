import '../../domain/enums.dart';
import '../../domain/regles_devis.dart';
import '../database/app_database.dart';

/// Une ligne de la liste des devis : le devis et son client (`null` : devis sans client).
class DevisResume {
  const DevisResume({required this.devis, this.client});

  final DevisFiche devis;
  final Client? client;

  /// Statut à afficher à la date [maintenant] : un devis dont la validité est dépassée est « Expiré »,
  /// même si la base ne l'a pas encore été mise à jour.
  StatutDevis statut(DateTime maintenant) => statutAffiche(devis.statut, devis.dateValidite, maintenant);
}

/// Tout ce qu'affiche le détail d'un devis : lignes, client, et la vente créée à la conversion.
class DevisDetail {
  const DevisDetail({required this.devis, required this.lignes, this.client, this.vente});

  final DevisFiche devis;

  /// Lignes dans l'ordre de saisie.
  final List<LigneDevis> lignes;

  /// `null` pour un devis sans client.
  final Client? client;

  /// La commande créée quand le devis a été converti.
  final Vente? vente;

  bool get estConverti => devis.venteId != null;

  StatutDevis statut(DateTime maintenant) => statutAffiche(devis.statut, devis.dateValidite, maintenant);

  bool peutModifier(DateTime maintenant) => peutEtreModifie(statut(maintenant), converti: estConverti);

  bool peutConvertir(DateTime maintenant) => peutEtreConverti(statut(maintenant), converti: estConverti);

  /// Statuts proposables à la main (« Marquer comme envoyé », « accepté », « refusé »).
  Set<StatutDevis> statutsProposes(DateTime maintenant) =>
      statutsPossibles(statut(maintenant), converti: estConverti);
}

/// Ce que la conversion d'un devis a créé.
class ResultatConversion {
  const ResultatConversion({required this.devis, required this.vente, this.facture, this.problemeFacture});

  /// Le devis, désormais accepté et lié à la commande.
  final DevisFiche devis;

  /// La commande (vente) créée à partir du devis.
  final Vente vente;

  /// La facture, quand elle a été demandée et établie.
  final Facture? facture;

  /// Pourquoi la facture n'a pas pu être établie (la commande, elle, existe) ; `null` si tout s'est bien passé
  /// ou si aucune facture n'était demandée.
  final String? problemeFacture;
}
