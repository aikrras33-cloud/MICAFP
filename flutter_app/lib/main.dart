import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

import 'screens/calculator_screen.dart';
import 'screens/home_screen.dart';
import 'services/daemon_service.dart';
import 'services/daemon_bridge.dart';
import 'services/battery_service.dart';
import 'services/ota_updater.dart';
import 'services/intranet_service.dart';
import 'services/p2p_service.dart';
import 'services/nain_status_service.dart';
import 'models/vpn_state.dart';
import 'theme/quantum_dark_theme.dart';
import 'theme/quantum_light_theme.dart';

/// MICAFP-UnifiedShield — Next-generation anti-censorship tool
/// Entry point for the Flutter application.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services (canonical API: each is a plain Dart class wired
  // into the widget tree via `Provider` / `ChangeNotifierProvider`).
  final daemonService = DaemonService();
  final batteryService = BatteryService();
  final daemonBridge = DaemonBridge()..init();
  final vpnState = VpnState.initial();
  final otaUpdater = OtaUpdater();
  final intranetService = IntranetService();
  final p2pService = P2PService();
  final nainStatusService = NainStatusService(daemonBridge, batteryService);

  // Request necessary permissions
  await requestPermissions();

  // Apply the Quantum Enterprise system chrome (transparent status bar +
  // deep-space navigation bar) before the first frame.
  quantumSystemChrome();

  // Initialize daemon connection
  await daemonService.initialize();

  // Start battery monitoring
  await batteryService.startMonitoring();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DaemonService>.value(value: daemonService),
        ChangeNotifierProvider<BatteryService>.value(value: batteryService),
        Provider<DaemonBridge>.value(value: daemonBridge),
        ChangeNotifierProvider<VpnState>.value(value: vpnState),
        Provider<OtaUpdater>.value(value: otaUpdater),
        Provider<IntranetService>.value(value: intranetService),
        Provider<P2PService>.value(value: p2pService),
        ChangeNotifierProvider<NainStatusService>.value(value: nainStatusService),
      ],
      child: const ShieldApp(),
    ),
  );
}

/// Request all necessary permissions for the app.
Future<void> requestPermissions() async {
  final permissions = <Permission>[
    Permission.notification,
    Permission.location,
    Permission.nearbyWifiDevices,
  ];

  if (Platform.isAndroid) {
    permissions.addAll([
      Permission.phone,
      Permission.sms,
      Permission.ignoreBatteryOptimizations,
      Permission.accessNotificationPolicy,
    ]);
  }

  if (Platform.isIOS) {
    permissions.addAll([
      Permission.microphone,
    ]);
  }

  for (final permission in permissions) {
    try {
      final status = await permission.status;
      if (!status.isGranted) {
        await permission.request();
      }
    } catch (e) {
      debugPrint('Permission request failed for $permission: $e');
    }
  }
}

/// Main application widget.
/// Title is always "Shield" — NEVER "VPN" or "proxy".
class ShieldApp extends StatefulWidget {
  const ShieldApp({super.key});

  @override
  State<ShieldApp> createState() => _ShieldAppState();
}

class _ShieldAppState extends State<ShieldApp> with WidgetsBindingObserver {
  Locale _locale = const Locale('en');
  ThemeMode _themeMode = ThemeMode.system;
  bool _isUnlocked = false;
  int _tapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Load saved preferences for locale and theme.
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedLocale = prefs.getString('locale');
      if (savedLocale != null) {
        _locale = Locale(savedLocale);
      }
      final savedTheme = prefs.getString('theme_mode');
      if (savedTheme != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == savedTheme,
          orElse: () => ThemeMode.system,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app goes to background, lock the shield UI
    if (state == AppLifecycleState.paused) {
      setState(() {
        _isUnlocked = false;
      });
    }

    // When app comes to foreground, check battery state
    if (state == AppLifecycleState.resumed) {
      final batteryService = context.read<BatteryService>();
      batteryService.refreshBatteryState();
    }
  }

  /// Handle rapid tap detection for anti-forensics trigger.
  /// 5 taps in 2 seconds triggers emergency wipe.
  void _handleAntiForensicsTap() {
    final now = DateTime.now();

    if (_lastTapTime != null && now.difference(_lastTapTime!).inSeconds > 2) {
      _tapCount = 0;
    }

    _tapCount++;
    _lastTapTime = now;

    if (_tapCount >= 5) {
      _tapCount = 0;
      _triggerAntiForensics();
    }
  }

  /// Trigger anti-forensics emergency wipe.
  Future<void> _triggerAntiForensics() async {
    try {
      // Vibrate as confirmation
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 500);
      }

      final daemonService = context.read<DaemonService>();
      await daemonService.triggerAntiForensics();

      // Lock the UI
      setState(() {
        _isUnlocked = false;
      });
    } catch (e) {
      debugPrint('Anti-forensics trigger failed: $e');
    }
  }

  /// Unlock the shield UI from the calculator.
  void _unlockShield() {
    setState(() {
      _isUnlocked = true;
    });
  }

  /// Lock the shield UI back to the calculator.
  void _lockShield() {
    setState(() {
      _isUnlocked = false;
    });
  }

  void _toggleLocale() {
    setState(() {
      _locale = _locale.languageCode == 'en' ? const Locale('fa') : const Locale('en');
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('locale', _locale.languageCode);
    });
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('theme_mode', _themeMode.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Quantum Enterprise RGB theming (§6): the dark theme is the canonical
    // look; the light theme is its 1:1 mirror. Persian locale swaps the
    // default face to Vazirmatn across the whole text theme.
    final isFa = _locale.languageCode == 'fa';
    final lightTheme = quantumLightTheme();
    final darkTheme = quantumDarkTheme();

    return MaterialApp(
      title: 'Shield',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: isFa
          ? lightTheme.copyWith(
              textTheme: lightTheme.textTheme.apply(fontFamily: 'Vazirmatn'))
          : lightTheme,
      darkTheme: isFa
          ? darkTheme.copyWith(
              textTheme: darkTheme.textTheme.apply(fontFamily: 'Vazirmatn'))
          : darkTheme,
      themeMode: _themeMode,
      home: GestureDetector(
        onTap: _handleAntiForensicsTap,
        child: _isUnlocked
            ? HomeScreen(
                onLock: _lockShield,
                onToggleLocale: _toggleLocale,
                onToggleTheme: _toggleTheme,
              )
            : CalculatorScreen(
                onUnlock: _unlockShield,
              ),
      ),
    );
  }
}

/// Extension for localization helpers on BuildContext.
extension LocalizationExtension on BuildContext {
  /// Get localized string — simple map-based approach for Persian + English.
  String l10n(String key) {
    final locale = Localizations.localeOf(this);
    final translations = locale.languageCode == 'fa' ? _persian : _english;
    return translations[key] ?? key;
  }
}

const _english = <String, String>{
  'app_title': 'Shield',
  'connect': 'Connect',
  'disconnect': 'Disconnect',
  'status_connected': 'Connected',
  'status_disconnected': 'Disconnected',
  'status_connecting': 'Connecting...',
  'battery_low': 'Low Battery',
  'battery_warning': 'Battery below 15%. Non-essential features disabled.',
  'data_used': 'Data Used',
  'transport': 'Transport',
  'settings': 'Settings',
  'lock': 'Lock',
  'calculator': 'Calculator',
  'paste_config': 'Paste Config Code',
  'dark_mode': 'Dark Mode',
  'language': 'Language',
};

const _persian = <String, String>{
  'app_title': 'شیلد',
  'connect': 'اتصال',
  'disconnect': 'قطع',
  'status_connected': 'متصل',
  'status_disconnected': 'قطع شده',
  'status_connecting': 'در حال اتصال...',
  'battery_low': 'باتری کم',
  'battery_warning': 'باتری زیر ۱۵٪. امکانات غیرضروری غیرفعال شد.',
  'data_used': 'داده مصرفی',
  'transport': 'انتقال',
  'settings': 'تنظیمات',
  'lock': 'قفل',
  'calculator': 'ماشین حساب',
  'paste_config': 'چسباندن کد پیکربندی',
  'dark_mode': 'حالت تاریک',
  'language': 'زبان',
};
