// lib/features/bms/presentation/screens/home_shell.dart
//
// Persistent Material 3 shell — owns the single Scaffold, an IndexedStack of
// the 3 tab bodies (Home/History/Connection), and the floating M3NavBar
// overlay. IndexedStack (not route-based tabs) keeps each tab's live state
// (BLE scan subscription, chart data) intact across tab switches.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/m3_theme.dart';
import '../../../../core/widgets/m3_nav_bar.dart';
import '../providers/bms_provider.dart';
import 'bms_dashboard.dart';
import 'history_screen.dart';
import 'scanner_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTabIndex = 0});

  /// Which tab to show first — 0 (Home) if a silent reconnect already
  /// succeeded before this widget mounted, 2 (Connection) otherwise, so the
  /// user lands on the actionable tab instead of an empty Home screen.
  final int initialTabIndex;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Seed the shared tab-index provider once, on first build, so it
    // reflects the splash screen's already-computed connection state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(shellTabIndexProvider.notifier).state = widget.initialTabIndex;
    });
  }

  static const _items = [
    M3NavItem(icon: Icons.home_rounded, label: 'Home'),
    M3NavItem(icon: Icons.show_chart_rounded, label: 'History'),
    M3NavItem(icon: Icons.bluetooth, label: 'Connection'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabIndexProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: M3Colors.surface,
      body: Stack(
        children: [
          IndexedStack(
            index: index,
            children: const [
              BmsDashboardBody(),
              HistoryScreen(),
              BleScannerScreenBody(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 12,
            child: Center(
              child: M3NavBar(
                items: _items,
                index: index,
                onChanged: (i) => ref.read(shellTabIndexProvider.notifier).state = i,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
