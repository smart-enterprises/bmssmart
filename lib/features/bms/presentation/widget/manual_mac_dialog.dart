// lib/features/bms/presentation/widgets/manual_mac_dialog.dart
//
// Dialog for entering a BMS MAC address manually, then running the
// scan-filter-connect flow (same path as QR scan). Chrome restyled to match
// M3Dialog (28dp radius, surfaceContainerHigh, icon in a tonal circle) —
// kept as its own Dialog rather than reusing M3Dialog directly since this
// one has a form + live status, not a fixed message.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ble/ble_service.dart';
import '../../../../core/theme/m3_theme.dart';
import '../providers/bms_provider.dart';

/// Shows the manual-MAC dialog. Returns true if the user successfully
/// connected (so callers can pop themselves), false otherwise.
Future<bool> showManualMacDialog(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ManualMacDialog(),
  );
  return result ?? false;
}

class _ManualMacDialog extends ConsumerStatefulWidget {
  const _ManualMacDialog();

  @override
  ConsumerState<_ManualMacDialog> createState() => _ManualMacDialogState();
}

class _ManualMacDialogState extends ConsumerState<_ManualMacDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _connecting = false;
  String? _statusMessage;
  String? _errorMessage;

  StreamSubscription<List<ScanResult>>? _bleScanSub;

  @override
  void dispose() {
    _bleScanSub?.cancel();
    FlutterBluePlus.stopScan();
    _controller.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────
  String? _validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return 'Enter a MAC address';
    }
    // The input formatter only allows hex + colons in correct positions,
    // so by the time we validate we just need to check completeness.
    if (input.length != 17) {
      return 'MAC must be 17 characters (e.g. A5:C2:39:20:DF:B2)';
    }
    final macPattern =
    RegExp(r'^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:'
    r'[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$');
    if (!macPattern.hasMatch(input)) {
      return 'Invalid MAC format';
    }
    return null;
  }

  // ── Connect flow ───────────────────────────────────────────────────────────
  Future<void> _onConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final targetMac = _controller.text.toUpperCase();

    setState(() {
      _connecting = true;
      _errorMessage = null;
      _statusMessage = 'Searching for $targetMac...';
    });

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _showError('Please turn on Bluetooth and try again.');
      return;
    }

    final completer = Completer<BluetoothDevice?>();
    Timer? timeout;

    // Match strategy: exact MAC first, then prefix match (last byte ±4) by
    // strongest RSSI. Daly BMS QR/labels often print the chip MAC, while the
    // advertised BLE MAC can differ in the last byte.
    final targetPrefix = targetMac.substring(0, 14);
    final targetLastByte = int.parse(targetMac.substring(15, 17), radix: 16);
    BluetoothDevice? bestPrefixMatch;
    int bestRssi = -200;

    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final mac = r.device.remoteId.str.toUpperCase();
        if (mac == targetMac && !completer.isCompleted) {
          completer.complete(r.device);
          return;
        }
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
          'Location (GPS) must be turned on for Bluetooth scanning. '
              'Enable it from the notification shade and try again.',
        );
      } else {
        _showError('Scan failed: $e');
      }
      return;
    }

    final foundDevice = (await completer.future) ?? bestPrefixMatch;
    timeout.cancel();
    await _bleScanSub?.cancel();
    _bleScanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    if (foundDevice == null) {
      _showError(
        'No device with that MAC was found.\n\n'
            'Make sure your BMS is powered on, in range, and not connected '
            'to another app.',
      );
      return;
    }

    if (!mounted) return;
    final foundMac = foundDevice.remoteId.str.toUpperCase();
    setState(() => _statusMessage = foundMac == targetMac
        ? 'Device found! Connecting...'
        : 'Found nearby device $foundMac\nConnecting...');

    // Trigger service creation + connection.
    ref.read(bleDeviceProvider.notifier).state = foundDevice;

    // Brief settle so the provider can instantiate the service.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final service = ref.read(bmsBleServiceProvider);
    if (service == null) {
      _showError('Failed to initialize BLE service.');
      return;
    }

    // Race-free wait: the service exposes a Completer-backed Future that
    // resolves when the handshake completes (success or error), regardless
    // of stream subscription timing.
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

    // Close dialog, then switch to the Home tab — bleDeviceProvider changing
    // already makes it reactively show the connected dashboard.
    Navigator.of(context).pop(true);
    ref.read(shellTabIndexProvider.notifier).state = 0;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _statusMessage = null;
      _errorMessage = message;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: M3Colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(M3Radii.dialog)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: M3Colors.secondaryContainer, shape: BoxShape.circle),
                child: const Icon(Icons.keyboard, color: M3Colors.onSecondaryContainer, size: 20),
              ),
              const SizedBox(height: 14),
              const Text('Enter MAC Address', style: TextStyle(color: M3Colors.onSurface, fontSize: 22, fontWeight: FontWeight.w400)),
              const SizedBox(height: 10),
              const Text(
                'Find the MAC address printed on the label of your BMS (usually 12 hex characters).',
                style: TextStyle(color: M3Colors.onSurfaceVariant, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                enabled: !_connecting,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: M3Colors.onSurface, fontSize: 16, fontFamily: 'monospace', letterSpacing: 1.5),
                inputFormatters: [_MacInputFormatter()],
                decoration: InputDecoration(
                  hintText: 'AA:BB:CC:DD:EE:FF',
                  hintStyle: TextStyle(color: M3Colors.onSurfaceVariant.withValues(alpha: 0.5), fontFamily: 'monospace', letterSpacing: 1.5),
                  filled: true,
                  fillColor: M3Colors.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: M3Colors.outlineVariant)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: M3Colors.outlineVariant)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: M3Colors.primary, width: 2)),
                  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: M3Colors.primary)),
                  focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: M3Colors.primary, width: 2)),
                  errorStyle: const TextStyle(color: M3Colors.primary),
                ),
                validator: _validate,
              ),
              if (_statusMessage != null || _errorMessage != null) ...[
                const SizedBox(height: 16),
                _buildStatusRow(),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _connecting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(color: M3Colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _connecting ? null : _onConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: M3Colors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: M3Colors.surfaceContainerHighest,
                      disabledForegroundColor: M3Colors.onSurfaceVariant,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    child: _connecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Connect'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow() {
    final isError = _errorMessage != null;
    final color = isError ? M3Colors.primary : M3Colors.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? M3Colors.primaryContainer : M3Colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isError)
            Icon(Icons.error_outline, color: color, size: 18)
          else
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: M3Colors.secondary)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? _statusMessage ?? '',
              style: TextStyle(color: isError ? M3Colors.onPrimaryContainer : M3Colors.onSecondaryContainer, fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input formatter ─────────────────────────────────────────────────────────
/// Auto-uppercases hex and inserts colons every 2 characters.
/// Filters non-hex input. Caps at 17 chars (12 hex + 5 colons).
class _MacInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    // Strip everything that isn't a hex digit.
    final hexOnly = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-F]'), '');

    // Cap at 12 hex characters.
    final capped =
    hexOnly.length > 12 ? hexOnly.substring(0, 12) : hexOnly;

    // Re-insert colons every 2 chars.
    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i > 0 && i % 2 == 0) buffer.write(':');
      buffer.write(capped[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
