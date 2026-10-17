import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';

/// Description d'un écran qui sera développé dans une étape ultérieure.
class PlaceholderInfo {
  const PlaceholderInfo({
    required this.titre,
    required this.icone,
    required this.etape,
    required this.description,
  });

  final String titre;
  final IconData icone;

  /// Numéro de l'étape (sur 12) où l'écran sera réellement construit.
  final int etape;
  final String description;
}

/// Écrans prévus mais pas encore développés (voir ROADMAP.md).
abstract final class EcransAVenir {
  static const PlaceholderInfo produits = PlaceholderInfo(
    titre: 'Produits',
    icone: Icons.inventory_2_outlined,
    etape: 3,
    description: 'Catalogue, fiches produits, photos et suivi du stock.',
  );
  static const PlaceholderInfo produitNouveau = PlaceholderInfo(
    titre: 'Nouveau produit',
    icone: Icons.add_circle_outline,
    etape: 3,
    description: 'Ajout et modification d’un produit.',
  );
  static const PlaceholderInfo clients = PlaceholderInfo(
    titre: 'Clients',
    icone: Icons.people_outline,
    etape: 4,
    description: 'Liste des clients, fiches et historique.',
  );
  static const PlaceholderInfo clientNouveau = PlaceholderInfo(
    titre: 'Nouveau client',
    icone: Icons.person_add_alt_outlined,
    etape: 4,
    description: 'Création d’une fiche client.',
  );
  static const PlaceholderInfo nouvelleVente = PlaceholderInfo(
    titre: 'Nouvelle vente',
    icone: Icons.point_of_sale_outlined,
    etape: 5,
    description: 'Panier, remise, frais de port, paiement et facture.',
  );
  static const PlaceholderInfo factures = PlaceholderInfo(
    titre: 'Factures',
    icone: Icons.receipt_long_outlined,
    etape: 6,
    description: 'Liste, aperçu, impression et partage des factures PDF.',
  );
  static const PlaceholderInfo devis = PlaceholderInfo(
    titre: 'Devis',
    icone: Icons.request_quote_outlined,
    etape: 7,
    description: 'Création de devis et conversion en facture.',
  );
  static const PlaceholderInfo devisNouveau = PlaceholderInfo(
    titre: 'Nouveau devis',
    icone: Icons.request_quote_outlined,
    etape: 7,
    description: 'Création et modification d’un devis.',
  );
  static const PlaceholderInfo cours = PlaceholderInfo(
    titre: 'Cours',
    icone: Icons.school_outlined,
    etape: 8,
    description: 'Cours de crochet, inscriptions et liste d’attente.',
  );
  static const PlaceholderInfo depenses = PlaceholderInfo(
    titre: 'Dépenses',
    icone: Icons.payments_outlined,
    etape: 9,
    description: 'Achats de laine, fournitures, frais de marché...',
  );
  static const PlaceholderInfo statistiques = PlaceholderInfo(
    titre: 'Statistiques',
    icone: Icons.insights_outlined,
    etape: 10,
    description: 'Chiffre d’affaires, meilleures ventes, marge estimée.',
  );
  static const PlaceholderInfo monEntreprise = PlaceholderInfo(
    titre: 'Mon entreprise',
    icone: Icons.storefront_outlined,
    etape: 6,
    description: 'Nom, adresse, SIREN, IBAN et message affichés sur les factures.',
  );
  static const PlaceholderInfo sauvegarde = PlaceholderInfo(
    titre: 'Sauvegarde et export',
    icone: Icons.backup_outlined,
    etape: 11,
    description: 'Sauvegarde, export CSV/JSON et restauration.',
  );

  /// Écran « Bientôt disponible » à afficher pour chaque route non développée.
  static const Map<String, PlaceholderInfo> parRoute = <String, PlaceholderInfo>{
    AppRoutes.produitNouveau: produitNouveau,
    AppRoutes.clientNouveau: clientNouveau,
    AppRoutes.venteNouvelle: nouvelleVente,
    AppRoutes.factures: factures,
    AppRoutes.devis: devis,
    AppRoutes.devisNouveau: devisNouveau,
    AppRoutes.cours: cours,
    AppRoutes.depenses: depenses,
    AppRoutes.statistiques: statistiques,
    AppRoutes.monEntreprise: monEntreprise,
    AppRoutes.sauvegarde: sauvegarde,
  };
}

/// Écran provisoire « Bientôt disponible ».
///
/// `integre: true` quand il est affiché dans un onglet de la barre de navigation
/// (pas de bouton retour).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.info, this.integre = false});

  final PlaceholderInfo info;
  final bool integre;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(info.titre),
        automaticallyImplyLeading: !integre,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(info.icone, size: 44, color: scheme.onSecondaryContainer),
                ),
                const SizedBox(height: 24),
                Text(
                  'Bientôt disponible',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  info.description,
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Chip(label: Text('Prévu à l’étape ${info.etape} sur 12')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
