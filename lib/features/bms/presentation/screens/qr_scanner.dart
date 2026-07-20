// lib/features/bms/presentation/screens/qr_scan_screen.dart
//
// Scans a QR code containing a BMS MAC address, then runs a filtered BLE
// scan to discover the device handle (Android requires this — you cannot
// connect to a raw MAC; the device must first be seen during a scan in
// this app session) and triggers connection.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/bms_provider.dart';
import 'bms_dashboard.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  final MobileScannerController _camera = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _processing = false;
  String? _statusMessage;
  String? _errorMessage;

  StreamSubscription<List<ScanResult>>? _bleScanSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _bleScanSub?.cancel();
    FlutterBluePlus.stopScan();
    _camera.dispose();
    super.dispose();
  }

  // ── MAC extraction ─────────────────────────────────────────────────────────
  /// Pulls the first MAC-looking substring out of [raw].
  /// Accepts AA:BB:CC:11:22:33 or AA-BB-CC-11-22-33; returns canonical
  /// uppercase colon form, or null if no MAC pattern is present.
  String? _extractMac(String raw) {
    final match = RegExp(
      r'([0-9A-Fa-f]{2})[:\-]([0-9A-Fa-f]{2})[:\-]([0-9A-Fa-f]{2})[:\-]'
      r'([0-9A-Fa-f]{2})[:\-]([0-9A-Fa-f]{2})[:\-]([0-9A-Fa-f]{2})',
    ).firstMatch(raw);

    if (match == null) return null;

    return [
      match.group(1)!,
      match.group(2)!,
      match.group(3)!,
      match.group(4)!,
      match.group(5)!,
      match.group(6)!,
    ].map((s) => s.toUpperCase()).join(':');
  }

  // ── QR detection ───────────────────────────────────────────────────────────
  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_processing) return;

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final mac = _extractMac(raw);
    if (mac == null) {
      setState(() => _errorMessage =
      'QR code does not contain a valid MAC address.\n\nGot: ${raw.length > 40 ? '${raw.substring(0, 40)}...' : raw}');
      return;
    }

    _findAndConnect(mac);
  }

  // ── Scan-filter-connect flow ───────────────────────────────────────────────
  Future<void> _findAndConnect(String targetMac) async {
    setState(() {
      _processing = true;
      _errorMessage = null;
      _statusMessage = 'Found MAC: $targetMac\nSearching for device...';
    });

    await _camera.stop();

    // Verify Bluetooth is on
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _showError('Please turn on Bluetooth and try again.');
      return;
    }

    BluetoothDevice? foundDevice;
    final completer = Completer<BluetoothDevice?>();
    Timer? timeout;

    // The MAC printed on a Daly BMS QR is often the chip MAC. The actual
    // advertised BLE MAC can differ in the last byte (typical chip behavior:
    // public address + 1 or 2 for the BLE radio). To find the device
    // reliably we:
    //   1. Prefer an exact match (still typical case).
    //   2. Otherwise accept any device whose first 5 bytes match the QR MAC,
    //      with the last byte within ±4 — and pick the strongest signal.
    final targetPrefix = targetMac.substring(0, 14); // "AA:BB:CC:DD:EE"
    final targetLastByte =
    int.parse(targetMac.substring(15, 17), radix: 16);

    BluetoothDevice? bestPrefixMatch;
    int bestRssi = -200;

    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final mac = r.device.remoteId.str.toUpperCase();

        // Exact match — perfect.
        if (mac == targetMac && !completer.isCompleted) {
          foundDevice = r.device;
          completer.complete(r.device);
          return;
        }

        // Prefix match within ±4 of the printed last byte. Track the
        // strongest signal so we don't pick a neighboring battery.
        if (mac.startsWith(targetPrefix) && mac.length == 17) {
          final lastByte = int.tryParse(mac.substring(15, 17), radix: 16);
          if (lastByte != null &&
              (lastByte - targetLastByte).abs() <= 4 &&
              r.rssi > bestRssi) {
            bestRssi = r.rssi;
            bestPrefixMatch = r.device;
          }
        }
      }
    });

    // 8-second timeout — usually finds it within 1-2s if powered & in range
    timeout = Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    } catch (e) {
      timeout.cancel();
      final errMsg = e.toString().toLowerCase();
      if (errMsg.contains('location') &&
          (errMsg.contains('service') || errMsg.contains('disable'))) {
        _showError(
          'Location (GPS) must be turned on for Bluetooth scanning.\n\n'
              'Pull down the notification shade and tap the Location icon, '
              'then try again.',
        );
      } else {
        _showError('Scan failed: $e');
      }
      return;
    }

    foundDevice = await completer.future;
    timeout.cancel();
    await _bleScanSub?.cancel();
    _bleScanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // No exact match — fall back to the closest-RSSI prefix match if any.
    foundDevice ??= bestPrefixMatch;

    if (foundDevice == null) {
      _showError(
        'Device not found.\n\nMake sure your BMS is:\n• Powered on\n• Within Bluetooth range\n• Not connected to another app',
      );
      return;
    }

    if (!mounted) return;
    final foundMac = foundDevice!.remoteId.str.toUpperCase();
    setState(() => _statusMessage = foundMac == targetMac
        ? 'Device found! Connecting...'
        : 'Found nearby device $foundMac\nConnecting...');

    // Hand off to the existing provider — this triggers BmsBleService.connect()
    ref.read(bleDeviceProvider.notifier).state = foundDevice;

    // Brief settle so the provider can instantiate the service.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final service = ref.read(bmsBleServiceProvider);
    if (service == null) {
      _showError('Failed to initialize BLE service.');
      return;
    }

    try {
      final status = await service.connectionFuture
          .timeout(const Duration(seconds: 20));
      if (status.state != BleConnectionState.connected) {
        throw Exception(status.errorMessage ?? 'Handshake failed');
      }
    } catch (e) {
      ref.read(bleDeviceProvider.notifier).state = null;
      _showError('Connection failed: $e');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BmsDashboard()),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _processing = false;
      _statusMessage = null;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
      _processing = false;
    });
    _camera.start();
  }

  // ── Gallery picker ─────────────────────────────────────────────────────────
  Future<void> _pickFromGallery() async {
    if (_processing) return;

    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      _showError('Could not open gallery: $e');
      return;
    }

    if (file == null) return; // User cancelled

    setState(() {
      _processing = true;
      _errorMessage = null;
      _statusMessage = 'Reading QR from image...';
    });

    BarcodeCapture? capture;
    try {
      capture = await _camera.analyzeImage(file.path);
    } catch (e) {
      _showError('Could not read image: $e');
      return;
    }

    final raw = capture?.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) {
      _showError(
        'No QR code found in this image.\n\n'
            'Make sure the QR is clear, well-lit, and fills most of the frame.',
      );
      return;
    }

    final mac = _extractMac(raw);
    if (mac == null) {
      _showError(
        'QR code does not contain a valid MAC address.\n\n'
            'Got: ${raw.length > 40 ? '${raw.substring(0, 40)}...' : raw}\n\n'
            'Tip: BMS labels often have two QRs. Pick the one labeled '
            '"Second step" or "scan to add device".',
      );
      return;
    }

    _findAndConnect(mac);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Scan BMS QR Code',
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF8B949E)),
        actions: [
          IconButton(
            tooltip: 'Pick from gallery',
            icon: const Icon(Icons.photo_library_outlined, color: Color(0xFF8B949E)),
            onPressed: _pickFromGallery,
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _camera,
              builder: (_, state, __) {
                final on = state.torchState == TorchState.on;
                return Icon(
                  on ? Icons.flash_on : Icons.flash_off,
                  color: on ? AppColors.primary : const Color(0xFF8B949E),
                );
              },
            ),
            onPressed: () => _camera.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onBarcodeDetected,
            errorBuilder: (context, error, _) => _CameraErrorView(error: error),
          ),
          _buildOverlay(),
          if (_statusMessage != null || _errorMessage != null) _buildStatusCard(),
        ],
      ),
    );
  }

  // ── QR aiming overlay ──────────────────────────────────────────────────────
  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double frameSize = 260;
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;
        final left = centerX - frameSize / 2;
        final top = centerY - frameSize / 2;
        final right = centerX + frameSize / 2;
        final bottom = centerY + frameSize / 2;

        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Four dim panels around a transparent center cutout.
              // This avoids BlendMode tricks that don't work on Impeller/Vulkan.
              Positioned(
                left: 0, right: 0, top: 0,
                height: top,
                child: Container(color: Colors.black54),
              ),
              Positioned(
                left: 0, right: 0, top: bottom,
                bottom: 0,
                child: Container(color: Colors.black54),
              ),
              Positioned(
                left: 0, top: top, bottom: constraints.maxHeight - bottom,
                width: left,
                child: Container(color: Colors.black54),
              ),
              Positioned(
                right: 0, top: top, bottom: constraints.maxHeight - bottom,
                width: constraints.maxWidth - right,
                child: Container(color: Colors.black54),
              ),

              // Corner brackets on top of the transparent frame
              Positioned(
                left: left,
                top: top,
                width: frameSize,
                height: frameSize,
                child: CustomPaint(painter: _CornerBracketPainter()),
              ),

              // Helper text below the frame
              Positioned(
                left: 0,
                right: 0,
                top: bottom + 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Align the QR code on your BMS\nwithin the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 14,
                      height: 1.5,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black87),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Status / Error cards ───────────────────────────────────────────────────
  Widget _buildStatusCard() {
    final isError = _errorMessage != null;
    final color = isError ? AppColors.danger : AppColors.primary;

    return Positioned(
      left: 20,
      right: 20,
      bottom: 32,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (!isError)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: color,
                    ),
                  )
                else
                  Icon(Icons.error_outline, color: color, size: 22),
                const SizedBox(width: 12),
                Text(
                  isError ? 'Failed' : 'Working...',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? _statusMessage ?? '',
              style: const TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (isError) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text(
                      'Gallery',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8B949E),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _retry,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
}

// ── Camera error fallback ──────────────────────────────────────────────────────
class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography, color: Colors.red.shade400, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Camera unavailable',
              style: TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.errorDetails?.message ?? error.errorCode.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Corner bracket painter ─────────────────────────────────────────────────────
class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const len = 28.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(const Offset(0, len), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(len, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - len), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - len, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), paint);
  }

  @override
  bool shouldRepaint(_CornerBracketPainter oldDelegate) => false;
}