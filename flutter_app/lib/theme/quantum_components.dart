// =============================================================================
// quantum_components.dart — Quantum Enterprise RGB components (§6.4 + §6.10)
//
// All 10+ components per the directive:
//   §6.4.1  QuantumConnectButton
//   §6.4.2  QuantumStatusCard
//   §6.4.3  QuantumCoreSwitcher
//   §6.4.4  QuantumEnterpriseLicensePanel
//   §6.4.5  QuantumSettingsRow
//   §6.4.5  QuantumToggle
//   §6.4.6  QuantumResilienceChain
//   §6.4.7  QuantumAIAssistantSheet
//           QuantumSparkline (used by StatusCard)
//           QuantumCountdownTimer (used by LicensePanel)
//   §6.10   QuantumAuroraBackground
//   §6.10   QuantumToast (forbidden SnackBar replacement)
//   §6.10   QuantumSpinner (forbidden CircularProgressIndicator replacement)
//   §6.10   QuantumDialog (forbidden Dialog replacement)
//
// Per §6.8 animation budget: all animations use AnimationController + vsync.
// Heavy painters wrapped in RepaintBoundary.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import 'quantum_glassmorphism.dart';
import 'quantum_theme.dart';

// =============================================================================
// §6.10  QuantumAuroraBackground
// =============================================================================

/// A subtle RGB aurora background. CustomPainter draws 3-5 blurred RGB blobs
/// that drift slowly across the canvas. Per §6.10 every screen has one.
///
/// Wrap in [RepaintBoundary] (already done internally) so the painter does
/// not repaint when sibling widgets rebuild.
class QuantumAuroraBackground extends StatefulWidget {
  const QuantumAuroraBackground({
    super.key,
    this.brightness = Brightness.dark,
    this.blobCount = 4,
    this.driftSpeed = 0.05,
  });

  final Brightness brightness;
  final int blobCount;
  final double driftSpeed;

  @override
  State<QuantumAuroraBackground> createState() => _QuantumAuroraBackgroundState();
}

class _QuantumAuroraBackgroundState extends State<QuantumAuroraBackground>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AuroraPainter(
          progress: _controller,
          blobCount: widget.blobCount,
          driftSpeed: widget.driftSpeed,
          isLight: widget.brightness == Brightness.light,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.progress,
    required this.blobCount,
    required this.driftSpeed,
    required this.isLight,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final int blobCount;
  final double driftSpeed;
  final bool isLight;

  static const _blobColors = [
    Color(0xFFFF0080), // magenta
    Color(0xFF00FFFF), // cyan
    Color(0xFF8000FF), // violet
    Color(0xFF00FF88), // green
    Color(0xFFFF8000), // orange
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value * 2 * math.pi * driftSpeed;
    final baseColor = isLight
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF050510);

    // Fill background.
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    for (var i = 0; i < blobCount; i++) {
      final phase = (i / blobCount) * 2 * math.pi;
      final dx = (math.sin(t + phase) * 0.4 + 0.5) * size.width;
      final dy = (math.cos(t * 0.7 + phase) * 0.3 + 0.5) * size.height;
      final radius = (size.longestSide * 0.35) * (0.7 + 0.3 * math.sin(t + phase * 2));
      final color = _blobColors[i % _blobColors.length]
          .withValues(alpha: isLight ? 0.05 : 0.12);

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ).createShader(
          Rect.fromCircle(center: Offset(dx, dy), radius: radius),
        );
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.blobCount != blobCount ||
      old.driftSpeed != driftSpeed ||
      old.isLight != isLight;
}

// =============================================================================
// §6.4.2 helper  QuantumSparkline
// =============================================================================

/// A sparkline of last 60 s throughput (60 data points, RGB gradient stroke,
/// no axes, 40 px tall). Per §6.4.2 + §6.8 — CustomPainter with RepaintBoundary.
class QuantumSparkline extends StatefulWidget {
  const QuantumSparkline({
    super.key,
    required this.data,
    this.height = 40,
    this.gradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: QuantumPalette.rgbAccent3,
    ),
  });

  final List<double> data;
  final double height;
  final Gradient gradient;

  @override
  State<QuantumSparkline> createState() => _QuantumSparklineState();
}

class _QuantumSparklineState extends State<QuantumSparkline> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          size: Size.infinite,
          painter: _SparklinePainter(
            data: widget.data,
            gradient: widget.gradient,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.gradient});

  final List<double> data;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxValue = data.reduce((a, b) => a > b ? a : b).clamp(0.0001, double.infinity);
    final stepX = size.width / (data.length - 1);
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i] / maxValue) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    // Fill below the line with a translucent gradient for depth.
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          QuantumPalette.rgbAccent3[0].withValues(alpha: 0.15),
          QuantumPalette.rgbAccent3[0].withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) {
    if (old.data.length != data.length) return true;
    for (var i = 0; i < data.length; i++) {
      if (old.data[i] != data[i]) return true;
    }
    return false;
  }
}

// =============================================================================
// §6.4.4 helper  QuantumCountdownTimer
// =============================================================================

/// 4-cell countdown timer (Days / Hours / Minutes / Seconds). Persian
/// numeral support when `locale == 'fa'` per §6.7. RGB-gradient borders that
/// animate faster as expiry approaches.
class QuantumCountdownTimer extends StatefulWidget {
  const QuantumCountdownTimer({
    super.key,
    required this.expiry,
    this.locale = 'en',
    this.onExpired,
  });

  final DateTime expiry;
  final String locale;
  final VoidCallback? onExpired;

  @override
  State<QuantumCountdownTimer> createState() => _QuantumCountdownTimerState();
}

class _QuantumCountdownTimerState extends State<QuantumCountdownTimer>
    with TickerProviderStateMixin {
  late final AnimationController _borderPulse;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _borderPulse = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    )..repeat(reverse: true);
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final diff = widget.expiry.difference(now);
    if (diff.isNegative || diff.inSeconds <= 0) {
      _remaining = Duration.zero;
      if (!_expired) {
        _expired = true;
        widget.onExpired?.call();
      }
    } else {
      _remaining = diff;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _borderPulse.dispose();
    super.dispose();
  }

  String _format(int n) {
    final s = n.toString().padLeft(2, '0');
    return widget.locale == 'fa'
        ? QuantumTypography.toPersianNumerals(s)
        : s;
  }

  @override
  Widget build(BuildContext context) {
    final days = _remaining.inDays;
    final hours = _remaining.inHours.remainder(24);
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);

    final urgency = days < 1 ? 1.0 : (days < 7 ? 0.5 : 0.0);

    return Row(
      children: [
        Expanded(
          child: _CountdownCell(
            value: _format(days),
            label: widget.locale == 'fa' ? 'روز' : 'DAYS',
            pulse: _borderPulse,
            urgency: urgency,
          ),
        ),
        const SizedBox(width: QuantumPalette.spaceXs),
        Expanded(
          child: _CountdownCell(
            value: _format(hours),
            label: widget.locale == 'fa' ? 'ساعت' : 'HRS',
            pulse: _borderPulse,
            urgency: urgency,
          ),
        ),
        const SizedBox(width: QuantumPalette.spaceXs),
        Expanded(
          child: _CountdownCell(
            value: _format(minutes),
            label: widget.locale == 'fa' ? 'دقیقه' : 'MIN',
            pulse: _borderPulse,
            urgency: urgency,
          ),
        ),
        const SizedBox(width: QuantumPalette.spaceXs),
        Expanded(
          child: _CountdownCell(
            value: _format(seconds),
            label: widget.locale == 'fa' ? 'ثانیه' : 'SEC',
            pulse: _borderPulse,
            urgency: urgency,
          ),
        ),
      ],
    );
  }
}

class _CountdownCell extends StatelessWidget {
  const _CountdownCell({
    required this.value,
    required this.label,
    required this.pulse,
    required this.urgency,
  });

  final String value;
  final String label;
  final Animation<double> pulse;
  final double urgency; // 0..1 — how close to expiry

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final intensity = 0.4 + pulse.value * 0.6 * (0.3 + urgency * 0.7);
        return QuantumGlassPill(
          padding: const EdgeInsets.symmetric(
            horizontal: QuantumPalette.spaceXs,
            vertical: QuantumPalette.spaceSm,
          ),
          borderColor: QuantumPalette.rgbAccent3[0].withValues(alpha: intensity),
          borderWidth: 1.5,
          boxShadow: [
            BoxShadow(
              color: QuantumPalette.rgbAccent3[0].withValues(alpha: urgency * 0.4),
              blurRadius: 12 * urgency,
              spreadRadius: 1,
            ),
          ],
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: QuantumPalette.textPrimary,
                  letterSpacing: -0.02,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.04,
                  color: QuantumPalette.textTertiary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// §6.10  QuantumSpinner (forbidden CircularProgressIndicator replacement)
// =============================================================================

/// RGB gradient stroke spinner. Replaces every default `CircularProgressIndicator`.
class QuantumSpinner extends StatefulWidget {
  const QuantumSpinner({
    super.key,
    this.size = 28,
    this.strokeWidth = 3,
  });

  final double size;
  final double strokeWidth;

  @override
  State<QuantumSpinner> createState() => _QuantumSpinnerState();
}

class _QuantumSpinnerState extends State<QuantumSpinner>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _SpinnerPainter(
            progress: _controller,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.progress,
    required this.strokeWidth,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = QuantumPalette.borderStrong,
    );

    // Sweep gradient
    final sweep = 2 * math.pi * 0.75; // 270° arc
    final start = -math.pi / 2 + progress.value * 2 * math.pi;
    final gradient = SweepGradient(
      startAngle: start,
      endAngle: start + sweep,
      colors: [
        QuantumPalette.rgbAccent3[0],
        QuantumPalette.rgbAccent3[1],
        QuantumPalette.rgbAccent3[2],
        QuantumPalette.rgbAccent3[0].withValues(alpha: 0.0),
      ],
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter old) =>
      old.strokeWidth != strokeWidth;
}

// =============================================================================
// §6.10  QuantumToast (forbidden SnackBar replacement)
// =============================================================================

/// Top-of-screen glassmorphic toast. RGB accent. 4 s auto-dismiss. Swipe-to-dismiss.
///
/// Usage:
/// ```dart
/// QuantumToast.show(context, message: 'License activated.');
/// ```
class QuantumToast extends StatefulWidget {
  const QuantumToast({
    super.key,
    required this.message,
    this.accentColor = const Color(0xFFFF0080),
    this.duration = QuantumDurations.toastDismiss,
    this.icon = Icons.check_circle,
  });

  final String message;
  final Color accentColor;
  final Duration duration;
  final IconData icon;

  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String message,
    Color accentColor = const Color(0xFFFF0080),
    Duration duration = QuantumDurations.toastDismiss,
    IconData icon = Icons.check_circle,
  }) {
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (ctx) => QuantumToast(
        message: message,
        accentColor: accentColor,
        duration: duration,
        icon: icon,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  State<QuantumToast> createState() => _QuantumToastState();
}

class _QuantumToastState extends State<QuantumToast>
    with TickerProviderStateMixin {
  late final AnimationController _in;
  late final AnimationController _out;
  late final AnimationController _slide;
  Timer? _auto;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    );
    _out = AnimationController(
      vsync: this,
      duration: QuantumDurations.fast,
    );
    _slide = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    );
    _in.forward();
    _slide.forward();
    _auto = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    _auto?.cancel();
    _out.forward().then((_) {
      if (QuantumToast._entry != null) {
        QuantumToast._entry!.remove();
        QuantumToast._entry = null;
      }
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _in.dispose();
    _out.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Positioned(
      top: mediaQuery.padding.top + 16 + _dragDy,
      left: QuantumPalette.spaceLg,
      right: QuantumPalette.spaceLg,
      child: FadeTransition(
        opacity: ReverseAnimation(_out),
        child: SlideTransition(
          position: QuantumTransitions.slideUp(_slide),
          child: GestureDetector(
            onVerticalDragUpdate: (d) {
              if (d.delta.dy < 0) {
                setState(() => _dragDy += d.delta.dy);
              }
            },
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! < -100) {
                _dismiss();
              } else {
                setState(() => _dragDy = 0);
              }
            },
            child: QuantumGlassCard(
              padding: const EdgeInsets.symmetric(
                horizontal: QuantumPalette.spaceLg,
                vertical: QuantumPalette.spaceMd,
              ),
              borderSide: BorderSide(
                color: widget.accentColor.withValues(alpha: 0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.25),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.accentColor, size: 22),
                  const SizedBox(width: QuantumPalette.spaceMd),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: QuantumPalette.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _dismiss,
                    child: const Icon(
                      Icons.close,
                      color: QuantumPalette.textTertiary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// §6.10  QuantumDialog (forbidden Dialog replacement)
// =============================================================================

class QuantumDialog {
  QuantumDialog._();

  /// Shows a dialog with `QuantumTransitions.scaleIn + fadeIn`.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: QuantumPalette.shadowDeep,
      transitionDuration: QuantumDurations.medium,
      transitionBuilder: (ctx, animation, secondary, child) {
        return FadeTransition(
          opacity: QuantumTransitions.fadeIn(animation),
          child: ScaleTransition(
            scale: QuantumTransitions.scaleIn(animation),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, sec) => Center(
        child: QuantumGlassModal(child: child),
      ),
    );
  }
}

// =============================================================================
// §6.4.1  QuantumConnectButton (the hero element)
// =============================================================================

enum QuantumConnectState { disconnected, connecting, connected }

/// The hero element of the Quantum Enterprise RGB theme.
///
/// 88×88 px circular button with an animated RGB ring around it. Per §6.4.1:
///   - disconnected → "Connect" label
///   - connecting → "Connecting…" + spinner
///   - connected → "Disconnect" + stop icon
///   - haptic + scale 0.95 on tap
///   - soft glow shadow
class QuantumConnectButton extends StatefulWidget {
  const QuantumConnectButton({
    super.key,
    required this.state,
    required this.onTap,
  });

  final QuantumConnectState state;
  final VoidCallback onTap;

  @override
  State<QuantumConnectButton> createState() => _QuantumConnectButtonState();
}

class _QuantumConnectButtonState extends State<QuantumConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _ring;
  late final AnimationController _scale;
  late final AnimationController _checkmark;
  bool _checkmarkVisible = false;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: QuantumDurations.rgbRingSlow,
    );
    _scale = AnimationController(
      vsync: this,
      duration: QuantumDurations.fast,
    );
    _checkmark = AnimationController(
      vsync: this,
      duration: QuantumDurations.slow,
    );
    _applyState();
  }

  @override
  void didUpdateWidget(covariant QuantumConnectButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _applyState();
    }
  }

  void _applyState() {
    switch (widget.state) {
      case QuantumConnectState.disconnected:
        _ring.stop();
        break;
      case QuantumConnectState.connecting:
        _ring.duration = QuantumDurations.rgbRingFast;
        _ring.repeat();
        break;
      case QuantumConnectState.connected:
        // Per §6.4.1: "When connected: ring stops rotating, becomes a steady
        // RGB gradient, a green checkmark icon overlays for 1.5 s then
        // fades."
        _ring.stop();
        if (!_checkmarkVisible) {
          _checkmarkVisible = true;
          _checkmark.forward(from: 0).then((_) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                setState(() => _checkmarkVisible = false);
                _checkmark.reset();
              }
            });
          });
        }
        break;
    }
  }

  Future<void> _handleTap() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 30);
    }
    _scale.forward().then((_) => _scale.reverse());
    widget.onTap();
  }

  @override
  void dispose() {
    _ring.dispose();
    _scale.dispose();
    _checkmark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 88.0;
    final ringStroke = 4.0;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ring, _scale, _checkmark]),
        builder: (context, _) {
          final scale = 1.0 - _scale.value * 0.05;
          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: size + 16,
              height: size + 16,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glow shadow
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: QuantumPalette.rgbAccent3[0]
                              .withValues(alpha: 0.4),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  // RGB ring (rotating)
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(size, size),
                      painter: _RgbRingPainter(
                        progress: _ring,
                        stroke: ringStroke,
                        steady: widget.state == QuantumConnectState.connected,
                      ),
                    ),
                  ),
                  // Inner button surface
                  Container(
                    width: size - ringStroke * 2 - 8,
                    height: size - ringStroke * 2 - 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: QuantumPalette.bgSurface,
                      border: Border.fromBorderSide(
                        const BorderSide(color: QuantumPalette.borderSubtle),
                      ),
                    ),
                    child: _buildCenter(),
                  ),
                  // Checkmark overlay
                  if (_checkmarkVisible)
                    Positioned.fill(
                      child: Opacity(
                        opacity: 1.0 - _checkmark.value,
                        child: Center(
                          child: Icon(
                            Icons.check_circle,
                            color: QuantumPalette.statusConnected,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenter() {
    switch (widget.state) {
      case QuantumConnectState.disconnected:
        return const Center(
          child: Text(
            'Connect',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: QuantumPalette.textPrimary,
              letterSpacing: -0.01,
            ),
          ),
        );
      case QuantumConnectState.connecting:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: QuantumSpinner(size: 20, strokeWidth: 2.5),
              ),
              SizedBox(height: 4),
              Text(
                'Connecting…',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: QuantumPalette.textSecondary,
                ),
              ),
            ],
          ),
        );
      case QuantumConnectState.connected:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.stop_rounded,
                color: QuantumPalette.statusDisconnected,
                size: 22,
              ),
              SizedBox(height: 2),
              Text(
                'Disconnect',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: QuantumPalette.textPrimary,
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _RgbRingPainter extends CustomPainter {
  _RgbRingPainter({
    required this.progress,
    required this.stroke,
    required this.steady,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double stroke;
  final bool steady;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );

    // Sweep gradient that rotates with the animation.
    final startAngle = -math.pi / 2 + progress.value * 2 * math.pi;
    final sweep = 2 * math.pi;
    final gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweep,
      colors: QuantumPalette.rgbSpectrum,
    );
    canvas.drawArc(
      rect,
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RgbRingPainter old) =>
      old.stroke != stroke || old.steady != steady;
}

// =============================================================================
// §6.4.2  QuantumStatusCard
// =============================================================================

/// A single stat cell for [QuantumStatusCard]. Public so callers can
/// construct cards.
class QuantumStat {
  const QuantumStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.unit,
  });

  final String label;
  final double value;
  final IconData icon;
  final String unit;
}

/// A glassmorphic status card per §6.4.2.
class QuantumStatusCard extends StatefulWidget {
  const QuantumStatusCard({
    super.key,
    required this.status,
    required this.uptime,
    required this.stats,
    required this.sparkData,
    this.locale = 'en',
  });

  final QuantumConnectState status;
  final String uptime; // e.g. "00:42:18"
  final List<QuantumStat> stats; // 2x2 grid (length 4)
  final List<double> sparkData; // 60 points
  final String locale;

  @override
  State<QuantumStatusCard> createState() => _QuantumStatusCardState();
}

class _QuantumStatusCardState extends State<QuantumStatusCard>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final List<int> _displayedValues;
  late final List<Timer?> _countUpTimers;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _displayedValues = widget.stats.map((s) => s.value.toInt()).toList();
    _countUpTimers = List<Timer?>.filled(widget.stats.length, null);
    for (var i = 0; i < widget.stats.length; i++) {
      _scheduleCountUp(i);
    }
  }

  void _scheduleCountUp(int i) {
    _countUpTimers[i]?.cancel();
    final target = widget.stats[i].value.toInt();
    final current = _displayedValues[i];
    if (current == target) return;
    final diff = (target - current).abs();
    final stepCount = diff.clamp(1, 30);
    final stepDelay = const Duration(seconds: 1) ~/ stepCount;
    _countUpTimers[i] = Timer.periodic(stepDelay, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_displayedValues[i] < target) {
          _displayedValues[i]++;
        } else if (_displayedValues[i] > target) {
          _displayedValues[i]--;
        } else {
          t.cancel();
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant QuantumStatusCard old) {
    super.didUpdateWidget(old);
    for (var i = 0; i < widget.stats.length && i < old.stats.length; i++) {
      if (old.stats[i].value != widget.stats[i].value) {
        _scheduleCountUp(i);
      }
    }
  }

  @override
  void dispose() {
    for (final t in _countUpTimers) {
      t?.cancel();
    }
    _pulse.dispose();
    super.dispose();
  }

  Color _statusColor() {
    switch (widget.status) {
      case QuantumConnectState.connected:
        return QuantumPalette.statusConnected;
      case QuantumConnectState.connecting:
        return QuantumPalette.statusConnecting;
      case QuantumConnectState.disconnected:
        return QuantumPalette.statusDisconnected;
    }
  }

  String _statusLabel() {
    switch (widget.status) {
      case QuantumConnectState.connected:
        return widget.locale == 'fa' ? 'متصل' : 'Connected';
      case QuantumConnectState.connecting:
        return widget.locale == 'fa' ? 'در حال اتصال' : 'Connecting';
      case QuantumConnectState.disconnected:
        return widget.locale == 'fa' ? 'قطع شده' : 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return QuantumGlassCard(
      padding: const EdgeInsets.all(QuantumPalette.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: status dot, status label, uptime
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final dotColor = _statusColor();
                  final isPulsing = widget.status == QuantumConnectState.connecting;
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      boxShadow: isPulsing
                          ? [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.5 + _pulse.value * 0.5),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                    ),
                  );
                },
              ),
              const SizedBox(width: QuantumPalette.spaceSm),
              Text(
                _statusLabel(),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.04,
                  color: QuantumPalette.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                widget.uptime,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  color: QuantumPalette.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: QuantumPalette.spaceLg),
          // 2x2 stats grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.4,
              mainAxisSpacing: QuantumPalette.spaceMd,
              crossAxisSpacing: QuantumPalette.spaceMd,
            ),
            itemCount: widget.stats.length,
            itemBuilder: (context, i) {
              final s = widget.stats[i];
              final v = _displayedValues[i];
              return Row(
                children: [
                  Icon(s.icon, size: 16, color: QuantumPalette.textSecondary),
                  const SizedBox(width: QuantumPalette.spaceXs),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.label,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.04,
                          color: QuantumPalette.textTertiary,
                        ),
                      ),
                      ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          colors: QuantumPalette.rgbAccent3,
                        ).createShader(rect),
                        child: Text(
                          '$v ${s.unit}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: QuantumPalette.spaceLg),
          // Sparkline
          QuantumSparkline(data: widget.sparkData),
        ],
      ),
    );
  }
}

// =============================================================================
// §6.4.3  QuantumCoreSwitcher
// =============================================================================

class QuantumCoreModel {
  const QuantumCoreModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
}

/// Horizontal scroll of core chips. Each chip 56×56 px circular avatar with
/// the core's icon and gradient color + name below in label style.
class QuantumCoreSwitcher extends StatefulWidget {
  const QuantumCoreSwitcher({
    super.key,
    required this.cores,
    required this.activeId,
    required this.onSelect,
    this.locale = 'en',
  });

  final List<QuantumCoreModel> cores;
  final String activeId;
  final void Function(String coreId) onSelect;
  final String locale;

  @override
  State<QuantumCoreSwitcher> createState() => _QuantumCoreSwitcherState();
}

class _QuantumCoreSwitcherState extends State<QuantumCoreSwitcher>
    with TickerProviderStateMixin {
  late final AnimationController _spring;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    )..forward();
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  Future<void> _onTap(QuantumCoreModel core) async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 20, amplitude: 80);
    }
    _spring.forward(from: 0);
    HapticFeedback.selectionClick();
    widget.onSelect(core.id);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: QuantumPalette.spaceLg),
        itemCount: widget.cores.length,
        separatorBuilder: (context, _) => const SizedBox(width: QuantumPalette.spaceMd),
        itemBuilder: (context, i) {
          final core = widget.cores[i];
          final isActive = core.id == widget.activeId;
          return _CoreChip(
            core: core,
            isActive: isActive,
            spring: _spring,
            onTap: () => _onTap(core),
          );
        },
      ),
    );
  }
}

class _CoreChip extends StatelessWidget {
  const _CoreChip({
    required this.core,
    required this.isActive,
    required this.spring,
    required this.onTap,
  });

  final QuantumCoreModel core;
  final bool isActive;
  final AnimationController spring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            AnimatedBuilder(
              animation: spring,
              builder: (context, child) {
                final scale = 1.0 +
                    (isActive
                        ? (1 - spring.value) * 0.15 * Curves.easeInOutCubicEmphasized.transform(spring.value)
                        : 0.0);
                return Transform.scale(scale: scale, child: child);
              },
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isActive)
                      RepaintBoundary(
                        child: CustomPaint(
                          size: const Size(56, 56),
                          painter: _RgbRingPainter(
                            progress: AlwaysStoppedAnimation(0.0),
                            stroke: 3,
                            steady: true,
                          ),
                        ),
                      ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isActive
                            ? LinearGradient(
                                colors: [
                                  core.color,
                                  core.color.withBlue(180),
                                ],
                              )
                            : null,
                        color: isActive ? null : QuantumPalette.bgElevated,
                        border: isActive
                            ? null
                            : Border.fromBorderSide(
                                const BorderSide(color: QuantumPalette.borderSubtle),
                              ),
                      ),
                      child: Icon(
                        core.icon,
                        color: isActive ? Colors.white : QuantumPalette.textTertiary,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              core.name,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? QuantumPalette.textPrimary : QuantumPalette.textTertiary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// §6.4.4  QuantumEnterpriseLicensePanel
// =============================================================================

/// The Enterprise License Panel per §6.4.4.
///
/// - RGB horizontal gradient banner (red → green → blue) — height 4 px — at top
/// - Card with verified-user icon (gold gradient), serial number, "Enterprise
///   Tier" label, org name, $999,999,999,999 value (gold gradient text)
/// - Countdown timer — 4 cells (Days / Hours / Minutes / Seconds) each in a
///   glassmorphic pill, RGB-gradient borders that animate faster as expiry
///   approaches
/// - Anti-tamper verified badge ("Signed by UnifiedShield Quantum Authority")
///   with a tiny lock icon
class QuantumEnterpriseLicensePanel extends StatelessWidget {
  const QuantumEnterpriseLicensePanel({
    super.key,
    required this.serialNumber,
    required this.organization,
    required this.expiry,
    required this.tierName,
    this.valueUsd = 999999999999,
    this.locale = 'en',
  });

  final String serialNumber;
  final String organization;
  final DateTime expiry;
  final String tierName;
  final int valueUsd;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final moneyFmt = valueUsd.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    final moneyStr = locale == 'fa'
        ? QuantumTypography.toPersianNumerals('\$$moneyFmt')
        : '\$$moneyFmt';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4 px RGB banner
        Container(
          height: 4,
          decoration: const BoxDecoration(
            gradient: QuantumGradients.enterpriseBanner,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(QuantumPalette.radiusCard),
            ),
          ),
        ),
        // Card body
        QuantumGlassCard(
          padding: const EdgeInsets.all(QuantumPalette.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top: gold verified-user icon + serial
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      colors: QuantumPalette.goldGradient,
                    ).createShader(rect),
                    child: const Icon(
                      Icons.verified_user,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: QuantumPalette.spaceMd),
                  Expanded(
                    child: Text(
                      serialNumber,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: QuantumPalette.textPrimary,
                        letterSpacing: -0.01,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: QuantumPalette.spaceLg),
              // Tier label
              Text(
                tierName,
                style: QuantumTypography.display3For(locale).copyWith(
                  color: QuantumPalette.textPrimary,
                ),
              ),
              const SizedBox(height: QuantumPalette.spaceXs),
              // Org name
              Text(
                organization,
                style: QuantumTypography.body1For(locale).copyWith(
                  color: QuantumPalette.textSecondary,
                ),
              ),
              const SizedBox(height: QuantumPalette.spaceMd),
              // Value
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: QuantumPalette.goldGradient,
                ).createShader(rect),
                child: Text(
                  moneyStr,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.01,
                  ),
                ),
              ),
              const SizedBox(height: QuantumPalette.spaceLg),
              // Countdown
              QuantumCountdownTimer(
                expiry: expiry,
                locale: locale,
              ),
              const SizedBox(height: QuantumPalette.spaceLg),
              // Anti-tamper badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: QuantumPalette.spaceMd,
                  vertical: QuantumPalette.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: QuantumPalette.bgElevated,
                  borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
                  border: Border.fromBorderSide(
                    const BorderSide(color: QuantumPalette.borderSubtle),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock,
                      size: 14,
                      color: QuantumPalette.statusConnected,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        locale == 'fa'
                            ? 'امضای UnifiedShield Quantum Authority'
                            : 'Signed by UnifiedShield Quantum Authority',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: QuantumPalette.textTertiary,
                          letterSpacing: 0.04,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// §6.4.5  QuantumToggle (custom switch)
// =============================================================================

/// Custom-painted 52×32 pill toggle. Off = `bgElevated` + `borderSubtle`,
/// on = RGB gradient with white knob animating 200 ms.
class QuantumToggle extends StatefulWidget {
  const QuantumToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<QuantumToggle> createState() => _QuantumToggleState();
}

class _QuantumToggleState extends State<QuantumToggle>
    with TickerProviderStateMixin {
  static const _width = 52.0;
  static const _height = 32.0;
  static const _knob = 24.0;

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: QuantumDurations.fast,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant QuantumToggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim.animateTo(widget.value ? 1.0 : 0.0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    HapticFeedback.selectionClick();
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 15, amplitude: 60);
    }
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          return Container(
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(QuantumPalette.radiusPill),
              gradient: LinearGradient(
                colors: [
                  Color.lerp(
                    QuantumPalette.bgElevated,
                    QuantumPalette.rgbAccent3[0],
                    _anim.value,
                  )!,
                  Color.lerp(
                    QuantumPalette.bgElevated,
                    QuantumPalette.rgbAccent3[1],
                    _anim.value,
                  )!,
                  Color.lerp(
                    QuantumPalette.bgElevated,
                    QuantumPalette.rgbAccent3[2],
                    _anim.value,
                  )!,
                ],
              ),
              border: Border.fromBorderSide(
                BorderSide(
                  color: Color.lerp(
                    QuantumPalette.borderSubtle,
                    Colors.transparent,
                    _anim.value,
                  )!,
                  width: 1,
                ),
              ),
              boxShadow: _anim.value > 0.1
                  ? [
                      BoxShadow(
                        color: QuantumPalette.rgbAccent3[0]
                            .withValues(alpha: 0.4 * _anim.value),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Align(
              alignment: Alignment.lerp(
                Alignment.centerLeft,
                Alignment.centerRight,
                _anim.value,
              )!,
              child: Container(
                width: _knob,
                height: _knob,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      spreadRadius: 0,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// §6.4.5  QuantumSettingsRow
// =============================================================================

/// iOS-style grouped list row with leading icon, title, trailing chevron
/// or toggle.
class QuantumSettingsRow extends StatelessWidget {
  const QuantumSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.toggleValue,
    this.onToggleChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// If non-null, shows a [QuantumToggle] on the trailing side instead of a
  /// chevron.
  final bool? toggleValue;
  final ValueChanged<bool>? onToggleChanged;

  @override
  Widget build(BuildContext context) {
    final hasToggle = toggleValue != null && onToggleChanged != null;
    final hasTrailing = trailing != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(QuantumPalette.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: QuantumPalette.spaceMd,
          vertical: QuantumPalette.spaceSm,
        ),
        child: Row(
          children: [
            // Leading icon (24×24, RGB gradient on tap)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: QuantumPalette.bgElevated,
                border: Border.fromBorderSide(
                  const BorderSide(color: QuantumPalette.borderSubtle),
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: QuantumPalette.textSecondary,
              ),
            ),
            const SizedBox(width: QuantumPalette.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: QuantumPalette.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: QuantumPalette.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hasToggle)
              QuantumToggle(
                value: toggleValue!,
                onChanged: onToggleChanged!,
              )
            else if (hasTrailing)
              trailing!
            else
              const Icon(
                Icons.chevron_right,
                color: QuantumPalette.textTertiary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// §6.4.6  QuantumResilienceChain
// =============================================================================

enum QuantumResilienceStepState { active, failed, idle }

class QuantumResilienceStep {
  const QuantumResilienceStep({
    required this.id,
    required this.label,
    required this.state,
  });

  final String id;
  final String label;
  final QuantumResilienceStepState state;
}

/// 8-step horizontal flowchart per §6.4.6:
/// PrimaryTransport → ChineseCdnWorker → P2pLibp2pRelay → DohTunnel →
/// IcmpTunnel → MeshNetwork → TorBridgeSnowflake → TorBridgeMeek.
///
/// Each step is a pill that lights up RGB when active, dims when failed.
class QuantumResilienceChain extends StatelessWidget {
  const QuantumResilienceChain({
    super.key,
    required this.steps,
    this.locale = 'en',
  });

  final List<QuantumResilienceStep> steps;

  /// UI locale (`'en'` / `'fa'`) — selects label language.
  final String locale;

  /// Default 8-step chain per §6.4.6 (caller can override the labels).
  static List<QuantumResilienceStep> defaultChain({
    QuantumResilienceStepState Function(int idx) stateOf = _allIdle,
  }) {
    const ids = [
      'PrimaryTransport',
      'ChineseCdnWorker',
      'P2pLibp2pRelay',
      'DohTunnel',
      'IcmpTunnel',
      'MeshNetwork',
      'TorBridgeSnowflake',
      'TorBridgeMeek',
    ];
    return List.generate(8, (i) => QuantumResilienceStep(
      id: ids[i],
      label: ids[i],
      state: stateOf(i),
    ));
  }

  static QuantumResilienceStepState _allIdle(int _) =>
      QuantumResilienceStepState.idle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: QuantumPalette.spaceLg),
        itemCount: steps.length,
        separatorBuilder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.arrow_forward_ios,
            size: 10,
            color: QuantumPalette.textTertiary,
          ),
        ),
        itemBuilder: (context, i) {
          final step = steps[i];
          return _ResiliencePill(step: step);
        },
      ),
    );
  }
}

class _ResiliencePill extends StatelessWidget {
  const _ResiliencePill({required this.step});

  final QuantumResilienceStep step;

  @override
  Widget build(BuildContext context) {
    Color accent;
    Color textColor;
    double backgroundOpacity;
    switch (step.state) {
      case QuantumResilienceStepState.active:
        accent = QuantumPalette.rgbAccent3[0];
        textColor = QuantumPalette.textPrimary;
        backgroundOpacity = 0.8;
        break;
      case QuantumResilienceStepState.failed:
        accent = QuantumPalette.statusDisconnected;
        textColor = QuantumPalette.textTertiary;
        backgroundOpacity = 0.4;
        break;
      case QuantumResilienceStepState.idle:
        accent = QuantumPalette.borderSubtle;
        textColor = QuantumPalette.textTertiary;
        backgroundOpacity = 0.3;
        break;
    }
    return QuantumGlassPill(
      padding: const EdgeInsets.symmetric(
        horizontal: QuantumPalette.spaceMd,
        vertical: QuantumPalette.spaceXs,
      ),
      borderColor: accent,
      borderWidth: step.state == QuantumResilienceStepState.active ? 1.5 : 1,
      backgroundOpacity: backgroundOpacity,
      boxShadow: step.state == QuantumResilienceStepState.active
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : null,
      child: Text(
        step.label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: step.state == QuantumResilienceStepState.active
              ? FontWeight.w700
              : FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

// =============================================================================
// §6.4.7  QuantumAIAssistantSheet
// =============================================================================

class QuantumAIMessage {
  const QuantumAIMessage({
    required this.role,
    required this.text,
    this.isStreaming = false,
  });

  final String role; // 'user' or 'ai'
  final String text;
  final bool isStreaming;
}

/// 70% screen-height sheet with greeting, conversation list, text input + mic.
class QuantumAIAssistantSheet extends StatefulWidget {
  const QuantumAIAssistantSheet({
    super.key,
    required this.messages,
    required this.onSend,
    this.onMicTap,
    this.suggestedPrompts = const [
      'Why is my connection slow?',
      'Which transport is best for MCI?',
      'Run a DPI test',
      'How long until my license expires?',
    ],
    this.locale = 'en',
  });

  final List<QuantumAIMessage> messages;
  final void Function(String text) onSend;
  final VoidCallback? onMicTap;
  final List<String> suggestedPrompts;
  final String locale;

  @override
  State<QuantumAIAssistantSheet> createState() => _QuantumAIAssistantSheetState();
}

class _QuantumAIAssistantSheetState extends State<QuantumAIAssistantSheet>
    with TickerProviderStateMixin {
  late final AnimationController _in;
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    )..forward();
    _input = TextEditingController();
  }

  @override
  void dispose() {
    _in.dispose();
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;
    return AnimatedBuilder(
      animation: _in,
      builder: (context, child) {
        return FadeTransition(
          opacity: QuantumTransitions.fadeIn(_in),
          child: SlideTransition(
            position: QuantumTransitions.slideUp(_in),
            child: ScaleTransition(
              scale: QuantumTransitions.scaleIn(_in),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        height: height,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: QuantumGlassModal(
          padding: const EdgeInsets.all(QuantumPalette.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Greeting
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: QuantumPalette.rgbAccent3,
                ).createShader(rect),
                child: Text(
                  widget.locale == 'fa'
                      ? 'سلام، من Shield AI هستم'
                      : "Hi, I'm Shield AI",
                  style: QuantumTypography.display2For(widget.locale).copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: QuantumPalette.spaceLg),
              // Conversation
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  itemCount: widget.messages.length,
                  itemBuilder: (context, i) {
                    final m = widget.messages[widget.messages.length - 1 - i];
                    final isUser = m.role == 'user';
                    return _MessageBubble(message: m, isUser: isUser);
                  },
                ),
              ),
              // Suggested prompts
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.suggestedPrompts.length,
                  separatorBuilder: (context, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = widget.suggestedPrompts[i];
                    return ActionChip(
                      label: Text(
                        p,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: QuantumPalette.textPrimary,
                        ),
                      ),
                      backgroundColor: QuantumPalette.bgSurface,
                      side: const BorderSide(color: QuantumPalette.borderSubtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          QuantumPalette.radiusButton,
                        ),
                      ),
                      onPressed: () => widget.onSend(p),
                    );
                  },
                ),
              ),
              const SizedBox(height: QuantumPalette.spaceSm),
              // Input + mic
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: QuantumPalette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.locale == 'fa'
                            ? 'پیام بنویسید…'
                            : 'Type a message…',
                        hintStyle: const TextStyle(
                          color: QuantumPalette.textTertiary,
                        ),
                        filled: true,
                        fillColor: QuantumPalette.bgSurface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: QuantumPalette.spaceMd,
                          vertical: QuantumPalette.spaceSm,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            QuantumPalette.radiusInput,
                          ),
                          borderSide: const BorderSide(
                            color: QuantumPalette.borderSubtle,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            QuantumPalette.radiusInput,
                          ),
                          borderSide: const BorderSide(
                            color: QuantumPalette.borderSubtle,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: QuantumPalette.spaceXs),
                  if (widget.onMicTap != null)
                    GestureDetector(
                      onTap: widget.onMicTap,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: QuantumPalette.rgbAccent3,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: QuantumPalette.rgbAccent3[0]
                                  .withValues(alpha: 0.4),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  const SizedBox(width: QuantumPalette.spaceXs),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: QuantumPalette.bgElevated,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          const BorderSide(color: QuantumPalette.borderSubtle),
                        ),
                      ),
                      child: const Icon(
                        Icons.send,
                        color: QuantumPalette.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isUser});

  final QuantumAIMessage message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(
          horizontal: QuantumPalette.spaceMd,
          vertical: QuantumPalette.spaceSm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? QuantumPalette.bgSurface
              : QuantumPalette.bgElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(QuantumPalette.radiusCard),
            topRight: const Radius.circular(QuantumPalette.radiusCard),
            bottomLeft: Radius.circular(isUser ? QuantumPalette.radiusCard : 4),
            bottomRight: Radius.circular(isUser ? 4 : QuantumPalette.radiusCard),
          ),
          border: isUser
              ? null
              : Border.fromBorderSide(
                  BorderSide(
                    color: QuantumPalette.rgbAccent3[0].withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
        ),
        child: Text(
          message.text + (message.isStreaming ? '▌' : ''),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: QuantumPalette.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
