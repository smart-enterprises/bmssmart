// lib/features/bms/presentation/screens/history_screen.dart
//
// Time-series charts of the headline metrics, drawn with a CustomPainter so
// the app needs no charting dependency. Data comes from the live service's
// rolling history buffer; the screen repaints as new points arrive.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
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

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(child: points.length < 2 ? _empty() : _buildList(points)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textSec),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text('History', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 19)),
        ],
      ),
    );
  }

  Widget _buildList(List<HistoryPoint> points) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _ChartCard(
          title: 'State of Charge',
          unit: '%',
          color: AppColors.success,
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
          color: AppColors.primary,
          points: points,
          value: (p) => p.voltage,
          decimals: 2,
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Current',
          unit: 'A',
          color: const Color(0xFF3B82F6),
          points: points,
          value: (p) => p.current,
          zeroBaseline: true,
          decimals: 1,
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Cell Imbalance (Δ)',
          unit: 'mV',
          color: const Color(0xFFD29922),
          points: points,
          value: (p) => p.deltaMv?.toDouble(),
          decimals: 0,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '${points.length} samples · spanning ${_span(points)}',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
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
              Icon(Icons.show_chart, size: 52, color: AppColors.border),
              SizedBox(height: 16),
              Text(
                'Collecting data…\nCharts appear once a few samples have arrived.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSec, fontSize: 14, height: 1.5),
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

    return GlassCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: AppColors.textSec, fontSize: 13)),
              Text(
                latest == null ? '—' : '${latest.toStringAsFixed(decimals)} $unit',
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _LinePainter(points: points, value: value, color: color, fixedMin: fixedMin, fixedMax: fixedMax, zeroBaseline: zeroBaseline),
            ),
          ),
        ],
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

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.value,
    required this.color,
    this.fixedMin,
    this.fixedMax,
    this.zeroBaseline = false,
  });

  final List<HistoryPoint> points;
  final double? Function(HistoryPoint) value;
  final Color color;
  final double? fixedMin;
  final double? fixedMax;
  final bool zeroBaseline;

  @override
  void paint(Canvas canvas, Size size) {
    final vals = <int, double>{};
    for (var i = 0; i < points.length; i++) {
      final v = value(points[i]);
      if (v != null) vals[i] = v;
    }
    if (vals.length < 2) return;

    var lo = fixedMin ?? vals.values.reduce((a, b) => a < b ? a : b);
    var hi = fixedMax ?? vals.values.reduce((a, b) => a > b ? a : b);
    if (zeroBaseline) {
      lo = lo < 0 ? lo : 0;
      hi = hi > 0 ? hi : 0;
    }
    if (hi - lo < 1e-9) {
      // Flat line — pad so it renders mid-height instead of dividing by zero.
      hi += 1;
      lo -= 1;
    }

    final n = points.length;
    double dx(int i) => n == 1 ? 0 : size.width * i / (n - 1);
    double dy(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    final grid = Paint()
      ..color = AppColors.trackBg
      ..strokeWidth = 1;
    for (var g = 0; g <= 2; g++) {
      final y = size.height * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Zero line for current, if it falls inside the range.
    if (zeroBaseline && lo < 0 && hi > 0) {
      final zeroPaint = Paint()
        ..color = AppColors.textTertiary
        ..strokeWidth = 1;
      final y = dy(0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), zeroPaint);
    }

    final path = Path();
    final fill = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = vals[i];
      if (v == null) continue;
      final p = Offset(dx(i), dy(v));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        fill.moveTo(p.dx, size.height);
        fill.lineTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
        fill.lineTo(p.dx, p.dy);
      }
    }
    fill.lineTo(dx(n - 1), size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.points != points;
}
