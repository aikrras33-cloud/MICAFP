import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/core_model.dart';
import '../models/vpn_state.dart';
import '../services/daemon_bridge.dart';
import '../widgets/status_card.dart';

/// Cores management screen — shows all available transport cores in a
/// grid and lets the user switch the active core.
///
/// Ported from `flutter_app/lib/screens/cores_screen.dart` per directive §3.22
/// (Option A — drop riverpod in favour of provider). The legacy
/// `ConsumerStatefulWidget` + `ref.watch`/`ref.read` is replaced with
/// `StatefulWidget` + `Provider.of<X>(context, ...)`.
///
/// §9 extension — Free Tier section: a horizontally-scrollable chip row of 5
/// free-tier transports (Tor+Snowflake, Psiphon, Lantern, Hysteria2 Community,
/// VLESS-Reality Community). These cores bypass the enterprise-license check
/// (the 9 paid-tier cores above require a valid Enterprise license; the 5
/// free-tier chips below are always selectable, even on the un-activated
/// Free edition).
class CoresScreen extends StatefulWidget {
  const CoresScreen({super.key});

  @override
  State<CoresScreen> createState() => _CoresScreenState();
}

class _CoresScreenState extends State<CoresScreen> {
  /// Local mutable list of cores (legacy `coresListProvider` StateProvider
  /// is gone — we hold the state locally and mutate via `setState`).
  List<CoreAdapter> _cores = defaultCores;

  /// §9 — the 5 free-tier cores, each rendered as a colored chip below the
  /// paid-tier grid. The order matches the daemon's `CoreManager::
  /// free_tier_cores()` priority order (Tor+Snowflake primary → VLESS-Reality
  /// quaternary).
  static const List<_FreeTierChipSpec> _freeTierChips = [
    _FreeTierChipSpec(
      id: 'tor_snowflake',
      label: 'Tor + Snowflake',
      labelFa: 'تور + اسنوفلیک',
      icon: Icons.ac_unit,
      color: Colors.lightBlue,
      socks5Port: 9050,
      tooltip: '§9 primary free-tier transport — pure-Rust arti TorClient '
          'with Snowflake WebRTC pluggable transport.',
    ),
    _FreeTierChipSpec(
      id: 'psiphon',
      label: 'Psiphon',
      labelFa: 'سایفون',
      icon: Icons.shield,
      color: Colors.green,
      socks5Port: 9080,
      tooltip: '§9 secondary free-tier transport — Psiphon SSH/obfs4/meek '
          'fallback chain through privately-operated servers.',
    ),
    _FreeTierChipSpec(
      id: 'lantern',
      label: 'Lantern',
      labelFa: 'لنترن',
      icon: Icons.lightbulb,
      color: Colors.amber,
      socks5Port: 9081,
      tooltip: '§9 tertiary free-tier transport — Lantern HTTP-fronting '
          'proxy through getlantern.org volunteer network.',
    ),
    _FreeTierChipSpec(
      id: 'hysteria2_community',
      label: 'Hysteria2 Community',
      labelFa: 'هیستریا ۲ جامعه',
      icon: Icons.speed,
      color: Colors.red,
      socks5Port: 9090,
      tooltip: '§9 quaternary free-tier transport — community-maintained '
          'Hysteria2 servers from t.me/s/hysteria2_free (refreshed weekly).',
    ),
    _FreeTierChipSpec(
      id: 'vless_reality_community',
      label: 'VLESS-Reality Community',
      labelFa: 'وی‌لس رئالیتی جامعه',
      icon: Icons.bolt,
      color: Colors.purple,
      socks5Port: 9091,
      tooltip: '§9 quaternary free-tier transport — community-maintained '
          'VLESS-Reality servers from t.me/s/v2ray_free (refreshed weekly).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final vpnState = context.watch<VpnState>();
    final isFa = Localizations.localeOf(context).languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(
        title: Text(isFa ? 'مدیریت هسته‌ها' : 'Core Management'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshCores,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 🆓 Free Tier section (§9) ──────────────────────────────────
            // Surfaces ABOVE the paid-tier grid so free users immediately see
            // the always-available options. Each chip is a tap target that
            // calls `DaemonBridge.switchCore('tor_snowflake')` etc., which
            // the daemon-side `CoreManager` resolves to the corresponding
            // free-tier `CoreTrait` impl.
            _FreeTierSection(
              chips: _freeTierChips,
              activeCoreId: vpnState.activeCore,
              isFa: isFa,
              onConnect: (coreId) => _switchCore(coreId),
            ),
            const SizedBox(height: 16),

            // ── Paid-tier grid (existing) ───────────────────────────────────
            Text(
              isFa ? 'هسته‌های پولی (نیازمند لایسنس Enterprise)'
                  : 'Paid Tier Cores (Enterprise license required)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _cores.length,
              itemBuilder: (context, index) {
                final core = _cores[index];
                final isActive = core.id == vpnState.activeCore;
                return _CoreCard(
                  core: core,
                  isActive: isActive,
                  isFa: isFa,
                  onSwitch: () => _switchCore(core.id),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshCores() async {
    try {
      final bridge = context.read<DaemonBridge>();
      final available = await bridge.getAvailableCores();
      if (available.isNotEmpty) {
        setState(() {
          _cores = available.map((e) {
            return CoreAdapter(
              id: e['id'] as String? ?? '',
              name: e['name'] as String? ?? '',
              nameFa: e['name_fa'] as String? ?? '',
              version: e['version'] as String? ?? '1.0.0',
              status: _parseCoreStatus(e['status'] as String?),
              health: HealthStatus(
                latency: e['latency'] as int? ?? 0,
                packetLoss: (e['packet_loss'] as num?)?.toDouble() ?? 0.0,
                blocked: e['blocked'] as bool? ?? false,
                dnsLeak: e['dns_leak'] as bool? ?? false,
                dpiExposure: (e['dpi_exposure'] as num?)?.toDouble() ?? 0.0,
                bandwidth: e['bandwidth'] as int? ?? 0,
              ),
              protocols: (e['protocols'] as List<dynamic>?)
                      ?.map((p) => p.toString())
                      .toList() ??
                  [],
              capabilities: (e['capabilities'] as List<dynamic>?)
                      ?.map((c) => c.toString())
                      .toList() ??
                  [],
            );
          }).toList();
        });
      }
    } catch (_) {}
  }

  CoreStatus _parseCoreStatus(String? status) {
    switch (status) {
      case 'connected':
        return CoreStatus.connected;
      case 'disconnected':
        return CoreStatus.disconnected;
      case 'connecting':
        return CoreStatus.connecting;
      case 'error':
        return CoreStatus.error;
      default:
        return CoreStatus.standby;
    }
  }

  void _switchCore(String coreId) async {
    try {
      final bridge = context.read<DaemonBridge>();
      await bridge.switchCore(coreId);
      // Mark the VPN as connected via the canonical VpnState ChangeNotifier.
      context.read<VpnState>().connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Core switch failed: $e')),
        );
      }
    }
  }
}

/// §9 — Spec for a single Free Tier chip.
class _FreeTierChipSpec {
  final String id;
  final String label;
  final String labelFa;
  final IconData icon;
  final Color color;
  final int socks5Port;
  final String tooltip;

  const _FreeTierChipSpec({
    required this.id,
    required this.label,
    required this.labelFa,
    required this.icon,
    required this.color,
    required this.socks5Port,
    required this.tooltip,
  });
}

/// §9 — The Free Tier section header + horizontally-scrollable chip row.
class _FreeTierSection extends StatelessWidget {
  final List<_FreeTierChipSpec> chips;
  final String activeCoreId;
  final bool isFa;
  final ValueChanged<String> onConnect;

  const _FreeTierSection({
    required this.chips,
    required this.activeCoreId,
    required this.isFa,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🆓', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              isFa ? 'لایه رایگان' : 'Free Tier',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.lightBlue,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isFa
                    ? 'بدون نیاز به لایسنس — همیشه قابل استفاده'
                    : 'No license required — always available',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final chip = chips[index];
              final isActive = chip.id == activeCoreId;
              return _FreeTierChip(
                spec: chip,
                isActive: isActive,
                isFa: isFa,
                onTap: () => onConnect(chip.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// §9 — A single Free Tier chip (88×96, colored icon + label + SOCKS5 port).
class _FreeTierChip extends StatelessWidget {
  final _FreeTierChipSpec spec;
  final bool isActive;
  final bool isFa;
  final VoidCallback onTap;

  const _FreeTierChip({
    required this.spec,
    required this.isActive,
    required this.isFa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? spec.color : spec.color.withValues(alpha: 0.55);
    return Tooltip(
      message: spec.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color,
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(spec.icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                isFa ? spec.labelFa : spec.label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SOCKS5 :${spec.socks5Port}',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(height: 4),
                Text(
                  isFa ? 'فعال' : 'ACTIVE',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoreCard extends StatelessWidget {
  final CoreAdapter core;
  final bool isActive;
  final bool isFa;
  final VoidCallback onSwitch;

  const _CoreCard({
    required this.core,
    required this.isActive,
    required this.isFa,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final score = core.score;
    final scoreColor = score >= 70
        ? Colors.green
        : score >= 40
            ? Colors.orange
            : Colors.red;

    return StatusCard(
      borderColor: isActive ? Colors.green.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  isFa ? core.nameFa : core.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'v${core.version}',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),

          const Divider(height: 16),

          // Health stats
          _HealthRow(
            label: isFa ? 'تأخیر' : 'Latency',
            value: '${core.health.latency}ms',
            icon: Icons.speed,
            color: core.health.latency < 200
                ? Colors.green
                : core.health.latency < 500
                    ? Colors.orange
                    : Colors.red,
          ),
          const SizedBox(height: 4),
          _HealthRow(
            label: isFa ? 'افت بسته' : 'Loss',
            value: '${(core.health.packetLoss * 100).toStringAsFixed(1)}%',
            icon: Icons.network_check,
            color: core.health.packetLoss < 0.05
                ? Colors.green
                : core.health.packetLoss < 0.15
                    ? Colors.orange
                    : Colors.red,
          ),
          const SizedBox(height: 4),
          _HealthRow(
            label: isFa ? 'دپی' : 'DPI',
            value: '${(core.health.dpiExposure * 100).toStringAsFixed(0)}%',
            icon: Icons.visibility_off,
            color: core.health.dpiExposure < 0.3
                ? Colors.green
                : core.health.dpiExposure < 0.6
                    ? Colors.orange
                    : Colors.red,
          ),

          // Blocked warning
          if (core.health.blocked) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block, color: Colors.red, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    isFa ? 'مسدود شده' : 'Blocked',
                    style: const TextStyle(color: Colors.red, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Score + Switch
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFa ? 'امتیاز' : 'Score',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                  Text(
                    score.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: core.health.blocked ? null : onSwitch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? Colors.green : Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isActive
                        ? (isFa ? 'فعال' : 'Active')
                        : (isFa ? 'انتخاب' : 'Switch'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _HealthRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
