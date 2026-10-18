import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Logo de l'application (pelote rose + crochet vert), dessiné à partir du SVG.
///
/// `monochrome: true` affiche la version une couleur, prévue pour les factures
/// et les impressions en noir et blanc.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.taille = 96, this.monochrome = false});

  final double taille;
  final bool monochrome;

  static const String cheminCouleur = 'assets/images/logo.svg';
  static const String cheminMonochrome = 'assets/images/logo_mono.svg';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      monochrome ? cheminMonochrome : cheminCouleur,
      width: taille,
      height: taille,
      semanticsLabel: 'Logo Crochet & Créations',
    );
  }
}
