// lib/features/bms/presentation/screens/ble_scanner_screen.dart
//
// Handles permissions, scanning, device list, and navigation to dashboard.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smartbms/features/bms/presentation/screens/qr_scanner.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/persistence/last_device_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bms_provider.dart';
import '../widget/manual_mac_dialog.dart';

import 'bms_dashboard.dart';
import 'debug_log_screen.dart';

class BleScannerScreen extends ConsumerStatefulWidget {
  const BleScannerScreen({super.key});

  @override
  ConsumerState<BleScannerScreen> createState() => _BleScannerScreenState();
}

class _BleScannerScreenState extends ConsumerState<BleScannerScreen> {
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
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Turn on Location', style: TextStyle(color: AppColors.text)),
            content: const Text(
              'Android requires Location (GPS) to be turned on for Bluetooth '
              'scanning on this version of the OS.\n\n'
              'How to fix:\n'
              '1. Pull down the notification shade\n'
              '2. Tap the Location icon to enable it\n'
              '3. Return here and tap Scan again\n\n'
              'SmartBMS does not use your location data.',
              style: TextStyle(color: AppColors.textSec, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Got it', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
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

    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const BmsDashboard()));
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
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'SmartBMS',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 0.4),
            ),
          ),
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            ),
          _GlassIconButton(
            icon: Icons.bug_report_outlined,
            tooltip: 'Debug log',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugLogScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectBanner() {
    final last = _lastDevice!;
    final name = last.name.isNotEmpty ? last.name : last.remoteId;
    final connecting = _connectingToId == last.remoteId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GlassCard(
        radius: 14,
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.history, color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Last connected', style: TextStyle(color: AppColors.textSec, fontSize: 11)),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _OrangeButton(label: connecting ? 'Connecting…' : 'Reconnect', onPressed: connecting ? () {} : _reconnectLast, compact: true),
            IconButton(
              tooltip: 'Forget',
              icon: const Icon(Icons.close, color: AppColors.textSec, size: 18),
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

    return Column(
      children: [
        if (_lastDevice != null) _buildReconnectBanner(),
        _buildScanHeader(),
        Expanded(child: _scanResults.isEmpty ? _buildEmptyState() : _buildDeviceList()),
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
            const Icon(Icons.bluetooth_disabled, size: 64, color: AppColors.danger),
            const SizedBox(height: 20),
            Text(_permissionError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSec, fontSize: 15)),
            const SizedBox(height: 24),
            _OrangeButton(label: 'Open Settings', onPressed: openAppSettings),
          ],
        ),
      ),
    );
  }

  Widget _buildScanHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GlassCard(
        radius: 14,
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isScanning ? 'Scanning for BMS devices...' : 'Tap to scan for devices',
                    style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  if (_scanResults.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${_scanResults.length} device${_scanResults.length == 1 ? '' : 's'} found',
                        style: const TextStyle(color: AppColors.textSec, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _IconActionButton(icon: Icons.keyboard, tooltip: 'Enter MAC manually', onPressed: _openManualMac),
            const SizedBox(width: 8),
            _IconActionButton(icon: Icons.qr_code_scanner, tooltip: 'Scan QR code', onPressed: _openQrScan),
            const SizedBox(width: 8),
            _OrangeButton(label: _isScanning ? 'Stop' : 'Scan', onPressed: _isScanning ? _stopScan : _startScan, compact: true),
          ],
        ),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_searching, size: 72, color: AppColors.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('No devices found', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text(
            'Make sure your BMS is powered on\nand in range',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSec, fontSize: 13),
          ),
          const SizedBox(height: 28),
          if (!_isScanning) ...[
            _OrangeButton(label: 'Start Scanning', onPressed: _startScan),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _openQrScan,
                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                  label: const Text('Scan QR'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSec,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                Container(width: 1, height: 14, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
                TextButton.icon(
                  onPressed: _openManualMac,
                  icon: const Icon(Icons.keyboard, size: 16),
                  label: const Text('Enter MAC'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSec,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      itemCount: _scanResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = _scanResults[index];
        return _DeviceTile(
          result: result,
          isConnecting: _connectingToId == result.device.remoteId.str,
          onTap: () => _connectToDevice(result.device),
        );
      },
    );
  }
}

// ── Device tile ───────────────────────────────────────────────────────────────
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.result, required this.isConnecting, required this.onTap});

  final ScanResult result;
  final bool isConnecting;
  final VoidCallback onTap;

  String get _displayName {
    final name = result.device.platformName;
    return name.isNotEmpty ? name : 'Unknown Device';
  }

  /// Daly's Bluetooth modules advertise as `DL-<mac>` and expose the fff0
  /// transparent-UART service. Either signal alone is enough to flag it.
  bool get _looksLikeDaly {
    if (result.device.platformName.toUpperCase().startsWith('DL-')) return true;
    return result.advertisementData.serviceUuids.any((uuid) => uuid.toString().toLowerCase().contains('fff0'));
  }

  Color get _rssiColor {
    if (result.rssi >= -60) return AppColors.success;
    if (result.rssi >= -80) return const Color(0xFFD29922);
    return AppColors.danger;
  }

  IconData get _rssiIcon {
    if (result.rssi >= -60) return Icons.signal_wifi_4_bar;
    if (result.rssi >= -80) return Icons.signal_wifi_4_bar_lock;
    return Icons.signal_wifi_bad;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 14,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: isConnecting ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.memory, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(result.device.remoteId.str, style: const TextStyle(color: AppColors.textSec, fontSize: 11)),
                    if (_looksLikeDaly)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text('✓ Daly BMS', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              if (isConnecting)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary))
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_rssiIcon, color: _rssiColor, size: 16),
                    const SizedBox(width: 4),
                    Text('${result.rssi} dBm', style: TextStyle(color: _rssiColor, fontSize: 12)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable orange button ────────────────────────────────────────────────────
class _OrangeButton extends StatelessWidget {
  const _OrangeButton({required this.label, required this.onPressed, this.compact = false});

  final String label;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: compact ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10) : const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      child: Text(label),
    );
  }
}

// ── Square icon-only button ───────────────────────────────────────────────────
class _IconActionButton extends StatelessWidget {
  const _IconActionButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(border: Border.all(color: AppColors.chipBorder), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.chipBorder),
        ),
        child: Icon(icon, color: AppColors.textSec, size: 18),
      ),
    );
  }
}
