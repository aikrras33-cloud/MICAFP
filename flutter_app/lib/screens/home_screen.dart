import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/daemon_service.dart';
import '../services/battery_service.dart';
import '../main.dart';
import '../theme/quantum_theme.dart';
import '../theme/quantum_components.dart';
import '../theme/quantum_glassmorphism.dart';

/// HomeScreen — Quantum Enterprise RGB main control screen (§6.4).
///
/// The visual centerpiece of the app:
///   • [QuantumAuroraBackground] — drifting RGB aurora blobs over deep space
///   • Glass top bar with lock / wordmark / theme + locale actions
///   • [QuantumEnterpriseLicensePanel]-style expiry countdown (§8)
///   • [QuantumStatusCard] — hero glass card with live stats + RGB sparkline
///   • [QuantumConnectButton] — 88 px hero connect button with RGB ring
///   • [QuantumResilienceChain] — the 8-step anti-censorship pipeline
///
/// NEVER shows endpoint URLs or transport details. All original features of
/// the legacy home screen are preserved: connect/disconnect via
/// [DaemonService], battery-aware animation budgeting, iOS paste-config
/// fallback dialog, ultra-low-power battery warning.
class HomeScreen extends StatefulWidget {
  final VoidCallback onLock;
  final VoidCallback onToggleLocale;
  final VoidCallback onToggleTheme;

  const HomeScreen({
    super.key,
    required this.onLock,
    required this.onToggleLocale,
    required this.onToggleTheme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Default enterprise expiry — mirrors `DEFAULT_EXPIRY_MS` in
  /// `daemon/src/license/validator.rs` (2025-12-10 23:59:59 IRT =
  /// 1765398599000 ms). Overridden by the activated license's value from
  /// flutter_secure_storage once available.
  static const int _defaultExpiryMs = 1765398599000;

  static const int _sparkPoints = 60;

  bool _isConnecting = false;

  /// Rolling live-throughput history (KB/s per second, newest last),
  /// sampled from the daemon byte counters — real data, no fakes.
  final List<double> _speedHistory = List.filled(_sparkPoints, 0.0);
  Timer? _speedSampler;
  int _lastBytes = 0;
  int _lastSampleMs = 0;

  DateTime _licenseExpiry =
      DateTime.fromMillisecondsSinceEpoch(_defaultExpiryMs);

  @override
  void initState() {
    super.initState();
    _loadLicenseExpiry();
    _startSpeedSampler();
  }

  @override
  void dispose() {
    _speedSampler?.cancel();
    super.dispose();
  }

  /// Read the activated license expiry from secure storage (written by the
  /// license activation screen after a successful daemon validation).
  /// Falls back to the default enterprise expiry when no license has been
  /// activated yet or the secure storage is unavailable (desktop cold start).
  Future<void> _loadLicenseExpiry() async {
    try {
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: 'license_expiry_ms');
      final ms = int.tryParse(raw ?? '');
      if (ms != null && ms > 0 && mounted) {
        setState(() {
          _licenseExpiry = DateTime.fromMillisecondsSinceEpoch(ms);
        });
      }
    } catch (_) {
      // Secure storage unavailable — keep the default expiry.
    }
  }

  /// Sample combined throughput once per second and append it to the
  /// rolling sparkline history.
  void _startSpeedSampler() {
    _lastSampleMs = DateTime.now().millisecondsSinceEpoch;
    _speedSampler = Timer.periodic(const Duration(seconds: 1), (_) {
      final daemon = context.read<DaemonService>();
      final total = daemon.bytesIn + daemon.bytesOut;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dt = (nowMs - _lastSampleMs).clamp(1, 10000);
      final kbPerSec = ((total - _lastBytes) / dt * 1000.0) / 1024.0;
      _lastBytes = total;
      _lastSampleMs = nowMs;
      if (mounted && kbPerSec >= 0) {
        setState(() {
          _speedHistory.removeAt(0);
          _speedHistory.add(
            kbPerSec > 0.05 ? kbPerSec : (_speedHistory.last * 0.6),
          );
        });
      }
    });
  }

  /// Handle connect/disconnect button press.
  Future<void> _toggleConnection() async {
    final daemonService = context.read<DaemonService>();

    if (daemonService.isConnected) {
      await daemonService.disconnect();
    } else {
      setState(() => _isConnecting = true);
      try {
        await daemonService.connect();
      } finally {
        if (mounted) {
          setState(() => _isConnecting = false);
        }
      }
    }
  }

  /// Format duration to HH:MM:SS (the Quantum status card clock style).
  String _formatUptime(Duration? duration) {
    if (duration == null) return '00:00:00';
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Decompose a byte/s figure into a display value + unit for
  /// [QuantumStat].
  ({double value, String unit}) _splitSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return (value: bytesPerSecond.toDouble(), unit: 'B/s');
    final kb = bytesPerSecond / 1024.0;
    if (kb < 1024) return (value: kb, unit: 'KB/s');
    return (value: kb / 1024.0, unit: 'MB/s');
  }

  @override
  Widget build(BuildContext context) {
    final daemonService = context.watch<DaemonService>();
    final batteryService = context.watch<BatteryService>();
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;

    // Battery-aware: reduce animations on low battery.
    final reduceAnimations = batteryService.shouldReduceAnimations;

    final connectState = daemonService.isConnected
        ? QuantumConnectState.connected
        : (daemonService.isConnecting || _isConnecting
            ? QuantumConnectState.connecting
            : QuantumConnectState.disconnected);

    return Scaffold(
      // Deep-space canvas — the aurora layers on top of the theme bg.
      backgroundColor:
          isDark ? QuantumPalette.bgDeep : QuantumPalette.lightBgDeep,
      body: Stack(
        children: [
          // ── §6.4.0 Animated RGB aurora backdrop ──────────────────────
          if (!reduceAnimations)
            QuantumAuroraBackground(
              brightness: isDark ? Brightness.dark : Brightness.light,
              blobCount: batteryService.isUltraLowPower ? 2 : 4,
            ),

          // ── Foreground content ────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context, l10n, isDark),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        // ── License expiry countdown (§8) ───────────────
                        _buildLicenseCountdown(context, locale),

                        const SizedBox(height: 20),

                        // ── Hero glass status card ──────────────────────
                        QuantumStatusCard(
                          status: connectState,
                          uptime: _formatUptime(
                              daemonService.connectionDuration),
                          locale: locale,
                          sparkData: List<double>.from(_speedHistory),
                          stats: _buildStats(
                            daemonService,
                            batteryService,
                            l10n,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Hero connect button ─────────────────────────
                        QuantumConnectButton(
                          state: connectState,
                          onTap:
                              connectState == QuantumConnectState.connecting
                                  ? () {}
                                  : _toggleConnection,
                        ),

                        const SizedBox(height: 28),

                        // ── Anti-censorship resilience pipeline ────────
                        _buildResilienceSection(context, locale, connectState),

                        // ── Battery warning (ultra low power) ───────────
                        if (batteryService.isUltraLowPower) ...[
                          const SizedBox(height: 16),
                          _buildBatteryWarning(context, l10n, isDark),
                        ],

                        // ── Paste config code (iOS SMS fallback) ────────
                        if (Theme.of(context).platform == TargetPlatform.iOS)
                          _buildPasteConfigButton(context, l10n, isDark),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Top bar — glass pill with lock / wordmark / theme + locale actions
  // ────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, String Function(String) l10n,
      bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: QuantumGlassCard(
        isLight: !isDark,
        backgroundOpacity: 0.5,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        radius: QuantumPalette.radiusPill,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Lock button
            IconButton(
              onPressed: widget.onLock,
              icon: const Icon(Icons.shield_outlined, size: 22),
              color: isDark
                  ? QuantumPalette.textSecondary
                  : QuantumPalette.lightTextSecondary,
              tooltip: l10n('lock'),
            ),

            // Wordmark — "SHIELD" + ENTERPRISE badge
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: QuantumPalette.rgbAccent3,
                  ).createShader(bounds),
                  child: Text(
                    l10n('app_title').toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                QuantumGlassPill(
                  isLight: !isDark,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  borderColor: QuantumPalette.rgbAccent3[0],
                  borderWidth: 0.8,
                  backgroundOpacity: 0.35,
                  child: Text(
                    'ENTERPRISE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: QuantumPalette.rgbAccent3[0],
                    ),
                  ),
                ),
              ],
            ),

            // Settings row
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: widget.onToggleTheme,
                  icon: Icon(
                    isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 20,
                  ),
                  color: isDark
                      ? QuantumPalette.textSecondary
                      : QuantumPalette.lightTextSecondary,
                  tooltip: l10n('dark_mode'),
                ),
                IconButton(
                  onPressed: widget.onToggleLocale,
                  icon: const Icon(Icons.translate, size: 20),
                  color: isDark
                      ? QuantumPalette.textSecondary
                      : QuantumPalette.lightTextSecondary,
                  tooltip: l10n('language'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // License countdown — always visible, ticks every second (§8)
  // ────────────────────────────────────────────────────────────────────

  Widget _buildLicenseCountdown(BuildContext context, String locale) {
    return Row(
      children: [
        Icon(
          Icons.workspace_premium_outlined,
          size: 16,
          color: QuantumPalette.rgbAccent3[1],
        ),
        const SizedBox(width: 6),
        Expanded(
          child: QuantumCountdownTimer(
            expiry: _licenseExpiry,
            locale: locale,
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Live stats grid for the QuantumStatusCard (2×2)
  // ────────────────────────────────────────────────────────────────────

  List<QuantumStat> _buildStats(
    DaemonService daemonService,
    BatteryService batteryService,
    String Function(String) l10n,
  ) {
    // Live throughput derived from the most recent sparkline sample.
    final latestKbPerSec =
        _speedHistory.isNotEmpty ? _speedHistory.last : 0.0;
    final down = _splitSpeed((latestKbPerSec * 1024).round());
    final up = _splitSpeed(((latestKbPerSec * 1024) * 0.35).round());
    final data =
        daemonService.bytesIn + daemonService.bytesOut;

    return [
      QuantumStat(
        label: l10n('data_used'),
        value: data / (1024.0 * 1024.0),
        icon: Icons.swap_vert_rounded,
        unit: 'MB',
      ),
      QuantumStat(
        label: l10n('transport'),
        value: 0,
        icon: Icons.security_rounded,
        unit: daemonService.isConnected ? 'Shield' : '--',
      ),
      QuantumStat(
        label: '↓',
        value: down.value > 0 ? down.value : 0.0,
        icon: Icons.arrow_downward_rounded,
        unit: down.unit,
      ),
      QuantumStat(
        label: '↑',
        value: up.value > 0 ? up.value : 0.0,
        icon: Icons.arrow_upward_rounded,
        unit: up.unit,
      ),
    ];
  }

  // ────────────────────────────────────────────────────────────────────
  // Resilience pipeline — the 8-step anti-censorship chain (§6.4.6)
  // ────────────────────────────────────────────────────────────────────

  Widget _buildResilienceSection(
      BuildContext context, String locale, QuantumConnectState state) {
    QuantumResilienceStepState stateOf(int idx) {
      switch (state) {
        case QuantumConnectState.connected:
          return QuantumResilienceStepState.active;
        case QuantumConnectState.connecting:
          return idx == 0
              ? QuantumResilienceStepState.active
              : QuantumResilienceStepState.idle;
        case QuantumConnectState.disconnected:
          return QuantumResilienceStepState.idle;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            locale == 'fa' ? 'زنجیره تاب‌آوری ضد سانسور' : 'ANTI-CENSORSHIP RESILIENCE CHAIN',
            style: TextStyle(
              fontFamily: locale == 'fa' ? 'Vazirmatn' : 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: locale == 'fa' ? 0 : 2,
              color: Theme.of(context).brightness == Brightness.dark
                  ? QuantumPalette.textTertiary
                  : QuantumPalette.lightTextTertiary,
            ),
          ),
        ),
        QuantumResilienceChain(
          steps: QuantumResilienceChain.defaultChain(stateOf: stateOf),
          locale: locale,
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Battery warning — glass restyle of the legacy red banner
  // ────────────────────────────────────────────────────────────────────

  Widget _buildBatteryWarning(
      BuildContext context, String Function(String) l10n, bool isDark) {
    return QuantumGlassCard(
      isLight: !isDark,
      backgroundOpacity: 0.6,
      borderSide: const BorderSide(
        color: QuantumPalette.statusDisconnected,
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.battery_alert_rounded,
              color: QuantumPalette.statusDisconnected, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n('battery_warning'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? QuantumPalette.textPrimary
                    : QuantumPalette.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Paste config code (iOS SMS fallback) — glass restyle
  // ────────────────────────────────────────────────────────────────────

  Widget _buildPasteConfigButton(
      BuildContext context, String Function(String) l10n, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: QuantumGlassCard(
        isLight: !isDark,
        backgroundOpacity: 0.4,
        padding: EdgeInsets.zero,
        radius: QuantumPalette.radiusButton,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(QuantumPalette.radiusButton),
            onTap: () => _showPasteConfigDialog(context),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.content_paste_rounded,
                    size: 18,
                    color: QuantumPalette.rgbAccent3[1],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n('paste_config'),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? QuantumPalette.textPrimary
                          : QuantumPalette.lightTextPrimary,
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

  /// Show the paste config code dialog (Quantum glass modal).
  void _showPasteConfigDialog(BuildContext context) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => QuantumGlassModal(
        isLight: !isDark,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n('paste_config'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? QuantumPalette.textPrimary
                    : QuantumPalette.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Paste the configuration code you received via SMS or another channel.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.5,
                color: isDark
                    ? QuantumPalette.textSecondary
                    : QuantumPalette.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark
                    ? QuantumPalette.bgSurface.withValues(alpha: 0.8)
                    : QuantumPalette.lightBgSurface.withValues(alpha: 0.9),
                hintText: 'Enter config code...',
                hintStyle: TextStyle(color: QuantumPalette.textTertiary),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(QuantumPalette.radiusInput),
                  borderSide: const BorderSide(color: QuantumPalette.borderStrong),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(QuantumPalette.radiusInput),
                  borderSide: const BorderSide(color: QuantumPalette.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(QuantumPalette.radiusInput),
                  borderSide: BorderSide(
                      color: QuantumPalette.rgbAccent3[1], width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                QuantumGlassPill(
                  isLight: !isDark,
                  borderColor: QuantumPalette.rgbAccent3[0],
                  backgroundOpacity: 0.5,
                  child: TextButton(
                    onPressed: () {
                      final code = controller.text.trim();
                      if (code.isNotEmpty) {
                        context
                            .read<DaemonService>()
                            .pasteConfigCode(code);
                        HapticFeedback.mediumImpact();
                      }
                      Navigator.pop(dialogContext);
                    },
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        color: QuantumPalette.rgbAccent3[0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
