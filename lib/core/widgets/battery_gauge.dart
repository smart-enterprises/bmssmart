// lib/core/widgets/battery_gauge.dart
//
// Semi-circular SOC gauge, ported from the design's BatteryGauge() SVG arc
// math. Flutter's Canvas.drawArc uses the same convention as the source SVG
// (0 rad = 3 o'clock, positive = clockwise, y-down) so the angles transfer
// directly with no sign flips.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum GaugeStatus { charging, discharging, idle }

class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.percent,
    required this.status,
    this.size = 260,
  });

  final double percent;
  final GaugeStatus status;
  final double size;

  static const _startDeg = 135.0;
  static const _endDeg = 405.0;

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0, 100);
    final (label, color, icon) = switch (status) {
      GaugeStatus.charging => ('Charging', AppColors.success, Icons.bolt),
      GaugeStatus.discharging => ('Discharging', AppColors.danger, Icons.arrow_downward),
      GaugeStatus.idle => ('Idle', AppColors.textSec, Icons.pause),
    };

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(percent: pct.toDouble()),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'STATE OF CHARGE',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: AppColors.textSec,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pct.round().toString(),
                    style: TextStyle(
                      fontSize: size * 0.28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      height: 1,
                      letterSpacing: -2,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: size * 0.04, left: 2),
                    child: Text(
                      '%',
                      style: TextStyle(
                        fontSize: size * 0.09,
                        color: AppColors.textSec,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.13)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.percent});
  final double percent;

  static const _strokeWidth = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - _strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);

    const startRad = BatteryGauge._startDeg * math.pi / 180;
    const sweepRad = (BatteryGauge._endDeg - BatteryGauge._startDeg) * math.pi / 180;

    final trackPaint = Paint()
      ..color = const Color(0x47949EAE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startRad, sweepRad, false, trackPaint);

    final valueSweep = sweepRad * (percent / 100).clamp(0, 1);
    if (valueSweep > 0) {
      final valuePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFB155), Color(0xFFFF8C00), Color(0xFFF76B1C)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawArc(rect, startRad, valueSweep, false, valuePaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.percent != percent;
}
