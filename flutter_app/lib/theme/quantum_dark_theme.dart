// =============================================================================
// quantum_dark_theme.dart — Quantum Enterprise RGB dark theme (default)
//
// Per §6.1: dark-first. Default theme returned by `MaterialApp.theme:`
// when `ThemeMode.system` resolves to dark.
//
// All overrides come from `quantum_theme.dart` (QuantumPalette +
// QuantumTypography). Material 3 is enabled and tuned.
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'quantum_theme.dart';

/// The Quantum Enterprise RGB dark theme.
///
/// Returned by `MaterialApp.darkTheme:`. Honors §6.10 forbidden patterns:
///   - `useMaterial3: true` (no Material 2 styling)
///   - `pageTransitionsTheme` customized for iOS-like push on all platforms
///   - `splashFactory` tuned to match the RGB accent system
///   - System chrome (status bar / nav bar) defaults are set via
///     [QuantumSystemChrome] helper below — call it from `main()` once.
ThemeData quantumDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: QuantumPalette.bgDeep,
    canvasColor: QuantumPalette.bgDeep,
    cardColor: QuantumPalette.bgSurface,
    dividerColor: QuantumPalette.borderSubtle,
    hintColor: QuantumPalette.textTertiary,
    shadowColor: QuantumPalette.shadowSoft,

    // Splash / highlight — subtle on dark glassmorphic surfaces.
    splashFactory: InkRipple.splashFactory,
    splashColor: QuantumPalette.rgbAccent3[0].withValues(alpha: 0.15),
    highlightColor: QuantumPalette.borderFocused,

    // Color scheme — every accent picked from QuantumPalette.
    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: Color(0xFFFF0080), // magenta — brand RGB accent
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF14142B),
      onPrimaryContainer: Color(0xFFF5F5FA),
      secondary: Color(0xFF00FFFF), // cyan
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF1F1F3D),
      onSecondaryContainer: Color(0xFFF5F5FA),
      tertiary: Color(0xFF8000FF), // violet
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFF1F1F3D),
      onTertiaryContainer: Color(0xFFF5F5FA),
      error: QuantumPalette.statusError,
      onError: Colors.white,
      errorContainer: Color(0xFF3D0000),
      onErrorContainer: Color(0xFFFFB3B3),
      surface: QuantumPalette.bgSurface,
      onSurface: QuantumPalette.textPrimary,
      surfaceContainerHighest: QuantumPalette.bgElevated,
      onSurfaceVariant: QuantumPalette.textSecondary,
      outline: QuantumPalette.borderSubtle,
      outlineVariant: QuantumPalette.borderStrong,
      shadow: QuantumPalette.shadowSoft,
      scrim: QuantumPalette.shadowDeep,
      inverseSurface: QuantumPalette.bgTooltip,
      onInverseSurface: QuantumPalette.textPrimary,
      inversePrimary: Color(0xFFFF0080),
    ),

    // Typography — text styles from QuantumTypography (Inter family).
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

    // App bar — glassmorphic, no default styling per §6.10.
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: QuantumPalette.textPrimary,
      ),
      iconTheme: IconThemeData(color: QuantumPalette.textPrimary, size: 24),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: QuantumPalette.bgDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),

    // Cards — glassmorphic via QuantumGlassCard, but keep default card
    // style tuned for non-glassmorphic fallback usage.
    cardTheme: CardThemeData(
      color: QuantumPalette.bgSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusCard),
        side: const BorderSide(color: QuantumPalette.borderSubtle, width: 1),
      ),
    ),

    // Buttons — pill-shaped primaries, 14 px radius secondaries.
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
        backgroundColor: QuantumPalette.bgElevated,
        foregroundColor: QuantumPalette.textPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
        ),
        side: const BorderSide(color: QuantumPalette.borderStrong, width: 1),
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
        foregroundColor: QuantumPalette.textPrimary,
        side: const BorderSide(color: QuantumPalette.borderStrong, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: QuantumPalette.textPrimary,
        highlightColor: QuantumPalette.borderFocused,
      ),
    ),

    // Inputs — 12 px radius, glassmorphic bg.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: QuantumPalette.bgSurface,
      hintStyle: const TextStyle(color: QuantumPalette.textTertiary),
      labelStyle: const TextStyle(color: QuantumPalette.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.borderFocused, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
        borderSide: const BorderSide(color: QuantumPalette.statusError),
      ),
    ),

    // Sliders, switches, progress indicators — all custom-painted per
    // §6.10 (QuantumToggle, QuantumSpinner). These are fallbacks only.
    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xFFFF0080),
      inactiveTrackColor: QuantumPalette.borderStrong,
      thumbColor: Colors.white,
      overlayColor: const Color(0xFFFF0080).withValues(alpha: 0.2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFFFF0080);
        }
        return QuantumPalette.bgElevated;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return QuantumPalette.borderSubtle;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: const Color(0xFFFF0080),
      linearTrackColor: QuantumPalette.borderStrong,
      circularTrackColor: QuantumPalette.borderSubtle,
    ),

    // SnackBar — replaced by QuantumToast per §6.10, but configure as
    // fallback so any code that still uses SnackBar doesn't render with
    // the default Material green.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: QuantumPalette.bgElevated,
      contentTextStyle: const TextStyle(
        color: QuantumPalette.textPrimary,
        fontFamily: 'Inter',
        fontSize: 14,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusCard),
      ),
    ),

    // Dialogs — replaced by QuantumDialog per §6.10, but configure as
    // fallback.
    dialogTheme: DialogThemeData(
      backgroundColor: QuantumPalette.bgElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusModal),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: QuantumPalette.textPrimary,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: QuantumPalette.textSecondary,
      ),
    ),

    // Bottom sheet — used by QuantumAIAssistantSheet.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: QuantumPalette.bgElevated,
      modalBackgroundColor: QuantumPalette.bgElevated,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(QuantumPalette.radiusModal),
        ),
      ),
    ),

    // List tiles — used by QuantumSettingsRow.
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: QuantumPalette.textSecondary,
      textColor: QuantumPalette.textPrimary,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: QuantumPalette.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        color: QuantumPalette.textTertiary,
      ),
    ),

    // Page transitions — iOS-like push on all platforms.
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

    // Dividers
    dividerTheme: DividerThemeData(
      color: QuantumPalette.borderSubtle,
      thickness: 1,
      space: 1,
    ),

    // Chip theme — used by QuantumCoreSwitcher fallback + suggested-prompt
    // chips on AI Assistant.
    chipTheme: ChipThemeData(
      backgroundColor: QuantumPalette.bgSurface,
      selectedColor: const Color(0xFFFF0080),
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: QuantumPalette.textPrimary,
      ),
      side: const BorderSide(color: QuantumPalette.borderSubtle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
      ),
    ),
  );
}

/// Helper to apply the Quantum system chrome (status bar + nav bar).
/// Call once from `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
void quantumSystemChrome() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: QuantumPalette.bgDeep,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  // Lock to portrait by default — the dashboard + assistant screens are
  // portrait-first. The user can opt-out per-screen.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
}
