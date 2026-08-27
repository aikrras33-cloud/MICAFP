import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

class DaemonBridge {
  static const MethodChannel _channel = MethodChannel('com.unifiedshield/daemon');
  static const MethodChannel _licenseChannel =
      MethodChannel('com.unifiedshield/license');
  static const EventChannel _statusChannel = EventChannel('com.unifiedshield/status');

  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _statusSubscription;
  bool _initialized = false;

  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _statusSubscription = _statusChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          try {
            _statusController.add(jsonDecode(event) as Map<String, dynamic>);
          } catch (_) {
            _statusController.add({'raw': event});
          }
        } else if (event is Map) {
          _statusController.add(Map<String, dynamic>.from(event));
        }
      },
      onError: (dynamic error) {
        _statusController.add({
          'error': true,
          'message': error.toString(),
        });
      },
    );
  }

  Future<void> startDaemon({
    required String coreId,
    String? obfuscationMode,
  }) async {
    init();
    try {
      await _channel.invokeMethod<void>('startDaemon', {
        'core_id': coreId,
        'obfuscation_mode': obfuscationMode ?? 'default',
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to start daemon',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> stopDaemon() async {
    try {
      await _channel.invokeMethod<void>('stopDaemon');
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to stop daemon',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStatus');
      if (result == null) {
        return {'status': 'unknown'};
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to get status',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> switchCore(String coreId) async {
    try {
      await _channel.invokeMethod<void>('switchCore', {
        'core_id': coreId,
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to switch core',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> updateReward({
    required String peerId,
    required int bytesRelayed,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateReward', {
        'peer_id': peerId,
        'bytes_relayed': bytesRelayed,
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to update reward',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> setKillSwitch(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKillSwitch', {
        'enabled': enabled,
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to set kill switch',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> triggerObfuscationMode(String mode) async {
    try {
      await _channel.invokeMethod<void>('triggerObfuscationMode', {
        'mode': mode,
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to trigger obfuscation mode',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> configureSplitTunneling({
    required List<String> excludedApps,
    required bool excludeIranianIps,
  }) async {
    try {
      await _channel.invokeMethod<void>('configureSplitTunneling', {
        'excluded_apps': excludedApps,
        'exclude_iranian_ips': excludeIranianIps,
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to configure split tunneling',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableCores() async {
    try {
      final result = await _channel.invokeMethod<List>('getAvailableCores');
      if (result == null) return [];
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to get available cores',
        code: e.code,
        details: e.details,
      );
    }
  }

  Future<void> reportIsp(String ispName, String? asn) async {
    try {
      await _channel.invokeMethod<void>('reportIsp', {
        'isp_name': ispName,
        'asn': asn ?? '',
      });
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to report ISP',
        code: e.code,
        details: e.details,
      );
    }
  }

  /// Validates an enterprise license against the daemon's locally embedded
  /// public key + SHA-256 signature. Returns the daemon's response map:
  ///   `{valid: bool, expiry_ms: int, tier: String}` on success,
  ///   `{valid: false, reason: String}` on failure.
  ///
  /// Per §8.5 + §8.8 — implemented in Rust via FFI (`validate_license`),
  /// surfaced via the `com.unifiedshield/license` MethodChannel.
  Future<Map<String, dynamic>> validateLicense({
    required String serial,
    required String organization,
  }) async {
    try {
      final result = await _licenseChannel.invokeMethod<Map>('validateLicense', {
        'serial': serial,
        'organization': organization,
      });
      if (result == null) {
        return const {
          'valid': false,
          'reason': 'Daemon returned null response.',
        };
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to validate license',
        code: e.code,
        details: e.details,
      );
    }
  }

  /// Returns the currently-stored license info (or null if not activated).
  ///
  /// Per §8.8 — backed by `get_license_info` FFI via the
  /// `com.unifiedshield/license` MethodChannel.
  Future<Map<String, dynamic>?> getLicenseInfo() async {
    try {
      final result = await _licenseChannel.invokeMethod<Map>('getLicenseInfo');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to fetch license info',
        code: e.code,
        details: e.details,
      );
    }
  }

  /// Force-disconnects the VPN — called by the expiry watchdog (§8.8).
  Future<void> forceDisconnect() async {
    try {
      await _licenseChannel.invokeMethod<void>('forceDisconnect');
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to force disconnect',
        code: e.code,
        details: e.details,
      );
    }
  }

  /// Register a callback to be invoked when the license expires (§8.8).
  ///
  /// The native side stores the callback pointer and invokes it from the
  /// expiry-watchdog task once the license crosses its expiry timestamp.
  /// Only the FIRST registration is honored; subsequent registrations are
  /// silently dropped.
  Future<void> registerExpiryCallback() async {
    try {
      await _licenseChannel.invokeMethod<void>('registerExpiryCallback');
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to register expiry callback',
        code: e.code,
        details: e.details,
      );
    }
  }

  /// Request the Android VpnService permission (opens the system VPN
  /// consent dialog). Returns true when the user grants it.
  ///
  /// Public wrapper over the `requestVpnPermission` MethodChannel call —
  /// used by [VpnService] before starting the tunnel.
  Future<bool?> requestVpnPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestVpnPermission');
    } on PlatformException catch (e) {
      throw DaemonException(
        message: e.message ?? 'Failed to request VPN permission',
        code: e.code,
        details: e.details,
      );
    }
  }

  void dispose() {
    _statusSubscription?.cancel();
    _statusController.close();
  }
}

class DaemonException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  DaemonException({
    required this.message,
    this.code,
    this.details,
  });

  @override
  String toString() => 'DaemonException($code): $message';
}
