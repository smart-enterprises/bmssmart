// lib/features/bms/presentation/screens/ble_scanner_screen.dart
//
// Handles permissions, scanning, device list, and connecting. This is the
// Connection tab body — BleScannerScreenBody is the content (no Scaffold);
// BleScannerScreen is a thin Scaffold wrapper kept only so this screen stays
// independently pushable/testable. The permission/scan/connect state
// machine is unchanged from the pre-M3 version — only the widget tree and
// the connect-tail navigation changed.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smartbms/features/bms/presentation/screens/qr_scanner.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/persistence/last_device_store.dart';
import '../../../../core/theme/m3_theme.dart';
import '../../../../core/widgets/m3_dialog.dart';
import '../../../../core/widgets/m3_list_card.dart';
import '../../../../core/widgets/m3_list_item.dart';
import '../../../../core/widgets/m3_top_app_bar.dart';
import '../providers/bms_provider.dart';
import '../widget/manual_mac_dialog.dart';

import 'debug_log_screen.dart';

class BleScannerScreen extends StatelessWidget {
  const BleScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: M3Colors.surface, body: BleScannerScreenBody());
  }
}

class BleScannerScreenBody extends ConsumerStatefulWidget {
  const BleScannerScreenBody({super.key});

  @override
  ConsumerState<BleScannerScreenBody> createState() => _BleScannerScreenBodyState();
}

class _BleScannerScreenBodyState extends ConsumerState<BleScannerScreenBody> {
  // ── State ──────────────────────────────────────────────────────────────────
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _permissionsGranted = false;
  String? _permissionError;
  String? _connectingToId;

  // Track adapter state continuously instead of polling .first — this avoids
  // the _flutterRestart platform exception thrown on hot-restart.
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningMonitor;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  /// The device the user last connected to, if any — offered as a one-tap
  /// reconnect so they don't have to scan every launch.
  LastDevice? _lastDevice;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
    _loadLastDevice();

    _isScanningMonitor = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isScanning = scanning);
    });

    // Listen to adapter state changes. The first event arrives shortly after
    // the platform channel is ready — this is hot-restart safe.
    _adapterSub = FlutterBluePlus.adapterState.listen(
      (state) {
        if (mounted) setState(() => _adapterState = state);
      },
      onError: (Object e) {
        // Swallow transient platform exceptions (e.g. hot-restart cleanup)
        // ignore: avoid_print
        print('[BleScannerScreen] adapterState error: $e');
      },
    );
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningMonitor?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _loadLastDevice() async {
    final last = await LastDeviceStore.load();
    if (mounted) setState(() => _lastDevice = last);
  }

  // ── Permissions ────────────────────────────────────────────────────────────
  Future<void> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      // Request all relevant permissions. On Android 12+, bluetoothScan/Connect
      // are required and location is NOT needed for BLE. On Android 11 and
      // below, only locationWhenInUse is enforced — bluetooth* requests will
      // auto-grant or be ignored by the OS.
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      // Only fail if a permission was *actively denied* (not just unavailable).
      // permanentlyDenied + denied are real failures; restricted/limited are OK.
      final scanStatus = results[Permission.bluetoothScan];
      final connectStatus = results[Permission.bluetoothConnect];
      final locationStatus = results[Permission.locationWhenInUse];

      final btScanOk = scanStatus == null || scanStatus.isGranted || scanStatus.isLimited;
      final btConnectOk = connectStatus == null || connectStatus.isGranted || connectStatus.isLimited;
      final locationOk = locationStatus == null || locationStatus.isGranted || locationStatus.isLimited;

      // On Android 12+, location may show "denied" but that's fine — we don't need it.
      // On Android 11-, bluetoothScan/Connect may show "denied" but they don't exist there.
      // So we only fail if BOTH the modern AND legacy paths are blocked.
      final modernPathOk = btScanOk && btConnectOk;
      final legacyPathOk = locationOk;

      if (!modernPathOk && !legacyPathOk) {
        if (mounted) {
          setState(() {
            _permissionsGranted = false;
            _permissionError = 'Bluetooth permission denied.\n\n'
                'On Android 12+: enable "Nearby devices"\n'
                'On Android 11-: enable "Location"\n\n'
                'Please grant access in Settings.';
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _permissionsGranted = true;
        _permissionError = null;
      });
    }
  }

  // ── Scanning ───────────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    if (!_permissionsGranted) {
      await _checkAndRequestPermissions();
      if (!_permissionsGranted) return;
    }

    // Use the cached adapter state — avoids _flutterRestart crash on hot reload.
    if (_adapterState != BluetoothAdapterState.on) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _adapterState == BluetoothAdapterState.unknown
                  ? 'Initializing Bluetooth, please try again in a moment...'
                  : 'Please turn on Bluetooth',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _scanResults.clear());

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // Ignore — there may be no scan in progress
    }

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          for (final r in results) {
            final idx = _scanResults.indexWhere((e) => e.device.remoteId == r.device.remoteId);
            if (idx >= 0) {
              _scanResults[idx] = r;
            } else {
              _scanResults.add(r);
            }
          }
          // Sort: named devices first, then by RSSI
          _scanResults.sort((a, b) {
            final aName = a.device.platformName.isNotEmpty;
            final bName = b.device.platformName.isNotEmpty;
            if (aName && !bName) return -1;
            if (!aName && bName) return 1;
            return b.rssi.compareTo(a.rssi);
          });
        });
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      if (!mounted) return;

      final errMsg = e.toString().toLowerCase();
      final isLocationServicesError = errMsg.contains('location') && (errMsg.contains('service') || errMsg.contains('disable'));

      if (isLocationServicesError) {
        // Show a dialog with instructions. We don't auto-launch the Location
        // settings screen because that would require an extra dependency
        // (app_settings) and is a quick action for the user anyway.
        showM3Dialog(
          context,
          icon: Icons.location_on_outlined,
          title: 'Turn on Location',
          message: 'Android requires Location (GPS) to be turned on for Bluetooth '
              'scanning on this version of the OS.\n\n'
              'How to fix:\n'
              '1. Pull down the notification shade\n'
              '2. Tap the Location icon to enable it\n'
              '3. Return here and tap Scan again\n\n'
              'SmartBMS does not use your location data.',
          showCancel: false,
          okLabel: 'Got it',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    }
  }

  void _stopScan() {
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  // ── Connection ─────────────────────────────────────────────────────────────
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_connectingToId != null) return;

    await FlutterBluePlus.stopScan();

    setState(() => _connectingToId = device.remoteId.str);

    // Set device in provider — this triggers BmsBleService creation
    ref.read(bleDeviceProvider.notifier).state = device;

    // Brief settle so the provider can instantiate the service.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Wait for the handshake using the race-free connectionFuture.
    try {
      final service = ref.read(bmsBleServiceProvider);
      if (service == null) {
        throw Exception('Failed to initialize BLE service');
      }
      final status = await service.connectionFuture.timeout(const Duration(seconds: 20));
      if (status.state != BleConnectionState.connected) {
        throw Exception(status.errorMessage ?? 'Connection failed');
      }
    } catch (e) {
      if (mounted) {
        ref.read(bleDeviceProvider.notifier).state = null;
        setState(() => _connectingToId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
      }
      return;
    }

    // Remember this device for one-tap reconnect next launch.
    await LastDeviceStore.save(device.remoteId.str, device.platformName);

    if (!mounted) return;
    setState(() => _connectingToId = null);

    // Switch to the Home tab — bleDeviceProvider changing already makes it
    // reactively show the connected dashboard, no Navigator push needed.
    ref.read(shellTabIndexProvider.notifier).state = 0;
  }

  /// Reconnects to the remembered device without scanning — flutter_blue_plus
  /// can address it directly by id.
  Future<void> _reconnectLast() async {
    final last = _lastDevice;
    if (last == null) return;
    await _connectToDevice(BluetoothDevice.fromId(last.remoteId));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: M3Colors.surface,
      child: Column(
        children: [
          M3TopAppBar(
            eyebrow: const Text('Bluetooth'),
            title: const Text('Connect a battery'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isScanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: M3Colors.primary)),
                  ),
                _CircleIconButton(
                  icon: Icons.bug_report_outlined,
                  tooltip: 'Debug log',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugLogScreen())),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildReconnectBanner() {
    final last = _lastDevice!;
    final name = last.name.isNotEmpty ? last.name : last.remoteId;
    final connecting = _connectingToId == last.remoteId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: M3ListItem(
        icon: Icons.history,
        iconColor: M3Colors.primary,
        iconBg: M3Colors.primaryContainer,
        headline: name,
        supporting: 'Last connected',
        last: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilledPillButton(label: connecting ? 'Connecting…' : 'Reconnect', onPressed: connecting ? () {} : _reconnectLast),
            IconButton(
              tooltip: 'Forget',
              icon: const Icon(Icons.close, color: M3Colors.onSurfaceVariant, size: 18),
              onPressed: () async {
                await LastDeviceStore.clear();
                if (mounted) setState(() => _lastDevice = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_permissionError != null) {
      return _buildPermissionError();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
      children: [
        if (_lastDevice != null) _buildReconnectBanner(),
        _buildQrPromo(),
        _buildScanHeader(),
        _scanResults.isEmpty ? _buildEmptyState() : _buildDeviceList(),
      ],
    );
  }

  Widget _buildPermissionError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: M3Colors.primary),
            const SizedBox(height: 20),
            Text(_permissionError!, textAlign: TextAlign.center, style: const TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 15)),
            const SizedBox(height: 24),
            _FilledPillButton(label: 'Open Settings', onPressed: openAppSettings, large: true),
          ],
        ),
      ),
    );
  }

  Widget _buildQrPromo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Material(
        color: M3Colors.primaryContainer,
        borderRadius: BorderRadius.circular(M3Radii.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(M3Radii.tile),
          onTap: _openQrScan,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.qr_code_scanner, color: M3Colors.primary, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scan QR code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: M3Colors.onPrimaryContainer)),
                      SizedBox(height: 2),
                      Text("Pair instantly from the pack's label",
                          style: TextStyle(fontSize: 12, color: M3Colors.onPrimaryContainer)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: M3Colors.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isScanning ? 'Scanning for BMS devices…' : 'Tap to scan for devices',
                  style: const TextStyle(color: M3Colors.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
                ),
                if (_scanResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${_scanResults.length} device${_scanResults.length == 1 ? '' : 's'} found',
                      style: const TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CircleIconButton(icon: Icons.keyboard, tooltip: 'Enter MAC manually', onPressed: _openManualMac),
          const SizedBox(width: 8),
          _FilledPillButton(label: _isScanning ? 'Stop' : 'Scan', onPressed: _isScanning ? _stopScan : _startScan),
        ],
      ),
    );
  }

  void _openQrScan() {
    _stopScan();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QrScanScreen()));
  }

  void _openManualMac() {
    _stopScan();
    showManualMacDialog(context, ref);
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching, size: 72, color: M3Colors.primary.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            const Text('No devices found', style: TextStyle(color: M3Colors.onSurface, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text(
              'Make sure your BMS is powered on\nand in range',
              textAlign: TextAlign.center,
              style: TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 28),
            if (!_isScanning) ...[
              _FilledPillButton(label: 'Start Scanning', onPressed: _startScan, large: true),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _openQrScan,
                    icon: const Icon(Icons.qr_code_scanner, size: 16),
                    label: const Text('Scan QR'),
                    style: TextButton.styleFrom(
                      foregroundColor: M3Colors.onSurfaceVariant,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Container(width: 1, height: 14, color: M3Colors.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
                  TextButton.icon(
                    onPressed: _openManualMac,
                    icon: const Icon(Icons.keyboard, size: 16),
                    label: const Text('Enter MAC'),
                    style: TextButton.styleFrom(
                      foregroundColor: M3Colors.onSurfaceVariant,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: M3ListCard(
        title: 'NEARBY DEVICES',
        child: Column(
          children: [
            for (var i = 0; i < _scanResults.length; i++)
              _DeviceTile(
                result: _scanResults[i],
                isConnecting: _connectingToId == _scanResults[i].device.remoteId.str,
                last: i == _scanResults.length - 1,
                onTap: () => _connectToDevice(_scanResults[i].device),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Device tile ───────────────────────────────────────────────────────────────
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.result, required this.isConnecting, required this.last, required this.onTap});

  final ScanResult result;
  final bool isConnecting;
  final bool last;
  final VoidCallback onTap;

  String get _displayName {
    final name = result.device.platformName;
    return name.isNotEmpty ? name : 'Unknown Device';
  }

  /// Daly's Bluetooth modules advertise as `DL-<mac>` and expose the fff0
  /// transparent-UART service; either signal alone is enough to flag it. JBD
  /// modules don't have a consistent name prefix across rebrands (Overkill
  /// Solar, EBM, etc.), so ff00 is the only reliable signal there.
  String? get _detectedProtocolLabel {
    final name = result.device.platformName.toUpperCase();
    final uuids = result.advertisementData.serviceUuids.map((u) => u.toString().toLowerCase());
    if (name.startsWith('DL-') || uuids.any((u) => u.contains('fff0'))) return 'Daly BMS';
    if (uuids.any((u) => u.contains('ff00'))) return 'JBD BMS';
    return null;
  }

  Color get _rssiColor {
    if (result.rssi >= -60) return M3Colors.success;
    if (result.rssi >= -80) return M3Colors.warningAmber;
    return M3Colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final protocol = _detectedProtocolLabel;
    final supporting = protocol != null ? '${result.device.remoteId.str} · ✓ $protocol' : result.device.remoteId.str;
    return M3ListItem(
      icon: Icons.memory,
      iconColor: M3Colors.primary,
      iconBg: M3Colors.primaryContainer,
      headline: _displayName,
      supporting: supporting,
      last: last,
      onTap: isConnecting ? null : onTap,
      trailing: isConnecting
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: M3Colors.primary))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${result.rssi} dBm', style: TextStyle(color: _rssiColor, fontSize: 12)),
              ],
            ),
    );
  }
}

// ── Filled pill button (M3 filled button, used in the Connection tab) ────────
class _FilledPillButton extends StatelessWidget {
  const _FilledPillButton({required this.label, required this.onPressed, this.large = false});

  final String label;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: M3Colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: large ? const EdgeInsets.symmetric(horizontal: 28, vertical: 14) : const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      child: Text(label),
    );
  }
}

// ── Circle icon-only button ───────────────────────────────────────────────────
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(icon, color: M3Colors.onSurfaceVariant, size: 18),
          ),
        ),
      ),
    );
  }
}
