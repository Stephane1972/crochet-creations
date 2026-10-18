import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adapte les icônes de la barre d'état (heure, batterie...) au thème :
/// foncées sur fond clair, claires sur fond sombre.
class AdaptiveSystemOverlay extends StatelessWidget {
  const AdaptiveSystemOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool sombre = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: sombre ? Brightness.light : Brightness.dark,
        statusBarBrightness: sombre ? Brightness.dark : Brightness.light,
      ),
      child: child,
    );
  }
}
