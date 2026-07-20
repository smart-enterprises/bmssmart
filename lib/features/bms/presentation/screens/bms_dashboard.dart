// lib/features/bms/presentation/screens/bms_dashboard.dart
//
// Material 3 BMS dashboard — Home tab content, ported from the approved
// design (bms-m3-dashboard.jsx). Every field is nullable because Daly
// answers each command separately; the dashboard shows what has arrived and
// omits pieces whose command hasn't been answered yet.
//
// BmsDashboardBody is the actual content (no Scaffold) — used directly by
// HomeShell as the Home tab. BmsDashboard is a thin Scaffold wrapper kept
// only so this screen stays independently pushable/testable.

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/persistence/last_device_store.dart';
import '../../../../core/theme/m3_theme.dart';
import '../../../../core/widgets/m3_dialog.dart';
import '../../../../core/widgets/m3_gauge.dart';
import '../../../../core/widgets/m3_list_item.dart';
import '../../../../core/widgets/m3_tile.dart';
import '../../../../core/widgets/m3_tonal_button.dart';
import '../../data/models/bms_models.dart';
import '../providers/bms_provider.dart';
import 'debug_log_screen.dart';

class BmsDashboard extends StatelessWidget {
  const BmsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: M3Colors.surface, body: BmsDashboardBody());
  }
}

class BmsDashboardBody extends ConsumerWidget {
  const BmsDashboardBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(bleDeviceProvider);
    final statusAsync = ref.watch(bleStatusProvider);
    final snapshotAsync = ref.watch(bmsSnapshotProvider);

    return Container(
      color: M3Colors.surface,
      child: Column(
        children: [
          _Header(device: device, statusAsync: statusAsync),
          Expanded(
            child: _Body(snapshotAsync: snapshotAsync, statusAsync: statusAsync, deviceName: device?.platformName),
          ),
        ],
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
    final scannedName = device?.platformName;
    // A silent reconnect loses platformName (see lastDeviceNameProvider) —
    // fall back to the name saved at the last successful connect.
    final rememberedName = ref.watch(lastDeviceNameProvider).value;
    final name = (scannedName != null && scannedName.isNotEmpty)
        ? scannedName
        : (rememberedName != null && rememberedName.isNotEmpty ? rememberedName : 'BMS');

    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 20),
      decoration: const BoxDecoration(
        color: M3Colors.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(M3Radii.topBar),
          bottomRight: Radius.circular(M3Radii.topBar),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Image.asset('assets/branding/warrior_logo.png', height: 28, fit: BoxFit.contain, alignment: Alignment.centerLeft),
              ),
              _MoreButton(onSelected: (action) => _handleMenu(context, ref, action)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: M3Colors.onSurfaceVariant))),
              const SizedBox(width: 8),
              statusAsync.when(
                data: (s) => _StatusDot(state: s.state),
                loading: () => const _StatusDot(state: BleConnectionState.connecting),
                error: (_, _) => const _StatusDot(state: BleConnectionState.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(BuildContext context, WidgetRef ref, _MenuAction action) async {
    switch (action) {
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
        ref.read(shellTabIndexProvider.notifier).state = 2;
    }
  }
}

enum _MenuAction { debugLog, forget, disconnect }

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
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Icon(Icons.more_horiz, color: M3Colors.onSurfaceVariant, size: 18),
      ),
      color: M3Colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _MenuAction.debugLog,
          child: Row(children: [Icon(Icons.bug_report_outlined, size: 18, color: M3Colors.onSurfaceVariant), SizedBox(width: 12), Text('Debug log')]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _MenuAction.forget,
          child: Row(children: [Icon(Icons.link_off, size: 18, color: M3Colors.onSurfaceVariant), SizedBox(width: 12), Text('Forget this device')]),
        ),
        PopupMenuItem(
          value: _MenuAction.disconnect,
          child: Row(children: [
            Icon(Icons.logout, size: 18, color: M3Colors.primary),
            SizedBox(width: 12),
            Text('Disconnect', style: TextStyle(color: M3Colors.primary)),
          ]),
        ),
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
      BleConnectionState.connected => ('Connected', M3Colors.success),
      BleConnectionState.connecting => ('Connecting', M3Colors.primary),
      BleConnectionState.disconnected => ('Disconnected', M3Colors.onSurfaceVariant),
      BleConnectionState.error => ('Error', M3Colors.primary),
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

class _StatusMessage extends ConsumerWidget {
  const _StatusMessage({required this.icon, required this.iconColor, required this.title, this.subtitle, this.spinner = false, this.showConnectCta = false});

  factory _StatusMessage.connecting(String? name) => _StatusMessage(
        icon: Icons.bluetooth_searching,
        iconColor: M3Colors.primary,
        title: 'Connecting to ${name?.isNotEmpty == true ? name : 'device'}…',
        spinner: true,
      );

  factory _StatusMessage.error(String message) =>
      _StatusMessage(icon: Icons.error_outline, iconColor: M3Colors.primary, title: 'Connection error', subtitle: message, showConnectCta: true);

  const _StatusMessage.disconnected()
      : icon = Icons.bluetooth_disabled,
        iconColor = M3Colors.onSurfaceVariant,
        title = 'No battery connected',
        subtitle = 'Connect a pack from the Connection tab to see live data here.',
        spinner = false,
        showConnectCta = true;

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool spinner;
  final bool showConnectCta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: M3Colors.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 13)),
            ],
            if (showConnectCta) ...[
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: M3Colors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => ref.read(shellTabIndexProvider.notifier).state = 2,
                child: const Text('Connect a battery'),
              ),
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
        padding: EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: _WaitingCard(),
      );
    }

    const tempThresholds = kTempThresholds;
    final maxTemp = snapshot.maxObservedTempC;
    final tempSeverity = maxTemp == null ? TempSeverity.normal : tempThresholds.classify(maxTemp.toDouble());

    final status = snapshot.status;
    final current = snapshot.currentAmps;
    final isCharging = status == ChargeStatus.charging;
    final isDischarging = status == ChargeStatus.discharging;
    final runtimeHours = (isDischarging && snapshot.remainingAh != null && current != null)
        ? estimateRuntimeHours(remainingAh: snapshot.remainingAh!, loadAmps: current.abs())
        : null;

    final timeToFullHours = (isCharging && snapshot.remainingAh != null && snapshot.nominalAh != null && current != null)
        ? estimateTimeToFullHours(remainingAh: snapshot.remainingAh!, nominalAh: snapshot.nominalAh!, chargeAmps: current)
        : null;

    final String runtimeValue;
    if (isDischarging) {
      runtimeValue = formatDuration(runtimeHours);
    } else if (isCharging) {
      runtimeValue = timeToFullHours == 0 ? 'Full' : formatDuration(timeToFullHours);
    } else {
      runtimeValue = '—';
    }

    final statusLabel = switch (status) {
      ChargeStatus.charging => 'charging',
      ChargeStatus.discharging => 'discharging',
      ChargeStatus.idle => 'idle',
      null => 'idle',
    };

    // Byte 6 bit 4 is undocumented on this hardware but empirically just
    // mirrors "discharge MOSFET off" — not a real fault. That state is
    // already shown on the Discharge toggle button itself, so don't also
    // raise it as an alarm.
    final visibleFaults = snapshot.activeFaults?.where((f) => f != 'Alarm (byte 6 bit 4)').toList();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tempSeverity != TempSeverity.normal && maxTemp != null) ...[
            _TempAlertBanner(tempC: maxTemp, severity: tempSeverity, thresholds: tempThresholds),
            const SizedBox(height: 12),
          ],
          if (visibleFaults != null && visibleFaults.isNotEmpty) ...[
            _FaultCard(faults: visibleFaults),
            const SizedBox(height: 12),
          ],

          Center(child: M3Gauge(percent: snapshot.soc!.round(), status: statusLabel, size: 228)),
          const SizedBox(height: 20),

          // Charging / Discharge tonal toggle row
          Row(
            children: [
              _MosfetToggle(isCharge: true, on: snapshot.chargeMosOn),
              const SizedBox(width: 10),
              _MosfetToggle(isCharge: false, on: snapshot.dischargeMosOn),
            ],
          ),
          const SizedBox(height: 20),

          // 2x3 stat grid
          Row(
            children: [
              Expanded(
                child: M3Tile(
                  label: isCharging ? 'Current · in' : (isDischarging ? 'Current · out' : 'Current · idle'),
                  value: current == null ? '—' : '${current >= 0 ? '+' : ''}${current.toStringAsFixed(2)}',
                  unit: 'A',
                  icon: isCharging ? Icons.arrow_upward : (isDischarging ? Icons.arrow_downward : Icons.pause),
                  tone: isCharging ? M3TileTone.success : (isDischarging ? M3TileTone.primary : M3TileTone.neutral),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M3Tile(label: 'Runtime left', value: runtimeValue, icon: Icons.access_time, tone: M3TileTone.tertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: M3TempTile(tempC: maxTemp?.toDouble() ?? 0)),
              const SizedBox(width: 12),
              Expanded(
                child: M3Tile(
                  label: '${snapshot.cellCount ?? snapshot.cellVoltages.length} cells · Total',
                  value: snapshot.packVoltage!.toStringAsFixed(2),
                  unit: 'V',
                  icon: Icons.bolt,
                  tone: M3TileTone.neutral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: M3Tile(
                  label: 'Remaining capacity',
                  value: snapshot.remainingAh?.toStringAsFixed(1) ?? '—',
                  unit: 'Ah',
                  icon: Icons.battery_full,
                  tone: M3TileTone.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M3Tile(
                  label: 'Total Ah',
                  value: snapshot.nominalAh?.toStringAsFixed(0) ?? '—',
                  unit: 'Ah',
                  icon: Icons.battery_std,
                  tone: M3TileTone.neutral,
                ),
              ),
            ],
          ),

          if (snapshot.cellVoltages.isNotEmpty) ...[
            const SizedBox(height: 16),
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
    return Container(
      decoration: BoxDecoration(color: M3Colors.surfaceContainerLow, borderRadius: BorderRadius.circular(M3Radii.card)),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: M3Colors.primary)),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Waiting for BMS data…\nOpen the debug log if this persists.',
              style: TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 14, height: 1.4),
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
    final color = isCritical ? M3Colors.primary : M3Colors.warningAmber;
    final title = isCritical ? 'Critical temperature' : 'Temperature warning';
    final limit = isCritical ? thresholds.criticalC : thresholds.warningC;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(M3Radii.tile),
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
                    style: const TextStyle(color: M3Colors.onSurface, fontSize: 13)),
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
        color: M3Colors.primaryContainer,
        borderRadius: BorderRadius.circular(M3Radii.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: M3Colors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                faults.length == 1 ? '1 active alarm' : '${faults.length} active alarms',
                style: const TextStyle(color: M3Colors.primary, fontSize: 14, fontWeight: FontWeight.w700),
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
                  const Text('• ', style: TextStyle(color: M3Colors.primary, fontSize: 13)),
                  Expanded(child: Text(f, style: const TextStyle(color: M3Colors.onPrimaryContainer, fontSize: 13))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charge / discharge toggle ─────────────────────────────────────────────────
class _MosfetToggle extends ConsumerStatefulWidget {
  const _MosfetToggle({required this.isCharge, required this.on});
  final bool isCharge;
  final bool? on;

  @override
  ConsumerState<_MosfetToggle> createState() => _MosfetToggleState();
}

class _MosfetToggleState extends ConsumerState<_MosfetToggle> {
  /// The dashboard keeps showing the BMS's real reported state throughout —
  /// this only disables the control so a second tap can't race the first.
  bool _busy = false;

  Future<void> _toggle() async {
    final currentlyOn = widget.on;
    if (currentlyOn == null || _busy) return;
    final turningOn = !currentlyOn;
    final label = widget.isCharge ? 'charge' : 'discharge';

    final confirmed = await showM3Dialog(
      context,
      icon: widget.isCharge ? Icons.power : Icons.bolt,
      destructive: !turningOn,
      title: turningOn ? 'Turn $label MOSFET on?' : 'Turn $label MOSFET off?',
      message: turningOn
          ? 'This re-enables ${widget.isCharge ? "charging" : "the pack's output"}.'
          : widget.isCharge
              ? 'The pack will stop accepting charge. You can turn it back on from here.'
              : "The pack will stop supplying power immediately — anything running from it will cut out.\n\nThe BMS stays reachable over Bluetooth, so you can turn it back on from here.",
      cancelLabel: 'Cancel',
      okLabel: turningOn ? 'Turn on' : 'Turn off',
    );

    if (confirmed != true || !mounted) return;

    final service = ref.read(bmsBleServiceProvider);
    if (service == null) return;

    setState(() => _busy = true);
    final ok = widget.isCharge ? await service.setChargeMos(on: turningOn) : await service.setDischargeMos(on: turningOn);
    if (!mounted) return;
    setState(() => _busy = false);

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
    final label = widget.isCharge ? 'Charging' : 'Discharge';
    final stateText = widget.on == null ? '' : (widget.on! ? ' · On' : ' · Off');
    final activeColor = widget.isCharge ? M3Colors.success : M3Colors.primary;
    return M3TonalButton(
      label: _busy ? 'Sending…' : '$label$stateText',
      icon: widget.isCharge ? Icons.power : Icons.bolt,
      active: widget.on ?? false,
      activeColor: activeColor,
      onTap: _busy ? () {} : _toggle,
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

    return Container(
      decoration: BoxDecoration(color: M3Colors.surfaceContainerLow, borderRadius: BorderRadius.circular(M3Radii.card)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
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
                    const Text('CELL VOLTAGES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: M3Colors.onSurfaceVariant, letterSpacing: 0.3)),
                    const SizedBox(height: 4),
                    Text(
                      'Δ ${(deltaV * 1000).toStringAsFixed(0)} mV · ${minV.toStringAsFixed(2)}–${maxV.toStringAsFixed(2)} V',
                      style: const TextStyle(fontSize: 12, color: M3Colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: voltages.asMap().entries.map((entry) {
              final i = entry.key;
              final v = entry.value;
              final isLast = i == voltages.length - 1;
              final pct = maxV - minV < 0.001 ? 1.0 : (v - minV) / (maxV - minV);
              final balancing = balancingCells.contains(i + 1);
              return M3ListItem(
                icon: Icons.bolt,
                iconColor: balancing ? M3Colors.tertiary : M3Colors.primary,
                iconBg: balancing ? M3Colors.tertiaryContainer : M3Colors.primaryContainer,
                headline: 'Cell ${i + 1}',
                supporting: balancing ? '${v.toStringAsFixed(2)} V · Balancing' : '${v.toStringAsFixed(2)} V',
                last: isLast,
                trailing: SizedBox(
                  width: 84,
                  height: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: 0.1 + pct * 0.9,
                      backgroundColor: M3Colors.surfaceContainerHighest,
                      color: M3Colors.primary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
