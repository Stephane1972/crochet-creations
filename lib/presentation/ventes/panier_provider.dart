import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/produit_vues.dart';
import '../../domain/calculs/panier.dart';
import '../../domain/calculs/stock.dart';
import '../../domain/enums.dart';
import '../../domain/erreurs.dart';

/// La vente en cours de préparation : le panier et le client choisi.
/// Immuable : chaque modification crée un nouvel état.
class VenteEnCours {
  const VenteEnCours({this.panier = const Panier(), this.client, this.notes = ''});

  final Panier panier;

  /// `null` = « client de passage » (vente rapide, sans fiche).
  final Client? client;

  /// Note facultative saisie dans le panier.
  final String notes;

  VenteEnCours avecPanier(Panier nouveau) => VenteEnCours(panier: nouveau, client: client, notes: notes);

  VenteEnCours avecClient(Client? nouveau) => VenteEnCours(panier: panier, client: nouveau, notes: notes);

  VenteEnCours avecNotes(String nouvelles) => VenteEnCours(panier: panier, client: client, notes: nouvelles);
}

/// Panier de la vente en cours. Il est conservé tant que l'application est ouverte : on peut
/// passer de l'onglet Vente à une fiche produit puis revenir sans le perdre.
///
/// Les méthodes qui ajoutent ou modifient un article lancent [ErreurMetier] (message en français)
/// si c'est impossible : l'écran l'affiche tel quel et le panier reste inchangé.
class VenteEnCoursNotifier extends Notifier<VenteEnCours> {
  @override
  VenteEnCours build() => const VenteEnCours();

  /// Ajoute un article du catalogue. Un produit à variantes se vend par variante.
  void ajouterProduit(ProduitResume resume, {VarianteProduit? variante, int quantite = 1}) {
    final Produit produit = resume.produit;
    if (!resume.vendable) {
      throw DonneeInvalide('« ${produit.nom} » n’est pas disponible à la vente.');
    }
    if (resume.aDesVariantes && variante == null) {
      throw DonneeInvalide('Choisissez une variante de « ${produit.nom} ».');
    }
    if (variante != null && variante.produitId != produit.id) {
      throw const DonneeInvalide('Cette variante n’appartient pas à ce produit.');
    }

    // Un produit « sur commande » n'a pas de limite de stock.
    final int? stock = suitLeStock(produit.statut) ? (variante?.quantiteStock ?? produit.quantiteStock) : null;
    state = state.avecPanier(
      state.panier.ajouter(
        produitId: produit.id,
        varianteId: variante?.id,
        designation: variante == null ? produit.nom : '${produit.nom} – ${variante.libelle}',
        prixUnitaireCentimes: variante?.prixCentimes ?? produit.prixVenteCentimes,
        quantite: quantite,
        stockDisponible: stock,
      ),
    );
  }

  /// Ajoute une ligne libre (création sur mesure, cours, frais...).
  void ajouterLigneLibre({
    required String designation,
    String? description,
    required NatureLigne nature,
    required int prixUnitaireCentimes,
    int quantite = 1,
  }) {
    state = state.avecPanier(
      state.panier.ajouter(
        designation: designation,
        description: description,
        nature: nature,
        prixUnitaireCentimes: prixUnitaireCentimes,
        quantite: quantite,
      ),
    );
  }

  void changerQuantite(int idLigne, int quantite) {
    state = state.avecPanier(state.panier.avecQuantite(idLigne, quantite));
  }

  void retirer(int idLigne) => state = state.avecPanier(state.panier.sans(idLigne));

  void definirRemise(RemiseType type, int valeur) {
    state = state.avecPanier(state.panier.avecRemise(type, valeur));
  }

  void definirFraisPort(int centimes) => state = state.avecPanier(state.panier.avecFraisPort(centimes));

  /// `null` = client de passage.
  void choisirClient(Client? client) => state = state.avecClient(client);

  void definirNotes(String notes) => state = state.avecNotes(notes);

  /// Repart d'une vente vide (après une validation, ou pour tout abandonner).
  void vider() => state = const VenteEnCours();
}

final venteEnCoursProvider = NotifierProvider<VenteEnCoursNotifier, VenteEnCours>(
  VenteEnCoursNotifier.new,
);
