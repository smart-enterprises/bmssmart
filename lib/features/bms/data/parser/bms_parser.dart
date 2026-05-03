// lib/parser/bms_parser.dart
//
// Pure Dart — no Flutter, no BLE, no Riverpod.
// Every function is stateless; the class cannot be instantiated.

import 'dart:typed_data';
import '../models/bms_models.dart';

// ── Exception ──────────────────────────────────────────────────────────────

/// Thrown when a raw BLE frame fails structural or checksum validation,
/// or when the payload is too short for the declared command.
class BmsParseException implements Exception {
  final String message;
  const BmsParseException(this.message);

  @override
  String toString() => 'BmsParseException: $message';
}

// ── Parser ─────────────────────────────────────────────────────────────────

/// Stateless parser for JBD BMS BLE frames.
///
/// Frame layout:
/// ┌──────┬─────┬────────┬─────┬─────────┬──────────────┬─────┐
/// │ 0xDD │ CMD │ STATUS │ LEN │ PAYLOAD │ CHECKSUM(2B) │0x77 │
/// └──────┴─────┴────────┴─────┴─────────┴──────────────┴─────┘
///   [0]   [1]    [2]     [3]   [4..N]     [N+1][N+2]   [N+3]
///
/// STATUS byte: 0x00 = OK.
/// CHECKSUM: low byte of (0xFF − Σpayload + 1).
/// Supported commands: 0x03 (main data), 0x04 (cell voltages).
abstract final class BmsParser {
  // ── Frame constants ──────────────────────────────────────────────────────

  static const int _startByte = 0xDD;
  static const int _endByte   = 0x77;
  static const int _cmdMain   = 0x03;
  static const int _cmdCells  = 0x04;

  static const int _idxCmd     = 1;
  static const int _idxStatus  = 2;
  static const int _idxLen     = 3;
  static const int _payloadStart = 4;
  static const int _minFrameLen  = 7; // start + cmd + status + len + 0 payload + 2 checksum + end

  // ── Public API ───────────────────────────────────────────────────────────

  /// Parses [bytes] into a [BmsFrame] subtype.
  ///
  /// Returns [BmsMainFrame] for command 0x03,
  /// or [BmsCellFrame] for command 0x04.
  ///
  /// Throws [BmsParseException] on any structural, length,
  /// checksum, or payload error.
  static BmsFrame parse(Uint8List bytes) {
    _validateFrame(bytes);

    final cmd     = bytes[_idxCmd];
    final payload = _extractPayload(bytes);

    return switch (cmd) {
      _cmdMain  => _parseMain(payload),
      _cmdCells => _parseCells(payload),
      _ => throw BmsParseException(
        'Unsupported command: 0x${cmd.toRadixString(16).padLeft(2, '0')}. '
            'Expected 0x03 or 0x04.',
      ),
    };
  }

  // ── Validation ───────────────────────────────────────────────────────────

  static void _validateFrame(Uint8List bytes) {
    if (bytes.length < _minFrameLen) {
      throw BmsParseException(
        'Frame too short: ${bytes.length} bytes (minimum $_minFrameLen).',
      );
    }

    if (bytes[0] != _startByte) {
      throw BmsParseException(
        'Invalid start byte: '
            '0x${bytes[0].toRadixString(16).padLeft(2, '0')} (expected 0xDD).',
      );
    }

    if (bytes.last != _endByte) {
      throw BmsParseException(
        'Invalid end byte: '
            '0x${bytes.last.toRadixString(16).padLeft(2, '0')} (expected 0x77).',
      );
    }

    final len = bytes[_idxLen];
    // header(4) + payload(len) + checksum(2) + end(1)
    final expectedLen = _payloadStart + len + 3;
    if (bytes.length != expectedLen) {
      throw BmsParseException(
        'Frame length mismatch: LEN field declares $len payload bytes '
            '(expected total $expectedLen), got ${bytes.length} bytes.',
      );
    }

    _validateChecksum(bytes, len);
  }

  static void _validateChecksum(Uint8List bytes, int payloadLen) {
    int sum = 0;
    for (int i = _payloadStart; i < _payloadStart + payloadLen; i++) {
      sum = (sum + bytes[i]) & 0xFF;
    }
    final computed  = (0xFF - sum + 1) & 0xFF;
    final frameLow  = bytes[_payloadStart + payloadLen + 1];

    if (computed != frameLow) {
      throw BmsParseException(
        'Checksum mismatch: computed '
            '0x${computed.toRadixString(16).padLeft(2, '0')}, '
            'received 0x${frameLow.toRadixString(16).padLeft(2, '0')}.',
      );
    }
  }

  // ── Payload extraction ───────────────────────────────────────────────────

  static Uint8List _extractPayload(Uint8List bytes) {
    final len = bytes[_idxLen];
    return Uint8List.sublistView(bytes, _payloadStart, _payloadStart + len);
  }

  // ── Command 0x03 ─────────────────────────────────────────────────────────

  static BmsMainFrame _parseMain(Uint8List p) {
    // Minimum: 2 bytes SOC + 2 bytes current = 4 bytes
    if (p.length < 4) {
      throw BmsParseException(
        'Main data payload too short: ${p.length} bytes (need ≥ 4).',
      );
    }

    // Bytes [0–1]: raw SOC — unit is 1/14 of a percent per LSB
    final socRaw     = _uint16(p, 0);
    final soc        = (socRaw / 14.0).clamp(0.0, 100.0);

    // Bytes [2–3]: signed current — unit is 10 mA per LSB → divide by 100 for Amps
    final currentRaw = _int16(p, 2);
    final current    = currentRaw / 100.0;

    return BmsMainFrame(
      soc:         double.parse(soc.toStringAsFixed(1)),
      currentAmps: double.parse(current.toStringAsFixed(2)),
      timestamp:   DateTime.now(),
    );
  }

  // ── Command 0x04 ─────────────────────────────────────────────────────────

  static BmsCellFrame _parseCells(Uint8List p) {
    if (p.length < 2) {
      throw BmsParseException(
        'Cell payload too short: ${p.length} bytes (need ≥ 2).',
      );
    }
    if (p.length.isOdd) {
      throw BmsParseException(
        'Cell payload has odd length (${p.length}); '
            'each cell requires exactly 2 bytes.',
      );
    }

    final cellCount = p.length ~/ 2;
    final voltages  = List<double>.generate(cellCount, (i) {
      final raw = _uint16(p, i * 2);
      return double.parse((raw / 1000.0).toStringAsFixed(3));
    });

    return BmsCellFrame(voltages: voltages, timestamp: DateTime.now());
  }

  // ── Bit helpers ──────────────────────────────────────────────────────────

  /// Big-endian unsigned 16-bit integer.
  static int _uint16(Uint8List b, int offset) =>
      (b[offset] << 8) | b[offset + 1];

  /// Big-endian signed 16-bit integer (two's complement).
  static int _int16(Uint8List b, int offset) {
    final raw = _uint16(b, offset);
    return raw >= 0x8000 ? raw - 0x10000 : raw;
  }
}