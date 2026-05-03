// lib/services/bms_ble_service.dart
//
// Responsibilities: BLE connection lifecycle, characteristic discovery,
// notification subscription, periodic polling, raw frame → BmsFrame parsing.
//
// Zero Riverpod imports. Consumed by bms_provider.dart.
//
// Depends on: flutter_blue_plus ^1.32.0
//   Add to pubspec.yaml:
//     flutter_blue_plus: ^1.32.0

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../features/bms/data/models/bms_models.dart';
import '../../features/bms/data/parser/bms_parser.dart';
// ── JBD standard UUIDs ─────────────────────────────────────────────────────
const String kJbdServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
const String kJbdNotifyUuid  = '0000ff01-0000-1000-8000-00805f9b34fb';
const String kJbdWriteUuid   = '0000ff02-0000-1000-8000-00805f9b34fb';

// ── Poll command frames ────────────────────────────────────────────────────

/// Full JBD request frame for command 0x03 (main data).
final Uint8List kCmdRequestMain = Uint8List.fromList(
  [0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77],
);

/// Full JBD request frame for command 0x04 (cell voltages).
final Uint8List kCmdRequestCells = Uint8List.fromList(
  [0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77],
);

// ── Service ────────────────────────────────────────────────────────────────

/// Manages the full lifecycle of a BLE connection to a JBD BMS.
///
/// Usage:
/// ```dart
/// final service = BmsBleService(device);
/// await service.connect();
///
/// service.snapshotStream.listen((snapshot) { ... });
///
/// await service.disconnect(); // call on dispose
/// ```
class BmsBleService {
  BmsBleService(this._device);

  final BluetoothDevice _device;

  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  // Broadcast so multiple listeners (providers, debug views) can attach.
  final StreamController<BmsSnapshot> _snapshotCtrl =
  StreamController<BmsSnapshot>.broadcast();

  BmsSnapshot _current = const BmsSnapshot();

  StreamSubscription<List<int>>? _notifySub;
  Timer? _pollTimer;

  bool _connected = false;

  // ── Public surface ────────────────────────────────────────────────────────

  /// Emits an updated [BmsSnapshot] whenever a valid 0x03 or 0x04 frame
  /// is received. Errors from individual frames are swallowed (logged in
  /// debug mode); the stream itself never closes due to a parse error.
  Stream<BmsSnapshot> get snapshotStream => _snapshotCtrl.stream;

  /// Connects to [_device], discovers services, subscribes to notifications,
  /// and starts the 1-second polling cycle.
  Future<void> connect() async {
    if (_connected) return;

    await _device.connect(autoConnect: false, license: License.commercial);
    await _discoverCharacteristics();
    await _subscribeNotifications();
    _startPolling();

    _connected = true;
  }

  /// Cancels polling, unsubscribes notifications, disconnects and closes
  /// the snapshot stream.
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    await _notifySub?.cancel();
    _notifySub = null;

    if (_connected) {
      await _device.disconnect();
      _connected = false;
    }

    await _snapshotCtrl.close();
  }

  // ── Setup ─────────────────────────────────────────────────────────────────

  Future<void> _discoverCharacteristics() async {
    final services = await _device.discoverServices();

    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() != kJbdServiceUuid) continue;

      for (final char in svc.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        if (uuid == kJbdNotifyUuid) _notifyChar = char;
        if (uuid == kJbdWriteUuid)  _writeChar  = char;
      }
    }

    if (_notifyChar == null || _writeChar == null) {
      throw StateError(
        'JBD characteristics not found. '
            'Verify the device exposes UUIDs $kJbdNotifyUuid and $kJbdWriteUuid.',
      );
    }
  }

  Future<void> _subscribeNotifications() async {
    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.onValueReceived.listen(_onRawBytes);
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _poll(); // immediate first poll
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      await _writeChar!.write(kCmdRequestMain, withoutResponse: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _writeChar!.write(kCmdRequestCells, withoutResponse: false);
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[BmsBleService] Poll write error: $e');
        return true;
      }());
      // Transient write errors are non-fatal; next tick retries.
    }
  }

  // ── Frame handling ────────────────────────────────────────────────────────

  void _onRawBytes(List<int> raw) {
    if (raw.isEmpty) return;

    final bytes = Uint8List.fromList(raw);

    late final BmsFrame frame;
    try {
      frame = BmsParser.parse(bytes);
    } on BmsParseException catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[BmsBleService] Parse error: $e');
        return true;
      }());
      return; // discard malformed frame; do not update snapshot
    }

    // Type-safe dispatch — compiler enforces exhaustiveness on sealed BmsFrame.
    _current = switch (frame) {
      BmsMainFrame f => _current.copyWith(mainFrame: f),
      BmsCellFrame f => _current.copyWith(cellFrame: f),
    };

    _snapshotCtrl.add(_current);
  }
}