import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Thèmes Material 3 de l'application : jour et nuit.
///
/// Le mode « automatique » est géré par `MaterialApp.themeMode`
/// (voir theme_mode_provider.dart).
abstract final class AppTheme {
  /// Police des titres. Le texte courant garde la police système (Roboto sur Android).
  static const String policeTitres = 'Poppins';

  // ---------------------------------------------------------------------------
  // Palettes
  // ---------------------------------------------------------------------------

  static const ColorScheme schemaJour = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.saugeFonce,
    onPrimary: AppColors.encreSurSauge,
    primaryContainer: AppColors.saugeTresClair,
    onPrimaryContainer: AppColors.saugeTresSombre,
    secondary: AppColors.roseSoutenu,
    onSecondary: AppColors.texteJour,
    secondaryContainer: AppColors.rosePastel,
    onSecondaryContainer: AppColors.prune,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: AppColors.fondJour,
    onSurface: AppColors.texteJour,
    onSurfaceVariant: AppColors.texteSecondaireJour,
    outline: AppColors.contourJour,
    outlineVariant: AppColors.filetJour,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.texteJour,
    onInverseSurface: AppColors.fondJour,
    inversePrimary: AppColors.vertClair,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white, // cartes
    surfaceContainer: AppColors.barreNavJour, // barre de navigation
    surfaceContainerHigh: AppColors.surfaceHauteJour,
    surfaceContainerHighest: AppColors.surfaceTresHauteJour,
  );

  static const ColorScheme schemaNuit = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.vertClair,
    onPrimary: AppColors.encreSurVertClair,
    primaryContainer: AppColors.vertSombreNuit,
    onPrimaryContainer: AppColors.vertPaleNuit,
    secondary: AppColors.roseClair,
    onSecondary: AppColors.encreSurRoseClair,
    secondaryContainer: AppColors.pruneNuit,
    onSecondaryContainer: AppColors.rosePastel,
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: AppColors.fondNuit,
    onSurface: AppColors.texteNuit,
    onSurfaceVariant: AppColors.texteSecondaireNuit,
    outline: AppColors.contourNuit,
    outlineVariant: AppColors.filetNuit,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.texteNuit,
    onInverseSurface: AppColors.fondNuit,
    inversePrimary: AppColors.saugeFonce,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: AppColors.surfaceBasseNuit,
    surfaceContainerLow: AppColors.carteNuit, // cartes
    surfaceContainer: AppColors.barreNavNuit, // barre de navigation
    surfaceContainerHigh: AppColors.surfaceHauteNuit,
    surfaceContainerHighest: AppColors.surfaceTresHauteNuit,
  );

  static final ThemeData light = _construire(schemaJour);
  static final ThemeData dark = _construire(schemaNuit);

  // ---------------------------------------------------------------------------
  // Construction commune
  // ---------------------------------------------------------------------------

  static ThemeData _construire(ColorScheme scheme) {
    final bool clair = scheme.brightness == Brightness.light;
    final TextTheme textTheme = _textTheme(scheme);

    // Sur fond clair, le vert sauge seul manque de contraste pour du texte :
    // on utilise la teinte « saugeTexte » pour les boutons texte et les liens.
    final Color accentTexte = clair ? AppColors.saugeTexte : scheme.primary;

    const BorderRadius rayon16 = BorderRadius.all(Radius.circular(16));
    const BorderRadius rayon20 = BorderRadius.all(Radius.circular(20));
    const BorderRadius rayon28 = BorderRadius.all(Radius.circular(28));

    OutlineInputBorder bordure(Color couleur, [double epaisseur = 1]) {
      return OutlineInputBorder(
        borderRadius: rayon16,
        borderSide: BorderSide(color: couleur, width: epaisseur),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      // Cartes : coins arrondis, ombre légère en mode jour, simple liseré en mode nuit.
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        elevation: clair ? 2 : 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: rayon20,
          side: clair ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
        ),
      ),
      // Boutons : arrondis (pilule) et assez grands pour être touchés facilement.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          foregroundColor: accentTexte,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          foregroundColor: accentTexte,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          foregroundColor: accentTexte,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          selectedForegroundColor: scheme.onSecondaryContainer,
          selectedBackgroundColor: scheme.secondaryContainer,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLow,
        labelStyle: textTheme.labelMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        border: bordure(scheme.outlineVariant),
        enabledBorder: bordure(scheme.outlineVariant),
        focusedBorder: bordure(scheme.primary, 2),
        errorBorder: bordure(scheme.error),
        focusedErrorBorder: bordure(scheme.error, 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((Set<WidgetState> etats) {
          final bool selectionne = etats.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
            color: selectionne ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> etats) {
          final bool selectionne = etats.contains(WidgetState.selected);
          return IconThemeData(
            size: 26,
            color: selectionne ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: const RoundedRectangleBorder(borderRadius: rayon16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: rayon28),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  /// Titres en Poppins (semi-gras), texte courant en police système.
  static TextTheme _textTheme(ColorScheme scheme) {
    final TextTheme base = scheme.brightness == Brightness.light
        ? Typography.material2021().black
        : Typography.material2021().white;
    final TextTheme colore = base.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    TextStyle? titre(TextStyle? style, [FontWeight poids = FontWeight.w600]) {
      return style?.copyWith(fontFamily: policeTitres, fontWeight: poids, letterSpacing: 0);
    }

    return colore.copyWith(
      displayLarge: titre(colore.displayLarge),
      displayMedium: titre(colore.displayMedium),
      displaySmall: titre(colore.displaySmall),
      headlineLarge: titre(colore.headlineLarge),
      headlineMedium: titre(colore.headlineMedium),
      headlineSmall: titre(colore.headlineSmall),
      titleLarge: titre(colore.titleLarge),
      titleMedium: titre(colore.titleMedium),
      titleSmall: titre(colore.titleSmall),
      // Libellés de boutons : un cran plus grands pour rester lisibles.
      labelLarge: titre(colore.labelLarge)?.copyWith(fontSize: 15),
    );
  }
}
