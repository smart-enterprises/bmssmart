// lib/core/widgets/m3_gauge.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// Circular SOC ring gauge — replaces the old BatteryGauge. Colored by
/// level (success/amber/primary), percent centered with a status pill below.
class M3Gauge extends StatelessWidget {
  const M3Gauge({super.key, required this.percent, required this.status, this.size = 240});

  final int percent;
  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = m3LevelColor(percent);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(percent: percent.clamp(0, 100) / 100, color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: '$percent', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w400, color: M3Colors.onSurface)),
                    const TextSpan(text: '%', style: TextStyle(fontSize: 22, color: M3Colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(color: M3Colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(M3Radii.chip)),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: M3Colors.onSurfaceVariant, letterSpacing: 0.6),
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
  final double percent;
  final Color color;
  const _GaugePainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;
    const strokeWidth = 16.0;

    final track = Paint()
      ..color = M3Colors.surfaceContainerHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * percent, false, arc);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.percent != percent || oldDelegate.color != color;
}
