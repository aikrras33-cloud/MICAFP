// =============================================================================
// quantum_motion.dart — Quantum Enterprise RGB motion system (§6.5)
//
// Single source of truth for the Quantum Enterprise motion vocabulary:
//   - QuantumCurves     (cubic easing curves per §6.5)
//   - QuantumDurations   (4-step duration scale per §6.5)
//   - QuantumTransitions (pre-built Tween+CurvedAnimation helpers)
//
// Per §6.1 core principle #5: every animation uses an AnimationController +
// vsync — no implicit setState animations. Per §6.8 the heavy painters
// (sparkline, aurora, spinner) wrap themselves in RepaintBoundary.
//
// Per §6.5 motion budget:
//   - 200 ms  — micro-interactions (toggles, chip taps)
//   - 350 ms  — state transitions (status changes, sheet open)
//   - 600 ms  — page transitions (slow)
//   - 1200 ms — hero animations (very slow)
//
// QuantumGradients.animatedRgbRing uses these to drive the 8 s sweep around
// the QuantumConnectButton. Re-exported from quantum_theme.dart for backward
// compatibility.
// =============================================================================

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

// =============================================================================
// §6.5  QuantumCurves
// =============================================================================

class QuantumCurves {
  QuantumCurves._();

  /// Per the directive: `Cubic(0.05, 0.7, 0.1, 1.0)` — a smooth, slightly
  /// emphasized ease-in-out for state changes (200-400 ms).
  ///
  /// Inspiration: Apple Vision Pro "spring" feel + Linear.app emphasis curve.
  /// Specifically tuned to feel "expensive" — quick start, gentle settle.
  static const Cubic easeInOutCubicEmphasized = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Spring curve for chip taps (§6.4.3 — QuantumCoreSwitcher).
  /// Apple-style overshoot for tactile, "physical" feedback on tap.
  static const Cubic spring = Cubic(0.34, 1.56, 0.64, 1.0);

  /// Standard linear — only for spinner rotation; everything else is eased.
  /// Used by QuantumSpinner + QuantumAuroraBackground drift.
  static const Cubic linear = Cubic(1.0, 1.0, 1.0, 1.0);

  /// Decelerate (for incoming elements — sheet open, dialog appear).
  static const Cubic decelerate = Cubic(0.0, 0.0, 0.2, 1.0);

  /// Accelerate (for outgoing elements — sheet close, dialog dismiss).
  static const Cubic accelerate = Cubic(0.4, 0.0, 1.0, 1.0);
}

// =============================================================================
// §6.5  QuantumDurations
// =============================================================================

class QuantumDurations {
  QuantumDurations._();

  /// Micro-interactions (toggles, chip taps, scale-on-press).
  static const Duration fast = Duration(milliseconds: 200);

  /// State transitions (status changes, sheet open, toast slide-in).
  static const Duration medium = Duration(milliseconds: 350);

  /// Page transitions (slow).
  static const Duration slow = Duration(milliseconds: 600);

  /// Hero animations (very slow) — connect-button state changes,
  /// RGB ring phase shifts.
  static const Duration verySlow = Duration(milliseconds: 1200);

  /// RGB ring rotation period on the Connect Button (§6.4.1).
  static const Duration rgbRingSlow = Duration(seconds: 8);

  /// When connecting, ring rotates 2× faster (4 s cycle).
  static const Duration rgbRingFast = Duration(seconds: 4);

  /// Auto-dismiss for QuantumToast (§6.10).
  static const Duration toastDismiss = Duration(seconds: 4);

  /// Pulse period for status dots + countdown urgency border (§6.4.2/§6.4.4).
  static const Duration pulse = Duration(milliseconds: 1500);

  /// Aurora drift period (§6.10).
  static const Duration auroraDrift = Duration(seconds: 30);
}

// =============================================================================
// §6.5  QuantumTransitions
// =============================================================================

/// Pure functions that build pre-configured [Animation] objects for
/// modals/sheets/dialogs. Per §6.5, every overlay must apply `scaleIn +
/// slideUp + fadeIn` together (the "Quantum entrance" combination).
///
/// Usage:
/// ```dart
/// ScaleTransition(
///   scale: QuantumTransitions.scaleIn(controller),
///   child: FadeTransition(
///     opacity: QuantumTransitions.fadeIn(controller),
///     child: SlideTransition(
///       position: QuantumTransitions.slideUp(controller),
///       child: ...,
///     ),
///   ),
/// )
/// ```
class QuantumTransitions {
  QuantumTransitions._();

  /// Returns an [Animation<double>] usable inside `ScaleTransition`.
  ///
  /// Scales from 0.92 → 1.0 with [QuantumCurves.easeInOutCubicEmphasized].
  /// Accepts any [Animation<double>] — typically an [AnimationController]
  /// or a `CurvedAnimation`.
  static Animation<double> scaleIn(Animation<double> controller) {
    return Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: QuantumCurves.easeInOutCubicEmphasized,
      ),
    );
  }

  /// Returns an [Animation<Offset>] for `SlideTransition`.
  ///
  /// Slides from 8% below origin to origin (subtle "rise" motion).
  static Animation<Offset> slideUp(Animation<double> controller) {
    return Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: controller,
            curve: QuantumCurves.easeInOutCubicEmphasized,
          ),
        );
  }

  /// Returns an [Animation<double>] for `FadeTransition`.
  ///
  /// Fades from 0.0 → 1.0 with [QuantumCurves.easeInOutCubicEmphasized].
  static Animation<double> fadeIn(Animation<double> controller) {
    return Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: QuantumCurves.easeInOutCubicEmphasized,
      ),
    );
  }

  /// Returns an [Animation<double>] for outgoing fade (1.0 → 0.0).
  /// Uses [QuantumCurves.accelerate] so dismissal feels snappy.
  static Animation<double> fadeOut(Animation<double> controller) {
    return Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: QuantumCurves.accelerate,
      ),
    );
  }

  /// Returns an [Animation<double>] for outgoing scale (1.0 → 0.92).
  static Animation<double> scaleOut(Animation<double> controller) {
    return Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: controller,
        curve: QuantumCurves.accelerate,
      ),
    );
  }

  /// Returns an [Animation<Offset>] for outgoing slide-down (origin → 8% below).
  static Animation<Offset> slideDown(Animation<double> controller) {
    return Tween<Offset>(begin: Offset.zero, end: const Offset(0, 0.08))
        .animate(
          CurvedAnimation(
            parent: controller,
            curve: QuantumCurves.accelerate,
          ),
        );
  }
}
