import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// National Intranet Mode service.
///
/// When Iran's internet is under severe restrictions or total shutdown,
/// this mode allows access to approved national services while
/// maintaining security and privacy.
///
/// Features:
/// - Whitelist-based domain access (Iranian banks, government, education)
/// - DNS-over-HTTPS for domestic resolvers
/// - Automatic detection of national intranet mode
/// - Fallback to P2P relay for critical external services
/// - Emergency contacts and information access
///
/// Ported from `flutter/lib/services/intranet_service.dart` per directive §3.5.
/// Adaptations:
///   - Riverpod import + provider declarations stripped (directive §3.22
///     drops riverpod). IntranetService is now a plain Dart class; wire
///     it into the widget tree via `Provider<IntranetService>.value(...)`
///     in `main.dart`'s MultiProvider.
///   - Legacy `flutter/` DaemonService methods `enableIntranetMode`,
///     `disableIntranetMode`, and `sendCommand` are NOT exposed on the
///     canonical `flutter_app` DaemonService (which uses narrower
///     MethodChannel primitives). IntranetService now talks to the
///     `com.unifiedshield.daemon` MethodChannel directly via its own
///     private `_channel`, mirroring the canonical DaemonService pattern.
class IntranetService {
  static final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  static const MethodChannel _channel = MethodChannel('com.unifiedshield.daemon');

  bool _intranetModeActive = false;
  IntranetMode _mode = IntranetMode.disabled;
  List<String> _accessibleDomains = [];

  bool get isIntranetModeActive => _intranetModeActive;
  IntranetMode get mode => _mode;
  List<String> get accessibleDomains => _accessibleDomains;

  /// Pre-defined categories of national services
  static const Map<String, List<String>> nationalCategories = {
    'banking': [
      'bmi.ir', 'bankmellat.ir', 'sb24.ir', 'pec.ir',
      'shaparak.ir', 'sep.ir', 'parsian-bank.ir',
    ],
    'government': [
      'dolat.ir', 'irancell.ir', 'mci.ir', 'post.ir',
      'ssaa.ir', 'dastyar.ir',
    ],
    'education': [
      'ac.ir', 'edu.ir', 'sut.ac.ir', 'ut.ac.ir',
      'sharif.edu', 'iust.ac.ir', 'tehran.ir',
    ],
    'health': [
      'tamin.ir', 'fda.ir', 'behdasht.gov.ir',
    ],
    'news': [
      'isna.ir', 'irna.ir', 'mehrnews.com', 'tasnimnews.com',
    ],
    'essential': [
      'digikala.com', 'snapp.ir', 'esam.ir', 'divar.ir',
    ],
  };

  /// Enable national intranet mode
  Future<void> enable({
    IntranetMode mode = IntranetMode.smart,
    List<String>? customDomains,
    bool blockAllExternal = false,
    bool enableP2PFallback = true,
  }) async {
    try {
      _log.i('Enabling national intranet mode: $mode');

      final domains = customDomains ?? _getDefaultDomains(mode);

      await _channel.invokeMethod<void>('enableIntranetMode', {
        'allowed_domains': domains,
        'block_all_external': blockAllExternal,
      });

      // Enable P2P fallback for critical services
      if (enableP2PFallback) {
        await _channel.invokeMethod<void>('sendCommand', {
          'method': 'p2p.fallback_enable',
          'params': {
            'critical_services': ['signal.org', 'telegram.org', 'whatsapp.com'],
          },
        });
      }

      _intranetModeActive = true;
      _mode = mode;
      _accessibleDomains = domains;

      _log.i('National intranet mode enabled with ${domains.length} domains');
    } on PlatformException catch (e) {
      _log.e('Failed to enable intranet mode: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Disable national intranet mode
  Future<void> disable() async {
    try {
      _log.i('Disabling national intranet mode');
      await _channel.invokeMethod<void>('disableIntranetMode');
      _intranetModeActive = false;
      _mode = IntranetMode.disabled;
      _accessibleDomains = [];
    } on PlatformException catch (e) {
      _log.e('Failed to disable intranet mode: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Auto-detect if national intranet mode should be activated
  Future<bool> autoDetect() async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'intranet.detect',
        'params': <String, dynamic>{},
      });
      if (response == null) return false;

      final shouldActivate = response['should_activate'] as bool? ?? false;
      final detectedMode = response['detected_mode'] as String? ?? 'disabled';

      if (shouldActivate) {
        _log.w('National intranet conditions detected! Activating...');
        await enable(
          mode: IntranetMode.values.firstWhere(
            (m) => m.name == detectedMode,
            orElse: () => IntranetMode.smart,
          ),
        );
      }

      return shouldActivate;
    } on PlatformException catch (e) {
      _log.e('Auto-detection failed: ${e.message}', error: e);
      return false;
    }
  }

  /// Get current intranet mode status
  Future<IntranetStatus> getStatus() async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'intranet.status',
        'params': <String, dynamic>{},
      });
      if (response == null) {
        return const IntranetStatus(mode: IntranetMode.disabled);
      }
      return IntranetStatus.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (e) {
      _log.e('Failed to get intranet status', error: e);
      return const IntranetStatus(mode: IntranetMode.disabled);
    }
  }

  /// Add a domain to the whitelist
  Future<void> addDomain(String domain) async {
    try {
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'intranet.add_domain',
        'params': {'domain': domain},
      });
      _accessibleDomains.add(domain);
    } on PlatformException catch (e) {
      _log.e('Failed to add domain $domain: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Remove a domain from the whitelist
  Future<void> removeDomain(String domain) async {
    try {
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'intranet.remove_domain',
        'params': {'domain': domain},
      });
      _accessibleDomains.remove(domain);
    } on PlatformException catch (e) {
      _log.e('Failed to remove domain $domain: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Get the emergency information page
  Future<Map<String, dynamic>> getEmergencyInfo() async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'intranet.emergency_info',
        'params': <String, dynamic>{},
      });
      if (response == null) {
        return {
          'emergency_numbers': ['110', '115', '125', '112'],
          'information_urls': [],
        };
      }
      return Map<String, dynamic>.from(response);
    } catch (e) {
      _log.e('Failed to get emergency info', error: e);
      return {
        'emergency_numbers': ['110', '115', '125', '112'],
        'information_urls': [],
      };
    }
  }

  List<String> _getDefaultDomains(IntranetMode mode) {
    switch (mode) {
      case IntranetMode.disabled:
        return [];
      case IntranetMode.essential:
        return [
          ...nationalCategories['banking']!,
          ...nationalCategories['government']!,
          ...nationalCategories['health']!,
        ];
      case IntranetMode.smart:
        return nationalCategories.values.expand((e) => e).toList();
      case IntranetMode.full:
        return ['*.ir']; // All .ir domains
    }
  }
}

/// Intranet mode enum
enum IntranetMode {
  disabled,
  essential,  // Only banking, government, health
  smart,      // All national services + P2P fallback
  full,       // All .ir domains
}

/// Intranet status model
class IntranetStatus {
  final IntranetMode mode;
  final List<String> accessibleDomains;
  final bool p2pFallbackActive;
  final DateTime? activatedAt;
  final int blockedConnections;
  final int allowedConnections;

  const IntranetStatus({
    this.mode = IntranetMode.disabled,
    this.accessibleDomains = const [],
    this.p2pFallbackActive = false,
    this.activatedAt,
    this.blockedConnections = 0,
    this.allowedConnections = 0,
  });

  factory IntranetStatus.fromJson(Map<String, dynamic> json) {
    return IntranetStatus(
      mode: IntranetMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => IntranetMode.disabled,
      ),
      accessibleDomains: (json['accessible_domains'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      p2pFallbackActive: json['p2p_fallback_active'] as bool? ?? false,
      activatedAt: json['activated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['activated_at'] as int)
          : null,
      blockedConnections: json['blocked_connections'] as int? ?? 0,
      allowedConnections: json['allowed_connections'] as int? ?? 0,
    );
  }
}
