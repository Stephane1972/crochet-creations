import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../clients/client_fiche_screen.dart';
import '../clients/client_form_screen.dart';
import '../common/placeholder_screen.dart';
import '../produits/produit_fiche_screen.dart';
import '../produits/produit_form_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/main_shell.dart';
import '../splash/splash_screen.dart';

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
