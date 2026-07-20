// lib/core/theme/app_theme.dart
//
// Design tokens for the light "rich UI" theme, ported 1:1 from the approved
// design (bms-dashboard.jsx: BMS_COLORS / GLASS / BG_GRADIENT). Opaque white
// cards with crisp shadows on a flat white background — no blur, no
// translucency, no ambient wash. Keep hex values in sync with that source if
// the design changes.

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const bg = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFFFF8C00);
  static const primarySoft = Color(0xFFFFE5CC);
  static const success = Color(0xFF22C55E);
  static const successSoft = Color(0xFFDCFCE7);
  static const danger = Color(0xFFEF4444);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const text = Color(0xFF1F2937);
  static const textSec = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const border = Color(0xFFE5E7EB);
  static const trackBg = Color(0x38949EAE); // rgba(148,163,184,0.22)

  /// Solid fill for icon chips and small badges (was translucent white).
  static const chipBg = Color(0xFFF6F7F9);
  static const chipBorder = Color(0xFFEBEDF0);
}

/// Solid card surface tokens: opaque fill, crisp border, defined (non-blurred)
/// shadow.
abstract final class Glass {
  static const fill = Color(0xFFFFFFFF);
  static const border = Color(0xFFEBEDF0);

  /// Matches the design's stacked `0 2px 6px rgba(20,24,32,.05), 0 10px 24px
  /// -12px rgba(20,24,32,.14)` — a tight contact shadow plus a soft, pulled-in
  /// ambient one.
  static const shadow = [
    BoxShadow(color: Color(0x0D141820), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x24141820), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -12),
  ];
}

/// The single shared app background — flat white. Used on every screen.
const appBackgroundGradient = LinearGradient(
  colors: [Colors.white, Colors.white],
);

/// A solid white card: opaque fill, crisp border, defined shadow. Matches
/// `glassCard()` in the design source (blur: 'none' in the current design).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = const EdgeInsets.all(18),
    this.margin,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Glass.fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Glass.border, width: 1),
        boxShadow: Glass.shadow,
      ),
      child: child,
    );
  }
}

/// No-op — the current design's background is flat, with no ambient wash
/// (`AmbientBg()` returns null in bms-dashboard.jsx). Kept as a widget so
/// call sites don't need to change if the design brings the wash back.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
