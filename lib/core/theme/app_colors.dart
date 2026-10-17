import 'package:flutter/material.dart';

/// Palette « Crochet & Créations ».
///
/// Les 11 premières couleurs viennent du cahier des charges.
/// Les teintes « dérivées » complètent la palette pour obtenir un contraste
/// suffisant (norme WCAG AA, 4,5:1) sur les textes : voir test/core/theme/app_theme_test.dart.
abstract final class AppColors {
  // --- Charte (imposée) ---
  static const Color rosePastel = Color(0xFFF6C9D4);
  static const Color roseSoutenu = Color(0xFFD98CA0);
  static const Color sauge = Color(0xFF7FA98C);
  static const Color saugeFonce = Color(0xFF6E9B7F);
  static const Color fondJour = Color(0xFFFBF7F4);
  static const Color texteJour = Color(0xFF33302E);

  static const Color fondNuit = Color(0xFF141715);
  static const Color carteNuit = Color(0xFF1F2421);
  static const Color texteNuit = Color(0xFFF3EFEA);
  static const Color vertClair = Color(0xFFA7C4B5);
  static const Color roseClair = Color(0xFFE8A9B8);

  // --- Teintes dérivées : mode jour ---
  /// Texte posé sur le vert sauge foncé (le blanc n'atteint que 3,1:1 sur ce vert).
  static const Color encreSurSauge = Color(0xFF1B2620);

  /// Vert profond pour les textes et liens sur fond clair (5,1:1 sur le fond crème).
  static const Color saugeTexte = Color(0xFF4A7359);
  static const Color saugeTresClair = Color(0xFFDCEBE2);
  static const Color saugeTresSombre = Color(0xFF1F3A2B);
  static const Color prune = Color(0xFF5A2D3B);
  static const Color texteSecondaireJour = Color(0xFF5E5853);
  static const Color contourJour = Color(0xFF8A827C);
  static const Color filetJour = Color(0xFFE5DCD6);
  static const Color barreNavJour = Color(0xFFF5EFEA);
  static const Color surfaceHauteJour = Color(0xFFEFE8E2);
  static const Color surfaceTresHauteJour = Color(0xFFE9E1DA);

  // --- Teintes dérivées : mode nuit ---
  static const Color encreSurVertClair = Color(0xFF12241A);
  static const Color vertSombreNuit = Color(0xFF2B4538);
  static const Color vertPaleNuit = Color(0xFFD3E6DA);
  static const Color encreSurRoseClair = Color(0xFF3A1A24);
  static const Color pruneNuit = Color(0xFF55303C);
  static const Color texteSecondaireNuit = Color(0xFFC4BDB6);
  static const Color contourNuit = Color(0xFF8E8780);
  static const Color filetNuit = Color(0xFF3A413D);
  static const Color barreNavNuit = Color(0xFF1B201D);
  static const Color surfaceBasseNuit = Color(0xFF101311);
  static const Color surfaceHauteNuit = Color(0xFF262C28);
  static const Color surfaceTresHauteNuit = Color(0xFF2D3430);
}
