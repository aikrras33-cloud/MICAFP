import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/intranet_service.dart';

/// National Intranet Mode screen.
///
/// Provides access to Iranian national services when internet
/// is severely restricted or in total shutdown mode.
///
/// Ported from `flutter/lib/screens/intranet_mode_screen.dart` per directive §3.5.
/// Adaptations:
///   - Riverpod (`ConsumerStatefulWidget`/`ref.read(intranetServiceProvider)`)
///     converted to `StatefulWidget` + `Provider.of<IntranetService>(...)`
///     per directive §3.22 (drop riverpod in favour of provider).
///   - The `l10n.app_localizations` import is replaced with hardcoded
///     English strings — the canonical `flutter_app` tree drives i18n via
///     the inline `_english`/`_persian` map in `main.dart` (see
///     `LocalizationExtension`), not via the `intl` code-gen path.
///   - The `intranetServiceProvider` riverpod declaration (formerly at the
///     bottom of `intranet_service.dart`) is gone; IntranetService is now
///     wired via `Provider<IntranetService>.value(...)` in `main.dart`.
class IntranetModeScreen extends StatefulWidget {
  const IntranetModeScreen({super.key});

  @override
  State<IntranetModeScreen> createState() => _IntranetModeScreenState();
}

class _IntranetModeScreenState extends State<IntranetModeScreen> {
  IntranetMode _selectedMode = IntranetMode.smart;
  bool _p2pFallback = true;
  bool _isActive = false;
  final Set<String> _selectedCategories = {'banking', 'government', 'health'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('National Intranet Mode'),
        actions: [
          if (_isActive)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      color: Color(0xFFFFB74D),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Color(0xFFFFB74D)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'National intranet mode restricts access to Iranian domestic services only. Activate during severe internet restrictions.',
                    style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Mode Selection
          const Text(
            'Select Mode',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),

          ...IntranetMode.values.where((m) => m != IntranetMode.disabled).map((mode) {
            return _ModeCard(
              mode: mode,
              isSelected: _selectedMode == mode,
              onTap: () => setState(() => _selectedMode = mode),
            );
          }),

          const SizedBox(height: 24),

          // Service Categories
          const Text(
            'Service Categories',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: IntranetService.nationalCategories.keys.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return FilterChip(
                label: Text(_getCategoryName(category)),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedCategories.add(category);
                    } else {
                      _selectedCategories.remove(category);
                    }
                  });
                },
                selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                checkmarkColor: const Color(0xFF00E5FF),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF30363D),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // P2P Fallback
          Card(
            child: SwitchListTile.adaptive(
              title: const Text('P2P Fallback'),
              subtitle: const Text('Use P2P relay for critical external services'),
              value: _p2pFallback,
              onChanged: (val) => setState(() => _p2pFallback = val),
              secondary: const Icon(Icons.hub, color: Color(0xFF7C4DFF)),
            ),
          ),

          const SizedBox(height: 24),

          // Available services list
          const Text(
            'Accessible Services',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),

          ..._selectedCategories.expand((cat) {
            return IntranetService.nationalCategories[cat]!.map((domain) {
              return Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.language, size: 20, color: Color(0xFF00E676)),
                  title: Text(domain, style: const TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                ),
              );
            });
          }),

          const SizedBox(height: 32),

          // Enable/Disable Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _toggleIntranetMode,
              icon: Icon(_isActive ? Icons.lan_outlined : Icons.lan),
              label: Text(
                _isActive ? 'Disable Intranet' : 'Enable National Intranet',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _isActive
                    ? const Color(0xFFFF5252)
                    : const Color(0xFF00E5FF),
                foregroundColor: _isActive ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Auto-detect button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _autoDetect,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Auto Detect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF7C4DFF),
                side: const BorderSide(color: Color(0xFF7C4DFF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getCategoryName(String category) {
    const names = {
      'banking': '🏦 Banking',
      'government': '🏛️ Government',
      'education': '🎓 Education',
      'health': '🏥 Health',
      'news': '📰 News',
      'essential': '🛒 Essential',
    };
    return names[category] ?? category;
  }

  Future<void> _toggleIntranetMode() async {
    final intranet = context.read<IntranetService>();
    try {
      if (_isActive) {
        await intranet.disable();
        setState(() => _isActive = false);
      } else {
        await intranet.enable(
          mode: _selectedMode,
          enableP2PFallback: _p2pFallback,
        );
        setState(() => _isActive = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _autoDetect() async {
    final intranet = context.read<IntranetService>();
    final detected = await intranet.autoDetect();
    if (!mounted) return;
    if (detected) {
      setState(() => _isActive = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ National intranet conditions detected. Mode activated.'),
          backgroundColor: Color(0xFFFFB74D),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Normal internet conditions detected.')),
      );
    }
  }
}

class _ModeCard extends StatelessWidget {
  final IntranetMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected
              ? const BorderSide(color: Color(0xFF00E5FF), width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Radio<IntranetMode>(
                  value: mode,
                  groupValue: isSelected ? mode : null,
                  onChanged: (_) => onTap(),
                  activeColor: const Color(0xFF00E5FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getModeTitle(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF00E5FF) : null,
                        ),
                      ),
                      Text(
                        _getModeDescription(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getModeTitle() {
    switch (mode) {
      case IntranetMode.disabled: return 'Disabled';
      case IntranetMode.essential: return '🟡 Essential';
      case IntranetMode.smart: return '🟢 Smart';
      case IntranetMode.full: return '🔴 Full';
    }
  }

  String _getModeDescription() {
    switch (mode) {
      case IntranetMode.disabled: return 'Intranet mode off';
      case IntranetMode.essential: return 'Banking, government, health only';
      case IntranetMode.smart: return 'All national services + P2P fallback';
      case IntranetMode.full: return 'All .ir domains allowed';
    }
  }
}
