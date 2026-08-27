import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// P2P relay network service for serverless connectivity.
///
/// Uses libp2p-based mesh networking to create a decentralized
/// relay network. When servers are blocked, peers can relay
/// traffic through each other to reach the open internet.
///
/// Architecture:
/// - Each peer acts as both client and relay
/// - DHT-based peer discovery
/// - NAT traversal via hole-punching
/// - Encrypted end-to-end relay channels
/// - Incentive system for relay providers
///
/// Ported from `flutter/lib/services/p2p_service.dart` per directive §3.5.
/// Adaptations:
///   - Riverpod import + provider declarations stripped (directive §3.22
///     drops riverpod). P2PService is now a plain Dart class; wire it
///     via `Provider<P2PService>.value(...)` in `main.dart`.
///   - Legacy `flutter/` DaemonService methods `sendCommand` and
///     `getP2PPeers` are NOT exposed on the canonical `flutter_app`
///     DaemonService. P2PService now talks to the
///     `com.unifiedshield.daemon` MethodChannel directly via its own
///     private `_channel`, mirroring the canonical DaemonService pattern.
class P2PService {
  static final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  static const MethodChannel _channel = MethodChannel('com.unifiedshield.daemon');

  bool _isP2PEnabled = false;
  int _peerCount = 0;
  int _relayCount = 0;
  final String _nodeId = '';

  bool get isP2PEnabled => _isP2PEnabled;
  int get peerCount => _peerCount;
  int get relayCount => _relayCount;
  String get nodeId => _nodeId;

  /// Enable P2P relay mode
  Future<void> enable({bool actAsRelay = true, int maxRelayConnections = 10}) async {
    try {
      _log.i('Enabling P2P relay mode (relay=$actAsRelay, max=$maxRelayConnections)');
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'p2p.enable',
        'params': {
          'act_as_relay': actAsRelay,
          'max_relay_connections': maxRelayConnections,
        },
      });
      _isP2PEnabled = true;
    } on PlatformException catch (e) {
      _log.e('Failed to enable P2P: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Disable P2P relay mode
  Future<void> disable() async {
    try {
      _log.i('Disabling P2P relay mode');
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'p2p.disable',
        'params': <String, dynamic>{},
      });
      _isP2PEnabled = false;
      _peerCount = 0;
      _relayCount = 0;
    } on PlatformException catch (e) {
      _log.e('Failed to disable P2P: ${e.message}', error: e);
      rethrow;
    }
  }

  /// Get current peer list
  Future<List<P2PPeer>> getPeers() async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'p2p.peers',
        'params': <String, dynamic>{},
      });
      if (response == null) return [];
      final peersJson = response['peers'] as List<dynamic>? ?? [];
      _peerCount = peersJson.length;
      return peersJson.map((p) => P2PPeer.fromJson(p as Map<String, dynamic>)).toList();
    } catch (e) {
      _log.e('Failed to get P2P peers', error: e);
      return [];
    }
  }

  /// Connect to a specific peer
  Future<bool> connectToPeer(String peerId) async {
    try {
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'p2p.connect',
        'params': {'peer_id': peerId},
      });
      _log.i('Connected to peer: $peerId');
      return true;
    } catch (e) {
      _log.e('Failed to connect to peer $peerId', error: e);
      return false;
    }
  }

  /// Disconnect from a specific peer
  Future<void> disconnectPeer(String peerId) async {
    try {
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'p2p.disconnect',
        'params': {'peer_id': peerId},
      });
      _log.i('Disconnected from peer: $peerId');
    } catch (e) {
      _log.e('Failed to disconnect from peer $peerId', error: e);
    }
  }

  /// Discover peers via DHT
  Future<List<P2PPeer>> discoverPeers({
    int count = 20,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'p2p.discover',
        'params': {
          'count': count,
          'timeout_ms': timeout.inMilliseconds,
        },
      });
      if (response == null) return [];
      final peersJson = response['peers'] as List<dynamic>? ?? [];
      return peersJson.map((p) => P2PPeer.fromJson(p as Map<String, dynamic>)).toList();
    } catch (e) {
      _log.e('Peer discovery failed', error: e);
      return [];
    }
  }

  /// Get relay statistics
  Future<P2PRelayStats> getRelayStats() async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'p2p.relay_stats',
        'params': <String, dynamic>{},
      });
      if (response == null) return const P2PRelayStats();
      _relayCount = response['active_relays'] as int? ?? 0;
      return P2PRelayStats.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      _log.e('Failed to get relay stats', error: e);
      return const P2PRelayStats();
    }
  }

  /// Send a message through the P2P relay network
  Future<bool> sendRelayMessage({
    required String destinationPeerId,
    required String payload,
    int ttl = 5,
  }) async {
    try {
      await _channel.invokeMethod<void>('sendCommand', {
        'method': 'p2p.relay_send',
        'params': {
          'destination': destinationPeerId,
          'payload': payload,
          'ttl': ttl,
        },
      });
      return true;
    } catch (e) {
      _log.e('Failed to send relay message', error: e);
      return false;
    }
  }

  /// Check P2P network health
  Future<P2PNetworkHealth> checkNetworkHealth() async {
    try {
      final response = await _channel.invokeMethod<Map>('sendCommand', {
        'method': 'p2p.health',
        'params': <String, dynamic>{},
      });
      if (response == null) {
        return const P2PNetworkHealth(
          healthy: false,
          reachablePeers: 0,
          avgLatency: 0,
        );
      }
      return P2PNetworkHealth.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      _log.e('P2P health check failed', error: e);
      return const P2PNetworkHealth(
        healthy: false,
        reachablePeers: 0,
        avgLatency: 0,
      );
    }
  }
}

/// P2P Peer model
class P2PPeer {
  final String peerId;
  final String address;
  final String country;
  final bool isRelay;
  final bool isOnline;
  final int latency;
  final double bandwidth; // KB/s
  final DateTime lastSeen;

  P2PPeer({
    required this.peerId,
    required this.address,
    this.country = '',
    this.isRelay = false,
    this.isOnline = false,
    this.latency = 0,
    this.bandwidth = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory P2PPeer.fromJson(Map<String, dynamic> json) {
    return P2PPeer(
      peerId: json['peer_id'] as String? ?? '',
      address: json['address'] as String? ?? '',
      country: json['country'] as String? ?? '',
      isRelay: json['is_relay'] as bool? ?? false,
      isOnline: json['is_online'] as bool? ?? false,
      latency: json['latency_ms'] as int? ?? 0,
      bandwidth: (json['bandwidth_kbps'] as num?)?.toDouble() ?? 0.0,
      lastSeen: json['last_seen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_seen'] as int)
          : DateTime.now(),
    );
  }
}

/// P2P Relay statistics
class P2PRelayStats {
  final int activeRelays;
  final int totalBytesRelayed;
  final int totalMessagesRelayed;
  final double avgRelayLatency;

  const P2PRelayStats({
    this.activeRelays = 0,
    this.totalBytesRelayed = 0,
    this.totalMessagesRelayed = 0,
    this.avgRelayLatency = 0.0,
  });

  factory P2PRelayStats.fromJson(Map<String, dynamic> json) {
    return P2PRelayStats(
      activeRelays: json['active_relays'] as int? ?? 0,
      totalBytesRelayed: json['total_bytes_relayed'] as int? ?? 0,
      totalMessagesRelayed: json['total_messages_relayed'] as int? ?? 0,
      avgRelayLatency: (json['avg_relay_latency_ms'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// P2P Network health
class P2PNetworkHealth {
  final bool healthy;
  final int reachablePeers;
  final double avgLatency;
  final int dhtSize;

  const P2PNetworkHealth({
    required this.healthy,
    required this.reachablePeers,
    required this.avgLatency,
    this.dhtSize = 0,
  });

  factory P2PNetworkHealth.fromJson(Map<String, dynamic> json) {
    return P2PNetworkHealth(
      healthy: json['healthy'] as bool? ?? false,
      reachablePeers: json['reachable_peers'] as int? ?? 0,
      avgLatency: (json['avg_latency_ms'] as num?)?.toDouble() ?? 0.0,
      dhtSize: json['dht_size'] as int? ?? 0,
    );
  }
}
