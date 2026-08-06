// lib/features/bms/presentation/screens/warrior_battery_screen.dart
//
// Battery — the pack screen from the Warrior design.
//
// Reads from batteryViewProvider, so it renders identically whether the
// numbers arrived over BLE or from the cloud. The one thing it does surface is
// WHICH source answered, because "these readings are 40 s old from the
// gateway" and "these are live off Bluetooth" mean different things when
// someone is standing in front of a pack deciding whether to trust the screen.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/warrior_theme.dart';
import '../../../../core/widgets/warrior_widgets.dart';
import '../../data/models/bms_models.dart';
import '../providers/battery_view.dart';

/// Pack nameplate. Not measured — the BMS reports neither its chemistry nor
/// its rated capacity, so these are configuration, and wrong values here make
/// the Ah and percentage-of-rated figures wrong with them.
const kPackLabel = '8S LiFePO₄ 24 V';
const kPackCapacityAh = 100.0;
const kMaxChargeAmps = 20.0;

class WarriorBatteryScreen extends ConsumerWidget {
  const WarriorBatteryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(batteryViewProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 116),
        children: [
          _Header(battery: b),
          const SizedBox(height: 16),
          if (!b.hasData)
            WEmptyState(
              icon: Icons.battery_unknown_rounded,
              title: 'No battery data',
              detail: b.cloudStale
                  ? 'The gateway has stopped uploading, and no pack is connected over Bluetooth.'
                  : 'Connect a pack over Bluetooth, or sign in to read it through the gateway.',
            )
          else ...[
            _SocHero(battery: b),
            const SizedBox(height: 12),
            _StatRow(battery: b),
            const SizedBox(height: 12),
            _Cells(battery: b),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.battery});

  final BatteryView battery;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (battery.status) {
      ChargeStatus.charging => (const Color(0xFFE6F6EE), W.green, 'Charging'),
      ChargeStatus.discharging => (W.warnBg, W.warnFg, 'Discharging'),
      ChargeStatus.idle => (W.soft, W.textMuted, 'Idle'),
      null => (W.soft, W.textTertiary, 'No data'),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pack 01 · $kPackLabel', style: WType.meta(W.textSecondary)),
                const SizedBox(height: 3),
                Text('Battery', style: WType.display(W.ink).copyWith(fontSize: 30)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(WRadius.full)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WLiveDot(color: fg, animate: battery.status != null),
                const SizedBox(width: 6),
                Text(label, style: WType.pill(fg).copyWith(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The near-black hero: a double-ring radial gauge with SOC outside and
/// current inside.
class _SocHero extends StatelessWidget {
  const _SocHero({required this.battery});

  final BatteryView battery;

  @override
  Widget build(BuildContext context) {
    final soc = battery.soc ?? 0;
    final amps = battery.currentAmps ?? 0;
    final charging = battery.status == ChargeStatus.charging;

    // Below 25% the ring turns red. Amber while discharging, green while
    // charging — the same rule the Home hero uses so the two never disagree.
    final socColor = soc <= 25 ? W.red : (charging ? W.green : W.amber);
    final ampColor = charging ? W.green : W.amber;
    final ampFraction = (amps.abs() / kMaxChargeAmps).clamp(0.0, 1.0);

    final runtime = battery.runtimeHours;
    final etaLabel = charging ? 'TIME TO FULL' : 'BACKUP LEFT';
    final eta = charging
        ? (battery.remainingAh != null && amps > 0.05
            ? formatDuration(estimateTimeToFullHours(
                remainingAh: battery.remainingAh!,
                nominalAh: kPackCapacityAh,
                chargeAmps: amps,
              ))
            : '—')
        : formatDuration(runtime);

    return WHeroCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STATE OF CHARGE', style: WType.eyebrow(Colors.white.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 236,
              height: 236,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(236, 236),
                    painter: _GaugePainter(
                      socFraction: (soc / 100).clamp(0.0, 1.0),
                      socColor: socColor,
                      ampFraction: ampFraction,
                      ampColor: ampColor,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            battery.soc != null ? soc.toStringAsFixed(0) : '—',
                            style: WType.display(Colors.white).copyWith(
                              fontSize: 64,
                              letterSpacing: -3.4,
                              height: 0.86,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '%',
                              style: WType.statSm(Colors.white.withValues(alpha: 0.5))
                                  .copyWith(fontSize: 21),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '$etaLabel · $eta',
                        style: WType.eyebrow(
                          Colors.white.withValues(alpha: 0.45),
                          size: 10.5,
                          tracking: 1.1,
                        ),
                      ),
                      const SizedBox(height: 11),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(WRadius.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (charging) ...[
                              Icon(Icons.bolt_rounded, size: 13, color: ampColor),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              battery.currentAmps != null
                                  ? '${amps.abs().toStringAsFixed(1)} A'
                                  : '— A',
                              style: WType.caption(ampColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: socColor, thick: true, label: 'CHARGE ${soc.toStringAsFixed(0)}%'),
              const SizedBox(width: 16),
              _Legend(
                color: ampColor,
                thick: false,
                label: 'CURRENT ${(ampFraction * 100).round()}% OF ${kMaxChargeAmps.toInt()} A',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'USABLE',
                  value: battery.remainingAh != null
                      ? '${battery.remainingAh!.toStringAsFixed(1)} Ah'
                      : '—',
                  align: CrossAxisAlignment.start,
                ),
              ),
              Expanded(
                child: _HeroStat(label: etaLabel, value: eta, align: CrossAxisAlignment.center),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'CAPACITY',
                  value: '${kPackCapacityAh.toInt()} Ah',
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.thick, required this.label});

  final Color color;
  final bool thick;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: thick ? 4 : 3,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: WType.eyebrow(Colors.white.withValues(alpha: 0.5), size: 10, tracking: 0.6),
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, required this.align});

  final String label;
  final String value;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: WType.eyebrow(Colors.white.withValues(alpha: 0.45), size: 9.5, tracking: 0.9),
        ),
        const SizedBox(height: 3),
        Text(value, style: WType.statSm(Colors.white).copyWith(fontSize: 15.5)),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.socFraction,
    required this.socColor,
    required this.ampFraction,
    required this.ampColor,
  });

  final double socFraction;
  final Color socColor;
  final double ampFraction;
  final Color ampColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    void arc(double radius, double width, Color color, double fraction) {
      final rect = Rect.fromCircle(center: c, radius: radius);
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      // Starts at 12 o'clock and runs clockwise, which is what makes a
      // part-full ring read as a level rather than as an abstract dial.
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, paint);
    }

    void track(double radius, double width, Color color) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke,
      );
    }

    track(104, 16, Colors.white.withValues(alpha: 0.09));
    if (socFraction > 0) arc(104, 16, socColor, socFraction);

    track(84, 5, Colors.white.withValues(alpha: 0.07));
    if (ampFraction > 0) arc(84, 5, ampColor, ampFraction);

    track(117, 1.5, socColor.withValues(alpha: 0.16));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.socFraction != socFraction ||
      old.ampFraction != ampFraction ||
      old.socColor != socColor ||
      old.ampColor != ampColor;
}

/// Pack temperature beside cell balance.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.battery});

  final BatteryView battery;

  @override
  Widget build(BuildContext context) {
    final temp = battery.tempC;
    final severity = temp == null ? null : kTempThresholds.classify(temp.toDouble());
    final (tempFg, tempLabel) = switch (severity) {
      TempSeverity.critical => (W.faultFg, 'Critical'),
      TempSeverity.warning => (W.warnFg, 'Warm'),
      TempSeverity.normal => (W.green, 'Normal'),
      null => (W.textTertiary, 'No data'),
    };

    final delta = battery.cellDeltaMv;
    // 50 mV is the point where a LiFePO₄ pack is drifting enough to be worth
    // looking at; under 20 mV is a healthy pack.
    final (balFg, balLabel) = switch (delta) {
      null => (W.textTertiary, 'No cells'),
      final d when d >= 50 => (W.warnFg, 'Drifting'),
      final d when d >= 20 => (W.textMuted, 'Slight drift'),
      _ => (W.green, 'Balanced'),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: WCard(
              child: WStatBlock(
                label: 'Pack temperature',
                value: temp?.toString() ?? wNoValue,
                unit: temp == null ? null : '°C',
                footer: Row(
                  children: [
                    Expanded(
                      child: WMeter(
                        fraction: temp == null ? 0 : (temp / kTempThresholds.criticalC).clamp(0.0, 1.0),
                        gradient: [tempFg, tempFg],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(tempLabel, style: WType.caption(tempFg)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: WCard(
              child: WStatBlock(
                label: 'Cell balance',
                value: delta?.toString() ?? wNoValue,
                unit: delta == null ? null : 'mV Δ',
                footer: Text(balLabel, style: WType.caption(balFg)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-cell voltages, with the highest and lowest called out. Those two are
/// the cells that matter — a pack fails at its extremes, not at its average.
class _Cells extends StatelessWidget {
  const _Cells({required this.battery});

  final BatteryView battery;

  @override
  Widget build(BuildContext context) {
    final cells = battery.cells;
    if (cells.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WSectionHeader(title: 'Cells'),
          WEmptyState(
            icon: Icons.view_column_rounded,
            title: 'No per-cell data',
            detail: battery.source == BatterySource.cloud
                ? 'The gateway has not uploaded cell voltages for this pack yet.'
                : 'The BMS has not reported cell voltages yet.',
          ),
        ],
      );
    }

    final mn = battery.cellMinV!;
    final mx = battery.cellMaxV!;
    // Scaled against the pack's real spread rather than an absolute range, so
    // a 6 mV difference is still visible instead of eight identical bars.
    final span = (mx - mn).abs() < 0.001 ? 0.001 : mx - mn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WSectionHeader(title: 'Cells', actionLabel: '${cells.length} in series'),
        for (var i = 0; i < cells.length; i++) ...[
          _CellRow(
            index: i + 1,
            volts: cells[i],
            fraction: ((cells[i] - mn) / span).clamp(0.0, 1.0),
            isMax: cells[i] == mx,
            isMin: cells[i] == mn,
            balancing: battery.balancingCells.contains(i + 1),
          ),
          if (i != cells.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _CellRow extends StatelessWidget {
  const _CellRow({
    required this.index,
    required this.volts,
    required this.fraction,
    required this.isMax,
    required this.isMin,
    required this.balancing,
  });

  final int index;
  final double volts;
  final double fraction;
  final bool isMax;
  final bool isMin;
  final bool balancing;

  @override
  Widget build(BuildContext context) {
    final fg = isMax ? W.red : (isMin ? W.warnFg : W.ink);
    final barColor = isMax ? W.red : (isMin ? W.amber : W.ink);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: W.soft, borderRadius: BorderRadius.circular(WRadius.row)),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$index', style: WType.caption(W.textSecondary)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WRadius.full),
              child: Container(
                height: 6,
                color: W.trough,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  // A floor of 6% keeps the lowest cell's bar visible instead
                  // of collapsing it to nothing, which reads as "no reading".
                  widthFactor: (0.06 + fraction * 0.94).clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(WRadius.full),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (balancing) ...[
            const SizedBox(width: 8),
            const Icon(Icons.balance_rounded, size: 14, color: W.textMuted),
          ],
          const SizedBox(width: 10),
          Text(volts.toStringAsFixed(3), style: WType.rowValue(fg)),
          const SizedBox(width: 3),
          Text('V', style: WType.caption(W.textSecondary)),
        ],
      ),
    );
  }
}
