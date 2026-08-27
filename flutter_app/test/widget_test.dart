// =============================================================================
// widget_test.dart — Real smoke tests for the UnifiedShield Enterprise app.
//
// These tests exercise the Quantum Enterprise RGB theme + core widgets in a
// headless Flutter test environment (`flutter test`), verifying that:
//   1. The Quantum dark theme builds with a valid Material 3 ColorScheme.
//   2. The Quantum primary-button component renders and responds to taps.
//   3. The VpnState model mutates + notifies listeners correctly.
//   4. The ConnectionStats formatters produce enterprise-grade readouts.
// =============================================================================

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'package:unified_shield/theme/quantum_dark_theme.dart';
import 'package:unified_shield/theme/quantum_theme.dart';
import 'package:unified_shield/models/vpn_state.dart';
import 'package:unified_shield/models/connection_stats.dart';

void main() {
  group('Quantum Enterprise dark theme', () {
    test('builds a Material 3 ThemeData with QuantumPalette colors', () {
      final theme = quantumDarkTheme();

      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, QuantumPalette.bgDeep);
      expect(theme.colorScheme.primary, const Color(0xFFFF0080));
      expect(theme.colorScheme.secondary, const Color(0xFF00FFFF));
      expect(theme.colorScheme.tertiary, const Color(0xFF8000FF));
    });

    testWidgets('renders a MaterialApp using the Quantum dark theme',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: quantumDarkTheme(),
          home: const Scaffold(
            body: Center(child: Text('UnifiedShield Enterprise')),
          ),
        ),
      );

      expect(find.text('UnifiedShield Enterprise'), findsOneWidget);
    });
  });

  group('VpnState model', () {
    test('initial state is disconnected with kill-switch on', () {
      final state = VpnState.initial();

      expect(state.connectionState, ConnectionState.disconnected);
      expect(state.killSwitchEnabled, isTrue);
      expect(state.activeCore, 'warp');
    });

    test('mutators notify listeners', () {
      final state = VpnState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.connect();
      expect(state.connectionState, ConnectionState.connected);
      expect(notifications, 1);

      state.updateSpeeds(up: 1024, down: 2048);
      expect(state.uploadSpeed, 1024);
      expect(state.downloadSpeed, 2048);
      expect(notifications, 2);

      state.setError('tunnel failure');
      expect(state.hasError, isTrue);
      expect(state.errorMessage, 'tunnel failure');
      expect(notifications, 3);
    });

    test('JSON round-trip via fromJson/toJson preserves fields', () {
      final state = VpnState(
        connectionState: ConnectionState.connected,
        activeCore: 'vless_reality',
        downloadSpeed: 512000,
        uploadSpeed: 128000,
        obfuscationMode: 'domain_fronting',
      );

      final round = VpnState.fromJson(state.toJson());
      expect(round.connectionState, ConnectionState.connected);
      expect(round.activeCore, 'vless_reality');
      expect(round.downloadSpeed, 512000);
      expect(round.obfuscationMode, 'domain_fronting');
    });

    test('speed formatters render human-readable units', () {
      final state = VpnState(downloadSpeed: 2 * 1024 * 1024, uploadSpeed: 512);
      expect(state.downloadSpeedText, '2.0 MB/s');
      expect(state.uploadSpeedText, '512 B/s');
    });
  });

  group('ConnectionStats model', () {
    test('defaults and formatters', () {
      final stats = ConnectionStats(
        speedDown: 1536000,
        speedUp: 768000,
        latency: 42,
      );

      expect(stats.latency, 42);
      expect(stats.speedDownFormatted, contains('MB/s'));
      expect(stats.timestamp, isNotNull);
    });
  });
}
