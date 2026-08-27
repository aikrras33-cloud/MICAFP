import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'daemon_bridge.dart';
import 'battery_service.dart';

/// NAIN (National Internet) status monitoring service.
///
/// Listens to NAIN status updates from the Rust daemon.
/// When a CompleteBlackout is detected:
///   - Shows warning to user
///   - Automatically activates mesh channels
///   - Requests all battery exemptions
///   - Temporarily boosts to Performance power mode
///
/// When FullInternet is restored:
///   - Deactivates mesh channels to save battery
///   - Returns to normal power mode
///
/// Ported from `flutter/lib/services/nain_status_service.dart` per directive §3.5.
/// Adaptations for canonical `flutter_app` API:
///   - Canonical `DaemonBridge.statusStream` emits `Map<String, dynamic>`
///     (not the legacy `StatusResponse` type). `_handleStatusUpdate` now
///     takes a Map and parses the `nain_status` field from it.
///   - Canonical `DaemonBridge` does not expose a `nainStatus` getter or
///     a `sendConfigUpdate(key, value)` method. We derive initial status
///     by calling `DaemonBridge.getStatus()` and read the `nain_status`
///     field; `sendConfigUpdate` is replaced with an inline private
///     `_sendConfigUpdate` helper that no-ops (the canonical
///     `triggerObfuscationMode(mode)` MethodChannel call is the closest
///     equivalent and is invoked only when explicitly relevant).
///   - Canonical `BatteryService` exposes `setLowPowerMode(bool)` rather
///     than a `setPowerMode(PowerMode)` enum, and does not expose
///     `requestOptimizationExemption()`. A `PowerMode` enum is declared
///     inline (performance/normal/save/critical); the `setPowerMode`
///     call maps to `setLowPowerMode(powerMode == PowerMode.save)`, and
///     `requestOptimizationExemption()` is invoked via the
///     `com.unifiedshield.daemon` MethodChannel directly.
class NainStatusService extends ChangeNotifier {
  final DaemonBridge _daemonBridge;
  final BatteryService _batteryService;

  NainStatus _currentStatus = NainStatus.fullInternet;
  bool _meshChannelsActive = false;
  bool _hasShownBlackoutWarning = false;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;

  static const MethodChannel _channel = MethodChannel('com.unifiedshield.daemon');

  NainStatusService(this._daemonBridge, this._batteryService) {
    _init();
  }

  NainStatus get currentStatus => _currentStatus;
  bool get meshChannelsActive => _meshChannelsActive;

  Future<void> _init() async {
    // Listen for status updates from daemon. Canonical DaemonBridge exposes
    // Stream<Map<String, dynamic>> statusStream — we parse the
    // `nain_status` string field out of each event.
    _statusSubscription = _daemonBridge.statusStream.listen(_handleStatusUpdate);

    // Get initial status by querying the daemon's getStatus() MethodChannel.
    try {
      final status = await _daemonBridge.getStatus();
      final nainStr = status['nain_status'] as String?;
      _currentStatus = _parseNainStatus(nainStr);
    } catch (e) {
      debugPrint('NainStatusService: failed to read initial status: $e');
    }
  }

  void _handleStatusUpdate(Map<String, dynamic> status) {
    final newStatus = _parseNainStatus(status['nain_status'] as String?);
    if (newStatus == _currentStatus) return;

    final previousStatus = _currentStatus;
    _currentStatus = newStatus;

    debugPrint('NAIN status changed: ${previousStatus.name} -> ${newStatus.name}');

    switch (newStatus) {
      case NainStatus.completeBlackout:
        _handleBlackout();
        break;
      case NainStatus.nationalIntranet:
        _handleNationalIntranet();
        break;
      case NainStatus.fullInternet:
        _handleFullInternet();
        break;
    }

    notifyListeners();
  }

  /// Handle CompleteBlackout — emergency mode
  void _handleBlackout() {
    // 1. Show warning to user
    if (!_hasShownBlackoutWarning) {
      _hasShownBlackoutWarning = true;
      _showBlackoutWarning();
    }

    // 2. Activate mesh channels (WiFi Aware, Bluetooth, acoustic)
    _activateMeshChannels();

    // 3. Request battery optimization exemptions
    _requestBatteryExemptions();

    // 4. Boost to Performance power mode (canonical BatteryService uses
    //    setLowPowerMode(bool); "performance" maps to low_power_mode=false).
    _setPowerMode(PowerMode.performance);

    // 5. Notify daemon to activate mesh relay mode
    _sendConfigUpdate('mesh_mode', 'active');
  }

  /// Handle National Intranet — limited connectivity
  void _handleNationalIntranet() {
    _hasShownBlackoutWarning = false;

    // Activate mesh channels preemptively
    _activateMeshChannels();

    // Set to normal power mode
    _setPowerMode(PowerMode.normal);

    // Notify daemon
    _sendConfigUpdate('mesh_mode', 'standby');
  }

  /// Handle Full Internet — normal operation
  void _handleFullInternet() {
    _hasShownBlackoutWarning = false;

    // Deactivate mesh channels to save battery
    _deactivateMeshChannels();

    // Return to normal power mode (will auto-adjust based on battery)
    _setPowerMode(PowerMode.normal);

    // Notify daemon
    _sendConfigUpdate('mesh_mode', 'inactive');
  }

  /// Activate all mesh communication channels
  void _activateMeshChannels() {
    if (_meshChannelsActive) return;

    _meshChannelsActive = true;
    debugPrint('Activating mesh channels');

    // Notify daemon to start WiFi Aware, Bluetooth, and acoustic channels
    _sendConfigUpdate('wifi_aware', 'active');
    _sendConfigUpdate('bluetooth_mesh', 'active');
    _sendConfigUpdate('acoustic_channel', 'standby');
  }

  /// Deactivate mesh channels to conserve battery
  void _deactivateMeshChannels() {
    if (!_meshChannelsActive) return;

    _meshChannelsActive = false;
    debugPrint('Deactivating mesh channels');

    // Notify daemon to stop mesh channels
    _sendConfigUpdate('wifi_aware', 'inactive');
    _sendConfigUpdate('bluetooth_mesh', 'inactive');
    _sendConfigUpdate('acoustic_channel', 'inactive');
  }

  /// Request all battery optimization exemptions
  void _requestBatteryExemptions() {
    // Request foreground service exemption via the daemon MethodChannel.
    // (Canonical BatteryService does not expose this; we invoke it
    // directly on `com.unifiedshield.daemon`.)
    try {
      _channel.invokeMethod<void>('requestBatteryOptimizationExemption');
    } on PlatformException catch (e) {
      debugPrint('NainStatusService: exemption request failed: ${e.message}');
    }

    // Request wake lock exemption (for mesh relay)
    _sendConfigUpdate('wake_lock', 'requested');

    // Request background data exemption
    _sendConfigUpdate('background_data', 'unrestricted');
  }

  /// Show blackout warning to user
  void _showBlackoutWarning() {
    // This is surfaced through the UI via the NAIN status indicator
    // The HomeScreen shows the warning state based on currentStatus
    // A more prominent dialog can be triggered here if needed
    debugPrint('BLACKOUT WARNING: Internet connectivity severely disrupted');
  }

  /// Update NAIN status (called by external listeners)
  void updateStatus(NainStatus status) {
    if (status == _currentStatus) return;

    _currentStatus = status;

    switch (status) {
      case NainStatus.completeBlackout:
        _handleBlackout();
        break;
      case NainStatus.nationalIntranet:
        _handleNationalIntranet();
        break;
      case NainStatus.fullInternet:
        _handleFullInternet();
        break;
    }

    notifyListeners();
  }

  // ── Adaptation helpers ────────────────────────────────────────────────

  /// Maps a string from the daemon's statusStream / getStatus() payload
  /// into the local `NainStatus` enum.
  static NainStatus _parseNainStatus(String? value) {
    switch (value) {
      case 'complete_blackout':
      case 'completeBlackout':
        return NainStatus.completeBlackout;
      case 'national_intranet':
      case 'nationalIntranet':
        return NainStatus.nationalIntranet;
      case 'full_internet':
      case 'fullInternet':
      case null:
        return NainStatus.fullInternet;
      default:
        debugPrint('NainStatusService: unknown nain_status value "$value"');
        return NainStatus.fullInternet;
    }
  }

  /// Replaces the legacy `DaemonBridge.sendConfigUpdate(key, value)` call
  /// (which does not exist on the canonical DaemonBridge). Routes the
  /// config update through the `com.unifiedshield.daemon` MethodChannel
  /// using a generic `sendConfigUpdate` method signature — the native
  /// side (Android/iOS) is expected to dispatch on the `key` field.
  void _sendConfigUpdate(String key, String value) {
    try {
      _channel.invokeMethod<void>('sendConfigUpdate', {
        'key': key,
        'value': value,
      });
    } on PlatformException catch (e) {
      debugPrint('NainStatusService: sendConfigUpdate($key) failed: ${e.message}');
    }
  }

  /// Replaces the legacy `BatteryService.setPowerMode(PowerMode)` call
  /// (which does not exist on the canonical BatteryService). Maps the
  /// local `PowerMode` enum onto the canonical `setLowPowerMode(bool)`
  /// accessor — `PowerMode.save` and `PowerMode.critical` both enable
  /// low-power mode; `performance` and `normal` disable it.
  void _setPowerMode(PowerMode mode) {
    final lowPower = mode == PowerMode.save || mode == PowerMode.critical;
    _batteryService.setLowPowerMode(lowPower);
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}

/// National-Internet reachability state, emitted by the Rust daemon in
/// `statusStream` events and in `getStatus()` responses.
enum NainStatus {
  /// All outbound internet connectivity is blocked.
  completeBlackout,
  /// Only Iranian national intranet services are reachable.
  nationalIntranet,
  /// Normal internet connectivity is available.
  fullInternet,
}

/// Local power-mode enum (matches the legacy `flutter/` BatteryService's
/// `PowerMode`). The canonical `flutter_app` BatteryService uses
/// `setLowPowerMode(bool)`; this enum is the input to the local
/// `_setPowerMode` adapter.
enum PowerMode {
  performance,
  normal,
  save,
  critical,
}
