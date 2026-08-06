// lib/features/bms/presentation/screens/home_shell.dart
//
// Persistent shell — owns the single Scaffold, an IndexedStack of the tab
// bodies, and the floating nav overlay. IndexedStack (not route-based tabs)
// keeps each tab's live state (BLE scan subscription, chart data) intact
// across tab switches.
//
// MIGRATION IN PROGRESS. Home and Battery are the Warrior design; History and
// Devices are still the Material 3 screens and are being converted one at a
// time. The nav and theme are already Warrior, so the tabs that have not moved
// yet look like the old app inside the new frame — deliberately visible rather
// than hidden behind a flag, so what is left to do is obvious.
//
// The design's Energy tab is not here yet: it needs kWh accumulated from
// history, which is a real derivation and not a restyle. It gets its slot when
// that screen exists rather than a placeholder that shows nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/warrior_theme.dart';
import '../../../../core/widgets/warrior_widgets.dart';
import '../providers/bms_provider.dart';
import 'warrior_battery_screen.dart';
import 'history_screen.dart';
import 'scanner_screen.dart';
import '../../../cloud/cloud_login_screen.dart';
import 'warrior_home_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTabIndex = 0});

  /// Which tab to show first — 0 (Home) if a silent reconnect already
  /// succeeded before this widget mounted, 3 (Devices) otherwise, so the user
  /// lands on the actionable tab instead of an empty Home screen.
  final int initialTabIndex;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Seed the shared tab-index provider once, on first build, so it reflects
    // the splash screen's already-computed connection state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(shellTabIndexProvider.notifier).state = widget.initialTabIndex;
    });
  }

  static const _items = [
    WNavItem(icon: Icons.home_rounded, label: 'Home'),
    WNavItem(icon: Icons.battery_std_rounded, label: 'Battery'),
    WNavItem(icon: Icons.show_chart_rounded, label: 'History'),
    WNavItem(icon: Icons.devices_other_rounded, label: 'Devices'),
  ];

  /// Devices is the tab to land on when nothing is connected — it is the only
  /// one with an action on it.
  static const _devicesTab = 3;

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabIndexProvider).clamp(0, _items.length - 1);
    // Side-effect only: gates the per-cell BLE request on the cell tab being
    // the one on top. See cellDetailVisibleProvider.
    ref.watch(cellDetailVisibleProvider);

    return Scaffold(
      backgroundColor: W.surface,
      body: Stack(
        children: [
          IndexedStack(
            index: index,
            children: [
              WarriorHomeScreen(
                // Sign-in lives behind the avatar rather than at startup: the
                // app works over BLE with no account, so a login wall would
                // break the case of standing next to a pack with no signal.
                onOpenSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CloudLoginScreen()),
                ),
                onOpenAlerts: () => _notYet(context, 'Alerts & events'),
                onOpenEnergy: () => _notYet(context, 'Energy & outages'),
              ),
              const WarriorBatteryScreen(),
              const HistoryScreen(),
              const BleScannerScreenBody(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: WFloatingNav(
              items: _items,
              index: index,
              onChanged: (i) => ref.read(shellTabIndexProvider.notifier).state = i,
            ),
          ),
        ],
      ),
    );
  }

  /// Honest stub for the screens still being built. A dead tap would read as a
  /// bug; this says what it is.
  void _notYet(BuildContext context, String screen) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$screen is not built yet.')),
    );
  }
}

/// Kept so callers that used the old constant still land somewhere sensible.
const kDevicesTabIndex = _HomeShellState._devicesTab;
