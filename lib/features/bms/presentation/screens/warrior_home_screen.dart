// lib/features/bms/presentation/screens/warrior_home_screen.dart
//
// Home — the power-flow screen from the Warrior design.
//
// This screen is where the app's two data sources meet. The battery half (SOC,
// current, backup time, charge MOSFET) comes off BLE directly from the BMS;
// the inverter half (mains voltage, load, output, charger state) comes from
// the cloud, uploaded by the ESP32 gateway. Either can be absent — no network
// in a plant room, or out of Bluetooth range from the far side of the house —
// so every panel degrades on its own and none of them blanks the others.
//
// TWO CONTROLS IN THE DESIGN ARE NOT CONTROLS HERE. The inverter's UART
// protocol is READ-ONLY: every command reports a value and none change a
// setting, so "Inverter output" and the Normal/UPS mode selector can only be
// shown, never driven. They are rendered as reported state with that said
// plainly, rather than as switches that would silently do nothing. "Battery
// charging" IS real — it maps to the BMS charge MOSFET, which the app already
// commands over BLE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/warrior_theme.dart';
import '../../../../core/widgets/warrior_widgets.dart';
import '../../../cloud/cloud_api.dart';
import '../../../cloud/cloud_providers.dart';
import '../../../../core/ble/ble_service.dart';
import '../../data/models/bms_models.dart';
import '../providers/battery_view.dart';
import '../providers/bms_provider.dart';

/// Rated capacity of the unit, used to turn the inverter's load percentage
/// into watts. The inverter reports only a percentage, so this is the one
/// number that makes it meaningful — wrong rating, wrong watts.
const kRatedVa = 1500;

class WarriorHomeScreen extends ConsumerWidget {
  const WarriorHomeScreen({super.key, this.onOpenAlerts, this.onOpenSettings, this.onOpenEnergy});

  final VoidCallback? onOpenAlerts;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenEnergy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(batteryViewProvider);
    final health = ref.watch(deviceHealthProvider).value;
    final inv = health?.inverter;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 116),
        children: [
          _Header(onOpenAlerts: onOpenAlerts, onOpenSettings: onOpenSettings, health: health),
          const SizedBox(height: 16),
          _StatusLine(health: health),
          const SizedBox(height: 16),
          _PowerFlowHero(battery: battery, inverter: inv),
          const SizedBox(height: 12),
          _BackupRow(battery: battery, inverter: inv),
          const SizedBox(height: 11),
          _ModeSelector(inverter: inv),
          const SizedBox(height: 11),
          _ControlCard(battery: battery, inverter: inv),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.onOpenAlerts, this.onOpenSettings, this.health});

  final VoidCallback? onOpenAlerts;
  final VoidCallback? onOpenSettings;
  final DeviceHealth? health;

  @override
  Widget build(BuildContext context) {
    // The badge means "there is something to look at", so it follows real
    // events rather than being permanently on as in the static design.
    final unread = health?.events.any((e) => e.severity != 'info') ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/branding/warrior_logo.png',
                height: 16,
                fit: BoxFit.contain,
                // The wordmark is branding, not information — if the asset is
                // ever missing the screen must still render its readings.
                errorBuilder: (_, _, _) => Text('WARRIOR', style: WType.eyebrow(W.ink, size: 13)),
              ),
              const SizedBox(width: 9),
              const WRacingStripes(height: 15, scale: 0.7),
            ],
          ),
          Row(
            children: [
              WIconButton(
                icon: Icons.notifications_none_rounded,
                badge: unread,
                onTap: onOpenAlerts ?? () {},
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onOpenSettings,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: W.ink,
                    borderRadius: BorderRadius.circular(WRadius.icon),
                  ),
                  child: Icon(Icons.person_rounded, size: 19, color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends ConsumerWidget {
  const _StatusLine({this.health});

  final DeviceHealth? health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleStatusProvider).value;
    final bleLive = ble?.state == BleConnectionState.connected;
    final cloudLive = health?.gatewayOnline ?? false;

    // Colour follows the worse of the two links rather than either alone: a
    // green dot while the gateway is offline would be a claim the app cannot
    // support just because Bluetooth happens to be in range.
    final (color, text) = switch ((bleLive, cloudLive)) {
      (true, true) => (W.green, 'Battery and inverter both reporting'),
      (true, false) => (W.amber, 'Battery live over Bluetooth · inverter offline'),
      (false, true) => (W.amber, 'Inverter reporting · battery not connected'),
      (false, false) => (W.textTertiary, health?.detail.isNotEmpty == true
          ? health!.detail
          : 'Not connected'),
    };

    return Row(
      children: [
        WLiveDot(color: color, animate: bleLive || cloudLive),
        const SizedBox(width: 7),
        Expanded(child: Text(text, style: WType.meta(W.textSecondary), maxLines: 2)),
      ],
    );
  }
}

/// The near-black hero: grid and battery on the left, animated flow lines in
/// the middle, load and output on the right.
class _PowerFlowHero extends StatelessWidget {
  const _PowerFlowHero({required this.battery, this.inverter});

  final BatteryView battery;
  final InverterState? inverter;

  @override
  Widget build(BuildContext context) {
    final inv = inverter;
    final onGrid = inv?.onGrid;
    final soc = battery.soc ?? 0;
    final charging = battery.status == null ? null : battery.status == ChargeStatus.charging;
    final loadW = inv?.loadWatts(kRatedVa);

    final gridAccent = switch (onGrid) {
      true => Colors.white.withValues(alpha: 0.75),
      false => W.red,
      null => Colors.white.withValues(alpha: 0.35),
    };
    final batAccent = switch (charging) {
      true => W.green,
      false => W.amber,
      null => Colors.white.withValues(alpha: 0.35),
    };

    return WHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // The reading is never cleared when a cycle is missed, so this
            // label is what distinguishes "live" from "the same numbers, but
            // from a while ago". Without it a frozen screen looks healthy.
            battery.isStale
                ? 'POWER FLOW · ${battery.ageLabel.toUpperCase()}'
                : 'POWER FLOW · LIVE',
            style: WType.eyebrow(Colors.white
                .withValues(alpha: battery.isStale ? 0.65 : 0.5)),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 98,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WHeroTile(
                        icon: Icons.electrical_services_rounded,
                        label: 'GRID IN',
                        value: inv?.mainsVolts?.toString() ?? wNoValue,
                        unit: 'V',
                        footer: switch (onGrid) {
                          true => 'Healthy',
                          false => 'Failed',
                          null => 'No data',
                        },
                        accent: gridAccent,
                        valueColor: onGrid == false ? W.red : Colors.white,
                        borderColor: onGrid == false
                            ? W.red.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 12),
                      _Dimmed(
                        stale: battery.isStale,
                        child: TweenAnimationBuilder<double>(
                          // Value animation belongs on this screen and no
                          // other: at a ~1 s cadence a snapped digit reads as
                          // a flicker, while on the slower screens the same
                          // tween is still catching up when the next reading
                          // lands and makes the app look laggy.
                          tween: Tween<double>(end: soc),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedSoc, _) => WHeroTile(
                            icon: Icons.battery_charging_full_rounded,
                            label: 'BATTERY',
                            value: battery.soc != null
                                ? animatedSoc.toStringAsFixed(0)
                                : wNoValue,
                            unit: '%',
                            footer: switch (charging) {
                              true => 'Charging',
                              false => 'Discharging',
                              null => 'No data',
                            },
                            accent: batAccent,
                            borderColor: batAccent.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _FlowDiagram(
                      gridActive: onGrid == true,
                      batteryActive: charging == false,
                      loadActive: (loadW ?? 0) > 0 || battery.hasData,
                    ),
                  ),
                ),
                SizedBox(
                  width: 106,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LoadCard(watts: loadW, percent: inv?.loadPercent),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'OUTPUT',
                              style: WType.eyebrow(Colors.white.withValues(alpha: 0.45), size: 10, tracking: 1),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              switch ((inv?.inverterOn, inv?.outputVolts)) {
                                (true, final v?) => '$v V',
                                (true, null) => 'Running',
                                (false, _) => 'Bypass · grid direct',
                                (null, _) => wNoValue,
                              },
                              style: WType.title(Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims a reading that has gone stale instead of removing it. Blanking would
/// make a missed cycle look like a fault; dimming says "still the last known
/// value" while the age label above says how old it is.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.stale, required this.child});

  final bool stale;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: stale ? 0.45 : 1,
        duration: const Duration(milliseconds: 250),
        child: child,
      );
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({this.watts, this.percent});

  final int? watts;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEBE42430), Color(0xF5C81A25)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LOAD NOW',
            style: WType.eyebrow(Colors.white.withValues(alpha: 0.8), size: 10, tracking: 1),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  watts?.toString() ?? wNoValue,
                  style: watts == null
                      ? WType.stat(Colors.white.withValues(alpha: 0.55))
                          .copyWith(fontSize: 18)
                      : WType.stat(Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Text('W', style: WType.caption(Colors.white)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            percent != null ? '$percent% of $kRatedVa VA' : 'no inverter data',
            style: WType.eyebrow(Colors.white.withValues(alpha: 0.85), size: 10.5, tracking: 0),
          ),
        ],
      ),
    );
  }
}

/// The dashed flow lines. Animated because the direction of flow is the whole
/// point of the panel — a static diagram cannot distinguish "grid is carrying
/// the house" from "grid is present but idle".
class _FlowDiagram extends StatefulWidget {
  const _FlowDiagram({required this.gridActive, required this.batteryActive, required this.loadActive});

  final bool gridActive;
  final bool batteryActive;
  final bool loadActive;

  @override
  State<_FlowDiagram> createState() => _FlowDiagramState();
}

class _FlowDiagramState extends State<_FlowDiagram> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _FlowPainter(
          phase: _c.value,
          gridActive: widget.gridActive,
          batteryActive: widget.batteryActive,
          loadActive: widget.loadActive,
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.phase,
    required this.gridActive,
    required this.batteryActive,
    required this.loadActive,
  });

  final double phase;
  final bool gridActive;
  final bool batteryActive;
  final bool loadActive;

  @override
  void paint(Canvas canvas, Size size) {
    void dashed(Path path, Color color, bool animate, double width) {
      final metrics = path.computeMetrics().toList();
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      const dash = 4.0, gap = 7.0;
      for (final m in metrics) {
        // Offsetting by the animation phase is what makes the dashes travel;
        // a static offset would draw the same picture whether power is
        // flowing or not.
        var d = animate ? -(phase * (dash + gap)) : 0.0;
        while (d < m.length) {
          final start = d.clamp(0.0, m.length);
          final end = (d + dash).clamp(0.0, m.length);
          if (end > start) canvas.drawPath(m.extractPath(start, end), paint);
          d += dash + gap;
        }
      }
    }

    // Laid out against the ACTUAL width rather than the design's fixed 74px.
    // At a fixed width the whole diagram floated in the middle of the column
    // with a gap at each end, so the lines connected nothing and the two
    // curves read as the outline of a box. Anchoring the ends to the column
    // edges is what makes it read as flow into a node and out to the load.
    final w = size.width, h = size.height;
    final midY = h / 2;
    final nodeX = w * 0.58;
    final elbowX = w * 0.42;

    final gridPath = Path()
      ..moveTo(0, h * 0.22)
      ..lineTo(elbowX - 10, h * 0.22)
      ..cubicTo(elbowX - 2, h * 0.22, elbowX, h * 0.3, elbowX, h * 0.36)
      ..lineTo(elbowX, midY - 8);
    final batPath = Path()
      ..moveTo(0, h * 0.78)
      ..lineTo(elbowX - 10, h * 0.78)
      ..cubicTo(elbowX - 2, h * 0.78, elbowX, h * 0.7, elbowX, h * 0.64)
      ..lineTo(elbowX, midY + 8);
    final loadPath = Path()
      ..moveTo(nodeX + 8, midY)
      ..lineTo(w, midY);

    dashed(
      gridPath,
      gridActive ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
      gridActive,
      2.2,
    );
    dashed(
      batPath,
      batteryActive ? W.amber : Colors.white.withValues(alpha: 0.12),
      batteryActive,
      2.2,
    );
    final joinPath = Path()
      ..moveTo(elbowX, midY - 8)
      ..lineTo(elbowX, midY + 8)
      ..moveTo(elbowX, midY)
      ..lineTo(nodeX - 8, midY);
    dashed(joinPath, Colors.white.withValues(alpha: 0.3), false, 2.0);
    dashed(loadPath, loadActive ? W.red : Colors.white.withValues(alpha: 0.12), loadActive, 2.4);

    canvas.drawCircle(Offset(nodeX, midY), 5.5, Paint()..color = W.red);
    canvas.drawCircle(
      Offset(nodeX, midY),
      10,
      Paint()
        ..color = W.red.withValues(alpha: 0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.phase != phase ||
      old.gridActive != gridActive ||
      old.batteryActive != batteryActive ||
      old.loadActive != loadActive;
}

/// Battery backup remaining, beside how much backup was actually used.
class _BackupRow extends ConsumerWidget {
  const _BackupRow({required this.battery, this.inverter});

  final BatteryView battery;
  final InverterState? inverter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soc = battery.soc;
    // Only a discharge current gives a runtime; charging or idle has no
    // meaningful "time left" and must not be presented as one. That rule
    // lives on BatteryView so both sources get it identically.
    final runtime = battery.runtimeHours;

    final history = ref.watch(cloudHistoryProvider).value;
    final outage = _outageToday(history);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: WGlassCard(
              child: WStatBlock(
                label: 'Battery backup',
                value: runtime != null ? formatDuration(runtime) : wNoValue,
                footer: Row(
                  children: [
                    Expanded(child: WMeter(fraction: (soc ?? 0) / 100)),
                    const SizedBox(width: 6),
                    Text(
                      soc != null ? '${soc.toStringAsFixed(0)}%' : '',
                      style: WType.caption(W.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: WCard(
              child: WStatBlock(
                label: 'Grid outages today',
                value: outage == null ? wNoValue : '${outage.count}',
                unit: outage == null ? null : (outage.count == 1 ? 'outage' : 'outages'),
                footer: Text(
                  outage == null
                      ? 'no history yet'
                      : outage.count == 0
                          ? 'mains steady all day'
                          : 'on battery ${formatDuration(outage.hours)}',
                  style: WType.caption(W.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Counts grid outages from the stored history by looking for runs where the
  /// inverter reported mains at or near zero. Derived rather than invented —
  /// the backend records no outage log of its own, and showing a plausible
  /// number here would be indistinguishable from a measured one.
  static ({int count, double hours})? _outageToday(List<CloudReading>? rows) {
    if (rows == null || rows.isEmpty) return null;
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final today = rows.where((r) => r.timestamp.isAfter(since) && r.inverter?.mainsVolts != null).toList();
    if (today.isEmpty) return null;

    var count = 0;
    var downMs = 0;
    var wasDown = false;
    for (var i = 0; i < today.length; i++) {
      final down = (today[i].inverter!.mainsVolts ?? 0) <= 50;
      if (down && !wasDown) count++;
      if (down && i > 0) {
        downMs += today[i].timestamp.difference(today[i - 1].timestamp).inMilliseconds;
      }
      wasDown = down;
    }
    return (count: count, hours: downMs / 3600000);
  }
}

/// Output mode, as REPORTED. The inverter protocol has no command that changes
/// it, so this is presented as a reading rather than a control.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({this.inverter});

  final InverterState? inverter;

  @override
  Widget build(BuildContext context) {
    final standby = inverter?.standby;
    final selected = switch (standby) {
      'ups_standby' => 'UPS',
      'inv_standby' => 'Inverter',
      'running' => 'Running',
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: selected == null ? 0.45 : 1,
          child: IgnorePointer(
            child: WSegmented(
              options: const ['Running', 'UPS', 'Inverter'],
              selected: selected ?? '',
              onChanged: (_) {},
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Text(
            'Reported by the inverter. Its firmware has no command to change '
            'the mode remotely — use the panel on the unit.',
            style: TextStyle(
              fontFamily: WType.family,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: W.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inverter output (read-only) above battery charging (a real BLE control).
class _ControlCard extends ConsumerWidget {
  const _ControlCard({required this.battery, this.inverter});

  final BatteryView battery;
  final InverterState? inverter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invOn = inverter?.inverterOn;
    final charging = battery.chargeMosOn;
    final chargeState = inverter?.chargeState;

    return WGlassCard(
      radius: WRadius.pillGroup,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WToggleRow(
            icon: Icons.bolt_rounded,
            iconBg: invOn == true ? const Color(0xFFE6F6EE) : W.soft,
            iconFg: invOn == true ? W.green : W.textMuted,
            title: 'Inverter output',
            subtitle: switch (invOn) {
              true => 'On · reported by the inverter',
              false => 'Off · running on bypass',
              null => 'No inverter data',
            },
            subtitleColor: invOn == true ? W.green : W.textSecondary,
            showDivider: true,
            // No switch: read-only protocol. A disabled switch would still
            // read as "this can be turned on", which it cannot.
            trailing: Icon(
              invOn == true ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
              size: 22,
              color: invOn == true ? W.green : W.textTertiary,
            ),
          ),
          WToggleRow(
            icon: Icons.battery_charging_full_rounded,
            iconBg: charging == true ? W.faultBg : W.soft,
            iconFg: charging == true ? W.red : W.textMuted,
            title: 'Battery charging',
            subtitle: switch ((charging, chargeState)) {
              (true, final s?) when s != 'off' => 'Charge MOSFET on · inverter reports $s',
              (true, _) => 'Charge MOSFET on',
              (false, _) => 'Charge MOSFET off',
              (null, _) => 'No battery data',
            },
            subtitleColor: charging == true ? W.red : W.textSecondary,
            trailing: WSwitch(
              value: charging ?? false,
              activeColor: W.red,
              // Null disables the switch, which is correct when there is no
              // BLE link — the command would go nowhere.
              // Disabled unless BLE is connected: the MOSFET command has no
              // cloud equivalent, so cloud-sourced numbers must not imply the
              // switch will do anything.
              onChanged: (charging == null || !battery.controlAvailable)
                  ? null
                  : (v) => _setChargeMos(context, ref, v),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setChargeMos(BuildContext context, WidgetRef ref, bool on) async {
    final service = ref.read(bmsBleServiceProvider);
    if (service == null) return;
    try {
      await service.setChargeMos(on: on);
    } catch (e) {
      if (!context.mounted) return;
      // The BMS's own next reading is the source of truth for the switch
      // position, so a failure here only needs reporting — the UI will not
      // have moved on its own.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change charging: $e')),
      );
    }
  }
}
