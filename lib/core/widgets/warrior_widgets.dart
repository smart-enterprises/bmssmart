// lib/core/widgets/warrior_widgets.dart
//
// The building blocks of the Warrior design. Every screen is assembled from
// these rather than styling containers inline, so that a change to (say) the
// glass card's blur happens in one place instead of nine.
//
// Naming follows the design's own vocabulary: hero card, glass card, tile,
// pill, segmented, floating nav.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/warrior_theme.dart';

/// The string a screen passes where a reading has no value.
const wNoValue = '—';

/// Renders a missing reading smaller and lighter than a real one. At 26px/800
/// an em dash is a solid black bar that reads as a loading skeleton — the
/// opposite of the intended "the sensor did not report this". Caught on
/// device, not in review.
TextStyle _valueStyle(String value, TextStyle real, Color placeholder) => value == wNoValue
    ? real.copyWith(
        color: placeholder,
        fontSize: (real.fontSize ?? 20) * 0.7,
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 500)],
      )
    : real;

/// The skewed red/orange/amber bars from the logo. They appear at the top
/// right of hero cards and beside the wordmark. Purely decorative — never the
/// only carrier of meaning.
class WRacingStripes extends StatelessWidget {
  const WRacingStripes({super.key, this.height = 46, this.opacity = 0.9, this.scale = 1});

  final double height;
  final double opacity;

  /// Multiplies the bar widths (7/4/3 at scale 1), so the same mark can sit
  /// beside a 16px wordmark or on a hero card.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform(
        transform: Matrix4.skewX(-0.3249), // -18deg
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bar(7 * scale, W.red),
            SizedBox(width: 4 * scale),
            _bar(4 * scale, W.orange),
            SizedBox(width: 4 * scale),
            _bar(3 * scale, W.amber),
          ],
        ),
      ),
    );
  }

  Widget _bar(double w, Color c) => Container(width: w, height: height, color: c);
}

/// The near-black card that anchors every screen. One per screen, by design —
/// a second one competes with the first and the hierarchy collapses.
class WHeroCard extends StatelessWidget {
  const WHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 16),
    this.stripes = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool stripes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(WRadius.hero),
      child: Container(
        color: W.ink,
        child: Stack(
          children: [
            if (stripes)
              const Positioned(top: 0, right: 26, child: WRacingStripes(height: 46)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Frosted card. The design layers these over the warm board so the surface
/// beneath shows through — the effect is what separates a "live" card from a
/// plain white one.
class WGlassCard extends StatelessWidget {
  const WGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(15, 14, 15, 14),
    this.radius = WRadius.card,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: WShadow.glass,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              // Warm tint rather than the design's translucent WHITE. The
              // design draws these over a warm board, where white-on-warm
              // reads as frosted glass; the app's screens are white, so the
              // same fill has nothing to sit against and the card disappears.
              // Verified on device — at 55% white it rendered as a faint
              // rectangle with no edge at all.
              color: W.soft.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: W.lineWarm),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Plain white card with a hairline border. The workhorse.
class WCard extends StatelessWidget {
  const WCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(15, 14, 15, 14),
    this.radius = WRadius.cardTight,
    this.borderColor = W.line,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: WShadow.card,
      ),
      child: child,
    );
  }
}

/// A small translucent tile INSIDE a hero card (grid in, battery). Distinct
/// from [WGlassCard]: it sits on near-black, so it lightens rather than blurs.
class WHeroTile extends StatelessWidget {
  const WHeroTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.footer,
    required this.accent,
    this.valueColor = Colors.white,
    this.borderColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String footer;

  /// Drives the icon and footer colour — green healthy, amber flowing, red bad.
  final Color accent;
  final Color valueColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(WRadius.tile),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: WType.eyebrow(Colors.white.withValues(alpha: 0.55), size: 10, tracking: 0.8),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: _valueStyle(
                    value,
                    WType.statSm(valueColor),
                    Colors.white.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: WType.caption(Colors.white.withValues(alpha: 0.55)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(footer, style: WType.eyebrow(accent, size: 10, tracking: 0)),
        ],
      ),
    );
  }
}

/// Segmented control (Normal / UPS). Two or more equal-width options in a
/// translucent trough; the selected one becomes a white raised pill.
class WSegmented extends StatelessWidget {
  const WSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        // Same reason as WGlassCard: a translucent-white trough on a white
        // screen leaves the options floating as bare text with no group
        // around them.
        color: W.soft,
        borderRadius: BorderRadius.circular(WRadius.pillGroup),
        border: Border.all(color: W.lineWarm),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: o == selected ? W.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: o == selected ? WShadow.card : null,
                  ),
                  child: Center(
                    child: Text(
                      o,
                      style: WType.pill(o == selected ? W.ink : W.textMuted),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filter pills — dark when active, soft grey when not. Used by Alerts and by
/// the Energy period chips.
class WPills extends StatelessWidget {
  const WPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.activeBg = W.ink,
    this.activeFg = Colors.white,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  final Color activeBg;
  final Color activeFg;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options) ...[
            GestureDetector(
              onTap: () => onChanged(o),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: o == selected ? activeBg : W.soft,
                  borderRadius: BorderRadius.circular(WRadius.full),
                ),
                child: Text(o, style: WType.pill(o == selected ? activeFg : W.textMuted)),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// The 50x30 pill switch. Material's Switch cannot be shaped like this without
/// fighting its own sizing, and the knob shadow matters at this scale.
class WSwitch extends StatelessWidget {
  const WSwitch({super.key, required this.value, required this.onChanged, this.activeColor = W.green});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? activeColor : W.switchOff,
            borderRadius: BorderRadius.circular(WRadius.full),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: WShadow.switchKnob,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon + title + subtitle + trailing control. The repeated row shape across
/// Home, Battery and Settings.
class WToggleRow extends StatelessWidget {
  const WToggleRow({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    this.trailing,
    this.onTap,
    this.showDivider = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(WRadius.iconSm),
            ),
            child: Icon(icon, size: 18, color: iconFg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: WType.title(W.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: WType.caption(subtitleColor)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );

    final content = showDivider
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row,
              const Divider(height: 1, color: Color(0x1417151A)),
            ],
          )
        : row;

    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content);
  }
}

/// The SOC / load meter — a rounded trough with an amber→red gradient fill.
class WMeter extends StatelessWidget {
  const WMeter({
    super.key,
    required this.fraction,
    this.height = 6,
    this.gradient = const [W.amber, W.red],
  });

  /// 0..1. Clamped, because a stale reading can briefly exceed the range.
  final double fraction;
  final double height;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(WRadius.full),
      child: Container(
        height: height,
        color: W.trough,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(WRadius.full),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small labelled stat block — label above, big number, footer below. Used
/// by the pair of cards under the hero on Home and across Energy.
class WStatBlock extends StatelessWidget {
  const WStatBlock({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.footer,
    this.valueColor = W.ink,
  });

  final String label;
  final String value;
  final String? unit;
  final Widget? footer;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: WType.caption(W.textSecondary)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: _valueStyle(value, WType.stat(valueColor), W.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(unit!, style: WType.caption(W.textSecondary)),
            ],
          ],
        ),
        if (footer != null) ...[const SizedBox(height: 9), footer!],
      ],
    );
  }
}

/// Section heading with an optional right-hand text action.
class WSectionHeader extends StatelessWidget {
  const WSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(title, style: WType.section(W.ink))),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Text(actionLabel!, style: WType.pill(W.red).copyWith(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// The pulsing status dot on the header line. Animated because "online" that
/// never moves is indistinguishable from a frozen screenshot — which is
/// exactly the failure this app exists to make visible.
class WLiveDot extends StatefulWidget {
  const WLiveDot({super.key, required this.color, this.size = 6, this.animate = true});

  final Color color;
  final double size;
  final bool animate;

  @override
  State<WLiveDot> createState() => _WLiveDotState();
}

class _WLiveDotState extends State<WLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(WLiveDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.3).animate(_c),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Square 38x38 header button — bell, back, add. Optionally carries an unread
/// dot.
class WIconButton extends StatelessWidget {
  const WIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = false,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: filled ? W.ink : W.surface,
              borderRadius: BorderRadius.circular(WRadius.icon),
              border: filled ? null : Border.all(color: W.line),
            ),
            child: Icon(icon, size: 18, color: filled ? Colors.white : const Color(0xFF4A4145)),
          ),
          if (badge)
            Positioned(
              top: 8,
              right: 9,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: W.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: W.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty / no-data state. Used wherever a reading genuinely has no source yet
/// — the design draws populated screens, but a screen with nothing to show
/// must say so rather than render zeroes that look like measurements.
class WEmptyState extends StatelessWidget {
  const WEmptyState({super.key, required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: W.soft,
        borderRadius: BorderRadius.circular(WRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: W.textTertiary),
          const SizedBox(height: 12),
          Text(title, style: WType.title(W.ink), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(detail, style: WType.body(W.textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// The floating tab bar. A white pill that hovers over the scrolling content,
/// with a gradient fade beneath it so text scrolls out cleanly instead of
/// colliding with the bar's edge.
///
/// The active tab is a filled red pill rather than a tinted icon — at this
/// size an icon-colour change alone is easy to miss, and the design leans on
/// the fill to carry it.
class WFloatingNav extends StatelessWidget {
  const WFloatingNav({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<WNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 8, 14, 14 + bottomInset),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), W.surface],
          stops: [0, 0.34],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: W.surface,
          borderRadius: BorderRadius.circular(WRadius.hero),
          border: Border.all(color: W.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3817151A),
              blurRadius: 22,
              offset: Offset(0, 6),
              spreadRadius: -8,
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == index ? W.red : Colors.transparent,
                      borderRadius: BorderRadius.circular(WRadius.row),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 20,
                          color: i == index ? Colors.white : const Color(0xFF9C9095),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WType.eyebrow(
                            i == index ? Colors.white : const Color(0xFF9C9095),
                            size: 10,
                            tracking: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class WNavItem {
  const WNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
