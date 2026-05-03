// lib/providers/bms_provider.dart
//
// Responsibilities: ALL Riverpod state management for the BMS feature.
// Zero BLE implementation details — delegates entirely to BmsBleService.
//
// Depends on: flutter_riverpod ^2.x

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/ble/ble_service.dart';
import '../../data/models/bms_models.dart';


// ── Device provider ───────────────────────────────────────────────────────

/// Holds the [BluetoothDevice] selected by the user in the scan/connect UI.
///
/// Override this before navigating to the BMS dashboard:
/// ```dart
/// ref.read(bleDeviceProvider.notifier).state = selectedDevice;
/// ```
final bleDeviceProvider = StateProvider<BluetoothDevice?>((ref) => null);

// ── Service provider ───────────────────────────────────────────────────────

/// Creates and manages the lifetime of [BmsBleService].
///
/// Scoped to the presence of a non-null [bleDeviceProvider].
/// Automatically calls [BmsBleService.connect] on creation and
/// [BmsBleService.disconnect] on disposal (e.g. when the user navigates away).
final bmsBleServiceProvider =
Provider.autoDispose<BmsBleService?>((ref) {
  final device = ref.watch(bleDeviceProvider);
  if (device == null) return null;

  final service = BmsBleService(device);

  service.connect().catchError((Object e) {
    assert(() {
      print('[bmsBleServiceProvider] Connection error: $e');
      return true;
    }());
  });

  ref.onDispose(() => service.disconnect()); // ← fix here

  return service;
});

// ── Primary snapshot stream ────────────────────────────────────────────────

/// Core provider — emits a new [BmsSnapshot] every time any BMS frame arrives.
///
/// Widgets that need multiple fields (SOC + current + cells) should watch
/// this directly to avoid multiple rebuilds.
final bmsSnapshotProvider =
StreamProvider.autoDispose<BmsSnapshot>((ref) {
  final service = ref.watch(bmsBleServiceProvider);
  if (service == null) return const Stream.empty();
  return service.snapshotStream;
});

// ── Derived convenience providers ────────────────────────────────────────
//
// Use these in widgets that care about a single value and want independent
// rebuild granularity. Do not create more than needed — each adds overhead.

/// Current SOC (%) — null while connecting or before first frame.
final bmsSocProvider = Provider.autoDispose<double?>((ref) =>
ref.watch(bmsSnapshotProvider).value?.mainFrame?.soc);

/// Signed current in Amperes — null while connecting or before first frame.
final bmsCurrentProvider = Provider.autoDispose<double?>((ref) =>
ref.watch(bmsSnapshotProvider).value?.mainFrame?.currentAmps);

/// Charge status — null while connecting or before first frame.
final bmsStatusProvider = Provider.autoDispose<ChargeStatus?>((ref) =>
ref.watch(bmsSnapshotProvider).value?.mainFrame?.status);

/// Cell voltage list — null while connecting or before first frame.
final bmsCellVoltagesProvider = Provider.autoDispose<List<double>?>((ref) =>
ref.watch(bmsSnapshotProvider).value?.cellFrame?.voltages);