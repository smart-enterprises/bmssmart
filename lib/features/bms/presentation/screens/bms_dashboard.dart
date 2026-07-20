// lib/features/bms/presentation/screens/bms_dashboard.dart
//
// Glassmorphic BMS dashboard — light theme, orange accent, ported from the
// approved design (bms-dashboard.jsx). Every field is nullable because Daly
// answers each command separately; the dashboard shows what has arrived and
// omits pieces whose command hasn't been answered yet.

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/persistence/last_device_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/battery_gauge.dart';
import '../../../../core/widgets/bms_widgets.dart';
import '../../../../core/widgets/pill_switch.dart';
import '../../data/models/bms_models.dart';
import '../providers/bms_provider.dart';
import 'debug_log_screen.dart';
import 'history_screen.dart';
import 'scanner_screen.dart';

class BmsDashboard extends ConsumerWidget {
  const BmsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(bleDeviceProvider);
    final statusAsync = ref.watch(bleStatusProvider);
    final snapshotAsync = ref.watch(bmsSnapshotProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  _Header(device: device, statusAsync: statusAsync),
                  Expanded(
                    child: _Body(snapshotAsync: snapshotAsync, statusAsync: statusAsync, deviceName: device?.platformName),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────
class _Header extends ConsumerWidget {
  const _Header({required this.device, required this.statusAsync});
  final BluetoothDevice? device;
  final AsyncValue<BleStatus> statusAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceName = device?.platformName;
    final name = (deviceName != null && deviceName.isNotEmpty) ? deviceName : 'Pack 01';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$name · LiFePO₄',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSec, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    statusAsync.when(
                      data: (s) => _StatusDot(state: s.state),
                      loading: () => const _StatusDot(state: BleConnectionState.connecting),
                      error: (_, _) => const _StatusDot(state: BleConnectionState.error),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Battery',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.4),
                ),
              ],
            ),
          ),
          _MoreButton(onSelected: (action) => _handleMenu(context, ref, action)),
        ],
      ),
    );
  }

  Future<void> _handleMenu(BuildContext context, WidgetRef ref, _MenuAction action) async {
    switch (action) {
      case _MenuAction.history:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
      case _MenuAction.debugLog:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugLogScreen()));
      case _MenuAction.forget:
        await LastDeviceStore.clear();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Forgotten — this device will no longer auto-reconnect.')),
          );
        }
      case _MenuAction.disconnect:
        ref.read(bleDeviceProvider.notifier).state = null;
        if (context.mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const BleScannerScreen()));
        }
    }
  }
}

enum _MenuAction { history, debugLog, forget, disconnect }

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onSelected});
  final ValueChanged<_MenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      onSelected: onSelected,
      icon: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.chipBorder),
        ),
        child: const Icon(Icons.more_horiz, color: AppColors.textSec, size: 18),
      ),
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => const [
        PopupMenuItem(value: _MenuAction.history, child: Row(children: [Icon(Icons.show_chart, size: 18, color: AppColors.textSec), SizedBox(width: 12), Text('History')])),
        PopupMenuItem(value: _MenuAction.debugLog, child: Row(children: [Icon(Icons.bug_report_outlined, size: 18, color: AppColors.textSec), SizedBox(width: 12), Text('Debug log')])),
        PopupMenuDivider(),
        PopupMenuItem(value: _MenuAction.forget, child: Row(children: [Icon(Icons.link_off, size: 18, color: AppColors.textSec), SizedBox(width: 12), Text('Forget this device')])),
        PopupMenuItem(value: _MenuAction.disconnect, child: Row(children: [Icon(Icons.logout, size: 18, color: AppColors.danger), SizedBox(width: 12), Text('Disconnect', style: TextStyle(color: AppColors.danger))])),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state});
  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      BleConnectionState.connected => ('Connected', AppColors.success),
      BleConnectionState.connecting => ('Connecting', AppColors.primary),
      BleConnectionState.disconnected => ('Disconnected', AppColors.textSec),
      BleConnectionState.error => ('Error', AppColors.danger),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  const _Body({required this.snapshotAsync, required this.statusAsync, required this.deviceName});
  final AsyncValue<BmsSnapshot> snapshotAsync;
  final AsyncValue<BleStatus> statusAsync;
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    return statusAsync.when(
      data: (status) => switch (status.state) {
        BleConnectionState.connecting => _StatusMessage.connecting(deviceName),
        BleConnectionState.error => _StatusMessage.error(status.errorMessage ?? 'Unknown error'),
        BleConnectionState.disconnected => const _StatusMessage.disconnected(),
        BleConnectionState.connected => _ConnectedBody(snapshotAsync: snapshotAsync),
      },
      loading: () => _StatusMessage.connecting(deviceName),
      error: (e, _) => _StatusMessage.error(e.toString()),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.icon, required this.iconColor, required this.title, this.subtitle, this.spinner = false});

  factory _StatusMessage.connecting(String? name) => _StatusMessage(
        icon: Icons.bluetooth_searching,
        iconColor: AppColors.primary,
        title: 'Connecting to ${name?.isNotEmpty == true ? name : 'device'}…',
        spinner: true,
      );

  factory _StatusMessage.error(String message) =>
      _StatusMessage(icon: Icons.error_outline, iconColor: AppColors.danger, title: 'Connection error', subtitle: message);

  const _StatusMessage.disconnected()
      : icon = Icons.bluetooth_disabled,
        iconColor = AppColors.textSec,
        title = 'Disconnected',
        subtitle = null,
        spinner = false;

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: iconColor))
            else
              Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSec, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Connected body ────────────────────────────────────────────────────────────
class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody({required this.snapshotAsync});
  final AsyncValue<BmsSnapshot> snapshotAsync;

  @override
  Widget build(BuildContext context) {
    final snapshot = snapshotAsync.value;

    if (snapshot == null || !snapshot.hasCoreData) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: _WaitingCard(),
      );
    }

    const tempThresholds = kTempThresholds;
    final maxTemp = snapshot.maxObservedTempC;
    final tempSeverity = maxTemp == null ? TempSeverity.normal : tempThresholds.classify(maxTemp.toDouble());

    final status = switch (snapshot.status) {
      ChargeStatus.charging => GaugeStatus.charging,
      ChargeStatus.discharging => GaugeStatus.discharging,
      ChargeStatus.idle => GaugeStatus.idle,
      null => GaugeStatus.idle,
    };

    final current = snapshot.currentAmps;
    final isCharging = status == GaugeStatus.charging;
    // isDischarging (derived from snapshot.status, which is only non-null when
    // currentAmps is) implies current != null — but Dart can't prove that
    // through the ChargeStatus indirection, so the checks below re-verify it
    // directly rather than asserting with `!`.
    final isDischarging = status == GaugeStatus.discharging;
    final runtimeHours = (isDischarging && snapshot.remainingAh != null && current != null)
        ? estimateRuntimeHours(remainingAh: snapshot.remainingAh!, loadAmps: current.abs())
        : null;

    final timeToFullHours = (isCharging && snapshot.remainingAh != null && snapshot.nominalAh != null && current != null)
        ? estimateTimeToFullHours(remainingAh: snapshot.remainingAh!, nominalAh: snapshot.nominalAh!, chargeAmps: current)
        : null;

    final String runtimeValue;
    final String runtimeSublabel;
    if (isDischarging) {
      runtimeValue = formatDuration(runtimeHours);
      runtimeSublabel = current != null ? 'at ${current.abs().toStringAsFixed(1)} A load' : 'no load';
    } else if (isCharging) {
      runtimeValue = timeToFullHours == 0 ? 'Full' : formatDuration(timeToFullHours);
      runtimeSublabel = current != null ? 'to full at ${current.toStringAsFixed(1)} A' : 'plugged in';
    } else {
      runtimeValue = '—';
      runtimeSublabel = 'no load';
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tempSeverity != TempSeverity.normal && maxTemp != null) ...[
            _TempAlertBanner(tempC: maxTemp, severity: tempSeverity, thresholds: tempThresholds),
            const SizedBox(height: 12),
          ],
          if (snapshot.hasFault) ...[
            _FaultCard(faults: snapshot.activeFaults!),
            const SizedBox(height: 12),
          ],

          // Gauge card with charge/discharge switches
          GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              children: [
                BatteryGauge(percent: snapshot.soc!, status: status, size: 240),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.only(top: 18),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.trackBg)),
                  ),
                  child: _MosfetSwitchRow(chargeOn: snapshot.chargeMosOn, dischargeOn: snapshot.dischargeMosOn),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2x3 stat grid
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Current',
                  value: current == null ? '—' : '${current >= 0 ? '+' : ''}${current.toStringAsFixed(2)}',
                  unit: 'A',
                  color: isCharging ? AppColors.success : (isDischarging ? AppColors.danger : AppColors.text),
                  sublabel: isCharging ? 'Energy in' : (isDischarging ? 'Energy out' : 'Resting'),
                  icon: isCharging ? Icons.arrow_upward : (isDischarging ? Icons.arrow_downward : Icons.pause),
                  iconColor: isCharging ? AppColors.success : (isDischarging ? AppColors.danger : AppColors.textSec),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Runtime',
                  value: runtimeValue,
                  sublabel: runtimeSublabel,
                  icon: Icons.access_time,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TemperatureCard(
                  tempC: maxTemp?.toDouble(),
                  thresholds: tempThresholds,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Total voltage',
                  value: snapshot.packVoltage!.toStringAsFixed(2),
                  unit: 'V',
                  sublabel: '${snapshot.cellCount ?? snapshot.cellVoltages.length} cells in series',
                  icon: Icons.bolt,
                  iconColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Capacity',
                  value: snapshot.remainingAh?.toStringAsFixed(1) ?? '—',
                  unit: snapshot.nominalAh != null ? '/ ${snapshot.nominalAh!.toStringAsFixed(0)} Ah' : 'Ah',
                  sublabel: 'Remaining',
                  icon: Icons.battery_full,
                  iconColor: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Cycles',
                  value: snapshot.cycleCount?.toString() ?? '—',
                  sublabel: 'Charge cycles',
                  icon: Icons.refresh,
                ),
              ),
            ],
          ),

          if (snapshot.cellVoltages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CellVoltageCard(voltages: snapshot.cellVoltages, balancingCells: snapshot.balancingCells),
          ],
        ],
      ),
    );
  }
}

// ── Waiting card ─────────────────────────────────────────────────────────────
class _WaitingCard extends StatelessWidget {
  const _WaitingCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Waiting for BMS data…\nOpen the debug log if this persists.',
              style: TextStyle(color: AppColors.textSec, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Temperature alert ────────────────────────────────────────────────────────
//
// Thresholds are fixed (kTempThresholds) — not user-adjustable. This banner
// is a plain status display, not a control.
class _TempAlertBanner extends StatelessWidget {
  const _TempAlertBanner({required this.tempC, required this.severity, required this.thresholds});
  final int tempC;
  final TempSeverity severity;
  final TempThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final isCritical = severity == TempSeverity.critical;
    final color = isCritical ? AppColors.danger : const Color(0xFFD29922);
    final title = isCritical ? 'Critical temperature' : 'Temperature warning';
    final limit = isCritical ? thresholds.criticalC : thresholds.warningC;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(isCritical ? Icons.warning_amber_rounded : Icons.thermostat, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Now $tempC °C — at or above the $limit °C ${isCritical ? 'critical' : 'warning'} level.',
                    style: const TextStyle(color: AppColors.text, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fault card ───────────────────────────────────────────────────────────────
class _FaultCard extends StatelessWidget {
  const _FaultCard({required this.faults});
  final List<String> faults;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 18),
              const SizedBox(width: 8),
              Text(
                faults.length == 1 ? '1 active alarm' : '${faults.length} active alarms',
                style: const TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...faults.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: AppColors.danger, fontSize: 13)),
                  Expanded(child: Text(f, style: const TextStyle(color: AppColors.text, fontSize: 13))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charge / discharge switches ───────────────────────────────────────────────
class _MosfetSwitchRow extends ConsumerStatefulWidget {
  const _MosfetSwitchRow({required this.chargeOn, required this.dischargeOn});
  final bool? chargeOn;
  final bool? dischargeOn;

  @override
  ConsumerState<_MosfetSwitchRow> createState() => _MosfetSwitchRowState();
}

class _MosfetSwitchRowState extends ConsumerState<_MosfetSwitchRow> {
  /// Which MOSFET has a command in flight, if any. The dashboard keeps
  /// showing the BMS's real reported state throughout — this only disables
  /// the control so a second tap can't race the first.
  bool _chargeBusy = false;
  bool _dischargeBusy = false;

  Future<void> _toggle({required bool isCharge, required bool currentlyOn}) async {
    final turningOn = !currentlyOn;
    final label = isCharge ? 'charge' : 'discharge';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(turningOn ? 'Turn $label MOSFET on?' : 'Turn $label MOSFET off?', style: const TextStyle(color: AppColors.text, fontSize: 17)),
        content: Text(
          turningOn
              ? 'This re-enables ${isCharge ? "charging" : "the pack's output"}.'
              : isCharge
                  ? 'The pack will stop accepting charge. You can turn it back on from here.'
                  : "The pack will stop supplying power immediately — anything running from it will cut out.\n\nThe BMS stays reachable over Bluetooth, so you can turn it back on from here.",
          style: const TextStyle(color: AppColors.textSec, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel', style: TextStyle(color: AppColors.textSec))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              turningOn ? 'Turn on' : 'Turn off',
              style: TextStyle(color: turningOn ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final service = ref.read(bmsBleServiceProvider);
    if (service == null) return;

    setState(() => isCharge ? _chargeBusy = true : _dischargeBusy = true);

    final ok = isCharge ? await service.setChargeMos(on: turningOn) : await service.setDischargeMos(on: turningOn);

    if (!mounted) return;
    setState(() => isCharge ? _chargeBusy = false : _dischargeBusy = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send the $label MOSFET command.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent. The $label MOSFET reading updates when the BMS reports its actual state.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _MosLabel(label: 'Charging', on: widget.chargeOn, busy: _chargeBusy, activeColor: AppColors.success),
            const SizedBox(width: 10),
            PillSwitch(
              on: widget.chargeOn ?? false,
              activeColor: AppColors.success,
              onChanged: (widget.chargeOn == null || _chargeBusy)
                  ? null
                  : (_) => _toggle(isCharge: true, currentlyOn: widget.chargeOn!),
            ),
          ],
        ),
        Row(
          children: [
            _MosLabel(label: 'Discharge', on: widget.dischargeOn, busy: _dischargeBusy, activeColor: AppColors.primary),
            const SizedBox(width: 10),
            PillSwitch(
              on: widget.dischargeOn ?? false,
              activeColor: AppColors.primary,
              onChanged: (widget.dischargeOn == null || _dischargeBusy)
                  ? null
                  : (_) => _toggle(isCharge: false, currentlyOn: widget.dischargeOn!),
            ),
          ],
        ),
      ],
    );
  }
}

class _MosLabel extends StatelessWidget {
  const _MosLabel({required this.label, required this.on, required this.busy, required this.activeColor});
  final String label;
  final bool? on;
  final bool busy;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
        Text(
          busy ? 'Sending…' : (on == null ? '—' : (on! ? 'On' : 'Off')),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on == true ? activeColor : AppColors.textSec),
        ),
      ],
    );
  }
}

// ── Cell voltages card ────────────────────────────────────────────────────────
class _CellVoltageCard extends StatelessWidget {
  const _CellVoltageCard({required this.voltages, this.balancingCells = const {}});
  final List<double> voltages;
  final Set<int> balancingCells;

  @override
  Widget build(BuildContext context) {
    if (voltages.isEmpty) return const SizedBox.shrink();

    final minV = voltages.reduce((a, b) => a < b ? a : b);
    final maxV = voltages.reduce((a, b) => a > b ? a : b);
    final deltaV = maxV - minV;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cell voltages', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      'Δ ${(deltaV * 1000).toStringAsFixed(0)} mV · ${minV.toStringAsFixed(2)}–${maxV.toStringAsFixed(2)} V',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSec),
                    ),
                  ],
                ),
              ),
              BalanceBadge(deltaVolts: deltaV),
            ],
          ),
          const SizedBox(height: 6),
          Column(
            children: voltages.asMap().entries.map((entry) {
              final i = entry.key;
              return Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.trackBg))),
                child: CellRow(
                  index: i + 1,
                  voltage: entry.value,
                  min: minV,
                  max: maxV,
                  isBalancing: balancingCells.contains(i + 1),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
