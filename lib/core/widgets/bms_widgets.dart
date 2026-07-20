// lib/core/widgets/bms_widgets.dart
//
// Small glass-styled dashboard pieces ported from the design: StatTile,
// CellRow, TemperatureCard, and the cell-balance badge.

import 'package:flutter/material.dart';

import '../../features/bms/data/models/bms_models.dart';
import '../theme/app_theme.dart';

/// A glass tile: icon chip top-right, big value, optional sublabel.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.sublabel,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final String? sublabel;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSec),
                ),
              ),
              if (icon != null)
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.chipBorder),
                  ),
                  child: Icon(icon, size: 14, color: iconColor ?? AppColors.textSec),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: color ?? AppColors.text,
                    letterSpacing: -0.6,
                  ),
                ),
                if (unit != null && unit!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(unit!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSec)),
                ],
              ],
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(sublabel!, style: const TextStyle(fontSize: 12, color: AppColors.textSec)),
          ],
        ],
      ),
    );
  }
}

/// Temperature colour: green below warning, amber at/above warning, red
/// at/above critical. Shares the same thresholds as the alert banner, so the
/// tile's color and the alert always agree on severity.
class TempMeta {
  final String label;
  final Color color;
  const TempMeta(this.label, this.color);

  static const _warningColor = Color(0xFFD29922);

  static TempMeta of(double tempC, TempThresholds thresholds) {
    return switch (thresholds.classify(tempC)) {
      TempSeverity.critical => const TempMeta('Critical', AppColors.danger),
      TempSeverity.warning => const TempMeta('Warning', _warningColor),
      TempSeverity.normal => const TempMeta('Normal', AppColors.success),
    };
  }
}

class TemperatureCard extends StatelessWidget {
  const TemperatureCard({super.key, required this.tempC, required this.thresholds});
  final double? tempC;
  final TempThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final t = tempC;
    final meta = t == null ? const TempMeta('—', AppColors.textSec) : TempMeta.of(t, thresholds);
    return StatTile(
      label: 'Temperature',
      value: t == null ? '—' : t.toStringAsFixed(1),
      unit: t == null ? null : '°C',
      color: meta.color,
      sublabel: meta.label,
      icon: Icons.thermostat,
      iconColor: meta.color,
    );
  }
}

/// Cell-balance status derived from the pack's min/max voltage spread.
class BalanceMeta {
  final String label;
  final Color color;
  const BalanceMeta(this.label, this.color);

  static BalanceMeta of(double deltaVolts) {
    if (deltaVolts <= 0.02) return const BalanceMeta('Balanced', AppColors.success);
    if (deltaVolts <= 0.05) return const BalanceMeta('Slight drift', AppColors.primary);
    return const BalanceMeta('Imbalanced', AppColors.danger);
  }
}

class BalanceBadge extends StatelessWidget {
  const BalanceBadge({super.key, required this.deltaVolts});
  final double deltaVolts;

  @override
  Widget build(BuildContext context) {
    final meta = BalanceMeta.of(deltaVolts);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: meta.color.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(meta.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: meta.color)),
        ],
      ),
    );
  }
}

/// One cell's row: index badge, name + HIGH/LOW tag, mini bar, voltage.
class CellRow extends StatelessWidget {
  const CellRow({
    super.key,
    required this.index,
    required this.voltage,
    required this.min,
    required this.max,
    this.isBalancing = false,
  });

  final int index;
  final double voltage;
  final double min;
  final double max;
  final bool isBalancing;

  static const _lo = 3.20;
  static const _hi = 3.60;

  @override
  Widget build(BuildContext context) {
    final pct = ((voltage - _lo) / (_hi - _lo)).clamp(0.0, 1.0);
    final isMin = voltage == min;
    final isMax = voltage == max;
    final indicator = isMax ? AppColors.primary : (isMin ? AppColors.textSec : AppColors.text);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
            child: Text('$index', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Cell $index', style: const TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500)),
                    if (isBalancing) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.balance, size: 11, color: Color(0xFF58A6FF)),
                    ],
                    const Spacer(),
                    if (isMin || isMax)
                      Text(
                        isMax ? 'HIGH' : 'LOW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: isMax ? AppColors.primary : AppColors.textSec,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: AppColors.trackBg,
                    valueColor: AlwaysStoppedAnimation(isMax ? AppColors.primary : AppColors.text.withValues(alpha: 0.85)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: voltage.toStringAsFixed(2),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: indicator, letterSpacing: -0.2),
                ),
                const TextSpan(text: ' V', style: TextStyle(fontSize: 12, color: AppColors.textSec, fontWeight: FontWeight.w500)),
              ],
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}
