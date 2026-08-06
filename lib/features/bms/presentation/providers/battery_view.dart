// lib/features/bms/presentation/providers/battery_view.dart
//
// One battery reading, from whichever source can currently supply it.
//
// The app has two independent paths to the same pack: BLE straight from the
// BMS, and the cloud, where the ESP32 gateway uploads the same telemetry. They
// fail independently — no network in a plant room, out of Bluetooth range from
// the far side of the house — so screens read from here instead of picking a
// source themselves, and none of them has to know which one answered.
//
// PREFERENCE ORDER: cloud first, BLE second. The cloud is preferred because it
// works from anywhere and the gateway is always next to the pack, while BLE
// only works within a few metres. But a cloud reading is only accepted while it
// is FRESH — a gateway that stopped uploading an hour ago must not out-rank a
// BLE link that is answering right now, which is the whole reason
// [kCloudFreshness] exists rather than a simple "cloud if signed in".
//
// Control is a separate question from data: charge/discharge MOSFET commands
// have no cloud equivalent, so [BatteryView.controlAvailable] is true only
// with a live BLE link, regardless of where the numbers came from.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../cloud/cloud_providers.dart';
import '../../data/models/bms_models.dart';
import 'bms_provider.dart';

/// How old a cloud reading may be and still be treated as live. The gateway
/// uploads about once a second, so anything past this means it has stopped —
/// at which point a working BLE link is the better answer.
const kCloudFreshness = Duration(seconds: 45);

/// How old the displayed reading may be before screens dim it.
///
/// Values are never blanked when a cycle is missed — a number that vanishes
/// and comes back reads as a fault in the app, and the last reading from two
/// seconds ago is still the best answer anyone has. It is dimmed instead, and
/// its age is stated, so "stale" is visible without being alarming.
const kStaleAfter = Duration(seconds: 5);

enum BatterySource { cloud, ble, none }

class BatteryView {
  const BatteryView({
    required this.source,
    this.soc,
    this.packVoltage,
    this.currentAmps,
    this.remainingAh,
    this.tempC,
    this.cycles,
    this.cells = const [],
    this.chargeMosOn,
    this.dischargeMosOn,
    this.balancingCells = const {},
    this.updatedAt,
    this.controlAvailable = false,
    this.cloudStale = false,
  });

  final BatterySource source;
  final double? soc;
  final double? packVoltage;
  final double? currentAmps;
  final double? remainingAh;
  final int? tempC;
  final int? cycles;
  final List<double> cells;
  final bool? chargeMosOn;
  final bool? dischargeMosOn;
  final Set<int> balancingCells;
  final DateTime? updatedAt;

  /// True only when BLE is connected. MOSFET control is a BLE command with no
  /// cloud equivalent, so a screen showing cloud data must still disable its
  /// switches.
  final bool controlAvailable;

  /// True when the cloud had a reading but it was too old to use. Distinct
  /// from having no cloud data at all — it means the gateway has stopped, which
  /// is worth saying out loud rather than silently falling back.
  final bool cloudStale;

  bool get hasData => source != BatterySource.none;

  /// How long ago these values were read from the pack.
  Duration? get age =>
      updatedAt == null ? null : DateTime.now().difference(updatedAt!);

  /// True once the reading is old enough to be worth dimming. Unknown age
  /// counts as stale — the alternative is presenting a number of unknown
  /// vintage as current.
  bool get isStale => hasData && (age ?? Duration.zero) > kStaleAfter;

  /// "3s ago" / "2m ago", for the freshness indicator that replaces blanking.
  String get ageLabel {
    final a = age;
    if (a == null) return 'no reading yet';
    if (a.inSeconds < 1) return 'just now';
    if (a.inSeconds < 60) return '${a.inSeconds}s ago';
    if (a.inMinutes < 60) return '${a.inMinutes}m ago';
    return '${a.inHours}h ago';
  }

  ChargeStatus? get status =>
      currentAmps == null ? null : resolveStatus(currentAmps!);

  double? get cellMinV => cells.isEmpty ? null : cells.reduce((a, b) => a < b ? a : b);
  double? get cellMaxV => cells.isEmpty ? null : cells.reduce((a, b) => a > b ? a : b);
  int? get cellDeltaMv => cells.isEmpty ? null : ((cellMaxV! - cellMinV!) * 1000).round();

  /// Hours left at the present discharge, or null when charging/idle — a
  /// runtime figure while charging would be meaningless.
  double? get runtimeHours => (remainingAh != null && (currentAmps ?? 0) < -0.05)
      ? estimateRuntimeHours(remainingAh: remainingAh!, loadAmps: -currentAmps!)
      : null;
}

/// Ticks once a second so age-dependent UI keeps counting while nothing is
/// arriving. Without it the "Xs ago" label would freeze at whatever it read on
/// the last frame — stuck at "1s ago" precisely when the link has died and the
/// age is the only thing worth knowing.
final freshnessTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
);

/// The single source screens read. Recomputes whenever either input changes.
final batteryViewProvider = Provider.autoDispose<BatteryView>((ref) {
  ref.watch(freshnessTickProvider);
  final bleStatus = ref.watch(bleStatusProvider).value;
  final bleConnected = bleStatus?.state == BleConnectionState.connected;
  final ble = ref.watch(bmsSnapshotProvider).value;
  final cloud = ref.watch(latestReadingProvider).value;

  final cloudUsable = cloud != null && cloud.age <= kCloudFreshness;
  final cloudStale = cloud != null && !cloudUsable;

  if (cloudUsable) {
    return BatteryView(
      source: BatterySource.cloud,
      soc: cloud.soc,
      packVoltage: cloud.voltage,
      currentAmps: cloud.current,
      remainingAh: cloud.remainingAh,
      tempC: cloud.temperature,
      cycles: cloud.cycles,
      cells: cloud.cells,
      chargeMosOn: cloud.chargeMosOn,
      dischargeMosOn: cloud.dischargeMosOn,
      updatedAt: cloud.timestamp,
      controlAvailable: bleConnected,
      // Balancing is not uploaded by the gateway, so it stays empty on the
      // cloud path rather than being guessed at.
    );
  }

  // Deliberately not gated on `bleConnected`. A dropped cycle or a reconnect
  // in progress must not empty the screen — the last snapshot is still the
  // truest thing available, and `age`/`isStale` say how old it is. Control is
  // gated on the live link instead, further down.
  if (ble != null && ble.hasCoreData) {
    return BatteryView(
      source: BatterySource.ble,
      soc: ble.soc,
      packVoltage: ble.packVoltage,
      currentAmps: ble.currentAmps,
      remainingAh: ble.remainingAh,
      tempC: ble.maxTempC,
      cycles: ble.cycleCount,
      cells: ble.cellVoltages,
      chargeMosOn: ble.chargeMosOn,
      dischargeMosOn: ble.dischargeMosOn,
      balancingCells: ble.balancingCells,
      updatedAt: ble.updatedAt,
      controlAvailable: bleConnected,
      cloudStale: cloudStale,
    );
  }

  return BatteryView(source: BatterySource.none, cloudStale: cloudStale);
});
