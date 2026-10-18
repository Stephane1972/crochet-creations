import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../common/placeholder_screen.dart';
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
    }

    final PlaceholderInfo? info = EcransAVenir.parRoute[settings.name];
    if (info != null) {
      return _page(settings, PlaceholderScreen(info: info));
    }
    return _page(settings, const _PageIntrouvable());
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
