// lib/core/widgets/m3_tile.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

enum M3TileTone { neutral, primary, success, tertiary }

class _ToneColors {
  final Color bg;
  final Color fg;
  final Color chipFg;
  const _ToneColors({required this.bg, required this.fg, required this.chipFg});
}

const _tones = {
  M3TileTone.neutral: _ToneColors(bg: M3Colors.surfaceContainerHigh, fg: M3Colors.onSurface, chipFg: M3Colors.onSurfaceVariant),
  M3TileTone.primary: _ToneColors(bg: Color(0xFFFBEAE8), fg: Color(0xFF5A1A15), chipFg: M3Colors.primary),
  M3TileTone.success: _ToneColors(bg: Color(0xFFEEF7EC), fg: Color(0xFF1E3D1B), chipFg: M3Colors.success),
  M3TileTone.tertiary: _ToneColors(bg: Color(0xFFE9F5F5), fg: Color(0xFF00363A), chipFg: M3Colors.tertiary),
};

/// M3 elevated tonal surface tile for the 2x2 metric grid — filled icon
/// chip, big value+unit, small label.
class M3Tile extends StatelessWidget {
  const M3Tile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    required this.icon,
    this.tone = M3TileTone.neutral,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final M3TileTone tone;

  @override
  Widget build(BuildContext context) {
    final t = _tones[tone]!;
    return Container(
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(M3Radii.tile)),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: t.chipFg),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: t.fg, letterSpacing: -0.2)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unit, style: TextStyle(fontSize: 12, color: t.fg.withValues(alpha: 0.75))),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: t.fg.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Temperature-specific tile — same shape as [M3Tile], colored by severity
/// via [m3TempMeta].
class M3TempTile extends StatelessWidget {
  const M3TempTile({super.key, required this.tempC});

  final double tempC;

  @override
  Widget build(BuildContext context) {
    final meta = m3TempMeta(tempC);
    return Container(
      decoration: BoxDecoration(color: meta.container, borderRadius: BorderRadius.circular(M3Radii.tile)),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.thermostat, size: 16, color: meta.color),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(tempC.toStringAsFixed(1), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: meta.on, letterSpacing: -0.2)),
              const SizedBox(width: 3),
              Text('°C', style: TextStyle(fontSize: 12, color: meta.on.withValues(alpha: 0.75))),
            ],
          ),
          const SizedBox(height: 4),
          Text(meta.label, style: TextStyle(fontSize: 12, color: meta.on.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
