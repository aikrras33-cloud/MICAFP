import 'package:flutter/foundation.dart';

/// VPN connection state.
///
/// Plain enum (no `@JsonValue` annotations — directive §3.22 drops
/// `freezed_annotation`/`json_serializable` code-gen; values are mapped
/// by name when crossing the MethodChannel boundary).
enum ConnectionState {
  connected,
  disconnected,
  connecting,
  error;

  static ConnectionState fromString(String? value) {
    switch (value) {
      case 'connected':
        return ConnectionState.connected;
      case 'connecting':
        return ConnectionState.connecting;
      case 'error':
        return ConnectionState.error;
      case 'disconnected':
      case null:
      default:
        return ConnectionState.disconnected;
    }
  }
}

/// VPN state value, exposed to the widget tree via
/// `ChangeNotifierProvider<VpnState>` (directive §3.22 — drops `@freezed`
/// in favour of a plain Dart class with named constructor + fields).
///
/// Fields are mutable so mutator methods (`connect`, `disconnect`,
/// `updateKillSwitch`, `setNationalIntranetMode`, `updateSpeeds`,
/// `setError`, `setActiveCore`, `setObfuscationMode`, `setCurrentIsp`)
/// can update state in place and then call `notifyListeners()` to drive
/// `Provider.of<VpnState>(context, listen: true)` rebuilds. External
/// callers should treat the public fields as read-only and use the
/// mutator methods to change state.
class VpnState extends ChangeNotifier {
  ConnectionState connectionState;
  String activeCore;
  List<String> shadowConnections;
  int uploadSpeed;
  int downloadSpeed;
  bool nationalIntranetMode;
  bool killSwitchEnabled;
  String errorMessage;
  String currentIsp;
  String obfuscationMode;

  /// Plain named constructor with field defaults matching the legacy
  /// `@freezed` `@Default(...)` values.
  VpnState({
    this.connectionState = ConnectionState.disconnected,
    this.activeCore = 'warp',
    this.shadowConnections = const [],
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.nationalIntranetMode = false,
    this.killSwitchEnabled = true,
    this.errorMessage = '',
    this.currentIsp = '',
    this.obfuscationMode = '',
  });

  /// Initial state factory — preserved for compatibility with legacy
  /// `VpnState.initial()` call sites.
  factory VpnState.initial() => VpnState();

  /// Construct from a JSON payload received over the MethodChannel
  /// (replaces the freezed `_$VpnStateFromJson` codegen).
  factory VpnState.fromJson(Map<String, dynamic> json) {
    return VpnState(
      connectionState: ConnectionState.fromString(json['connectionState'] as String?),
      activeCore: json['activeCore'] as String? ?? 'warp',
      shadowConnections: (json['shadowConnections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      uploadSpeed: (json['uploadSpeed'] as num?)?.toInt() ?? 0,
      downloadSpeed: (json['downloadSpeed'] as num?)?.toInt() ?? 0,
      nationalIntranetMode: json['nationalIntranetMode'] as bool? ?? false,
      killSwitchEnabled: json['killSwitchEnabled'] as bool? ?? true,
      errorMessage: json['errorMessage'] as String? ?? '',
      currentIsp: json['currentIsp'] as String? ?? '',
      obfuscationMode: json['obfuscationMode'] as String? ?? '',
    );
  }

  /// Serialise to JSON (replaces the freezed `_$VpnStateToJson` codegen).
  Map<String, dynamic> toJson() => {
        'connectionState': connectionState.name,
        'activeCore': activeCore,
        'shadowConnections': shadowConnections,
        'uploadSpeed': uploadSpeed,
        'downloadSpeed': downloadSpeed,
        'nationalIntranetMode': nationalIntranetMode,
        'killSwitchEnabled': killSwitchEnabled,
        'errorMessage': errorMessage,
        'currentIsp': currentIsp,
        'obfuscationMode': obfuscationMode,
      };

  /// Copy-with helper (replaces the freezed-generated `copyWith`).
  /// Returns a new VpnState instance; does NOT notify listeners.
  VpnState copyWith({
    ConnectionState? connectionState,
    String? activeCore,
    List<String>? shadowConnections,
    int? uploadSpeed,
    int? downloadSpeed,
    bool? nationalIntranetMode,
    bool? killSwitchEnabled,
    String? errorMessage,
    String? currentIsp,
    String? obfuscationMode,
  }) {
    return VpnState(
      connectionState: connectionState ?? this.connectionState,
      activeCore: activeCore ?? this.activeCore,
      shadowConnections: shadowConnections ?? this.shadowConnections,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      nationalIntranetMode: nationalIntranetMode ?? this.nationalIntranetMode,
      killSwitchEnabled: killSwitchEnabled ?? this.killSwitchEnabled,
      errorMessage: errorMessage ?? this.errorMessage,
      currentIsp: currentIsp ?? this.currentIsp,
      obfuscationMode: obfuscationMode ?? this.obfuscationMode,
    );
  }

  // ── Mutators ───────────────────────────────────────────────────────────
  // Each mutator updates fields in place and then calls notifyListeners()
  // so `Provider.of<VpnState>(context, listen: true)` rebuilds dependent
  // widgets.

  /// Mark the VPN as connected (used by cores_screen after a successful
  /// `DaemonBridge.switchCore(coreId)` call).
  void connect() {
    connectionState = ConnectionState.connected;
    notifyListeners();
  }

  /// Mark the VPN as connecting (used by VpnService during reconnect).
  void setConnecting() {
    connectionState = ConnectionState.connecting;
    notifyListeners();
  }

  /// Mark the VPN as disconnected.
  void disconnect() {
    connectionState = ConnectionState.disconnected;
    notifyListeners();
  }

  /// Update the kill-switch toggle (used by settings_screen).
  void updateKillSwitch(bool enabled) {
    killSwitchEnabled = enabled;
    notifyListeners();
  }

  /// Update the national-intranet toggle (used by settings_screen).
  void setNationalIntranetMode(bool enabled) {
    nationalIntranetMode = enabled;
    notifyListeners();
  }

  /// Update the live up/down speed counters (called by HomeScreen polling).
  void updateSpeeds({int? up, int? down}) {
    if (up != null) uploadSpeed = up;
    if (down != null) downloadSpeed = down;
    notifyListeners();
  }

  /// Set an error message and flip the state to `error`.
  void setError(String message) {
    errorMessage = message;
    connectionState = ConnectionState.error;
    notifyListeners();
  }

  /// Switch the active core id.
  void setActiveCore(String coreId) {
    activeCore = coreId;
    notifyListeners();
  }

  /// Update the current obfuscation mode label.
  void setObfuscationMode(String mode) {
    obfuscationMode = mode;
    notifyListeners();
  }

  /// Update the detected ISP label.
  void setCurrentIsp(String isp) {
    currentIsp = isp;
    notifyListeners();
  }
}

/// Helper getters ported from the legacy `VpnStateX` extension.
extension VpnStateX on VpnState {
  String get connectionText {
    switch (connectionState) {
      case ConnectionState.connected:
        return 'Connected';
      case ConnectionState.disconnected:
        return 'Disconnected';
      case ConnectionState.connecting:
        return 'Connecting...';
      case ConnectionState.error:
        return 'Error';
    }
  }

  String get connectionTextFa {
    switch (connectionState) {
      case ConnectionState.connected:
        return 'متصل';
      case ConnectionState.disconnected:
        return 'قطع';
      case ConnectionState.connecting:
        return 'در حال اتصال...';
      case ConnectionState.error:
        return 'خطا';
    }
  }

  String get uploadSpeedText => _formatSpeed(uploadSpeed);
  String get downloadSpeedText => _formatSpeed(downloadSpeed);

  static String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  bool get isConnected => connectionState == ConnectionState.connected;
  bool get isConnecting => connectionState == ConnectionState.connecting;
  bool get isDisconnected => connectionState == ConnectionState.disconnected;
  bool get hasError => connectionState == ConnectionState.error;
}
