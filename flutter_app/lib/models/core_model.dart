/// Core status enum — plain enum (no `@JsonValue` annotations — directive
/// §3.22 drops `freezed_annotation`/`json_serializable` code-gen).
enum CoreStatus {
  connected,
  disconnected,
  connecting,
  error,
  standby;

  static CoreStatus fromString(String? value) {
    switch (value) {
      case 'connected':
        return CoreStatus.connected;
      case 'connecting':
        return CoreStatus.connecting;
      case 'error':
        return CoreStatus.error;
      case 'standby':
        return CoreStatus.standby;
      case 'disconnected':
      case null:
      default:
        return CoreStatus.disconnected;
    }
  }
}

/// Immutable health-status value type with a const constructor (replaces
/// the legacy `@freezed`-generated `HealthStatus` class).
class HealthStatus {
  final int latency;
  final double packetLoss;
  final bool blocked;
  final bool dnsLeak;
  final double dpiExposure;
  final int bandwidth;

  const HealthStatus({
    this.latency = 0,
    this.packetLoss = 0.0,
    this.blocked = false,
    this.dnsLeak = false,
    this.dpiExposure = 0.0,
    this.bandwidth = 0,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      latency: (json['latency'] as num?)?.toInt() ?? 0,
      packetLoss: (json['packetLoss'] as num?)?.toDouble() ?? 0.0,
      blocked: json['blocked'] as bool? ?? false,
      dnsLeak: json['dnsLeak'] as bool? ?? false,
      dpiExposure: (json['dpiExposure'] as num?)?.toDouble() ?? 0.0,
      bandwidth: (json['bandwidth'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'latency': latency,
        'packetLoss': packetLoss,
        'blocked': blocked,
        'dnsLeak': dnsLeak,
        'dpiExposure': dpiExposure,
        'bandwidth': bandwidth,
      };

  HealthStatus copyWith({
    int? latency,
    double? packetLoss,
    bool? blocked,
    bool? dnsLeak,
    double? dpiExposure,
    int? bandwidth,
  }) {
    return HealthStatus(
      latency: latency ?? this.latency,
      packetLoss: packetLoss ?? this.packetLoss,
      blocked: blocked ?? this.blocked,
      dnsLeak: dnsLeak ?? this.dnsLeak,
      dpiExposure: dpiExposure ?? this.dpiExposure,
      bandwidth: bandwidth ?? this.bandwidth,
    );
  }
}

/// Immutable core-adapter value type with a const constructor (replaces
/// the legacy `@freezed`-generated `CoreAdapter` class).
class CoreAdapter {
  final String id;
  final String name;
  final String nameFa;
  final String version;
  final CoreStatus status;
  final HealthStatus health;
  final List<String> protocols;
  final List<String> capabilities;

  const CoreAdapter({
    required this.id,
    required this.name,
    this.nameFa = '',
    this.version = '1.0.0',
    this.status = CoreStatus.standby,
    this.health = const HealthStatus(),
    this.protocols = const [],
    this.capabilities = const [],
  });

  factory CoreAdapter.fromJson(Map<String, dynamic> json) {
    return CoreAdapter(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      nameFa: json['nameFa'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      status: CoreStatus.fromString(json['status'] as String?),
      health: json['health'] is Map
          ? HealthStatus.fromJson(Map<String, dynamic>.from(json['health'] as Map))
          : const HealthStatus(),
      protocols: (json['protocols'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameFa': nameFa,
        'version': version,
        'status': status.name,
        'health': health.toJson(),
        'protocols': protocols,
        'capabilities': capabilities,
      };

  CoreAdapter copyWith({
    String? id,
    String? name,
    String? nameFa,
    String? version,
    CoreStatus? status,
    HealthStatus? health,
    List<String>? protocols,
    List<String>? capabilities,
  }) {
    return CoreAdapter(
      id: id ?? this.id,
      name: name ?? this.name,
      nameFa: nameFa ?? this.nameFa,
      version: version ?? this.version,
      status: status ?? this.status,
      health: health ?? this.health,
      protocols: protocols ?? this.protocols,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}

/// Helper getters ported from the legacy `CoreAdapterX` extension.
extension CoreAdapterX on CoreAdapter {
  double get score {
    if (health.blocked) return 0.0;
    if (status == CoreStatus.error) return 0.0;

    double latencyScore = 0;
    if (health.latency > 0) {
      latencyScore = (1.0 - (health.latency / 1000).clamp(0.0, 1.0)) * 30;
    }

    double packetLossScore = (1.0 - health.packetLoss) * 25;

    double dpiScore = (1.0 - health.dpiExposure) * 25;

    double dnsScore = health.dnsLeak ? 0.0 : 20.0;

    return (latencyScore + packetLossScore + dpiScore + dnsScore).clamp(0.0, 100.0);
  }

  String get statusText {
    switch (status) {
      case CoreStatus.connected:
        return 'Connected';
      case CoreStatus.disconnected:
        return 'Disconnected';
      case CoreStatus.connecting:
        return 'Connecting';
      case CoreStatus.error:
        return 'Error';
      case CoreStatus.standby:
        return 'Standby';
    }
  }

  String get statusTextFa {
    switch (status) {
      case CoreStatus.connected:
        return 'متصل';
      case CoreStatus.disconnected:
        return 'قطع';
      case CoreStatus.connecting:
        return 'در حال اتصال';
      case CoreStatus.error:
        return 'خطا';
      case CoreStatus.standby:
        return 'آماده';
    }
  }
}

/// Default cores available out-of-the-box (const list — the underlying
/// `CoreAdapter` constructor is const, so this list is compile-time
/// constant).
const List<CoreAdapter> defaultCores = [
  CoreAdapter(
    id: 'warp',
    name: 'Cloudflare WARP',
    nameFa: 'کلودفلر وارپ',
    version: '1.0.0',
    protocols: ['wireguard', 'warp'],
    capabilities: ['ipv4', 'ipv6', 'split_tunnel'],
  ),
  CoreAdapter(
    id: 'xray',
    name: 'Xray-core',
    nameFa: 'ایکس‌ری',
    version: '1.8.0',
    protocols: ['vless', 'vmess', 'trojan', 'shadowsocks'],
    capabilities: ['xhttp', 'splithttp', 'ws', 'grpc', 'tcp', 'reality'],
  ),
  CoreAdapter(
    id: 'hysteria',
    name: 'Hysteria 2',
    nameFa: 'هیستریا ۲',
    version: '2.0.0',
    protocols: ['hysteria2', 'quic'],
    capabilities: ['udp_relay', 'bandwidth_control'],
  ),
  CoreAdapter(
    id: 'naive',
    name: 'NaïveProxy',
    nameFa: 'نایو پروکسی',
    version: '1.0.0',
    protocols: ['http_proxy', 'https_proxy'],
    capabilities: ['domain_fronting', 'chrome_fingerprint'],
  ),
  CoreAdapter(
    id: 'tuic',
    name: 'TUIC',
    nameFa: 'توئیک',
    version: '1.0.0',
    protocols: ['tuic', 'quic'],
    capabilities: ['udp_relay', 'congestion_control'],
  ),
  CoreAdapter(
    id: 'psiphon',
    name: 'Psiphon',
    nameFa: 'سایفون',
    version: '1.0.0',
    protocols: ['ssh', 'obfs4', 'meek'],
    capabilities: ['domain_fronting', 'obfuscation', 'shutdown_resistant'],
  ),
  CoreAdapter(
    id: 'outline',
    name: 'Outline Shadowsocks',
    nameFa: 'اوتلاین',
    version: '1.0.0',
    protocols: ['shadowsocks'],
    capabilities: ['transport_encryption'],
  ),
  CoreAdapter(
    id: 'meek',
    name: 'Meek Lite',
    nameFa: 'میک لایت',
    version: '1.0.0',
    protocols: ['meek', 'domain_fronting'],
    capabilities: ['domain_fronting', 'cdn_relay'],
  ),
  CoreAdapter(
    id: 'snowflake',
    name: 'Snowflake',
    nameFa: 'اسنوفلیک',
    version: '1.0.0',
    protocols: ['webrtc', 'kcp'],
    capabilities: ['webrtc_relay', 'p2p', 'shutdown_resistant'],
  ),
];
