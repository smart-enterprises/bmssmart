// lib/features/bms/presentation/screens/history_screen.dart
//
// Time-series charts of the headline metrics, drawn with M3LineChart (a
// CustomPainter, so the app needs no charting dependency). Data comes from
// the live service's rolling history buffer; the screen repaints as new
// points arrive. Content is unchanged from the pre-M3 version — this is a
// pure restyle, still the History tab body (no back button: it's a
// persistent tab now, not a pushed screen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/m3_theme.dart';
import '../../../../core/widgets/m3_line_chart.dart';
import '../../../../core/widgets/m3_list_card.dart';
import '../../../../core/widgets/m3_top_app_bar.dart';
import '../../data/models/bms_models.dart';
import '../providers/bms_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild as snapshots arrive; the buffer itself lives on the service.
    ref.watch(bmsSnapshotProvider);
    final service = ref.watch(bmsBleServiceProvider);
    final points = service?.history ?? const <HistoryPoint>[];

    return Container(
      color: M3Colors.surface,
      child: Column(
        children: [
          const M3TopAppBar(eyebrow: Text('Battery'), title: Text('History')),
          Expanded(child: points.length < 2 ? _empty() : _buildList(points)),
        ],
      ),
    );
  }

  Widget _buildList(List<HistoryPoint> points) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      children: [
        _ChartCard(
          title: 'State of Charge',
          unit: '%',
          color: M3Colors.success,
          points: points,
          value: (p) => p.soc,
          fixedMin: 0,
          fixedMax: 100,
          decimals: 0,
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Pack Voltage',
          unit: 'V',
          color: M3Colors.primary,
          points: points,
          value: (p) => p.voltage,
          decimals: 2,
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Current',
          unit: 'A',
          color: M3Colors.tertiary,
          points: points,
          value: (p) => p.current,
          zeroBaseline: true,
          decimals: 1,
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Cell Imbalance (Δ)',
          unit: 'mV',
          color: M3Colors.warningAmber,
          points: points,
          value: (p) => p.deltaMv?.toDouble(),
          decimals: 0,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '${points.length} samples · spanning ${_span(points)}',
            style: const TextStyle(color: M3Colors.outline, fontSize: 12),
          ),
        ),
      ],
    );
  }

  static String _span(List<HistoryPoint> pts) {
    final d = pts.last.t.difference(pts.first.t);
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart, size: 52, color: M3Colors.outlineVariant),
              SizedBox(height: 16),
              Text(
                'Collecting data…\nCharts appear once a few samples have arrived.',
                textAlign: TextAlign.center,
                style: TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.unit,
    required this.color,
    required this.points,
    required this.value,
    this.fixedMin,
    this.fixedMax,
    this.zeroBaseline = false,
    this.decimals = 1,
  });

  final String title;
  final String unit;
  final Color color;
  final List<HistoryPoint> points;
  final double? Function(HistoryPoint) value;
  final double? fixedMin;
  final double? fixedMax;
  final bool zeroBaseline;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final latest = _latestNonNull();

    return M3ListCard(
      title: title.toUpperCase(),
      trailing: Text(
        latest == null ? '—' : '${latest.toStringAsFixed(decimals)} $unit',
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: SizedBox(
        height: 96,
        width: double.infinity,
        child: M3LineChart<HistoryPoint>(
          points: points,
          value: value,
          color: color,
          fixedMin: fixedMin,
          fixedMax: fixedMax,
          zeroBaseline: zeroBaseline,
        ),
      ),
    );
  }

  double? _latestNonNull() {
    for (final p in points.reversed) {
      final v = value(p);
      if (v != null) return v;
    }
    return null;
  }
}
