// lib/features/bms/data/models/bms_models.dart
//
// Daly BMS domain models. Pure Dart — zero Flutter / BLE / Riverpod imports.
//
// Daly splits its telemetry across several small commands rather than one big
// status frame, so a complete picture is assembled by merging the responses of
// 0x90/0x91/0x92/0x93/0x94/0x95 into a single BmsSnapshot.

// ── Charge status ──────────────────────────────────────────────────────────

enum ChargeStatus { charging, discharging, idle }

/// Resolves [ChargeStatus] from [currentAmps] using a ±0.1 A dead band
/// to prevent flickering on noisy readings near zero.
ChargeStatus resolveStatus(double currentAmps) {
  if (currentAmps > 0.1) return ChargeStatus.charging;
  if (currentAmps < -0.1) return ChargeStatus.discharging;
  return ChargeStatus.idle;
}

/// Hours remaining at the present discharge load, or null when there's no
/// meaningful estimate (not discharging, or load is ~0 A).
double? estimateRuntimeHours({required double remainingAh, required double loadAmps}) {
  if (loadAmps <= 0.05) return null;
  return remainingAh / loadAmps;
}

/// Hours until the pack reaches full charge at the present charge rate, or
/// null when there's no meaningful estimate (no capacity data, or the charge
/// current is too small to be a real projection). Returns 0 once the
/// remaining gap to full is negligible, rather than a tiny/noisy duration.
///
/// Like [estimateRuntimeHours], this is a simple linear projection: it
/// assumes the present current holds steady. It reads increasingly optimistic
/// once the pack enters the CV taper near 100%, where charge current tapers
/// off well before the linear estimate would predict completion.
double? estimateTimeToFullHours({
  required double remainingAh,
  required double nominalAh,
  required double chargeAmps,
}) {
  final capacityToFillAh = (nominalAh - remainingAh).clamp(0.0, nominalAh);
  if (capacityToFillAh <= 0.05) return 0;
  return estimateRuntimeHours(remainingAh: capacityToFillAh, loadAmps: chargeAmps);
}

/// Formats hours as "Xh Ym" ("Ym" alone under an hour, rounded to the minute).
String formatDuration(double? hours) {
  if (hours == null || !hours.isFinite || hours < 0) return '—';
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h <= 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

// ── Temperature thresholds ───────────────────────────────────────────────────

enum TempSeverity { normal, warning, critical }

/// Fixed temperature thresholds, in °C. Not user-adjustable by design.
class TempThresholds {
  final int warningC;
  final int criticalC;
  const TempThresholds({required this.warningC, required this.criticalC});

  TempSeverity classify(double tempC) {
    if (tempC >= criticalC) return TempSeverity.critical;
    if (tempC >= warningC) return TempSeverity.warning;
    return TempSeverity.normal;
  }

  @override
  String toString() => 'TempThresholds(warn: $warningC°C, crit: $criticalC°C)';
}

/// The pack's temperature alert levels. Fixed, not user-editable.
const kTempThresholds = TempThresholds(warningC: 70, criticalC: 85);

// ── Sealed DalyFrame hierarchy ─────────────────────────────────────────────
//
// One subtype per Daly command. Each is the parsed form of a single 13-byte
// response frame.

sealed class DalyFrame {
  final DateTime timestamp;
  const DalyFrame({required this.timestamp});
}

/// 0x90 — pack voltage, current, SOC.
final class DalySocFrame extends DalyFrame {
  /// Total pack voltage in Volts.
  final double packVoltage;

  /// Signed current in Amperes (positive = charging, negative = discharging).
  final double currentAmps;

  /// State of charge in percent (0.0–100.0).
  final double soc;

  const DalySocFrame({
    required this.packVoltage,
    required this.currentAmps,
    required this.soc,
    required super.timestamp,
  });

  @override
  String toString() =>
      'DalySocFrame(${packVoltage}V, ${currentAmps}A, $soc%)';
}

/// 0x91 — highest / lowest cell voltage and which cell they belong to.
final class DalyMinMaxCellFrame extends DalyFrame {
  final int maxCellMv;
  final int maxCellNumber;
  final int minCellMv;
  final int minCellNumber;

  const DalyMinMaxCellFrame({
    required this.maxCellMv,
    required this.maxCellNumber,
    required this.minCellMv,
    required this.minCellNumber,
    required super.timestamp,
  });

  int get deltaMv => maxCellMv - minCellMv;

  @override
  String toString() =>
      'DalyMinMaxCellFrame(max ${maxCellMv}mV #$maxCellNumber, '
      'min ${minCellMv}mV #$minCellNumber, Δ${deltaMv}mV)';
}

/// 0x92 — pack temperature extremes, in degrees Celsius.
final class DalyTempFrame extends DalyFrame {
  final int maxTempC;
  final int maxTempSensor;
  final int minTempC;
  final int minTempSensor;

  const DalyTempFrame({
    required this.maxTempC,
    required this.maxTempSensor,
    required this.minTempC,
    required this.minTempSensor,
    required super.timestamp,
  });

  @override
  String toString() => 'DalyTempFrame(max $maxTempC°C, min $minTempC°C)';
}

/// 0x93 — MOSFET state and remaining capacity.
final class DalyMosFrame extends DalyFrame {
  /// Raw state byte: 0 = stationary, 1 = charging, 2 = discharging.
  final int stateByte;
  final bool chargeMosOn;
  final bool dischargeMosOn;

  /// BMS life-cycle counter (0–255, wraps). Useful as a liveness signal.
  final int bmsLife;

  /// Remaining capacity in Amp-hours.
  final double remainingAh;

  const DalyMosFrame({
    required this.stateByte,
    required this.chargeMosOn,
    required this.dischargeMosOn,
    required this.bmsLife,
    required this.remainingAh,
    required super.timestamp,
  });

  @override
  String toString() =>
      'DalyMosFrame(state $stateByte, chg $chargeMosOn, dsg $dischargeMosOn, '
      '${remainingAh}Ah)';
}

/// 0x94 — pack configuration and cycle count.
final class DalyStatusFrame extends DalyFrame {
  final int cellCount;
  final int tempSensorCount;
  final bool chargerConnected;
  final bool loadConnected;
  final int cycleCount;

  const DalyStatusFrame({
    required this.cellCount,
    required this.tempSensorCount,
    required this.chargerConnected,
    required this.loadConnected,
    required this.cycleCount,
    required super.timestamp,
  });

  @override
  String toString() =>
      'DalyStatusFrame($cellCount cells, $tempSensorCount temps, '
      '$cycleCount cycles)';
}

/// 0x95 — one sub-frame of the multi-frame cell voltage response.
///
/// Each frame carries up to three cells; [frameNumber] is 1-based, so frame 1
/// holds cells 1–3, frame 2 holds cells 4–6, and so on.
final class DalyCellVoltageFrame extends DalyFrame {
  final int frameNumber;

  /// Up to three cell voltages in millivolts, in physical cell order.
  final List<int> millivolts;

  const DalyCellVoltageFrame({
    required this.frameNumber,
    required this.millivolts,
    required super.timestamp,
  });

  /// 1-based index of the first cell carried by this frame.
  int get firstCellNumber => (frameNumber - 1) * 3 + 1;

  @override
  String toString() =>
      'DalyCellVoltageFrame(#$frameNumber, cells from $firstCellNumber: '
      '$millivolts)';
}

/// 0xD9 / 0xDA — the BMS echoing back a MOSFET control command.
///
/// This is only an acknowledgement that the command was received, not proof
/// that the MOSFET actually changed state: a BMS under protection will ack and
/// then refuse. So this frame deliberately does not update the snapshot — the
/// 0x93 poll reports the real state a moment later.
final class DalyMosAckFrame extends DalyFrame {
  /// True for the charge MOSFET (0xD9), false for discharge (0xDA).
  final bool isCharge;

  /// The state that was requested, echoed back.
  final bool requestedOn;

  const DalyMosAckFrame({
    required this.isCharge,
    required this.requestedOn,
    required super.timestamp,
  });

  @override
  String toString() => 'DalyMosAckFrame(${isCharge ? "charge" : "discharge"} '
      'MOS → ${requestedOn ? "ON" : "OFF"} acknowledged)';
}

/// 0x96 — per-sensor temperatures. Like 0x95, this can span multiple frames
/// (7 sensors per frame), though a small pack answers in one.
final class DalyCellTempFrame extends DalyFrame {
  final int frameNumber;

  /// Temperatures in °C for the sensors carried by this frame, in order.
  /// Unused sensor slots (transmitted as 0xFF) are omitted.
  final List<int> temps;

  const DalyCellTempFrame({
    required this.frameNumber,
    required this.temps,
    required super.timestamp,
  });

  int get firstSensorIndex => (frameNumber - 1) * 7;

  @override
  String toString() =>
      'DalyCellTempFrame(#$frameNumber, temps $temps)';
}

/// 0x97 — which cells are actively balancing, as a set of 1-based cell numbers.
final class DalyBalanceFrame extends DalyFrame {
  final Set<int> balancingCells;

  const DalyBalanceFrame({
    required this.balancingCells,
    required super.timestamp,
  });

  @override
  String toString() => 'DalyBalanceFrame(balancing: '
      '${balancingCells.isEmpty ? "none" : balancingCells.join(",")})';
}

/// 0x98 — active protection/alarm flags, already decoded into readable labels.
final class DalyFaultFrame extends DalyFrame {
  /// Human-readable labels for every alarm bit that is currently set.
  /// Empty means the pack reports no active faults.
  final List<String> activeFaults;

  /// The BMS's own fault counter (data byte 7).
  final int faultCount;

  const DalyFaultFrame({
    required this.activeFaults,
    required this.faultCount,
    required super.timestamp,
  });

  bool get hasFault => activeFaults.isNotEmpty;

  @override
  String toString() => 'DalyFaultFrame(${activeFaults.isEmpty ? "no faults" : activeFaults.join("; ")})';
}

/// 0x50 — rated pack capacity and nominal cell voltage.
final class DalyRatedFrame extends DalyFrame {
  /// Rated (nameplate) capacity in Amp-hours.
  final double ratedAh;

  /// Nominal per-cell voltage in Volts.
  final double ratedCellVolts;

  const DalyRatedFrame({
    required this.ratedAh,
    required this.ratedCellVolts,
    required super.timestamp,
  });

  @override
  String toString() =>
      'DalyRatedFrame(${ratedAh}Ah, ${ratedCellVolts}V/cell)';
}

// ── History ────────────────────────────────────────────────────────────────

/// One time-stamped sample of the headline metrics, for the history charts.
class HistoryPoint {
  final DateTime t;
  final double? soc;
  final double? voltage;
  final double? current;
  final int? deltaMv;

  const HistoryPoint({
    required this.t,
    this.soc,
    this.voltage,
    this.current,
    this.deltaMv,
  });
}

// ── JBD frames ────────────────────────────────────────────────────────────
//
// JBD (Jiabaida — commonly rebranded as Overkill Solar, EBM, and others)
// speaks a different protocol from Daly, carried over a different BLE
// service (ff00 vs Daly's fff0). Frames are DD...77-bounded and
// variable-length, unlike Daly's fixed 13 bytes. See jbd_parser.dart for the
// frame format and an important caveat: these offsets are inherited from an
// earlier version of this app and have not yet been re-verified against a
// real device in this project.

sealed class JbdFrame {
  final DateTime timestamp;
  const JbdFrame({required this.timestamp});
}

/// 0x03 — main pack data: voltage, current, capacity, cycles, SOC, MOSFET
/// state, and NTC temperatures, all in one frame (unlike Daly, which splits
/// these across several commands).
final class JbdMainFrame extends JbdFrame {
  final double packVoltage;
  final double currentAmps;
  final double remainingAh;
  final double nominalAh;
  final int cycleCount;
  final int protectionStateBits;
  final double soc;
  final int mosfetState;
  final int cellCount;

  /// NTC sensor temperatures in °C, in sensor order.
  final List<double> ntcTempsC;

  const JbdMainFrame({
    required this.packVoltage,
    required this.currentAmps,
    required this.remainingAh,
    required this.nominalAh,
    required this.cycleCount,
    required this.protectionStateBits,
    required this.soc,
    required this.mosfetState,
    required this.cellCount,
    required this.ntcTempsC,
    required super.timestamp,
  });

  // Reversed from the commonly published convention (bit0=charge,
  // bit1=discharge) — verified 2026-07-20 by replaying a captured HCI snoop
  // log of a single official-app "Discharge off" action and cross-checking
  // the resulting raw mosfetState against what the official app's own
  // screen showed afterward (Charge: on, Discharge: off), not just a
  // checksum match. Mirrors the reversed Daly MOSFET opcodes elsewhere in
  // this project — treat every "documented" JBD polarity as unverified
  // until checked against this hardware.
  bool get dischargeMosOn => (mosfetState & 0x01) != 0;
  bool get chargeMosOn => (mosfetState & 0x02) != 0;

  @override
  String toString() => 'JbdMainFrame(${packVoltage}V, ${currentAmps}A, $soc%, '
      '$cellCount cells, chg=$chargeMosOn dsg=$dischargeMosOn)';
}

/// 0x04 — every cell voltage in a single frame (unlike Daly's 0x95, which
/// pages 3 cells per sub-frame).
final class JbdCellVoltageFrame extends JbdFrame {
  final List<double> voltages;
  const JbdCellVoltageFrame({required this.voltages, required super.timestamp});

  @override
  String toString() => 'JbdCellVoltageFrame(${voltages.length} cells: $voltages)';
}

// ── BmsSnapshot ────────────────────────────────────────────────────────────

/// Merged view of every Daly response received so far.
///
/// Fields are nullable because Daly answers each command separately: a
/// snapshot is progressively filled in as responses arrive, and any given
/// field stays null until its command has been answered at least once.
class BmsSnapshot {
  final double? packVoltage;
  final double? currentAmps;
  final double? soc;

  final double? remainingAh;
  final double? nominalAh;
  final int? cycleCount;

  final int? cellCount;
  final int? tempSensorCount;

  /// Per-cell voltages in Volts, index 0 = cell 1. Empty until 0x95 arrives.
  final List<double> cellVoltages;

  final int? maxCellMv;
  final int? maxCellNumber;
  final int? minCellMv;
  final int? minCellNumber;

  final int? maxTempC;
  final int? minTempC;

  /// Per-sensor temperatures in °C, index 0 = sensor 1. Empty until 0x96.
  final List<int> cellTemps;

  final bool? chargeMosOn;
  final bool? dischargeMosOn;

  /// 1-based numbers of cells that are actively balancing (from 0x97).
  final Set<int> balancingCells;

  /// Active protection/alarm labels (from 0x98). Empty means no active fault.
  /// Null means 0x98 has not been answered yet — distinct from "answered, and
  /// nothing is wrong".
  final List<String>? activeFaults;

  final DateTime? updatedAt;

  const BmsSnapshot({
    this.packVoltage,
    this.currentAmps,
    this.soc,
    this.remainingAh,
    this.nominalAh,
    this.cycleCount,
    this.cellCount,
    this.tempSensorCount,
    this.cellVoltages = const [],
    this.maxCellMv,
    this.maxCellNumber,
    this.minCellMv,
    this.minCellNumber,
    this.maxTempC,
    this.minTempC,
    this.cellTemps = const [],
    this.chargeMosOn,
    this.dischargeMosOn,
    this.balancingCells = const {},
    this.activeFaults,
    this.updatedAt,
  });

  /// True once 0x98 has been answered and reports at least one active alarm.
  bool get hasFault => activeFaults != null && activeFaults!.isNotEmpty;

  /// Highest temperature currently known, from per-sensor readings if we have
  /// them, else the 0x92 max. Null until any temperature has arrived.
  int? get maxObservedTempC {
    if (cellTemps.isNotEmpty) return cellTemps.reduce((a, b) => a > b ? a : b);
    return maxTempC;
  }

  /// True once the essential 0x90 telemetry has landed — the point at which
  /// the dashboard has something real to render.
  bool get hasCoreData => packVoltage != null && soc != null;

  ChargeStatus? get status =>
      currentAmps == null ? null : resolveStatus(currentAmps!);

  double? get minCellVolts =>
      cellVoltages.isEmpty ? null : cellVoltages.reduce((a, b) => a < b ? a : b);
  double? get maxCellVolts =>
      cellVoltages.isEmpty ? null : cellVoltages.reduce((a, b) => a > b ? a : b);
  double? get deltaCellVolts {
    final lo = minCellVolts, hi = maxCellVolts;
    return (lo == null || hi == null) ? null : hi - lo;
  }

  double? get averageCellVolts => cellVoltages.isEmpty
      ? null
      : cellVoltages.reduce((a, b) => a + b) / cellVoltages.length;

  BmsSnapshot copyWith({
    double? packVoltage,
    double? currentAmps,
    double? soc,
    double? remainingAh,
    double? nominalAh,
    int? cycleCount,
    int? cellCount,
    int? tempSensorCount,
    List<double>? cellVoltages,
    int? maxCellMv,
    int? maxCellNumber,
    int? minCellMv,
    int? minCellNumber,
    int? maxTempC,
    int? minTempC,
    List<int>? cellTemps,
    bool? chargeMosOn,
    bool? dischargeMosOn,
    Set<int>? balancingCells,
    List<String>? activeFaults,
    DateTime? updatedAt,
  }) =>
      BmsSnapshot(
        packVoltage: packVoltage ?? this.packVoltage,
        currentAmps: currentAmps ?? this.currentAmps,
        soc: soc ?? this.soc,
        remainingAh: remainingAh ?? this.remainingAh,
        nominalAh: nominalAh ?? this.nominalAh,
        cycleCount: cycleCount ?? this.cycleCount,
        cellCount: cellCount ?? this.cellCount,
        tempSensorCount: tempSensorCount ?? this.tempSensorCount,
        cellVoltages: cellVoltages ?? this.cellVoltages,
        maxCellMv: maxCellMv ?? this.maxCellMv,
        maxCellNumber: maxCellNumber ?? this.maxCellNumber,
        minCellMv: minCellMv ?? this.minCellMv,
        minCellNumber: minCellNumber ?? this.minCellNumber,
        maxTempC: maxTempC ?? this.maxTempC,
        minTempC: minTempC ?? this.minTempC,
        cellTemps: cellTemps ?? this.cellTemps,
        chargeMosOn: chargeMosOn ?? this.chargeMosOn,
        dischargeMosOn: dischargeMosOn ?? this.dischargeMosOn,
        balancingCells: balancingCells ?? this.balancingCells,
        activeFaults: activeFaults ?? this.activeFaults,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Folds a freshly parsed [frame] into this snapshot.
  ///
  /// Cell voltage frames are merged positionally rather than appended, so a
  /// dropped sub-frame leaves the previous value in place instead of shifting
  /// every later cell down a slot.
  BmsSnapshot merge(DalyFrame frame) {
    return switch (frame) {
      DalySocFrame f => copyWith(
          packVoltage: f.packVoltage,
          currentAmps: f.currentAmps,
          soc: f.soc,
          updatedAt: f.timestamp,
        ),
      DalyMinMaxCellFrame f => copyWith(
          maxCellMv: f.maxCellMv,
          maxCellNumber: f.maxCellNumber,
          minCellMv: f.minCellMv,
          minCellNumber: f.minCellNumber,
          updatedAt: f.timestamp,
        ),
      DalyTempFrame f => copyWith(
          maxTempC: f.maxTempC,
          minTempC: f.minTempC,
          updatedAt: f.timestamp,
        ),
      DalyMosFrame f => copyWith(
          chargeMosOn: f.chargeMosOn,
          dischargeMosOn: f.dischargeMosOn,
          remainingAh: f.remainingAh,
          updatedAt: f.timestamp,
        ),
      DalyStatusFrame f => copyWith(
          cellCount: f.cellCount,
          tempSensorCount: f.tempSensorCount,
          cycleCount: f.cycleCount,
          updatedAt: f.timestamp,
        ),
      DalyRatedFrame f => copyWith(
          nominalAh: f.ratedAh,
          updatedAt: f.timestamp,
        ),
      DalyCellVoltageFrame f => copyWith(
          cellVoltages: _mergeCellVoltages(f),
          updatedAt: f.timestamp,
        ),
      DalyCellTempFrame f => copyWith(
          cellTemps: _mergeCellTemps(f),
          updatedAt: f.timestamp,
        ),
      DalyBalanceFrame f => copyWith(
          balancingCells: f.balancingCells,
          updatedAt: f.timestamp,
        ),
      DalyFaultFrame f => copyWith(
          activeFaults: f.activeFaults,
          updatedAt: f.timestamp,
        ),
      // An ack is not evidence of a state change — let the next 0x93 report
      // what actually happened rather than showing an optimistic lie.
      DalyMosAckFrame() => this,
    };
  }

  /// Folds a freshly parsed JBD [frame] into this snapshot. JBD's 0x03 sends
  /// everything but cell voltages in one shot, and 0x04 sends every cell
  /// voltage in one shot too — no positional merging needed, unlike Daly's
  /// paged cell frames.
  BmsSnapshot mergeJbd(JbdFrame frame) {
    return switch (frame) {
      JbdMainFrame f => copyWith(
          packVoltage: f.packVoltage,
          currentAmps: f.currentAmps,
          soc: f.soc,
          remainingAh: f.remainingAh,
          nominalAh: f.nominalAh,
          cycleCount: f.cycleCount,
          cellCount: f.cellCount,
          chargeMosOn: f.chargeMosOn,
          dischargeMosOn: f.dischargeMosOn,
          tempSensorCount: f.ntcTempsC.length,
          cellTemps: f.ntcTempsC.map((t) => t.round()).toList(),
          maxTempC: f.ntcTempsC.isEmpty ? null : f.ntcTempsC.reduce((a, b) => a > b ? a : b).round(),
          minTempC: f.ntcTempsC.isEmpty ? null : f.ntcTempsC.reduce((a, b) => a < b ? a : b).round(),
          updatedAt: f.timestamp,
        ),
      JbdCellVoltageFrame f => copyWith(
          cellVoltages: f.voltages,
          updatedAt: f.timestamp,
        ),
    };
  }

  List<int> _mergeCellTemps(DalyCellTempFrame f) {
    final start = f.firstSensorIndex;
    if (start < 0) return cellTemps;

    final needed = start + f.temps.length;
    final limit = tempSensorCount ?? needed;
    final next = List<int>.from(cellTemps);
    while (next.length < needed && next.length < limit) {
      next.add(0);
    }
    for (var i = 0; i < f.temps.length; i++) {
      final idx = start + i;
      if (idx >= next.length || idx >= limit) break;
      next[idx] = f.temps[i];
    }
    return next;
  }

  List<double> _mergeCellVoltages(DalyCellVoltageFrame f) {
    final start = f.firstCellNumber - 1;
    if (start < 0) return cellVoltages;

    // Grow to fit this frame, then overwrite only the slots it covers. Cap at
    // cellCount when known so trailing padding cells (Daly pads the last frame
    // with zeroes) never appear on the dashboard.
    final needed = start + f.millivolts.length;
    final limit = cellCount ?? needed;
    final next = List<double>.from(cellVoltages);
    while (next.length < needed && next.length < limit) {
      next.add(0);
    }

    for (var i = 0; i < f.millivolts.length; i++) {
      final idx = start + i;
      if (idx >= next.length || idx >= limit) break;
      next[idx] = f.millivolts[i] / 1000.0;
    }
    return next;
  }

  @override
  String toString() => 'BmsSnapshot(soc: $soc%, pack: ${packVoltage}V, '
      'current: ${currentAmps}A, cells: ${cellVoltages.length})';
}
