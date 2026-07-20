// lib/features/bms/data/parser/jbd_parser.dart
//
// Pure Dart — no Flutter, no BLE, no Riverpod.
//
// JBD (Jiabaida — commonly rebranded as Overkill Solar, EBM, and others)
// BLE/UART protocol. Frames are variable-length, bounded by 0xDD...0x77, with
// a different layout for requests (host→device) than responses (device→host):
//
//  ┌──────┬──────┬─────────┬─────┬─────────┬──────────────┬──────┐
//  │ 0xDD │ 0xA5 │ REGISTER│ LEN │ (none)  │ CHECKSUM(2B) │ 0x77 │   request
//  └──────┴──────┴─────────┴─────┴─────────┴──────────────┴──────┘
//  ┌──────┬──────┬─────────┬─────┬─────────┬──────────────┬──────┐
//  │ 0xDD │ CMD  │ STATUS  │ LEN │ PAYLOAD │ CHECKSUM(2B) │ 0x77 │   response
//  └──────┴──────┴─────────┴─────┴─────────┴──────────────┴──────┘
//
// The checksum is the two's-complement (mod 0x10000) of the sum of every
// byte from offset 2 up to (but not including) the checksum itself — i.e.
// [register-or-status, len, payload...]. The byte at offset 1 (the fixed
// 0xA5 request marker, or the echoed command in a response) is never part of
// the sum. Verified against two known-good request frames: `buildRequest`'s
// test asserts byte-for-byte equality with them.
//
// ⚠️ INHERITED, NOT YET HARDWARE-VERIFIED IN THIS PROJECT: this offset table
// carried over from an earlier version of this app (before it was converted
// to speak Daly) and has not been checked against a real device in this
// session. Daly's protocol had at least one real hardware surprise (reversed
// MOSFET opcodes) versus what's commonly documented — treat every field
// offset below as a hypothesis to confirm against captured frames, not fact,
// until verified. No write/control commands are implemented yet for exactly
// this reason.

import 'dart:typed_data';
import '../models/bms_models.dart';

class JbdParseException implements Exception {
  final String message;
  const JbdParseException(this.message);

  @override
  String toString() => 'JbdParseException: $message';
}

abstract final class JbdParser {
  static const int startByte = 0xDD;
  static const int endByte = 0x77;

  /// Fixed marker at offset 1 of every request frame (this protocol's "read"
  /// operation code).
  static const int readOp = 0xA5;

  static const int cmdMain = 0x03;
  static const int cmdCellVoltages = 0x04;

  /// Write operation marker at offset 1 of a write frame (mirrors [readOp]).
  static const int writeOp = 0x5A;

  /// Register 0xFB, previously believed (2026-07-20, earlier same day) to be
  /// a MOSFET "toggle" command based on a captured HCI log where writes to
  /// it correlated cleanly with mosfetState changes. That correlation turned
  /// out to be coincidental/wrong: a later, cleaner capture of a single
  /// deliberate official-app action showed the real official app uses
  /// [cmdSetMosState] (0xE1) instead, and 0xFB was never re-observed in that
  /// capture. Kept only as a historical note — do not send writes to this
  /// register; see [cmdSetMosState].
  static const int cmdMosLegacyUnverified = 0xFB;

  /// Register for the MOSFET absolute-state write. Verified 2026-07-20 by
  /// replaying a captured HCI snoop log of a single deliberate official-app
  /// action (turning Discharge off) and cross-checking the resulting raw
  /// mosfetState against what the official app's own screen showed
  /// afterward — not just a checksum match. The payload is [0x00, mode],
  /// and mode is a 2-bit field matching this project's mosfetState bit
  /// convention (see JbdMainFrame — bit0=discharge, bit1=charge, reversed
  /// from commonly published docs):
  ///
  ///   bit0 of mode = 1 means "discharge OFF" (0 = discharge on)
  ///   bit1 of mode = 1 means "charge OFF"    (0 = charge on)
  ///
  /// i.e. mode = (~mosfetState) & 0x3. All three mode values seen in the
  /// capture (0, 1, 2) match this formula byte-for-byte, including
  /// checksums; mode=1 additionally has an independently confirmed
  /// before/after effect. The official app always follows this write with
  /// [cmdMosApply] — replicated here even though its exact purpose isn't
  /// independently confirmed, since every working capture included it.
  static const int cmdSetMosState = 0xE1;

  /// Sent immediately after every [cmdSetMosState] write in the captured
  /// official-app traffic, always with payload [0x00, 0x00]. Purpose
  /// unconfirmed (commit/apply trigger?) — replicated defensively; see
  /// [cmdSetMosState].
  static const int cmdMosApply = 0x01;

  static const int _idxCmd = 1;
  static const int _idxLen = 3;
  static const int _dataStart = 4;
  static const int _minFrameLen = 7;

  /// Builds a read-request frame for [register] (e.g. [cmdMain] or
  /// [cmdCellVoltages]). JBD read requests carry no payload.
  static Uint8List buildRequest(int register) {
    // Checksum spans [register, len] — the leading 0xA5 marker is excluded.
    final sum = register + 0x00;
    final chk = (0x10000 - sum) & 0xFFFF;
    return Uint8List.fromList([
      startByte,
      readOp,
      register,
      0x00,
      (chk >> 8) & 0xFF,
      chk & 0xFF,
      endByte,
    ]);
  }

  /// Builds the absolute MOSFET-state write — see [cmdSetMosState].
  static Uint8List buildMosState({required bool chargeOn, required bool dischargeOn}) {
    final mode = (dischargeOn ? 0x00 : 0x01) | (chargeOn ? 0x00 : 0x02);
    return _buildWrite(cmdSetMosState, [0x00, mode]);
  }

  /// Builds the companion "apply" write always sent right after a
  /// [buildMosState] write in the captured official-app traffic — see
  /// [cmdMosApply].
  static Uint8List buildMosApply() => _buildWrite(cmdMosApply, [0x00, 0x00]);

  static Uint8List _buildWrite(int register, List<int> payload) {
    // Checksum spans [register, len, payload...] — the leading 0x5A marker
    // is excluded, same formula as read requests.
    var sum = register + payload.length;
    for (final b in payload) {
      sum += b;
    }
    final chk = (0x10000 - sum) & 0xFFFF;
    return Uint8List.fromList([
      startByte,
      writeOp,
      register,
      payload.length,
      ...payload,
      (chk >> 8) & 0xFF,
      chk & 0xFF,
      endByte,
    ]);
  }

  /// True if [bytes] is a complete, checksum-valid, correctly-bounded frame.
  static bool isValidFrame(Uint8List bytes) {
    if (bytes.length < _minFrameLen) return false;
    if (bytes[0] != startByte) return false;
    if (bytes.last != endByte) return false;
    final len = bytes[_idxLen];
    if (bytes.length != _dataStart + len + 3) return false;
    return _checksumOk(bytes, len);
  }

  static bool _checksumOk(Uint8List bytes, int len) {
    var sum = 0;
    for (var i = 2; i < _dataStart + len; i++) {
      sum += bytes[i];
    }
    final computed = (0x10000 - sum) & 0xFFFF;
    final frameChk = (bytes[_dataStart + len] << 8) | bytes[_dataStart + len + 1];
    if (computed == frameChk) return true;

    // Some clones checksum the payload only, without STATUS+LEN. Accept
    // either, same forgiving fallback used for Daly's clone variants.
    var payloadOnly = 0;
    for (var i = _dataStart; i < _dataStart + len; i++) {
      payloadOnly += bytes[i];
    }
    final altComputed = (0x10000 - payloadOnly) & 0xFFFF;
    return altComputed == frameChk;
  }

  /// Parses a complete response frame. Throws [JbdParseException] on a
  /// malformed frame or an unsupported command.
  static JbdFrame parse(Uint8List bytes) {
    if (bytes.length < _minFrameLen) {
      throw JbdParseException('Frame too short: ${bytes.length} bytes (minimum $_minFrameLen).');
    }
    if (bytes[0] != startByte) {
      throw JbdParseException(
        'Invalid start byte: 0x${bytes[0].toRadixString(16).padLeft(2, '0')} (expected 0xDD).',
      );
    }
    if (bytes.last != endByte) {
      throw JbdParseException(
        'Invalid end byte: 0x${bytes.last.toRadixString(16).padLeft(2, '0')} (expected 0x77).',
      );
    }

    final cmd = bytes[_idxCmd];
    final len = bytes[_idxLen];
    final expectedLen = _dataStart + len + 3;
    if (bytes.length != expectedLen) {
      throw JbdParseException(
        'Frame length mismatch: LEN=$len, expected total $expectedLen, got ${bytes.length}.',
      );
    }
    if (!_checksumOk(bytes, len)) {
      throw JbdParseException('Checksum mismatch.');
    }

    final payload = Uint8List.sublistView(bytes, _dataStart, _dataStart + len);
    final now = DateTime.now();

    return switch (cmd) {
      cmdMain => _parseMain(payload, now),
      cmdCellVoltages => _parseCellVoltages(payload, now),
      _ => throw JbdParseException(
          'Unsupported command: 0x${cmd.toRadixString(16).padLeft(2, '0')}. Expected 0x03 or 0x04.',
        ),
    };
  }

  // ── Command 0x03 ─────────────────────────────────────────────────────────
  //
  //   offset 0-1:   pack voltage          (uint16, ×10 mV)
  //   offset 2-3:   current               (int16, ×10 mA, two's complement)
  //   offset 4-5:   remaining capacity    (uint16, ×10 mAh)
  //   offset 6-7:   nominal capacity      (uint16, ×10 mAh)
  //   offset 8-9:   cycle count           (uint16)
  //   offset 10-11: production date       (uint16, packed Y/M/D) — unused
  //   offset 12-13: balance status (low)  (uint16 bitmask) — unused for now
  //   offset 14-15: balance status (high) (uint16 bitmask) — unused for now
  //   offset 16-17: protection state      (uint16 bitmask)
  //   offset 18:    software version      (uint8) — unused
  //   offset 19:    SOC                   (uint8, %)
  //   offset 20:    MOSFET state          (uint8: bit0=charge, bit1=discharge)
  //   offset 21:    cell count            (uint8)
  //   offset 22:    NTC count             (uint8)
  //   offset 23+:   NTC temperatures      (uint16 each, in 0.1 K)

  static JbdMainFrame _parseMain(Uint8List p, DateTime now) {
    if (p.length < 23) {
      throw JbdParseException('Main payload too short: ${p.length} bytes (need ≥ 23).');
    }

    final packVoltage = _uint16(p, 0) / 100.0;
    final current = _int16(p, 2) / 100.0;
    final remaining = _uint16(p, 4) / 100.0;
    final nominal = _uint16(p, 6) / 100.0;
    final cycles = _uint16(p, 8);
    final protectionBits = _uint16(p, 16);
    final soc = p[19].clamp(0, 100).toDouble();
    final mosfetState = p[20];
    final cellCount = p[21];
    final ntcCount = p.length > 22 ? p[22] : 0;

    final temps = <double>[];
    for (var i = 0; i < ntcCount; i++) {
      final offset = 23 + i * 2;
      if (offset + 1 >= p.length) break;
      final rawTenthKelvin = _uint16(p, offset);
      temps.add(rawTenthKelvin / 10.0 - 273.15);
    }

    return JbdMainFrame(
      packVoltage: _round(packVoltage, 2),
      currentAmps: _round(current, 2),
      remainingAh: _round(remaining, 3),
      nominalAh: _round(nominal, 3),
      cycleCount: cycles,
      protectionStateBits: protectionBits,
      soc: soc,
      mosfetState: mosfetState,
      cellCount: cellCount,
      ntcTempsC: temps.map((t) => _round(t, 1)).toList(),
      timestamp: now,
    );
  }

  // ── Command 0x04 ─────────────────────────────────────────────────────────
  //
  // All cells in one frame — pairs of uint16 millivolts, no header.

  static JbdCellVoltageFrame _parseCellVoltages(Uint8List p, DateTime now) {
    if (p.length.isOdd) {
      throw JbdParseException('Cell payload odd length (${p.length}); need 2 bytes per cell.');
    }
    final cellCount = p.length ~/ 2;
    final voltages = List<double>.generate(
      cellCount,
      (i) => _round(_uint16(p, i * 2) / 1000.0, 3),
    );
    return JbdCellVoltageFrame(voltages: voltages, timestamp: now);
  }

  // ── Bit helpers ──────────────────────────────────────────────────────────

  static int _uint16(Uint8List b, int offset) => (b[offset] << 8) | b[offset + 1];

  static int _int16(Uint8List b, int offset) {
    final raw = _uint16(b, offset);
    return raw >= 0x8000 ? raw - 0x10000 : raw;
  }

  static double _round(double v, int places) => double.parse(v.toStringAsFixed(places));
}
