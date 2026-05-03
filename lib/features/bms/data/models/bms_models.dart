// lib/models/bms_models.dart
//
// Pure Dart — zero Flutter / BLE / Riverpod imports.
// Everything downstream depends on this file; keep it dependency-free.

// ── Charge status ──────────────────────────────────────────────────────────

enum ChargeStatus { charging, discharging, idle }

/// Resolves [ChargeStatus] from [currentAmps] using a ±0.1 A dead band
/// to prevent flickering on noisy readings near zero.
ChargeStatus resolveStatus(double currentAmps) {
  if (currentAmps > 0.1) return ChargeStatus.charging;
  if (currentAmps < -0.1) return ChargeStatus.discharging;
  return ChargeStatus.idle;
}

// ── Sealed BmsFrame hierarchy ──────────────────────────────────────────────

/// Sealed base — exhaustively pattern-matched in the service and UI.
/// Adding a new subtype is a compile error until every switch is updated.
sealed class BmsFrame {
  final DateTime timestamp;
  const BmsFrame({required this.timestamp});
}

/// Parsed result of command 0x03 — main battery data.
final class BmsMainFrame extends BmsFrame {
  /// State of Charge in percent (0.0–100.0).
  final double soc;

  /// Signed current in Amperes.
  /// Positive → charging, negative → discharging.
  final double currentAmps;

  /// Derived from [currentAmps] via [resolveStatus].
  final ChargeStatus status;

  BmsMainFrame({
    required this.soc,
    required this.currentAmps,
    required super.timestamp,
  }) : status = resolveStatus(currentAmps);

  @override
  String toString() =>
      'BmsMainFrame(soc: $soc%, current: ${currentAmps}A, status: $status)';
}

/// Parsed result of command 0x04 — individual cell voltages.
final class BmsCellFrame extends BmsFrame {
  /// Per-cell voltages in Volts, index-aligned to physical cell position.
  final List<double> voltages;

  const BmsCellFrame({
    required this.voltages,
    required super.timestamp,
  });

  int get cellCount => voltages.length;
  double get minVoltage => voltages.reduce((a, b) => a < b ? a : b);
  double get maxVoltage => voltages.reduce((a, b) => a > b ? a : b);

  /// Balance spread — a large delta (> 50 mV) indicates imbalance.
  double get deltaVoltage => maxVoltage - minVoltage;

  @override
  String toString() =>
      'BmsCellFrame(cells: $cellCount, min: ${minVoltage}V, '
          'max: ${maxVoltage}V, Δ: ${deltaVoltage}V)';
}

// ── BmsSnapshot ────────────────────────────────────────────────────────────

/// Accumulates the latest frame of each type.
/// Emitted by the BLE service every time ANY frame is received.
class BmsSnapshot {
  final BmsMainFrame? mainFrame;
  final BmsCellFrame? cellFrame;

  const BmsSnapshot({this.mainFrame, this.cellFrame});

  /// Returns a new snapshot with the provided frames replacing the old ones.
  BmsSnapshot copyWith({BmsMainFrame? mainFrame, BmsCellFrame? cellFrame}) =>
      BmsSnapshot(
        mainFrame: mainFrame ?? this.mainFrame,
        cellFrame: cellFrame ?? this.cellFrame,
      );

  /// True once at least one frame of each type has arrived.
  bool get isComplete => mainFrame != null && cellFrame != null;

  @override
  String toString() => 'BmsSnapshot(main: $mainFrame, cells: $cellFrame)';
}