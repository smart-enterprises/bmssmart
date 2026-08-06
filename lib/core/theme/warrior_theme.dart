// lib/core/theme/warrior_theme.dart
//
// The Warrior design language, ported from the "Warrior Inverter App" design
// (claude.ai/design project "BMS App UI Design").
//
// This is deliberately NOT a Material 3 colour scheme with a seed. The design
// is a custom visual system — near-black hero cards on a warm board, glass
// cards, pill filters, a floating nav — and expressing it through M3's tonal
// palettes would fight it the whole way. The M3 theme in m3_theme.dart is left
// in place for the screens that have not been migrated yet.
//
// Colour discipline, straight from the design brief: red is the primary and
// the active state, the racing-stripe oranges carry battery flow and warnings,
// green is reserved for healthy/on states. Nothing else introduces a hue.

import 'package:flutter/material.dart';

/// The palette. Hex values are the design's, unchanged — see the PALETTE strip
/// in `Warrior Inverter App.dc.html`.
abstract final class W {
  /// Primary. Active states, the load card, the flow line, alert accents.
  static const red = Color(0xFFE42430);
  static const redDark = Color(0xFFC2181F);

  /// The racing stripes. Battery flow and warnings only.
  static const orange = Color(0xFFF58220);
  static const amber = Color(0xFFFBA43C);

  /// Near-black. Hero cards, headings, the avatar chip.
  static const ink = Color(0xFF17151A);

  /// Healthy / on. Never used decoratively.
  static const green = Color(0xFF17A46B);

  /// Warm neutrals.
  static const board = Color(0xFFF2EDEA); // the board behind the phone
  static const soft = Color(0xFFF7F3F1); // inset rows, inactive pills
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFEDE7E5); // hairline borders on white cards
  static const lineWarm = Color(0xFFE6DFDC);

  /// Text.
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF8A7F82);
  static const textTertiary = Color(0xFFA2969A);
  static const textMuted = Color(0xFF6E6368);

  /// Severity, used by alerts and by any inline warning chip.
  static const faultBg = Color(0xFFFDEAEA);
  static const faultFg = Color(0xFFC2181F);
  static const faultBorder = Color(0xFFF5DADB);
  static const warnBg = Color(0xFFFEF3E6);
  static const warnFg = Color(0xFFC96A0E);
  static const warnBorder = Color(0xFFF6E4CF);
  static const infoBg = soft;
  static const infoFg = textMuted;
  static const infoBorder = line;

  /// Track colour for an off switch.
  static const switchOff = Color(0xFFDDD4D1);

  /// The meter trough behind the SOC bar.
  static const trough = Color(0xFFF0EAE8);
}

/// Corner radii. The design uses a narrow, deliberate set — hero cards are the
/// roundest thing on screen and everything else steps down from there.
abstract final class WRadius {
  static const hero = 24.0;
  static const card = 20.0;
  static const cardTight = 18.0;
  static const pillGroup = 22.0;
  static const row = 16.0;
  static const tile = 14.0;
  static const icon = 12.0;
  static const iconSm = 11.0;
  static const full = 999.0;
}

/// Archivo, bundled rather than fetched. The app is used in places with no
/// network (a BLE-only pairing session in a room with no signal), so a webfont
/// would leave the whole UI in a fallback face exactly when someone is trying
/// to read a fault code.
///
/// The file is the VARIABLE font, one file for every weight. Flutter maps
/// `fontWeight` onto a variable axis inconsistently across platforms, so every
/// style here also pins the `wght` axis explicitly via [FontVariation] — that
/// is what actually moves the axis, with fontWeight kept for the platforms and
/// fallbacks that use it.
abstract final class WType {
  static const family = 'Archivo';

  static List<FontVariation> _v(double weight) => [FontVariation('wght', weight)];

  static TextStyle _base(
    double size,
    double weight,
    double height,
    double letterSpacing,
    Color color,
  ) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: _v(weight),
    // Tabular figures: live readings change every second or two, and
    // proportional digits make the whole number jitter sideways when a 1
    // becomes an 8. The design calls for this explicitly.
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The big statement number/heading. 800 at -1.2px, per the design.
  static TextStyle display(Color color) => _base(29, 800, 1.05, -1.2, color);

  /// Hero card values — the 26px numbers on the load card and stat cards.
  static TextStyle stat(Color color) => _base(26, 800, 1.0, -1.0, color);

  /// The 19px values inside the small glass tiles.
  static TextStyle statSm(Color color) => _base(19, 800, 1.1, -0.5, color);

  /// Section headings ("What's drawing power").
  static TextStyle section(Color color) => _base(15, 800, 1.2, -0.3, color);

  /// Row titles.
  static TextStyle title(Color color) => _base(14, 700, 1.25, -0.1, color);

  /// Body / list text.
  static TextStyle body(Color color) => _base(13.5, 500, 1.5, 0, color);

  /// Bold inline values in rows.
  static TextStyle rowValue(Color color) => _base(14, 800, 1.2, -0.2, color);

  /// Secondary captions under a title.
  static TextStyle caption(Color color) => _base(11.5, 600, 1.3, 0, color);

  /// The 12.5px muted status line under the header.
  static TextStyle meta(Color color) => _base(12.5, 500, 1.35, 0, color);

  /// All-caps eyebrow labels — "POWER FLOW · LIVE", "GRID IN".
  static TextStyle eyebrow(Color color, {double size = 10.5, double tracking = 1.4}) =>
      _base(size, 700, 1.2, tracking, color);

  /// Pill / segmented button text.
  static TextStyle pill(Color color) => _base(12.5, 700, 1.2, 0, color);
}

/// Shadows. The design has exactly two: a tight one on plain white cards and a
/// wide soft one under glass cards.
abstract final class WShadow {
  static const card = [
    BoxShadow(color: Color(0x0F17151A), blurRadius: 5, offset: Offset(0, 2)),
  ];

  static const glass = [
    BoxShadow(color: Color(0x2E17151A), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -16),
  ];

  static const switchKnob = [
    BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

/// The Flutter [ThemeData] carrying the Warrior language. Widgets in
/// `warrior_widgets.dart` do most of the visual work directly; this exists so
/// that stock Material widgets still used inside the app (dialogs, snackbars,
/// text fields, the scroll behaviour) do not fall back to Material defaults
/// and stand out.
ThemeData buildWarriorTheme() {
  const scheme = ColorScheme.light(
    primary: W.red,
    onPrimary: Colors.white,
    secondary: W.amber,
    onSecondary: W.ink,
    error: W.faultFg,
    onError: Colors.white,
    surface: W.surface,
    onSurface: W.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: WType.family,
    scaffoldBackgroundColor: W.surface,
    splashFactory: InkSparkle.splashFactory,
    // The design has no elevated app bar anywhere — every screen scrolls its
    // own header. A themed default stops a stray Scaffold appBar from
    // introducing a Material surface tint that exists nowhere in the design.
    appBarTheme: const AppBarTheme(
      backgroundColor: W.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: W.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: W.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WRadius.card)),
      titleTextStyle: WType.section(W.ink),
      contentTextStyle: WType.body(W.textSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: W.ink,
      contentTextStyle: WType.body(Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WRadius.tile)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: W.soft,
      hintStyle: WType.body(W.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WRadius.tile),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WRadius.tile),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WRadius.tile),
        borderSide: const BorderSide(color: W.red, width: 1.6),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0x1417151A), thickness: 1, space: 1),
    textTheme: TextTheme(
      displayLarge: WType.display(W.ink),
      headlineMedium: WType.stat(W.ink),
      titleLarge: WType.section(W.ink),
      titleMedium: WType.title(W.ink),
      bodyMedium: WType.body(W.textSecondary),
      labelLarge: WType.pill(W.ink),
    ),
  );
}
