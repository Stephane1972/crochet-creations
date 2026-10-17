import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/app_logo.dart';

/// Écran de démarrage : logo animé, puis passage automatique à l'accueil.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Durée d'affichage avant de passer à l'accueil.
  static const Duration duree = Duration(milliseconds: 1800);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controleur;
  late final Animation<double> _opacite;
  late final Animation<double> _echelle;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _controleur = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacite = CurvedAnimation(parent: _controleur, curve: Curves.easeOut);
    _echelle = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _controleur, curve: Curves.easeOutBack),
    );
    _controleur.forward();
    _minuteur = Timer(SplashScreen.duree, _continuer);
  }

  void _continuer() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.accueil);
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              scheme.secondaryContainer.withValues(alpha: 0.55),
              scheme.surface,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _opacite,
            child: ScaleTransition(
              scale: _echelle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AppLogo(taille: 168),
                    const SizedBox(height: 24),
                    Text(
                      AppConstants.nomApplication,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.accroche,
                      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
