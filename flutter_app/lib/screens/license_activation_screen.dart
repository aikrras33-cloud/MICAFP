// =============================================================================
// license_activation_screen.dart — Quantum Enterprise RGB license activation
//
// Per §8.5:
//   - Big RGB gradient title "Activate Enterprise License"
//   - Form fields: Serial Number (auto-uppercase, auto-dash every 5 chars),
//     Organization Name
//   - "Validate" button (glassmorphic, RGB gradient)
//   - On validate: call `daemon.validateLicense(serial, org)` → daemon
//     recomputes signature, checks against embedded public key, returns
//     `{valid: bool, expiry_ms: i64, tier: String}`.
//   - If valid: save to secure storage, navigate to home screen, show
//     success toast "License activated. Expires in {X} days."
//   - If invalid: show error "License is invalid or tampered." and shake the
//     form fields.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vibration/vibration.dart';

import '../services/daemon_bridge.dart';
import '../theme/quantum_components.dart';
import '../theme/quantum_glassmorphism.dart';
import '../theme/quantum_theme.dart';

class LicenseActivationScreen extends StatefulWidget {
  const LicenseActivationScreen({
    super.key,
    required this.onActivated,
    this.locale = 'en',
  });

  /// Called after a successful activation. Typically navigates to home.
  final VoidCallback onActivated;
  final String locale;

  @override
  State<LicenseActivationScreen> createState() =>
      _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen>
    with TickerProviderStateMixin {
  static final _secureStorage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  );

  final _serialController = TextEditingController();
  final _orgController = TextEditingController();
  final _serialFocus = FocusNode();
  final _orgFocus = FocusNode();

  late final AnimationController _shake;
  late final AnimationController _loading;
  late final AnimationController _success;

  bool _isValidating = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    );
    _loading = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _success = AnimationController(
      vsync: this,
      duration: QuantumDurations.slow,
    );
  }

  @override
  void dispose() {
    _serialController.dispose();
    _orgController.dispose();
    _serialFocus.dispose();
    _orgFocus.dispose();
    _shake.dispose();
    _loading.dispose();
    _success.dispose();
    super.dispose();
  }

  /// Auto-uppercase + auto-dash every 5 chars.
  /// Example: "MICAFPRGBENTULTRA2025" → "MICAF-PRGBE-NTULT-RA202-5"
  String _formatSerial(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      if (i > 0 && i % 5 == 0) {
        buffer.write('-');
      }
      buffer.write(cleaned[i]);
    }
    return buffer.toString();
  }

  void _onSerialChanged(String value) {
    final formatted = _formatSerial(value);
    if (formatted != value) {
      _serialController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    if (_hasError) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });
    }
  }

  Future<void> _vibrate(int ms) async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: ms);
    }
  }

  Future<void> _validate() async {
    if (_isValidating) return;

    final serial = _serialController.text.trim();
    final org = _orgController.text.trim();
    if (serial.isEmpty || org.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = widget.locale == 'fa'
            ? 'لطفاً همه فیلدها را پر کنید'
            : 'Please fill in all fields.';
      });
      _shake.forward(from: 0);
      _vibrate(50);
      return;
    }

    setState(() {
      _isValidating = true;
      _hasError = false;
      _errorMessage = null;
    });
    _loading.repeat();

    final bridge = DaemonBridge();
    try {
      final result = await bridge.validateLicense(
        serial: serial,
        organization: org,
      );
      _loading.stop();
      // Defensive null-safe access — daemon may return either
      // `{valid: true, expiry_ms: int, tier: String}` on success or
      // `{valid: false, reason: String}` on failure.
      final isValid = result['valid'] == true;
      if (!isValid) {
        throw DaemonException(
          message: result['reason'] as String? ??
              'License is invalid or tampered.',
          code: 'LICENSE_INVALID',
        );
      }
      // Success path: persist to flutter_secure_storage per §8.5 + §8.8.
      // All four fields are written atomically so the post-activation flow
      // (home screen reads them via getLicenseInfo()) sees a consistent
      // state.
      final expiryMs = (result['expiry_ms'] as num?)?.toInt() ?? 0;
      final tier = (result['tier'] as String?) ?? '';
      await _secureStorage.write(key: 'license_serial', value: serial);
      await _secureStorage.write(key: 'license_org', value: org);
      await _secureStorage.write(key: 'license_tier', value: tier);
      await _secureStorage.write(
        key: 'license_expiry_ms',
        value: expiryMs.toString(),
      );
      await _secureStorage.write(key: 'license_activated', value: 'true');

      // Calculate days remaining for the toast.
      final expiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      final days = expiry.difference(DateTime.now()).inDays;

      // Show success state then navigate.
      _success.forward(from: 0);
      QuantumToast.show(
        context,
        message: widget.locale == 'fa'
            ? 'لایسنس فعال شد. ${QuantumTypography.toPersianNumerals(days.toString())} روز باقی مانده.'
            : 'License activated. Expires in $days days.',
        accentColor: QuantumPalette.statusConnected,
        icon: Icons.verified_user,
      );
      _vibrate(30);
      // Allow the toast to be visible for ~1.5s before navigating.
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        widget.onActivated();
      }
    } on DaemonException catch (e) {
      _loading.stop();
      setState(() {
        _isValidating = false;
        _hasError = true;
        _errorMessage = e.message;
      });
      _shake.forward(from: 0);
      _vibrate(100);
    } on PlatformException catch (e) {
      _loading.stop();
      setState(() {
        _isValidating = false;
        _hasError = true;
        _errorMessage = e.message ?? 'License is invalid or tampered.';
      });
      _shake.forward(from: 0);
      _vibrate(100);
    } catch (e) {
      _loading.stop();
      setState(() {
        _isValidating = false;
        _hasError = true;
        _errorMessage = 'License is invalid or tampered.';
      });
      _shake.forward(from: 0);
      _vibrate(100);
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Aurora background
          const QuantumAuroraBackground(),
          // Body
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: QuantumPalette.spaceXl,
                    vertical: QuantumPalette.spaceSection,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight -
                          (QuantumPalette.spaceSection * 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Big RGB gradient title
                        ShaderMask(
                          shaderCallback: (rect) =>
                              QuantumGradients.animatedRgbRing().createShader(rect),
                          child: Text(
                            locale == 'fa'
                                ? 'فعال‌سازی لایسنس Enterprise'
                                : 'Activate Enterprise License',
                            style: QuantumTypography.display1For(locale)
                                .copyWith(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: QuantumPalette.spaceMd),
                        Text(
                          locale == 'fa'
                              ? 'شماره سریال و نام سازمان خود را وارد کنید'
                              : 'Enter your serial number and organization name.',
                          style: QuantumTypography.body2For(locale).copyWith(
                            color: QuantumPalette.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: QuantumPalette.spaceSection),
                        // Form card
                        AnimatedBuilder(
                          animation: _shake,
                          builder: (context, child) {
                            final dx = math.sin(_shake.value * math.pi * 6) *
                                8 *
                                (1 - _shake.value);
                            return Transform.translate(
                              offset: Offset(dx, 0),
                              child: child,
                            );
                          },
                          child: QuantumGlassCard(
                            padding: const EdgeInsets.all(
                              QuantumPalette.spaceLg,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _QuantumField(
                                  label: locale == 'fa'
                                      ? 'شماره سریال'
                                      : 'Serial Number',
                                  hint: 'MICAF-PRGBE-NTULT-RA202-5',
                                  controller: _serialController,
                                  focusNode: _serialFocus,
                                  onChanged: _onSerialChanged,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9-]'),
                                    ),
                                  ],
                                  errorText: _hasError ? '' : null,
                                  prefixIcon: Icons.vpn_key,
                                ),
                                const SizedBox(height: QuantumPalette.spaceMd),
                                _QuantumField(
                                  label: locale == 'fa'
                                      ? 'نام سازمان'
                                      : 'Organization Name',
                                  hint: locale == 'fa'
                                      ? 'سازمان VIP Enterprise'
                                      : 'Enterprise VIP User',
                                  controller: _orgController,
                                  focusNode: _orgFocus,
                                  errorText: _hasError ? '' : null,
                                  prefixIcon: Icons.business,
                                  textCapitalization:
                                      TextCapitalization.words,
                                ),
                                if (_hasError && _errorMessage != null) ...[
                                  const SizedBox(height: QuantumPalette.spaceSm),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: QuantumPalette.statusError,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 13,
                                            color: QuantumPalette.statusError,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: QuantumPalette.spaceLg),
                                // Validate button
                                _QuantumValidateButton(
                                  loading: _isValidating,
                                  loadingController: _loading,
                                  successController: _success,
                                  onPressed: _validate,
                                  label: locale == 'fa'
                                      ? 'اعتبارسنجی'
                                      : 'Validate',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: QuantumPalette.spaceSection),
                        // Anti-tamper footer
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.lock,
                              size: 12,
                              color: QuantumPalette.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              locale == 'fa'
                                  ? 'اعتبارسنجی ۱۰۰٪ محلی — بدون تماس با سرور'
                                  : 'Validation 100% local — no phone-home to a server.',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: QuantumPalette.textTertiary,
                                letterSpacing: 0.04,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Private helper widgets
// -----------------------------------------------------------------------------

class _QuantumField extends StatelessWidget {
  const _QuantumField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.prefixIcon,
    this.onChanged,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final IconData prefixIcon;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.04,
            color: QuantumPalette.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 14,
            color: QuantumPalette.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            hintStyle: const TextStyle(
              color: QuantumPalette.textTertiary,
              fontFamily: 'JetBrains Mono',
              fontSize: 14,
            ),
            filled: true,
            fillColor: QuantumPalette.bgSurface,
            prefixIcon: Icon(prefixIcon, color: QuantumPalette.textSecondary),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: QuantumPalette.spaceMd,
              vertical: QuantumPalette.spaceMd,
            ),
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
              borderSide: const BorderSide(
                color: QuantumPalette.borderFocused,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
              borderSide: const BorderSide(
                color: QuantumPalette.statusError,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(QuantumPalette.radiusInput),
              borderSide: BorderSide(
                color: QuantumPalette.statusError,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuantumValidateButton extends StatelessWidget {
  const _QuantumValidateButton({
    required this.loading,
    required this.loadingController,
    required this.successController,
    required this.onPressed,
    required this.label,
  });

  final bool loading;
  final AnimationController loadingController;
  final AnimationController successController;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onPressed,
      child: AnimatedBuilder(
        animation: Listenable.merge([loadingController, successController]),
        builder: (context, child) {
          return Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
              gradient: const LinearGradient(
                colors: QuantumPalette.rgbAccent3,
              ),
              boxShadow: [
                BoxShadow(
                  color: QuantumPalette.rgbAccent3[0]
                      .withValues(alpha: 0.4 + successController.value * 0.4),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (loading)
                  const Center(
                    child: QuantumSpinner(size: 22, strokeWidth: 2.5),
                  )
                else
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (successController.value > 0.1)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Opacity(
                              opacity: successController.value,
                              child: const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.01,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// At end of file — `math` is imported at top for the shake animation.
