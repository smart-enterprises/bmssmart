// lib/core/widgets/m3_line_chart.dart
//
// Gradient-fill line chart, generalized from history_screen.dart's original
// _LinePainter — same generic value-extractor API, restyled to M3 tokens.

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// Draws a gradient-filled line chart for [points], extracting the plotted
/// value via [value] (nullable — gaps are simply skipped). Pass [fixedMin]/
/// [fixedMax] for a fixed scale (e.g. 0-100 for a percentage), or leave null
/// to auto-scale to the data. [zeroBaseline] additionally forces 0 into the
/// visible range and draws a zero line (for signed values like current).
class M3LineChart<T> extends StatelessWidget {
  const M3LineChart({
    super.key,
    required this.points,
    required this.value,
    required this.color,
    this.fixedMin,
    this.fixedMax,
    this.zeroBaseline = false,
  });

  final List<T> points;
  final double? Function(T) value;
  final Color color;
  final double? fixedMin;
  final double? fixedMax;
  final bool zeroBaseline;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _M3LinePainter<T>(
        points: points,
        value: value,
        color: color,
        fixedMin: fixedMin,
        fixedMax: fixedMax,
        zeroBaseline: zeroBaseline,
      ),
    );
  }
}

class _M3LinePainter<T> extends CustomPainter {
  _M3LinePainter({
    required this.points,
    required this.value,
    required this.color,
    this.fixedMin,
    this.fixedMax,
    this.zeroBaseline = false,
  });

  final List<T> points;
  final double? Function(T) value;
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
      hi += 1;
      lo -= 1;
    }

    final n = points.length;
    double dx(int i) => n == 1 ? 0 : size.width * i / (n - 1);
    double dy(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    final grid = Paint()
      ..color = M3Colors.outlineVariant
      ..strokeWidth = 1;
    for (var g = 0; g <= 2; g++) {
      final y = size.height * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (zeroBaseline && lo < 0 && hi > 0) {
      final zeroPaint = Paint()
        ..color = M3Colors.outline
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
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _M3LinePainter<T> oldDelegate) => oldDelegate.points != points;
}
