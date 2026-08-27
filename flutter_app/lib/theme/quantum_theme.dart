// =============================================================================
// quantum_theme.dart — Quantum Enterprise RGB Design System (§6 of directive)
//
// Single source of truth for the Quantum Enterprise RGB theme:
//   - QuantumPalette     (color tokens per §6.2)
//   - QuantumTypography  (text styles per §6.3)
//   - QuantumMotion      (curves + durations + transitions per §6.5)
//   - QuantumGradients   (RGB ring + aurora helpers)
//
// Dark-first per §6.1. RGB accents animated sparingly. Glassmorphism in
// quantum_glassmorphism.dart.
// =============================================================================

import 'package:flutter/material.dart';

// Motion vocabulary lives in `quantum_motion.dart` per §6.5; re-exported here
// so existing code that imports `quantum_theme.dart` still sees
// QuantumCurves / QuantumDurations / QuantumTransitions.
export 'quantum_motion.dart';

// =============================================================================
// §6.2  QuantumPalette
// =============================================================================

class QuantumPalette {
  QuantumPalette._(); // never instantiate

  // ---- Backgrounds (dark-first) ----
  /// Deepest layer — the canvas behind everything else.
  static const Color bgDeep = Color(0xFF050510);

  /// Card layer — used by QuantumGlassCard backgrounds.
  static const Color bgSurface = Color(0xFF0A0A1F);

  /// Modal layer — used by QuantumGlassModal / sheets / dialogs.
  static const Color bgElevated = Color(0xFF14142B);

  /// Top layer — tooltips, popovers.
  static const Color bgTooltip = Color(0xFF1F1F3D);

  // ---- Text ----
  static const Color textPrimary = Color(0xFFF5F5FA);
  static const Color textSecondary = Color(0xFFA0A0B8);
  static const Color textTertiary = Color(0xFF6B6B85);
  static const Color textDisabled = Color(0xFF3F3F5F);

  // ---- RGB brand spectrum (animated gradient ring) ----
  /// 9-stop RGB spectrum. Index 0 == index 8 so the loop is seamless when
  /// used as a sweep gradient on a circular button (§6.4.1).
  static const List<Color> rgbSpectrum = [
    Color(0xFFFF0080), // magenta
    Color(0xFFFF00FF), // fuchsia
    Color(0xFF8000FF), // violet
    Color(0xFF0080FF), // azure
    Color(0xFF00FFFF), // cyan
    Color(0xFF00FF80), // spring green
    Color(0xFFFFFF00), // yellow
    Color(0xFFFF8000), // orange
    Color(0xFFFF0080), // back to magenta (loop)
  ];

  /// 3 accents used by static (non-animated) RGB gradient text/borders.
  static const List<Color> rgbAccent3 = [
    Color(0xFFFF0080),
    Color(0xFF00FFFF),
    Color(0xFF8000FF),
  ];

  /// Gold gradient for the verified-user icon + Enterprise value (§6.4.4).
  static const List<Color> goldGradient = [
    Color(0xFFFFD700),
    Color(0xFFFFA500),
    Color(0xFFFFD700),
  ];

  // ---- Status colors (connection states) ----
  static const Color statusConnected = Color(0xFF00FF88);
  static const Color statusConnecting = Color(0xFFFFAA00);
  static const Color statusDisconnected = Color(0xFFFF3366);
  static const Color statusError = Color(0xFFFF0000);
  static const Color statusWarning = Color(0xFFFFCC00);

  // ---- Borders ----
  static const Color borderSubtle = Color(0x14FFFFFF); // 8% white
  static const Color borderStrong = Color(0x29FFFFFF); // 16% white
  static const Color borderFocused = Color(0x4DFFFFFF); // 30% white

  // ---- Shadows ----
  static const Color shadowSoft = Color(0x40000000); // 25% black
  static const Color shadowDeep = Color(0x80000000); // 50% black

  // ---- Light-mode mirrors (§6.6) ----
  /// Light mode is a 1:1 inversion of the dark palette.
  static const Color lightBgDeep = Color(0xFFFFFFFF);
  static const Color lightBgSurface = Color(0xFFF7F7FB);
  static const Color lightBgElevated = Color(0xFFFFFFFF);
  static const Color lightBgTooltip = Color(0xFFFFFFFF);

  static const Color lightTextPrimary = Color(0xFF0A0A1F);
  static const Color lightTextSecondary = Color(0xFF4A4A66);
  static const Color lightTextTertiary = Color(0xFF7A7A95);
  static const Color lightTextDisabled = Color(0xFFBFBFD0);

  static const Color lightBorderSubtle = Color(0x14000000); // 8% black
  static const Color lightBorderStrong = Color(0x29000000); // 16% black
  static const Color lightBorderFocused = Color(0x4D000000); // 30% black

  static const Color lightShadowSoft = Color(0x14000000); // 8% black (subtle)
  static const Color lightShadowDeep = Color(0x29000000); // 16% black

  // ---- Spacing (§6.1 core principle #7 — 4 px base grid) ----
  static const double spaceXxs = 4;
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 20;
  static const double spaceXl = 24;
  static const double spaceSection = 32;

  // ---- Radii (§6.1 core principle #8) ----
  static const double radiusCard = 20;
  static const double radiusButton = 14;
  static const double radiusInput = 12;
  static const double radiusModal = 24;
  static const double radiusPill = 999;
}

// =============================================================================
// §6.3  QuantumTypography
// =============================================================================

class QuantumTypography {
  QuantumTypography._();

  // ---- Latin (Inter) ----
  static const TextStyle display1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02,
    height: 1.2,
  );
  static const TextStyle display2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02,
    height: 1.25,
  );
  static const TextStyle display3 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.01,
    height: 1.3,
  );
  static const TextStyle title1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01,
    height: 1.3,
  );
  static const TextStyle title2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01,
    height: 1.35,
  );
  static const TextStyle title3 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const TextStyle body1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle body2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.04,
    height: 1.4,
  );
  static const TextStyle mono = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  // ---- Persian (Vazirmatn) — mirror every size ----
  static const TextStyle display1Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );
  static const TextStyle display2Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );
  static const TextStyle display3Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );
  static const TextStyle title1Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );
  static const TextStyle title2Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );
  static const TextStyle title3Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );
  static const TextStyle body1Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.7,
  );
  static const TextStyle body2Fa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.7,
  );
  static const TextStyle labelFa = TextStyle(
    fontFamily: 'Vazirmatn',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  /// Picks the right text style for the current locale.
  /// Pass `fa` to get the Vazirmatn variant.
  static TextStyle display1For(String languageCode) =>
      languageCode == 'fa' ? display1Fa : display1;
  static TextStyle display2For(String languageCode) =>
      languageCode == 'fa' ? display2Fa : display2;
  static TextStyle display3For(String languageCode) =>
      languageCode == 'fa' ? display3Fa : display3;
  static TextStyle body1For(String languageCode) =>
      languageCode == 'fa' ? body1Fa : body1;
  static TextStyle body2For(String languageCode) =>
      languageCode == 'fa' ? body2Fa : body2;

  /// Persian numeral map for §6.7 countdown timer.
  static const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  /// Converts ASCII digits in [input] to Persian digits.
  static String toPersianNumerals(String input) {
    return String.fromCharCodes(
      input.codeUnits.map((u) {
        if (u >= 0x30 && u <= 0x39) {
          return _persianDigits.codeUnitAt(u - 0x30);
        }
        return u;
      }),
    );
  }
}

// =============================================================================
// §6.2 + §6.4 + §6.10  QuantumGradients (helpers)
//
// NOTE: QuantumCurves / QuantumDurations / QuantumTransitions now live in
// `quantum_motion.dart` per §6.5 and are re-exported from this file via
// `export 'quantum_motion.dart';` above.
// =============================================================================

class QuantumGradients {
  QuantumGradients._();

  /// The signature RGB ring gradient on the Connect Button (§6.4.1).
  ///
  /// 9-stop linear gradient over [QuantumPalette.rgbSpectrum]. The widget
  /// that uses this gradient (typically a [CustomPainter]) rotates it via an
  /// [AnimationController] so the spectrum sweeps around the circle.
  ///
  /// Pass [progress] = `animationController.value` to rotate the alignment
  /// vector.
  static LinearGradient animatedRgbRing({double progress = 0.0}) {
    return LinearGradient(
      begin: Alignment(-1 + progress * 2, -1),
      end: Alignment(1 - progress * 2, 1),
      colors: QuantumPalette.rgbSpectrum,
      stops: List<double>.generate(
        QuantumPalette.rgbSpectrum.length,
        (i) => i / (QuantumPalette.rgbSpectrum.length - 1),
      ),
    );
  }

  /// Aurora background — a [RadialGradient] using the RGB accent3 colors with
  /// low opacity, drawn behind everything else (§6.10). Used by
  /// [QuantumAuroraBackground] (see quantum_components.dart).
  static RadialGradient auroraBackground() {
    return const RadialGradient(
      center: Alignment(0, -0.3),
      radius: 1.4,
      colors: [
        Color(0x22FF0080), // magenta 13%
        Color(0x1A00FFFF), // cyan 10%
        Color(0x228000FF), // violet 13%
        Color(0x00050510), // bgDeep 0%
      ],
      stops: [0.0, 0.35, 0.7, 1.0],
    );
  }

  /// Horizontal red→green→blue banner for the Enterprise License Panel
  /// (§6.4.4 — the 4 px banner at top of the panel).
  static const LinearGradient enterpriseBanner = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFFF0080), // magenta-red
      Color(0xFF00FF88), // green
      Color(0xFF0080FF), // blue
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Gold gradient for the verified-user icon (§6.4.4).
  static const LinearGradient goldIcon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: QuantumPalette.goldGradient,
  );

  /// RGB gradient used for the on-state of [QuantumToggle] (§6.4.5 custom
  /// switch — 52×32 pill).
  static const LinearGradient toggleOn = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: QuantumPalette.rgbAccent3,
  );
}
