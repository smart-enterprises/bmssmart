// lib/core/ble/ble_service.dart
//
// Manages the full BLE connection lifecycle for a BMS device. Speaks two
// protocols — Daly and JBD — auto-detected from the GATT services the device
// actually advertises after connecting (fff0 -> Daly, ff00 -> JBD). All the
// connection lifecycle, replay streams, and history tracking below is shared;
// only characteristic matching, poll commands, frame extraction, and parsing
// branch by protocol.
//
// No Riverpod imports. Consumed by bms_provider.dart.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../features/bms/data/models/bms_models.dart';
import '../../features/bms/data/parser/bms_parser.dart';
import '../../features/bms/data/parser/jbd_parser.dart';
import '../diagnostics/app_logger.dart';
import 'replay_stream.dart';

// ── Daly BLE module UUIDs ───────────────────────────────────────────────────
// The DL-xxxxxxxx modules expose a Nordic-style transparent UART bridge on
// fff0: fff1 notifies with BMS replies, fff2 accepts host requests.
const String kDalyServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const String kDalyNotifyUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
const String kDalyWriteUuid = '0000fff2-0000-1000-8000-00805f9b34fb';

// ── JBD BLE UUIDs ────────────────────────────────────────────────────────────
const String kJbdServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
const String kJbdNotifyUuid = '0000ff01-0000-1000-8000-00805f9b34fb';
const String kJbdWriteUuid = '0000ff02-0000-1000-8000-00805f9b34fb';

// ── Host addresses (Daly only — JBD's request frame has no address byte) ────
/// Host address used by the Bluetooth module.
const int kHostAddrBluetooth = 0x80;

/// Host address used over a direct UART link. Some clone BT modules pass the
/// UART address through unchanged, so it serves as a fallback.
const int kHostAddrUart = 0x40;

/// Commands polled every cycle, in order.
const List<int> kPollCommands = [
  BmsParser.cmdSoc, // 0x90 — voltage / current / SOC
  BmsParser.cmdMinMaxCell, // 0x91 — cell extremes
  BmsParser.cmdTemp, // 0x92 — temperatures
  BmsParser.cmdMos, // 0x93 — MOS state + remaining capacity
  BmsParser.cmdStatus, // 0x94 — cell count + cycles
  BmsParser.cmdCellVoltages, // 0x95 — per-cell voltages (multi-frame)
  BmsParser.cmdCellTemps, // 0x96 — per-sensor temperatures (multi-frame)
  BmsParser.cmdBalance, // 0x97 — cell balancing state
  BmsParser.cmdFaults, // 0x98 — protection / alarm flags
];

/// Commands polled once on connect — values that never change at runtime.
const List<int> kOneShotCommands = [
  BmsParser.cmdRated, // 0x50 — rated capacity
];

/// JBD commands polled every cycle. Unlike Daly, one 0x03 request returns
/// everything but cell voltages in a single frame.
const List<int> kJbdPollCommands = [
  JbdParser.cmdMain, // 0x03 — voltage / current / SOC / capacity / MOS / temps
  JbdParser.cmdCellVoltages, // 0x04 — every cell voltage in one frame
];

// ── Protocol ─────────────────────────────────────────────────────────────────
enum BmsProtocol { daly, jbd }

// ── Connection state ─────────────────────────────────────────────────────────
enum BleConnectionState { connecting, connected, disconnected, error }

class BleStatus {
  final BleConnectionState state;
  final String? errorMessage;
  const BleStatus(this.state, {this.errorMessage});
}

// ── Service ──────────────────────────────────────────────────────────────────
class BmsBleService {
  BmsBleService(this._device);

  final BluetoothDevice _device;

  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  /// Which protocol the connected device speaks. Null until GATT service
  /// discovery has run — see [_discoverCharacteristics].
  BmsProtocol? _protocol;
  BmsProtocol? get protocol => _protocol;

  final StreamController<BmsSnapshot> _snapshotCtrl =
      StreamController<BmsSnapshot>.broadcast();
  final StreamController<BleStatus> _statusCtrl =
      StreamController<BleStatus>.broadcast();

  /// Resolves when the initial handshake completes (success or failure).
  /// Callers should `await service.connectionFuture` instead of trying to
  /// listen on the broadcast statusStream — the latter has a timing race
  /// because events emitted before listeners attach are dropped.
  final Completer<BleStatus> _connectCompleter = Completer<BleStatus>();
  Future<BleStatus> get connectionFuture => _connectCompleter.future;

  BmsSnapshot _current = const BmsSnapshot();
  BleStatus _lastStatus = const BleStatus(BleConnectionState.disconnected);

  /// Rolling history for the charts — one point per poll cycle. Capped so a
  /// long session can't grow memory without bound; at ~2 s/cycle this holds
  /// roughly the last hour.
  static const int _kMaxHistory = 1800;
  final List<HistoryPoint> _history = [];
  List<HistoryPoint> get history => List.unmodifiable(_history);

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  Timer? _pollTimer;

  /// Serializes every GATT write on [_writeChar] — the poll loop's timer and
  /// a user-triggered control write are otherwise independent call sites
  /// that can fire close together, and flutter_blue_plus does not queue
  /// concurrent writes to the same characteristic on its own. An overlapping
  /// write can be silently mangled on the wire even though both local calls
  /// report success and the BMS still acks something. Chain every write
  /// through this so only one is ever in flight.
  Future<void> _writeQueue = Future.value();

  Future<void> _serializedWrite(Uint8List frame, {required bool withoutResponse}) {
    final result = _writeQueue.then((_) => _writeChar!.write(frame, withoutResponse: withoutResponse));
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  bool _connected = false;
  bool _disposed = false;

  /// Host address currently being used for requests. Daly only — starts at
  /// the Bluetooth address and falls back to the UART one if the BMS stays
  /// silent — see [_maybeFallbackHostAddress].
  int _hostAddr = kHostAddrBluetooth;

  /// Number of consecutive poll cycles that produced no valid frame.
  int _silentCycles = 0;

  /// Total valid frames decoded — also gates the address fallback, which must
  /// not fire once the BMS has proven it is answering.
  int _validFrames = 0;

  /// Cycles of silence tolerated before trying the other host address.
  static const int _kSilentCyclesBeforeFallback = 3;

  // ── Public surface ───────────────────────────────────────────────────────
  //
  // Both streams replay the latest value to every new subscriber before
  // forwarding live events. The controllers are broadcast, so anything emitted
  // before a listener attaches is otherwise lost — and the dashboard always
  // subscribes late, after connectionFuture has already resolved. Without the
  // replay it would never observe the `connected` status and would sit on the
  // connecting spinner forever while data was flowing underneath it.

  Stream<BmsSnapshot> get snapshotStream =>
      replayLatest(_snapshotCtrl, () => _current);
  Stream<BleStatus> get statusStream =>
      replayLatest(_statusCtrl, () => _lastStatus);
  BluetoothDevice get device => _device;

  /// Latest status, for callers that want a value rather than a stream.
  BleStatus get currentStatus => _lastStatus;

  /// Latest snapshot, for callers that want a value rather than a stream.
  BmsSnapshot get currentSnapshot => _current;

  /// Host address in use — surfaced for the debug screen. Daly only.
  int get hostAddress => _hostAddr;

  Future<void> connect() async {
    if (_connected || _disposed) {
      AppLogger.instance.w('ble',
          'connect() called but service is ${_disposed ? "disposed" : "already connected"}');
      return;
    }

    final mac = _device.remoteId.str;
    final name =
        _device.platformName.isNotEmpty ? _device.platformName : 'unnamed';
    AppLogger.instance.i('ble', '→ connect() to $name [$mac]');

    _emit(const BleStatus(BleConnectionState.connecting));

    // Watch for unexpected disconnects
    _connStateSub = _device.connectionState.listen((state) {
      AppLogger.instance.d('ble', 'connectionState event: $state');
      if (state == BluetoothConnectionState.disconnected && _connected) {
        _connected = false;
        _pollTimer?.cancel();
        AppLogger.instance.w('ble', 'Unexpected disconnect from $mac');
        _emit(const BleStatus(BleConnectionState.disconnected));
      }
    });

    try {
      AppLogger.instance.d('ble', 'calling _device.connect()...');
      final t0 = DateTime.now();
      await _device.connect(autoConnect: false, license: License.free);
      AppLogger.instance.ok('ble',
          'GATT connect succeeded in ${DateTime.now().difference(t0).inMilliseconds}ms');

      try {
        AppLogger.instance.d('ble', 'requesting MTU 247...');
        final negotiated = await _device.requestMtu(247);
        AppLogger.instance.ok('ble', 'MTU negotiated: $negotiated bytes');
      } catch (e) {
        AppLogger.instance.w('ble', 'MTU request rejected: $e (will use fragments)');
      }

      AppLogger.instance.d('ble', 'discovering services...');
      await _discoverCharacteristics();

      AppLogger.instance.d('ble', 'enabling notifications...');
      await _subscribeNotifications();

      AppLogger.instance.d('ble', 'starting poll loop...');
      _startPolling();

      _connected = true;
      const okStatus = BleStatus(BleConnectionState.connected);
      _emit(okStatus);
      if (!_connectCompleter.isCompleted) {
        _connectCompleter.complete(okStatus);
      }
      AppLogger.instance.ok('ble', '✓ Connection complete (protocol: $_protocol)');
    } catch (e) {
      AppLogger.instance.e('ble', '✗ Connect failed: $e');
      final errStatus = BleStatus(
        BleConnectionState.error,
        errorMessage: e.toString(),
      );
      _emit(errStatus);
      if (!_connectCompleter.isCompleted) {
        _connectCompleter.complete(errStatus);
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _disposed = true;

    // If a caller is awaiting connectionFuture, resolve it so they don't hang.
    if (!_connectCompleter.isCompleted) {
      _connectCompleter.complete(
        const BleStatus(BleConnectionState.disconnected,
            errorMessage: 'Service disposed before handshake completed'),
      );
    }

    _pollTimer?.cancel();
    _pollTimer = null;

    await _notifySub?.cancel();
    _notifySub = null;

    await _connStateSub?.cancel();
    _connStateSub = null;

    if (_connected) {
      try {
        await _device.disconnect();
      } catch (_) {}
      _connected = false;
    }

    _rxBuffer.clear();

    if (!_snapshotCtrl.isClosed) await _snapshotCtrl.close();
    if (!_statusCtrl.isClosed) await _statusCtrl.close();
  }

  // ── Setup ────────────────────────────────────────────────────────────────
  Future<void> _discoverCharacteristics() async {
    final services = await _device.discoverServices();
    AppLogger.instance.d('ble', 'Found ${services.length} services');

    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      AppLogger.instance
          .d('ble', '  service: $svcUuid (${svc.characteristics.length} chars)');

      if (_protocol == null) {
        if (_uuidMatches(svcUuid, kDalyServiceUuid)) {
          _protocol = BmsProtocol.daly;
          AppLogger.instance.ok('ble', '  detected protocol: Daly (service fff0)');
        } else if (_uuidMatches(svcUuid, kJbdServiceUuid)) {
          _protocol = BmsProtocol.jbd;
          AppLogger.instance.ok('ble', '  detected protocol: JBD (service ff00)');
        }
      }

      for (final char in svc.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        final props = <String>[];
        if (char.properties.read) props.add('read');
        if (char.properties.write) props.add('write');
        if (char.properties.writeWithoutResponse) props.add('writeNoResp');
        if (char.properties.notify) props.add('notify');
        if (char.properties.indicate) props.add('indicate');
        AppLogger.instance.d('ble', '    char: $uuid [${props.join(",")}]');

        final isDalyChar = _uuidMatches(svcUuid, kDalyServiceUuid);
        final isJbdChar = _uuidMatches(svcUuid, kJbdServiceUuid);
        if (!isDalyChar && !isJbdChar) continue;

        final notifyUuid = isDalyChar ? kDalyNotifyUuid : kJbdNotifyUuid;
        final writeUuid = isDalyChar ? kDalyWriteUuid : kJbdWriteUuid;
        final label = isDalyChar ? 'Daly' : 'JBD';

        if (_uuidMatches(uuid, notifyUuid)) {
          _notifyChar = char;
          AppLogger.instance.ok('ble', '  matched $label notify char');
        }
        if (_uuidMatches(uuid, writeUuid)) {
          _writeChar = char;
          AppLogger.instance.ok('ble', '  matched $label write char');
        }
      }
    }

    // Fallback: try matching by properties if UUIDs differ slightly. This
    // also covers the case where the protocol itself wasn't recognized from
    // the service UUID (e.g. an unlisted clone) — the device may still work
    // if characteristics can be matched generically. Default the protocol to
    // Daly in that case, since that's this app's original/primary target and
    // preserves existing behavior for anyone connecting to an unrecognized
    // device today.
    if (_notifyChar == null || _writeChar == null) {
      AppLogger.instance
          .w('ble', 'Known UUIDs not found, falling back to property matching');
      for (final svc in services) {
        for (final char in svc.characteristics) {
          if (_notifyChar == null && char.properties.notify) {
            _notifyChar = char;
            AppLogger.instance.w('ble', '  fallback notify: ${char.uuid}');
          }
          if (_writeChar == null &&
              (char.properties.write || char.properties.writeWithoutResponse)) {
            _writeChar = char;
            AppLogger.instance.w('ble', '  fallback write: ${char.uuid}');
          }
        }
      }
    }

    if (_protocol == null) {
      AppLogger.instance.w('ble',
          'Could not detect protocol from advertised services — defaulting to Daly');
      _protocol = BmsProtocol.daly;
    }

    if (_notifyChar == null || _writeChar == null) {
      AppLogger.instance.e('ble',
          'Required characteristics not found! notify=${_notifyChar != null}, write=${_writeChar != null}');
      throw StateError(
        'BMS characteristics not found. '
        'Notify: ${_notifyChar != null}, Write: ${_writeChar != null}. '
        'Verify the device exposes a notify + write characteristic pair.',
      );
    }
  }

  /// Compares two UUIDs tolerating the 16-bit short form some stacks report
  /// (`fff0` vs the full `0000fff0-0000-1000-8000-00805f9b34fb`).
  static bool _uuidMatches(String actual, String expected) {
    if (actual == expected) return true;
    final shortExpected = expected.substring(4, 8);
    return actual == shortExpected || actual == '0x$shortExpected';
  }

  Future<void> _subscribeNotifications() async {
    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.onValueReceived.listen(
      _onRawBytes,
      onError: (Object e) {
        AppLogger.instance.e('ble', 'Notify stream error: $e');
      },
    );
  }

  // ── Polling ──────────────────────────────────────────────────────────────
  //
  // Daly answers one command at a time and has no request pipelining, so the
  // commands are issued sequentially with a gap between them. 0x95 is the
  // expensive one: it replies with ceil(cells/3) separate frames, so it gets
  // extra settle time before the cycle restarts. JBD is simpler — two
  // commands, one frame each — but is polled with the same sequential
  // discipline for consistency and because it's untested at this point.
  void _startPolling() {
    _pollOneShots();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _pollOneShots() async {
    if (_protocol != BmsProtocol.daly) return;
    for (final cmd in kOneShotCommands) {
      if (!_canWrite) return;
      await _sendDaly(cmd);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  bool get _canWrite => _connected && !_disposed && _writeChar != null;

  /// Guards against a slow cycle overlapping the next timer tick.
  bool _polling = false;

  Future<void> _poll() async {
    if (_disposed || _writeChar == null) return;
    // The very first _poll() runs before _connected flips true, so allow it.
    if (_polling) {
      AppLogger.instance.d('poll', 'previous cycle still running, skipping tick');
      return;
    }
    _polling = true;

    final framesAtStart = _validFrames;
    try {
      if (_protocol == BmsProtocol.jbd) {
        for (final cmd in kJbdPollCommands) {
          if (_disposed || _writeChar == null) return;
          await _sendJbd(cmd);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      } else {
        for (final cmd in kPollCommands) {
          if (_disposed || _writeChar == null) return;
          await _sendDaly(cmd);
          // 0x95 and 0x96 fan out into several reply frames; give them room.
          final multiFrame = cmd == BmsParser.cmdCellVoltages ||
              cmd == BmsParser.cmdCellTemps;
          await Future<void>.delayed(
            multiFrame
                ? const Duration(milliseconds: 300)
                : const Duration(milliseconds: 120),
          );
        }
      }
    } catch (e) {
      AppLogger.instance.e('poll', 'Poll cycle error: $e');
    } finally {
      _polling = false;
    }

    if (_validFrames == framesAtStart) {
      _silentCycles++;
      AppLogger.instance
          .w('poll', 'cycle produced no valid frames ($_silentCycles in a row)');
      _maybeFallbackHostAddress();
    } else {
      _silentCycles = 0;
      _recordHistory();
    }
  }

  void _recordHistory() {
    if (!_current.hasCoreData) return;
    _history.add(HistoryPoint(
      t: DateTime.now(),
      soc: _current.soc,
      voltage: _current.packVoltage,
      current: _current.currentAmps,
      deltaMv: _current.deltaCellVolts == null
          ? null
          : (_current.deltaCellVolts! * 1000).round(),
    ));
    if (_history.length > _kMaxHistory) {
      _history.removeRange(0, _history.length - _kMaxHistory);
    }
  }

  // ── Control ──────────────────────────────────────────────────────────────

  /// Switches the charge MOSFET on or off (Daly: 0xDA write; JBD: 0xFB
  /// toggle — see [_sendMosControl]).
  Future<bool> setChargeMos({required bool on}) => _sendMosControl(isCharge: true, on: on);

  /// Switches the discharge MOSFET on or off (Daly: 0xD9 write; JBD: 0xFB
  /// toggle — see [_sendMosControl]).
  ///
  /// Turning this off cuts the pack's output to whatever it is powering. The
  /// BMS itself stays awake and reachable over BLE, so it can be switched back
  /// on from here.
  Future<bool> setDischargeMos({required bool on}) => _sendMosControl(isCharge: false, on: on);

  Future<bool> _sendMosControl({required bool isCharge, required bool on}) async {
    if (!_canWrite) {
      AppLogger.instance.w('control', 'Not connected — command dropped');
      return false;
    }

    final label = isCharge ? 'charge' : 'discharge';

    final Uint8List frame;
    Uint8List? applyFrame;
    if (_protocol == BmsProtocol.jbd) {
      // 0xE1 sets BOTH MOSFETs' state in one write (verified against a
      // captured official-app HCI log — see JbdParser.cmdSetMosState), so
      // the switch that isn't being touched must have its current state
      // re-sent alongside the one that is, or it would get clobbered.
      final targetCharge = isCharge ? on : (_current.chargeMosOn ?? true);
      final targetDischarge = isCharge ? (_current.dischargeMosOn ?? true) : on;
      frame = JbdParser.buildMosState(chargeOn: targetCharge, dischargeOn: targetDischarge);
      applyFrame = JbdParser.buildMosApply();
    } else {
      final cmd = isCharge ? BmsParser.cmdSetChargeMos : BmsParser.cmdSetDischargeMos;
      frame = BmsParser.buildMosControl(cmd, on: on, hostAddr: _hostAddr);
    }

    AppLogger.instance.i('control', '→ $label MOS ${on ? "ON" : "OFF"}: ${_hex(frame)}');

    try {
      await _serializedWrite(frame, withoutResponse: true);
      if (applyFrame != null) {
        // The captured official-app traffic always has the device ack the
        // state write (~60ms) before the app sends the apply write. Sending
        // both back-to-back with no gap meant the device sometimes never
        // acked the state write at all — its firmware appears to need a
        // beat between commands, same as the gap already used between poll
        // commands below.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await _serializedWrite(applyFrame, withoutResponse: true);
      }
      // The next poll reports the resulting state; nothing is assumed here.
      return true;
    } catch (e) {
      AppLogger.instance.e('control', '$label MOS write failed: $e');
      return false;
    }
  }

  Future<void> _sendDaly(int cmd) async {
    final frame = BmsParser.buildRequest(cmd, hostAddr: _hostAddr);
    AppLogger.instance.d('poll',
        'TX cmd 0x${cmd.toRadixString(16)} (addr 0x${_hostAddr.toRadixString(16)}): ${_hex(frame)}');
    await _writeFrame(frame);
  }

  Future<void> _sendJbd(int register) async {
    final frame = JbdParser.buildRequest(register);
    AppLogger.instance
        .d('poll', 'TX reg 0x${register.toRadixString(16)}: ${_hex(frame)}');
    await _writeFrame(frame);
  }

  Future<void> _writeFrame(Uint8List frame) async {
    try {
      await _serializedWrite(frame, withoutResponse: true);
    } catch (e) {
      // Some modules reject write-without-response; retry once with response.
      AppLogger.instance
          .w('poll', 'writeNoResp failed ($e), retrying with response');
      try {
        await _serializedWrite(frame, withoutResponse: false);
      } catch (e2) {
        AppLogger.instance.e('poll', 'Write error: $e2');
      }
    }
  }

  /// Daly's UART builds expect host address 0x40 while the BT module expects
  /// 0x80, and the module variants are not consistent about which they pass
  /// through. Rather than make the user guess, try the other address after a
  /// few silent cycles. Once any valid frame has arrived the address is known
  /// good and this stops trying. Daly only — JBD's request frame has no host
  /// address byte.
  void _maybeFallbackHostAddress() {
    if (_protocol != BmsProtocol.daly) return;
    if (_validFrames > 0) return;
    if (_silentCycles < _kSilentCyclesBeforeFallback) return;

    _hostAddr = _hostAddr == kHostAddrBluetooth ? kHostAddrUart : kHostAddrBluetooth;
    _silentCycles = 0;
    AppLogger.instance.w('poll',
        'No reply on previous host address — switching to 0x${_hostAddr.toRadixString(16)}');
  }

  // ── Frame handling ───────────────────────────────────────────────────────
  //
  // BLE notifications deliver MTU-sized chunks that do not respect frame
  // boundaries — a reply can be split across two notifications, and a
  // multi-frame response usually arrives as several frames batched into one
  // notification. So bytes are buffered and frames are extracted as they
  // become available. Daly frames are a fixed 13 bytes; JBD frames are
  // variable length (bounded by 0xDD...0x77, with a LEN byte at offset 3). A
  // byte that fails validation is dropped so the scan can resync on the next
  // candidate — this recovers from mid-frame stack hiccups.

  /// Rolling buffer of unparsed bytes.
  final List<int> _rxBuffer = [];

  /// Maximum buffer size before we force a flush (prevents runaway growth
  /// if the BMS goes silent mid-frame).
  static const int _kMaxBufferSize = 256;

  void _onRawBytes(List<int> raw) {
    if (raw.isEmpty) return;

    AppLogger.instance
        .d('rx', '${raw.length}B: ${_hex(Uint8List.fromList(raw))}');

    _rxBuffer.addAll(raw);

    // Hard cap to prevent runaway growth from a stuck partial frame.
    if (_rxBuffer.length > _kMaxBufferSize) {
      AppLogger.instance
          .w('rx', 'RX buffer overflow (${_rxBuffer.length}B), flushing');
      _rxBuffer.clear();
      return;
    }

    var changed = false;
    final extractOne =
        _protocol == BmsProtocol.jbd ? _tryExtractJbdFrame : _tryExtractDalyFrame;
    while (extractOne()) {
      changed = true;
    }

    if (changed && !_snapshotCtrl.isClosed) {
      _snapshotCtrl.add(_current);
    }
  }

  /// Extracts at most one Daly frame (fixed 13 bytes). Returns true if the
  /// snapshot was updated.
  bool _tryExtractDalyFrame() {
    while (true) {
      final startIdx = _rxBuffer.indexOf(BmsParser.startByte);
      if (startIdx < 0) {
        _rxBuffer.clear();
        return false;
      }
      if (startIdx > 0) {
        _rxBuffer.removeRange(0, startIdx);
      }
      if (_rxBuffer.length < BmsParser.frameLength) return false;

      final candidate =
          Uint8List.fromList(_rxBuffer.sublist(0, BmsParser.frameLength));

      if (!BmsParser.isValidFrame(candidate)) {
        // False start — drop the 0xA5 and resync on the next one.
        _rxBuffer.removeAt(0);
        continue;
      }

      _rxBuffer.removeRange(0, BmsParser.frameLength);

      DalyFrame frame;
      try {
        frame = BmsParser.parse(candidate);
      } on BmsParseException catch (e) {
        AppLogger.instance.e('parse', '$e | raw: ${_hex(candidate)}');
        return false;
      }

      _validFrames++;
      _current = _current.merge(frame);
      AppLogger.instance.ok('parse', frame.toString());
      return true;
    }
  }

  /// Extracts at most one JBD frame (variable length, DD...77). Returns true
  /// if the snapshot was updated.
  bool _tryExtractJbdFrame() {
    while (true) {
      final startIdx = _rxBuffer.indexOf(JbdParser.startByte);
      if (startIdx < 0) {
        _rxBuffer.clear();
        return false;
      }
      if (startIdx > 0) {
        _rxBuffer.removeRange(0, startIdx);
      }
      // Need at least start+cmd+status+len to know the full frame length.
      if (_rxBuffer.length < 4) return false;

      final len = _rxBuffer[3];
      final expectedLen = 4 + len + 3;
      if (expectedLen > _kMaxBufferSize) {
        AppLogger.instance.w('rx', 'absurd JBD LEN=$len, dropping byte');
        _rxBuffer.removeAt(0);
        continue;
      }
      if (_rxBuffer.length < expectedLen) return false;

      final candidate = Uint8List.fromList(_rxBuffer.sublist(0, expectedLen));

      if (!JbdParser.isValidFrame(candidate)) {
        // False start — drop the 0xDD and resync on the next one.
        _rxBuffer.removeAt(0);
        continue;
      }

      _rxBuffer.removeRange(0, expectedLen);

      if (candidate[1] == JbdParser.cmdSetMosState || candidate[1] == JbdParser.cmdMosApply) {
        // Ack for a MOS-state or apply write — carries no state, just
        // confirms receipt. Not a frame JbdParser.parse understands (or
        // needs to).
        AppLogger.instance.d('parse', 'MOS write ack: ${_hex(candidate)}');
        continue;
      }

      JbdFrame frame;
      try {
        frame = JbdParser.parse(candidate);
      } on JbdParseException catch (e) {
        AppLogger.instance.e('parse', '$e | raw: ${_hex(candidate)}');
        return false;
      }

      _validFrames++;
      _current = _current.mergeJbd(frame);
      AppLogger.instance.ok('parse', frame.toString());
      return true;
    }
  }

  void _emit(BleStatus status) {
    _lastStatus = status;
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
}
