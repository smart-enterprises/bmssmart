// lib/features/bms/presentation/providers/bms_provider.dart
//
// Single source of truth for all BMS Riverpod state.

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../data/models/bms_models.dart';

// ── Device provider ──────────────────────────────────────────────────────────
/// The device chosen by the user in the scan screen.
/// Set this before navigating to the dashboard.
final bleDeviceProvider = StateProvider<BluetoothDevice?>((ref) => null);

// ── Service provider ─────────────────────────────────────────────────────────
/// Creates and owns the BmsBleService lifetime.
/// Auto-disposes when the device is cleared or the scope is left.
final bmsBleServiceProvider = Provider.autoDispose<BmsBleService?>((ref) {
  final device = ref.watch(bleDeviceProvider);
  if (device == null) return null;

  // The service must outlive the gap between "scanner starts connecting" and
  // "dashboard mounts and starts watching". Without keepAlive, the scanner's
  // ref.read registers no listener, so this provider would be auto-disposed on
  // the next event-loop turn — mid-handshake — and disconnect() would resolve
  // the pending connection with "Service disposed before handshake completed".
  // Lifetime is driven by bleDeviceProvider instead: clearing the device
  // rebuilds this provider and disposes the old service.
  ref.keepAlive();

  final service = BmsBleService(device);

  service.connect().catchError((Object e) {
    AppLogger.instance.e('provider', 'Connection error: $e');
  });

  ref.onDispose(service.disconnect);
  return service;
});

// ── Connection status stream ─────────────────────────────────────────────────
final bleStatusProvider = StreamProvider.autoDispose<BleStatus>((ref) {
  final service = ref.watch(bmsBleServiceProvider);
  if (service == null) {
    return Stream.value(const BleStatus(BleConnectionState.disconnected));
  }
  return service.statusStream;
});

// ── Snapshot stream ──────────────────────────────────────────────────────────
final bmsSnapshotProvider = StreamProvider.autoDispose<BmsSnapshot>((ref) {
  final service = ref.watch(bmsBleServiceProvider);
  if (service == null) return const Stream.empty();
  return service.snapshotStream;
});

// ── Derived convenience providers ────────────────────────────────────────────
final bmsSocProvider = Provider.autoDispose<double?>(
  (ref) => ref.watch(bmsSnapshotProvider).value?.soc,
);

final bmsCurrentProvider = Provider.autoDispose<double?>(
  (ref) => ref.watch(bmsSnapshotProvider).value?.currentAmps,
);

final bmsStatusProvider = Provider.autoDispose<ChargeStatus?>(
  (ref) => ref.watch(bmsSnapshotProvider).value?.status,
);

final bmsCellVoltagesProvider = Provider.autoDispose<List<double>?>(
  (ref) => ref.watch(bmsSnapshotProvider).value?.cellVoltages,
);
