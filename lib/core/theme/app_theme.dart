// lib/core/theme/app_theme.dart
//
// Design tokens for the light glassmorphic theme, ported 1:1 from the
// approved design (bms-dashboard.jsx: BMS_COLORS / GLASS / BG_GRADIENT).
// Keep hex values in sync with that source if the design changes.

import 'dart:ui';

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
}

/// Frosted-glass surface tokens (blur + translucent fill + soft shadow).
abstract final class Glass {
  static const fill = Color(0xA3FFFFFF); // rgba(255,255,255,0.64)
  static const fillStrong = Color(0xCCFFFFFF); // rgba(255,255,255,0.8)
  static const border = Color(0xBFFFFFFF); // rgba(255,255,255,0.75)
  static const blurSigma = 16.0; // CSS blur(22px) reads stronger than Flutter's sigma
}

/// The single shared app background — warm, orange-tinted, a touch darker
/// than the glass cards so frosted surfaces read as raised above it. Ties to
/// the Warrior brand accent. Used on every screen.
const appBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFF3E0), Color(0xFFFCDFB8), Color(0xFFF8CB94)],
  stops: [0.0, 0.5, 1.0],
);

/// A frosted-glass card: translucent fill, blurred backdrop, soft border and
/// shadow. Matches `glassCard()` in the design source.
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x381F2937),
            blurRadius: 34,
            offset: Offset(0, 10),
            spreadRadius: -14,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: Glass.blurSigma, sigmaY: Glass.blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Glass.fill,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Glass.border, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Soft ambient color blobs behind the glass — gives the frosted cards
/// something to visually refract, matching `AmbientBg()` in the design.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            _Blob(
              top: -0.08,
              left: -0.12,
              widthFactor: 0.55,
              heightFactor: 0.32,
              color: Color(0x42FF8C00), // rgba(255,140,0,0.26)
            ),
            _Blob(
              top: 0.30,
              right: -0.16,
              widthFactor: 0.55,
              heightFactor: 0.34,
              color: Color(0x3DFFB155), // rgba(255,177,85,0.24)
            ),
            _Blob(
              bottom: -0.10,
              left: 0.10,
              widthFactor: 0.60,
              heightFactor: 0.32,
              color: Color(0x38788CAA), // rgba(120,140,170,0.22)
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.widthFactor,
    required this.heightFactor,
    required this.color,
  });

  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double widthFactor;
  final double heightFactor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : w * 2;
      return Positioned(
        top: top == null ? null : top! * h,
        bottom: bottom == null ? null : bottom! * h,
        left: left == null ? null : left! * w,
        right: right == null ? null : right! * w,
        width: w * widthFactor,
        height: h * heightFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0.0, 0.7],
            ),
          ),
        ),
      );
    });
  }
}
