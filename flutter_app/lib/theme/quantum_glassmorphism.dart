// =============================================================================
// quantum_glassmorphism.dart — Quantum Enterprise RGB glassmorphism widgets
//
// Per §6.1 core principle #3: every card has a backdrop blur (10-20 px),
// 1 px border with 8% white overlay, inner highlight (top edge), outer
// shadow (subtle drop).
//
// Per §6.6 light mode: glassmorphism becomes subtle shadow + 1 px gray
// border instead of backdrop blur (because light mode + backdrop blur
// looks muddy).
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import 'quantum_theme.dart';

/// A glassmorphic card.
///
/// Wraps [ClipRRect] + [BackdropFilter] + [Container] with:
///   - bg `bgSurface.withOpacity(0.7)`
///   - 1 px `borderSubtle` border
///   - `BoxShadow` `shadowSoft`
///   - 20 px radius (override via [radius])
///
/// In light mode (pass [isLight] = true) the backdrop blur is skipped per
/// §6.6 — instead we use subtle shadow + 1 px gray border.
class QuantumGlassCard extends StatelessWidget {
  const QuantumGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(QuantumPalette.spaceLg),
    this.radius = QuantumPalette.radiusCard,
    this.blurSigmaX = 16.0,
    this.blurSigmaY = 16.0,
    this.isLight = false,
    this.backgroundOpacity = 0.7,
    this.borderSide,
    this.boxShadow,
    this.margin,
  });

  /// Card content.
  final Widget child;

  /// Inner padding (defaults to 20 px per §6.1 #7).
  final EdgeInsetsGeometry padding;

  /// Corner radius (defaults to 20 px per §6.1 #8).
  final double radius;

  /// Backdrop blur sigma (defaults to 16 px per §6.4.2).
  final double blurSigmaX;
  final double blurSigmaY;

  /// If true, skips backdrop blur and uses subtle shadow + 1 px gray
  /// border instead (§6.6).
  final bool isLight;

  /// Background opacity (defaults to 0.7 per §6.4.2).
  final double backgroundOpacity;

  /// Optional border override (defaults to `borderSubtle`).
  final BorderSide? borderSide;

  /// Optional box-shadow override (defaults to `shadowSoft`).
  final List<BoxShadow>? boxShadow;

  /// Optional outer margin.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isLightMode = isLight ||
        Theme.of(context).brightness == Brightness.light;

    final bgColor = (isLightMode
            ? QuantumPalette.lightBgSurface
            : QuantumPalette.bgSurface)
        .withValues(alpha: isLightMode ? 0.9 : backgroundOpacity);

    final border = borderSide ??
        BorderSide(
          color: isLightMode
              ? QuantumPalette.lightBorderSubtle
              : QuantumPalette.borderSubtle,
          width: 1,
        );

    final shadows = boxShadow ??
        [
          BoxShadow(
            color: isLightMode
                ? QuantumPalette.lightShadowSoft
                : QuantumPalette.shadowSoft,
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ];

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.fromBorderSide(border),
        boxShadow: shadows,
        // Inner highlight (top edge) per §6.1 #3.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: isLightMode ? 0.06 : 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4],
        ),
      ),
      child: child,
    );

    // In light mode, skip the backdrop filter (§6.6).
    if (isLightMode) {
      return Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: container,
        ),
      );
    }

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurSigmaX,
            sigmaY: blurSigmaY,
          ),
          child: container,
        ),
      ),
    );
  }
}

/// A glassmorphic modal variant.
///
/// Uses `bgElevated` at 20% opacity (or full opacity in light mode) with a
/// 24 px radius — used by sheets, dialogs, popovers.
class QuantumGlassModal extends StatelessWidget {
  const QuantumGlassModal({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(QuantumPalette.spaceLg),
    this.radius = QuantumPalette.radiusModal,
    this.isLight = false,
    this.backgroundOpacity = 0.2,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool isLight;
  final double backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final isLightMode = isLight ||
        Theme.of(context).brightness == Brightness.light;

    final bgColor = (isLightMode
            ? QuantumPalette.lightBgElevated
            : QuantumPalette.bgElevated)
        .withValues(alpha: isLightMode ? 1.0 : backgroundOpacity);

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.fromBorderSide(BorderSide(
          color: isLightMode
              ? QuantumPalette.lightBorderSubtle
              : QuantumPalette.borderSubtle,
          width: 1,
        )),
        boxShadow: [
          BoxShadow(
            color: isLightMode
                ? QuantumPalette.lightShadowDeep
                : QuantumPalette.shadowDeep,
            blurRadius: 48,
            spreadRadius: 0,
            offset: const Offset(0, 16),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: isLightMode ? 0.08 : 0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4],
        ),
      ),
      child: child,
    );

    if (isLightMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: container,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: container,
      ),
    );
  }
}

/// A glassmorphic pill — used by [QuantumCountdownTimer] cells, suggested
/// prompts on the AI Assistant, and [QuantumResilienceChain] steps.
class QuantumGlassPill extends StatelessWidget {
  const QuantumGlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: QuantumPalette.spaceMd,
      vertical: QuantumPalette.spaceXs,
    ),
    this.isLight = false,
    this.borderColor,
    this.borderWidth = 1.0,
    this.backgroundOpacity = 0.7,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool isLight;
  final Color? borderColor;
  final double borderWidth;
  final double backgroundOpacity;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final isLightMode = isLight ||
        Theme.of(context).brightness == Brightness.light;

    final border = borderColor ??
        (isLightMode
            ? QuantumPalette.lightBorderSubtle
            : QuantumPalette.borderSubtle);

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: (isLightMode
                ? QuantumPalette.lightBgElevated
                : QuantumPalette.bgElevated)
            .withValues(alpha: isLightMode ? 0.9 : backgroundOpacity),
        borderRadius: BorderRadius.circular(QuantumPalette.radiusPill),
        border: Border.fromBorderSide(
          BorderSide(color: border, width: borderWidth),
        ),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: isLightMode
                    ? QuantumPalette.lightShadowSoft
                    : QuantumPalette.shadowSoft,
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
      ),
      child: child,
    );

    if (isLightMode) {
      return container;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(QuantumPalette.radiusPill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: container,
      ),
    );
  }
}
