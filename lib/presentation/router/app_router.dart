import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../clients/client_fiche_screen.dart';
import '../clients/client_form_screen.dart';
import '../common/placeholder_screen.dart';
import '../devis/devis_conversion_screen.dart';
import '../devis/devis_detail_screen.dart';
import '../devis/devis_form_screen.dart';
import '../devis/devis_screen.dart';
import '../entreprise/mon_entreprise_screen.dart';
import '../factures/facture_detail_screen.dart';
import '../factures/factures_screen.dart';
import '../produits/produit_fiche_screen.dart';
import '../produits/produit_form_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/main_shell.dart';
import '../splash/splash_screen.dart';
import '../ventes/panier_screen.dart';
import '../ventes/vente_confirmation_screen.dart';

/// Associe chaque nom de route (voir AppRoutes) à son écran.
///
/// Les routes dont l'écran n'est pas encore développé affichent l'écran
/// « Bientôt disponible » (voir EcransAVenir). Quand une étape livre un écran,
/// on retire la route de EcransAVenir.parRoute et on ajoute un `case` ici.
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _page(settings, const SplashScreen());
      case AppRoutes.accueil:
        return _fondu(settings, const MainShell());
      case AppRoutes.reglages:
        return _page(settings, const SettingsScreen());
      case AppRoutes.monEntreprise:
        return _page(settings, const MonEntrepriseScreen());
      case AppRoutes.factures:
        return _page(settings, const FacturesScreen());
      case AppRoutes.factureDetail:
        final int? idFacture = _identifiant(settings);
        return _page(
          settings,
          idFacture == null ? const _PageIntrouvable() : FactureDetailScreen(factureId: idFacture),
        );
      case AppRoutes.devis:
        return _page(settings, const DevisScreen());
      case AppRoutes.devisNouveau:
        return _page(settings, const DevisFormScreen());
      case AppRoutes.devisDetail:
        final int? idDevis = _identifiant(settings);
        return _page(
          settings,
          idDevis == null ? const _PageIntrouvable() : DevisDetailScreen(devisId: idDevis),
        );
      case AppRoutes.devisModifier:
        final int? idDevisModif = _identifiant(settings);
        return _page(
          settings,
          idDevisModif == null ? const _PageIntrouvable() : DevisFormScreen(devisId: idDevisModif),
        );
      case AppRoutes.devisConversion:
        final int? idDevisConv = _identifiant(settings);
        return _page(
          settings,
          idDevisConv == null ? const _PageIntrouvable() : DevisConversionScreen(devisId: idDevisConv),
        );
      case AppRoutes.produitNouveau:
        return _page(settings, const ProduitFormScreen());
      case AppRoutes.produitFiche:
        final int? idFiche = _identifiant(settings);
        return _page(
          settings,
          idFiche == null ? const _PageIntrouvable() : ProduitFicheScreen(produitId: idFiche),
        );
      case AppRoutes.produitModifier:
        final int? idModif = _identifiant(settings);
        return _page(
          settings,
          idModif == null ? const _PageIntrouvable() : ProduitFormScreen(produitId: idModif),
        );
      case AppRoutes.clientNouveau:
        return _page(settings, const ClientFormScreen());
      case AppRoutes.clientFiche:
        final int? idClient = _identifiant(settings);
        return _page(
          settings,
          idClient == null ? const _PageIntrouvable() : ClientFicheScreen(clientId: idClient),
        );
      case AppRoutes.panier:
        return _page(settings, const PanierScreen());
      case AppRoutes.venteConfirmation:
        final int? idVente = _identifiant(settings);
        return _page(
          settings,
          idVente == null ? const _PageIntrouvable() : VenteConfirmationScreen(venteId: idVente),
        );
      case AppRoutes.clientModifier:
        final int? idClientModif = _identifiant(settings);
        return _page(
          settings,
          idClientModif == null ? const _PageIntrouvable() : ClientFormScreen(clientId: idClientModif),
        );
    }

    final PlaceholderInfo? info = EcransAVenir.parRoute[settings.name];
    if (info != null) {
      return _page(settings, PlaceholderScreen(info: info));
    }
    return _page(settings, const _PageIntrouvable());
  }

  /// Identifiant passé en `arguments` à la route (un entier), `null` s'il manque.
  static int? _identifiant(RouteSettings settings) {
    final Object? arguments = settings.arguments;
    return arguments is int ? arguments : null;
  }

  static Route<dynamic> _page(RouteSettings settings, Widget ecran) {
    return MaterialPageRoute<void>(settings: settings, builder: (BuildContext context) => ecran);
  }

  /// Transition en fondu (splash → accueil).
  static Route<dynamic> _fondu(RouteSettings settings, Widget ecran) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaire) {
        return ecran;
      },
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaire,
        Widget child,
      ) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}

class _PageIntrouvable extends StatelessWidget {
  const _PageIntrouvable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Cette page n’existe pas.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.accueil,
                  (Route<dynamic> route) => false,
                ),
                child: const Text('Retour à l’accueil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
