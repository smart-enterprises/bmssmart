// lib/features/bms/presentation/screens/splash_screen.dart
//
// App entry screen. Shows the brand mark for a minimum of [_minSplash]; if a
// previously-connected BMS is remembered, it attempts a silent reconnect in
// the background during that window (extending up to [_maxSplash] total if
// the connection is still in progress) and skips straight to the dashboard
// on success. Otherwise it falls through to the scanner.

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/persistence/last_device_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bms_provider.dart';
import 'home_shell.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// Always shown for at least this long, so the splash never flashes past
  /// too fast to register even when a device isn't remembered.
  static const _minSplash = Duration(seconds: 3);

  /// Hard cap on total time spent waiting for a silent reconnect before
  /// giving up and falling through to the scanner.
  static const _maxSplash = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final start = DateTime.now();
    final last = await LastDeviceStore.load();

    final connected = last == null ? false : await _tryReconnect(last, start);

    final remaining = _minSplash - DateTime.now().difference(start);
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeShell(initialTabIndex: connected ? 0 : kDevicesTabIndex),
      ),
    );
  }

  /// Attempts a silent connect to [last], budgeted against [_maxSplash] from
  /// [start]. Mirrors the scanner's manual-connect flow (same provider
  /// wiring, same cleanup-on-failure) but with no UI feedback of its own —
  /// failure here just means "fall through to the scanner", not an error to
  /// show the user.
  Future<bool> _tryReconnect(LastDevice last, DateTime start) async {
    ref.read(bleDeviceProvider.notifier).state = BluetoothDevice.fromId(last.remoteId);
    // Brief settle so the provider can instantiate the service before we read it.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final service = ref.read(bmsBleServiceProvider);
    if (service == null) {
      ref.read(bleDeviceProvider.notifier).state = null;
      return false;
    }

    final budget = _maxSplash - DateTime.now().difference(start);
    if (budget <= Duration.zero) {
      ref.read(bleDeviceProvider.notifier).state = null;
      return false;
    }

    try {
      final status = await service.connectionFuture.timeout(budget);
      if (status.state == BleConnectionState.connected) {
        await LastDeviceStore.save(last.remoteId, last.name);
        return true;
      }
    } catch (_) {
      // Timeout or connect error — treated the same: fall through silently.
    }
    ref.read(bleDeviceProvider.notifier).state = null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(decoration: BoxDecoration(gradient: appBackgroundGradient)),
          const AmbientBackground(),
          Center(
            child: Image.asset(
              'assets/branding/warrior_loading.gif',
              width: 230,
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
    );
  }
}
