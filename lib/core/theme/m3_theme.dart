// lib/core/theme/m3_theme.dart
//
// Material 3 (Material You) design tokens, ported 1:1 from the approved
// design source (bms-m3-dashboard.jsx: the `M3` color object). Seed color is
// "Warrior red" (#B3261E), replacing the app's older orange brand color.
// Keep hex values in sync with that source if the design changes.
//
// This is additive — lib/core/theme/app_theme.dart (AppColors/Glass/
// GlassCard) stays untouched, since debug_log_screen.dart, qr_scanner.dart,
// and splash_screen.dart still depend on it and are out of scope for the M3
// redesign.

import 'package:flutter/material.dart';

abstract final class M3Colors {
  static const primary = Color(0xFFB3261E);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFF6E9E7);
  static const onPrimaryContainer = Color(0xFF410002);

  static const secondary = Color(0xFF77574E);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFF3EBE8);
  static const onSecondaryContainer = Color(0xFF2C1510);

  static const tertiary = Color(0xFF00696D);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFE6F5F5);
  static const onTertiaryContainer = Color(0xFF002021);

  static const success = Color(0xFF3B6939);
  static const successContainer = Color(0xFFE9F5E6);

  /// Not part of the mock's token list — formalizes the amber already
  /// hardcoded across bms_dashboard.dart/history_screen.dart/
  /// scanner_screen.dart (temperature/RSSI warnings, mid-range gauge level).
  static const warningAmber = Color(0xFFD29922);
  static const warningAmberContainer = Color(0xFFFDF1E2);
  static const onWarningAmberContainer = Color(0xFF4A2E00);

  static const surface = Color(0xFFFFFFFF);
  static const surfaceDim = Color(0xFFEDEDED);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFFAFAFA);
  static const surfaceContainer = Color(0xFFF5F5F5);
  static const surfaceContainerHigh = Color(0xFFF0F0F0);
  static const surfaceContainerHighest = Color(0xFFE9E9E9);

  static const onSurface = Color(0xFF1C1B1B);
  static const onSurfaceVariant = Color(0xFF5C5C5C);
  static const outline = Color(0xFF8A8A8A);
  static const outlineVariant = Color(0xFFDDDDDD);

  static const inverseSurface = Color(0xFF302F2F);
  static const inverseOnSurface = Color(0xFFF5F5F5);
}

/// Corner radii used throughout the M3 surfaces — kept centralized so tiles/
/// cards/dialogs/nav pill stay visually consistent.
abstract final class M3Radii {
  static const tile = 24.0;
  static const card = 28.0;
  static const dialog = 28.0;
  static const chip = 999.0;
  static const navPill = 32.0;
  static const topBar = 28.0;
}

/// Battery-level color: green when high, amber through mid, red when low.
/// Mirrors m3LevelColor() in the design source.
Color m3LevelColor(num percent) {
  if (percent >= 50) return M3Colors.success;
  if (percent >= 20) return M3Colors.warningAmber;
  return M3Colors.primary;
}

/// Temperature severity color/label/container. Mirrors m3TempMeta() in the
/// design source.
class M3TempMeta {
  final String label;
  final Color color;
  final Color container;
  final Color on;
  const M3TempMeta({required this.label, required this.color, required this.container, required this.on});
}

M3TempMeta m3TempMeta(double tempC) {
  if (tempC >= 50) {
    return const M3TempMeta(label: 'High', color: M3Colors.primary, container: Color(0xFFFBEAE8), on: Color(0xFF5A1A15));
  }
  if (tempC >= 38) {
    return const M3TempMeta(
      label: 'Elevated',
      color: M3Colors.warningAmber,
      container: M3Colors.warningAmberContainer,
      on: M3Colors.onWarningAmberContainer,
    );
  }
  return const M3TempMeta(label: 'Normal', color: M3Colors.success, container: Color(0xFFEEF7EC), on: Color(0xFF1E3D1B));
}

ThemeData buildM3ThemeData() {
  const scheme = ColorScheme.light(
    primary: M3Colors.primary,
    onPrimary: M3Colors.onPrimary,
    primaryContainer: M3Colors.primaryContainer,
    onPrimaryContainer: M3Colors.onPrimaryContainer,
    secondary: M3Colors.secondary,
    onSecondary: M3Colors.onSecondary,
    secondaryContainer: M3Colors.secondaryContainer,
    onSecondaryContainer: M3Colors.onSecondaryContainer,
    tertiary: M3Colors.tertiary,
    onTertiary: M3Colors.onTertiary,
    tertiaryContainer: M3Colors.tertiaryContainer,
    onTertiaryContainer: M3Colors.onTertiaryContainer,
    error: M3Colors.primary,
    onError: M3Colors.onPrimary,
    surface: M3Colors.surface,
    onSurface: M3Colors.onSurface,
    onSurfaceVariant: M3Colors.onSurfaceVariant,
    outline: M3Colors.outline,
    outlineVariant: M3Colors.outlineVariant,
    inverseSurface: M3Colors.inverseSurface,
    onInverseSurface: M3Colors.inverseOnSurface,
    surfaceContainerLowest: M3Colors.surfaceContainerLowest,
    surfaceContainerLow: M3Colors.surfaceContainerLow,
    surfaceContainer: M3Colors.surfaceContainer,
    surfaceContainerHigh: M3Colors.surfaceContainerHigh,
    surfaceContainerHighest: M3Colors.surfaceContainerHighest,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: M3Colors.surface,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: M3Colors.onSurface,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: M3Colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(M3Radii.dialog)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: M3Colors.inverseSurface,
      contentTextStyle: const TextStyle(color: M3Colors.inverseOnSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textTheme: ThemeData.light().textTheme.apply(
          bodyColor: M3Colors.onSurface,
          displayColor: M3Colors.onSurface,
          fontFamily: 'Roboto',
        ),
  );
}
