import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Logo de l'application (la fillette aux pelotes), affiché dans un carré aux coins arrondis.
///
/// L'image vient de `assets/images/logo_application.png` ; c'est aussi elle qui sert d'icône de lancement
/// (voir `tool/generate_icons.py`). Le logo des factures et des devis est un autre fichier, voir `ressources_pdf.dart`.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.taille = 96});

  final double taille;

  static const String chemin = 'assets/images/logo_application.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Logo ${AppConstants.nomApplication}',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(taille * 0.22),
          child: Image.asset(
            chemin,
            width: taille,
            height: taille,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
