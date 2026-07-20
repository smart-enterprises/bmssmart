// lib/features/bms/data/parser/bms_parser.dart
//
// Pure Dart — no Flutter, no BLE, no Riverpod.

import 'dart:typed_data';
import '../models/bms_models.dart';

class BmsParseException implements Exception {
  final String message;
  const BmsParseException(this.message);

  @override
  String toString() => 'BmsParseException: $message';
}

/// Stateless parser for Daly BMS frames.
///
/// Every Daly frame — request and response alike — is exactly 13 bytes:
///
/// ┌──────┬──────┬─────┬─────┬──────────────┬──────────┐
/// │ 0xA5 │ ADDR │ CMD │ LEN │ DATA (8 B)   │ CHECKSUM │
/// └──────┴──────┴─────┴─────┴──────────────┴──────────┘
///   [0]    [1]   [2]   [3]    [4..11]         [12]
///
/// LEN is always 0x08. The checksum is the low byte of the sum of bytes 0..11.
///
/// ADDR identifies the host on a request (0x40 for UART, 0x80 for the
/// Bluetooth module) and the responding BMS on a reply (typically 0x01).
/// Replies are accepted from any address — multi-pack addressing is not a
/// case this app handles, so the address carries no information worth
/// enforcing on, and clone modules are inconsistent about it.
abstract final class BmsParser {
  static const int startByte = 0xA5;
  static const int dataLength = 0x08;
  static const int frameLength = 13;

  // Command IDs.
  static const int cmdSoc = 0x90;
  static const int cmdMinMaxCell = 0x91;
  static const int cmdTemp = 0x92;
  static const int cmdMos = 0x93;
  static const int cmdStatus = 0x94;
  static const int cmdCellVoltages = 0x95;
  static const int cmdCellTemps = 0x96;
  static const int cmdBalance = 0x97;
  static const int cmdFaults = 0x98;
  static const int cmdRated = 0x50;

  // Write commands. The BMS echoes the command back as acknowledgement.
  //
  // NOTE: verified against the real pack over UART on 2026-07-19 — on this
  // Daly unit the opcodes are the reverse of the commonly-cited mapping:
  // 0xDA toggles the CHARGE MOSFET and 0xD9 toggles the DISCHARGE MOSFET.
  // Do not "correct" these back without re-testing on hardware; a wrong
  // mapping silently drives the opposite MOSFET.
  static const int cmdSetChargeMos = 0xDA;
  static const int cmdSetDischargeMos = 0xD9;

  static const int _idxAddr = 1;
  static const int _idxCmd = 2;
  static const int _idxLen = 3;
  static const int _dataStart = 4;
  static const int _idxChecksum = 12;

  /// Current is transmitted as an unsigned value biased by 30000 so that
  /// discharge (negative) current stays positive on the wire.
  static const int _currentOffset = 30000;

  /// Temperatures are transmitted biased by 40 so that sub-zero readings stay
  /// positive on the wire.
  static const int _tempOffset = 40;

  /// Builds a 13-byte request frame for [cmd].
  ///
  /// [hostAddr] is 0x40 over UART and 0x80 through the Bluetooth module.
  /// [data] is the payload for write commands, zero-padded to 8 bytes; read
  /// commands carry no payload and leave it all zero.
  static Uint8List buildRequest(int cmd, {int hostAddr = 0x80, List<int>? data}) {
    if (data != null && data.length > dataLength) {
      throw ArgumentError.value(
        data,
        'data',
        'Daly payload is at most $dataLength bytes',
      );
    }

    final f = Uint8List(frameLength);
    f[0] = startByte;
    f[_idxAddr] = hostAddr;
    f[_idxCmd] = cmd;
    f[_idxLen] = dataLength;
    if (data != null) {
      for (var i = 0; i < data.length; i++) {
        f[_dataStart + i] = data[i] & 0xFF;
      }
    }
    f[_idxChecksum] = checksumOf(f);
    return f;
  }

  /// Builds a MOSFET control frame. [cmd] must be [cmdSetChargeMos] or
  /// [cmdSetDischargeMos].
  static Uint8List buildMosControl(int cmd, {required bool on, int hostAddr = 0x80}) {
    assert(cmd == cmdSetChargeMos || cmd == cmdSetDischargeMos);
    return buildRequest(cmd, hostAddr: hostAddr, data: [on ? 0x01 : 0x00]);
  }

  /// Low byte of the sum of the first 12 bytes.
  static int checksumOf(Uint8List frame) {
    var sum = 0;
    for (var i = 0; i < _idxChecksum; i++) {
      sum += frame[i];
    }
    return sum & 0xFF;
  }

  /// True if [bytes] is a structurally valid frame. Cheap enough to use as a
  /// scan predicate while hunting for frame boundaries in a byte stream.
  static bool isValidFrame(Uint8List bytes) {
    if (bytes.length != frameLength) return false;
    if (bytes[0] != startByte) return false;
    if (bytes[_idxLen] != dataLength) return false;
    return bytes[_idxChecksum] == checksumOf(bytes);
  }

  /// Parses [bytes] into a [DalyFrame] subtype.
  ///
  /// Throws [BmsParseException] on a malformed frame or an unsupported
  /// command.
  static DalyFrame parse(Uint8List bytes) {
    _validateFrame(bytes);

    final cmd = bytes[_idxCmd];
    final d = Uint8List.sublistView(bytes, _dataStart, _dataStart + dataLength);
    final now = DateTime.now();

    return switch (cmd) {
      cmdSoc => _parseSoc(d, now),
      cmdMinMaxCell => _parseMinMaxCell(d, now),
      cmdTemp => _parseTemp(d, now),
      cmdMos => _parseMos(d, now),
      cmdStatus => _parseStatus(d, now),
      cmdCellVoltages => _parseCellVoltages(d, now),
      cmdCellTemps => _parseCellTemps(d, now),
      cmdBalance => _parseBalance(d, now),
      cmdFaults => _parseFaults(d, now),
      cmdRated => _parseRated(d, now),
      cmdSetChargeMos || cmdSetDischargeMos => _parseMosAck(cmd, d, now),
      _ => throw BmsParseException(
          'Unsupported command: 0x${cmd.toRadixString(16).padLeft(2, '0')}.',
        ),
    };
  }

  // ── Validation ───────────────────────────────────────────────────────────

  static void _validateFrame(Uint8List bytes) {
    if (bytes.length != frameLength) {
      throw BmsParseException(
        'Bad frame length: ${bytes.length} bytes (expected $frameLength).',
      );
    }
    if (bytes[0] != startByte) {
      throw BmsParseException(
        'Invalid start byte: '
        '0x${bytes[0].toRadixString(16).padLeft(2, '0')} (expected 0xA5).',
      );
    }
    if (bytes[_idxLen] != dataLength) {
      throw BmsParseException(
        'Invalid data length: ${bytes[_idxLen]} (expected 8).',
      );
    }
    final computed = checksumOf(bytes);
    if (computed != bytes[_idxChecksum]) {
      throw BmsParseException(
        'Checksum mismatch: computed '
        '0x${computed.toRadixString(16).padLeft(2, '0')}, received '
        '0x${bytes[_idxChecksum].toRadixString(16).padLeft(2, '0')}.',
      );
    }
  }

  // ── 0x90 — SOC / voltage / current ───────────────────────────────────────

  static DalySocFrame _parseSoc(Uint8List d, DateTime now) {
    final packVoltage = _uint16(d, 0) / 10.0;
    // d[2..3] is the acquisition-board voltage — same value on most units,
    // not worth surfacing.
    final currentAmps = (_uint16(d, 4) - _currentOffset) / 10.0;
    final soc = _uint16(d, 6) / 10.0;

    return DalySocFrame(
      packVoltage: _round(packVoltage, 1),
      currentAmps: _round(currentAmps, 1),
      soc: _round(soc.clamp(0.0, 100.0), 1),
      timestamp: now,
    );
  }

  // ── 0x91 — min / max cell voltage ────────────────────────────────────────

  static DalyMinMaxCellFrame _parseMinMaxCell(Uint8List d, DateTime now) =>
      DalyMinMaxCellFrame(
        maxCellMv: _uint16(d, 0),
        maxCellNumber: d[2],
        minCellMv: _uint16(d, 3),
        minCellNumber: d[5],
        timestamp: now,
      );

  // ── 0x92 — temperatures ──────────────────────────────────────────────────

  static DalyTempFrame _parseTemp(Uint8List d, DateTime now) => DalyTempFrame(
        maxTempC: d[0] - _tempOffset,
        maxTempSensor: d[1],
        minTempC: d[2] - _tempOffset,
        minTempSensor: d[3],
        timestamp: now,
      );

  // ── 0x93 — MOSFET state ──────────────────────────────────────────────────

  static DalyMosFrame _parseMos(Uint8List d, DateTime now) => DalyMosFrame(
        stateByte: d[0],
        chargeMosOn: d[1] != 0,
        dischargeMosOn: d[2] != 0,
        bmsLife: d[3],
        remainingAh: _round(_uint32(d, 4) / 1000.0, 3),
        timestamp: now,
      );

  // ── 0x94 — pack configuration ────────────────────────────────────────────

  static DalyStatusFrame _parseStatus(Uint8List d, DateTime now) =>
      DalyStatusFrame(
        cellCount: d[0],
        tempSensorCount: d[1],
        chargerConnected: d[2] != 0,
        loadConnected: d[3] != 0,
        // d[4] is a DI/DO bitfield; cycles live in the last two data bytes.
        cycleCount: _uint16(d, 5),
        timestamp: now,
      );

  // ── 0x95 — cell voltages (multi-frame) ───────────────────────────────────

  static DalyCellVoltageFrame _parseCellVoltages(Uint8List d, DateTime now) {
    final frameNumber = d[0];
    if (frameNumber == 0) {
      throw BmsParseException(
        'Cell voltage frame number is 0 (frames are 1-based).',
      );
    }

    // Three cells per frame at d[1..6]; d[7] is reserved. Daly pads the final
    // frame with zeroes, which the snapshot trims once cellCount is known.
    final mv = <int>[
      for (var i = 0; i < 3; i++) _uint16(d, 1 + i * 2),
    ];

    return DalyCellVoltageFrame(
      frameNumber: frameNumber,
      millivolts: mv,
      timestamp: now,
    );
  }

  // ── 0x96 — per-sensor temperatures (multi-frame) ─────────────────────────

  static DalyCellTempFrame _parseCellTemps(Uint8List d, DateTime now) {
    final frameNumber = d[0];
    if (frameNumber == 0) {
      throw BmsParseException('Cell temp frame number is 0 (1-based).');
    }
    // Seven sensors per frame at d[1..7], each biased by 40. Unused sensors
    // are transmitted as 0xFF; stop at the first one.
    final temps = <int>[];
    for (var i = 1; i < 8; i++) {
      if (d[i] == 0xFF) break;
      temps.add(d[i] - _tempOffset);
    }
    return DalyCellTempFrame(
      frameNumber: frameNumber,
      temps: temps,
      timestamp: now,
    );
  }

  // ── 0x97 — cell balancing state ──────────────────────────────────────────

  static DalyBalanceFrame _parseBalance(Uint8List d, DateTime now) {
    // Data bytes 0..5 form a 48-bit little-endian-by-byte mask: byte 0 bit 0 is
    // cell 1, byte 0 bit 7 is cell 8, byte 1 bit 0 is cell 9, and so on.
    final balancing = <int>{};
    for (var byte = 0; byte < 6; byte++) {
      for (var bit = 0; bit < 8; bit++) {
        if ((d[byte] & (1 << bit)) != 0) {
          balancing.add(byte * 8 + bit + 1);
        }
      }
    }
    return DalyBalanceFrame(balancingCells: balancing, timestamp: now);
  }

  // ── 0x98 — protection / alarm flags ──────────────────────────────────────

  static DalyFaultFrame _parseFaults(Uint8List d, DateTime now) {
    final faults = <String>[];
    // Data bytes 0..6 are flag bytes; byte 7 is the fault count. Layout below
    // is the standard Daly alarm map (L1 = warning, L2 = protection). Bits not
    // in the table still surface, labelled by position, so nothing is hidden.
    for (var byte = 0; byte < 7; byte++) {
      for (var bit = 0; bit < 8; bit++) {
        if ((d[byte] & (1 << bit)) == 0) continue;
        faults.add(_faultLabels[byte][bit] ?? 'Alarm (byte $byte bit $bit)');
      }
    }
    return DalyFaultFrame(
      activeFaults: faults,
      faultCount: d[7],
      timestamp: now,
    );
  }

  /// Daly 0x98 alarm bit → label. `null` entries are reserved/unused bits.
  static const List<List<String?>> _faultLabels = [
    // byte 0 — cell & pack voltage
    [
      'Cell voltage high (warn)', 'Cell voltage high (protect)',
      'Cell voltage low (warn)', 'Cell voltage low (protect)',
      'Pack voltage high (warn)', 'Pack voltage high (protect)',
      'Pack voltage low (warn)', 'Pack voltage low (protect)',
    ],
    // byte 1 — temperature
    [
      'Charge temp high (warn)', 'Charge temp high (protect)',
      'Charge temp low (warn)', 'Charge temp low (protect)',
      'Discharge temp high (warn)', 'Discharge temp high (protect)',
      'Discharge temp low (warn)', 'Discharge temp low (protect)',
    ],
    // byte 2 — current & SOC
    [
      'Charge overcurrent (warn)', 'Charge overcurrent (protect)',
      'Discharge overcurrent (warn)', 'Discharge overcurrent (protect)',
      'SOC high (warn)', 'SOC high (protect)',
      'SOC low (warn)', 'SOC low (protect)',
    ],
    // byte 3 — differential
    [
      'Cell voltage difference (warn)', 'Cell voltage difference (protect)',
      'Temperature difference (warn)', 'Temperature difference (protect)',
      null, null, null, null,
    ],
    // byte 4 — MOS & sensor hardware
    [
      'Charge MOS temp high', 'Discharge MOS temp high',
      'Charge MOS temp sensor fault', 'Discharge MOS temp sensor fault',
      'Cell temp sensor fault', 'EEPROM fault',
      'RTC fault', 'Precharge fault',
    ],
    // byte 5 — communication & module hardware
    [
      'Vehicle comm fault', 'Internal comm fault',
      'Current module fault', 'Pack voltage detection fault',
      'Temp sensor fault', 'Charge MOS fault',
      'Discharge MOS fault', 'Precharge MOS fault',
    ],
    // byte 6 — misc (labelled generically where undocumented)
    [null, null, null, null, null, null, null, null],
  ];

  // ── 0xD9 / 0xDA — MOSFET control acknowledgement ─────────────────────────

  static DalyMosAckFrame _parseMosAck(int cmd, Uint8List d, DateTime now) =>
      DalyMosAckFrame(
        isCharge: cmd == cmdSetChargeMos,
        requestedOn: d[0] != 0,
        timestamp: now,
      );

  // ── 0x50 — rated capacity ────────────────────────────────────────────────

  static DalyRatedFrame _parseRated(Uint8List d, DateTime now) => DalyRatedFrame(
        ratedAh: _round(_uint32(d, 0) / 1000.0, 3),
        ratedCellVolts: _round(_uint32(d, 4) / 1000.0, 3),
        timestamp: now,
      );

  // ── Bit helpers ──────────────────────────────────────────────────────────

  static int _uint16(Uint8List b, int offset) =>
      (b[offset] << 8) | b[offset + 1];

  static int _uint32(Uint8List b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];

  static double _round(double v, int places) =>
      double.parse(v.toStringAsFixed(places));
}
