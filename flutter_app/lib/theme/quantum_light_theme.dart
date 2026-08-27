// =============================================================================
// quantum_light_theme.dart — Quantum Enterprise RGB light theme (mirror)
//
// Per §6.6: light mode is NOT a separate design. It is a 1:1 inversion of
// the dark palette. RGB accents stay the same. Glassmorphism becomes subtle
// shadow + 1 px gray border instead of backdrop blur (because light mode +
// backdrop blur looks muddy).
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'quantum_theme.dart';

/// The Quantum Enterprise RGB light theme (mirror of the dark theme).
ThemeData quantumLightTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: QuantumPalette.lightBgDeep,
    canvasColor: QuantumPalette.lightBgDeep,
    cardColor: QuantumPalette.lightBgSurface,
    dividerColor: QuantumPalette.lightBorderSubtle,
    hintColor: QuantumPalette.lightTextTertiary,
    shadowColor: QuantumPalette.lightShadowSoft,

    splashFactory: InkRipple.splashFactory,
    splashColor: QuantumPalette.rgbAccent3[0].withValues(alpha: 0.15),
    highlightColor: QuantumPalette.lightBorderFocused,

    colorScheme: const ColorScheme.light(
      brightness: Brightness.light,
      primary: Color(0xFFFF0080), // magenta — brand RGB accent (same in both themes)
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFFFFF),
      onPrimaryContainer: Color(0xFF0A0A1F),
      secondary: Color(0xFF0080FF), // azure (slightly darker for contrast on white)
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE5F7FF),
      onSecondaryContainer: Color(0xFF0A1F3D),
      tertiary: Color(0xFF8000FF), // violet
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF0E5FF),
      onTertiaryContainer: Color(0xFF1A0A3D),
      error: QuantumPalette.statusError,
      onError: Colors.white,
      errorContainer: Color(0xFFFFE5E5),
      onErrorContainer: Color(0xFF7F0000),
      surface: QuantumPalette.lightBgSurface,
      onSurface: QuantumPalette.lightTextPrimary,
      surfaceContainerHighest: QuantumPalette.lightBgElevated,
      onSurfaceVariant: QuantumPalette.lightTextSecondary,
      outline: QuantumPalette.lightBorderSubtle,
      outlineVariant: QuantumPalette.lightBorderStrong,
      shadow: QuantumPalette.lightShadowSoft,
      scrim: QuantumPalette.lightShadowDeep,
      inverseSurface: QuantumPalette.lightBgTooltip,
      onInverseSurface: QuantumPalette.lightTextPrimary,
      inversePrimary: Color(0xFFFF0080),
    ),

    // (fontFamily is NOT a valid ThemeData.copyWith parameter; the family is
    // applied per-style inside QuantumTypography text styles.)
    textTheme: const TextTheme(
      displayLarge: QuantumTypography.display1,
      displayMedium: QuantumTypography.display2,
      displaySmall: QuantumTypography.display3,
      headlineLarge: QuantumTypography.title1,
      headlineMedium: QuantumTypography.title2,
      headlineSmall: QuantumTypography.title3,
      titleLarge: QuantumTypography.title2,
      titleMedium: QuantumTypography.title3,
      titleSmall: QuantumTypography.body1,
      bodyLarge: QuantumTypography.body1,
      bodyMedium: QuantumTypography.body2,
      bodySmall: QuantumTypography.label,
      labelLarge: QuantumTypography.body1,
      labelMedium: QuantumTypography.body2,
      labelSmall: QuantumTypography.label,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: QuantumPalette.lightTextPrimary,
      ),
      iconTheme: IconThemeData(color: QuantumPalette.lightTextPrimary, size: 24),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: QuantumPalette.lightBgDeep,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),

    cardTheme: CardThemeData(
      color: QuantumPalette.lightBgSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusCard),
        side: const BorderSide(color: QuantumPalette.lightBorderSubtle, width: 1),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFF0080),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: QuantumPalette.lightBgElevated,
        foregroundColor: QuantumPalette.lightTextPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
        ),
        side: const BorderSide(color: QuantumPalette.lightBorderStrong, width: 1),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFFF0080),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: QuantumPalette.lightTextPrimary,
        side: const BorderSide(color: QuantumPalette.lightBorderStrong, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: QuantumPalette.lightTextPrimary,
        highlightColor: QuantumPalette.lightBorderFocused,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: QuantumPalette.lightBgSurface,
      hintStyle: const TextStyle(color: QuantumPalette.lightTextTertiary),
      labelStyle: const TextStyle(color: QuantumPalette.lightTextSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.lightBorderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.lightBorderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.lightBorderFocused, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.statusError),
      ),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xFFFF0080),
      inactiveTrackColor: QuantumPalette.lightBorderStrong,
      thumbColor: Colors.black87,
      overlayColor: const Color(0xFFFF0080).withValues(alpha: 0.2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFFFF0080);
        }
        return QuantumPalette.lightBgElevated;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return QuantumPalette.lightBorderSubtle;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: const Color(0xFFFF0080),
      linearTrackColor: QuantumPalette.lightBorderStrong,
      circularTrackColor: QuantumPalette.lightBorderSubtle,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: QuantumPalette.lightBgElevated,
      contentTextStyle: const TextStyle(
        color: QuantumPalette.lightTextPrimary,
        fontFamily: 'Inter',
        fontSize: 14,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusCard),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: QuantumPalette.lightBgElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusModal),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: QuantumPalette.lightTextPrimary,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: QuantumPalette.lightTextSecondary,
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: QuantumPalette.lightBgElevated,
      modalBackgroundColor: QuantumPalette.lightBgElevated,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(QuantumPalette.radiusModal),
        ),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: QuantumPalette.lightTextSecondary,
      textColor: QuantumPalette.lightTextPrimary,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: QuantumPalette.lightTextPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        color: QuantumPalette.lightTextTertiary,
      ),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),

    dividerTheme: DividerThemeData(
      color: QuantumPalette.lightBorderSubtle,
      thickness: 1,
      space: 1,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: QuantumPalette.lightBgSurface,
      selectedColor: const Color(0xFFFF0080),
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: QuantumPalette.lightTextPrimary,
      ),
      side: const BorderSide(color: QuantumPalette.lightBorderSubtle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
      ),
    ),
  );
}
