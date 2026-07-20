// JBD BMS parser tests. Pure Dart — no widgets, no BLE.
//
// These lock in the offsets/checksum inherited from an earlier version of
// this app. They are NOT a substitute for verifying against a real device —
// see the warning at the top of jbd_parser.dart.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbms/features/bms/data/models/bms_models.dart';
import 'package:smartbms/features/bms/data/parser/jbd_parser.dart';

/// Builds a response frame with a correct checksum (STATUS+LEN+payload span).
Uint8List response(int cmd, int status, List<int> payload) {
  final len = payload.length;
  final f = Uint8List(4 + len + 3);
  f[0] = JbdParser.startByte;
  f[1] = cmd;
  f[2] = status;
  f[3] = len;
  for (var i = 0; i < len; i++) {
    f[4 + i] = payload[i];
  }
  var sum = 0;
  for (var i = 2; i < 4 + len; i++) {
    sum += f[i];
  }
  final chk = (0x10000 - sum) & 0xFFFF;
  f[4 + len] = (chk >> 8) & 0xFF;
  f[4 + len + 1] = chk & 0xFF;
  f[4 + len + 2] = JbdParser.endByte;
  return f;
}

void main() {
  group('buildRequest', () {
    test('produces the exact bytes of the two known-good request frames', () {
      // These two frames are the only concrete, independently-known-correct
      // reference points for this protocol in this project (carried over
      // from the app's pre-Daly version) — treat them as golden.
      expect(
        JbdParser.buildRequest(0x03),
        equals([0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77]),
      );
      expect(
        JbdParser.buildRequest(0x04),
        equals([0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77]),
      );
    });

    test('every built request is checksum-valid', () {
      for (final reg in [0x00, 0x03, 0x04, 0x2f]) {
        final frame = JbdParser.buildRequest(reg);
        expect(JbdParser.isValidFrame(frame), isTrue, reason: 'register 0x${reg.toRadixString(16)}');
      }
    });
  });

  group('buildMosState', () {
    // Golden: all three mode values captured byte-for-byte from a Bluetooth
    // HCI snoop log of a single deliberate official-app action (2026-07-20).
    // mode=1 additionally has an independently confirmed before/after effect
    // (checked against the official app's own on-screen state, not just a
    // checksum) — see JbdParser.cmdSetMosState. Do not "correct" these
    // without redoing that correlation.
    test('matches captured traffic: both on (mode 0)', () {
      expect(
        JbdParser.buildMosState(chargeOn: true, dischargeOn: true),
        equals([0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x00, 0xFF, 0x1D, 0x77]),
      );
    });

    test('matches captured traffic: charge on, discharge off (mode 1)', () {
      expect(
        JbdParser.buildMosState(chargeOn: true, dischargeOn: false),
        equals([0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x01, 0xFF, 0x1C, 0x77]),
      );
    });

    test('matches captured traffic: charge off, discharge on (mode 2)', () {
      expect(
        JbdParser.buildMosState(chargeOn: false, dischargeOn: true),
        equals([0xDD, 0x5A, 0xE1, 0x02, 0x00, 0x02, 0xFF, 0x1B, 0x77]),
      );
    });

    test('every combination produces a checksum-valid frame', () {
      for (final chg in [true, false]) {
        for (final dsg in [true, false]) {
          final frame = JbdParser.buildMosState(chargeOn: chg, dischargeOn: dsg);
          expect(JbdParser.isValidFrame(frame), isTrue, reason: 'chg=$chg dsg=$dsg');
        }
      }
    });
  });

  group('buildMosApply', () {
    test('matches captured traffic', () {
      expect(
        JbdParser.buildMosApply(),
        equals([0xDD, 0x5A, 0x01, 0x02, 0x00, 0x00, 0xFF, 0xFD, 0x77]),
      );
    });
  });

  group('validation', () {
    test('rejects a bad start byte', () {
      final f = response(0x03, 0x00, List.filled(23, 0));
      f[0] = 0xA5; // Daly's start byte — must not be accepted here.
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
      expect(JbdParser.isValidFrame(f), isFalse);
    });

    test('rejects a bad end byte', () {
      final f = response(0x03, 0x00, List.filled(23, 0));
      f[f.length - 1] = 0x00;
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
    });

    test('rejects a corrupted checksum', () {
      final f = response(0x03, 0x00, List.filled(23, 0));
      f[f.length - 2] ^= 0xFF;
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
      expect(JbdParser.isValidFrame(f), isFalse);
    });

    test('rejects a length mismatch', () {
      final f = response(0x03, 0x00, List.filled(23, 0));
      f[3] = 5; // LEN says 5, but payload is actually 23 bytes.
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
    });

    test('rejects an unsupported command', () {
      final f = response(0x99, 0x00, [0x00]);
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
    });

    test('accepts the payload-only checksum fallback (clone variant)', () {
      final f = response(0x04, 0x00, [0x0c, 0xd1]);
      // Recompute checksum over payload only, not STATUS+LEN+payload.
      var payloadSum = 0;
      for (final b in [0x0c, 0xd1]) {
        payloadSum += b;
      }
      final chk = (0x10000 - payloadSum) & 0xFFFF;
      f[f.length - 3] = (chk >> 8) & 0xFF;
      f[f.length - 2] = chk & 0xFF;
      expect(JbdParser.isValidFrame(f), isTrue);
      expect(() => JbdParser.parse(f), returnsNormally);
    });
  });

  group('0x03 — main pack data', () {
    // 13.1V(1310), 0.0A(0 biased... actually JBD current has no bias, signed
    // directly), remaining 5.00Ah(500), nominal 10.00Ah(1000), cycles 12,
    // date/balance fields zero, protection 0, version byte 0, SOC 85%,
    // MOSFET both on (0x03), 4 cells, 1 NTC at 25.0°C -> (25+273.15)*10=2982.
    Uint8List mainPayload({
      int voltage = 1310,
      int current = 0,
      int remaining = 500,
      int nominal = 1000,
      int cycles = 12,
      int protection = 0,
      int soc = 85,
      int mosfet = 0x03,
      int cellCount = 4,
      List<int> ntcRaw = const [2982],
    }) {
      final p = <int>[
        (voltage >> 8) & 0xFF, voltage & 0xFF,
        (current >> 8) & 0xFF, current & 0xFF,
        (remaining >> 8) & 0xFF, remaining & 0xFF,
        (nominal >> 8) & 0xFF, nominal & 0xFF,
        (cycles >> 8) & 0xFF, cycles & 0xFF,
        0x00, 0x00, // production date
        0x00, 0x00, // balance low
        0x00, 0x00, // balance high
        (protection >> 8) & 0xFF, protection & 0xFF,
        0x10, // software version
        soc,
        mosfet,
        cellCount,
        ntcRaw.length,
      ];
      for (final t in ntcRaw) {
        p.add((t >> 8) & 0xFF);
        p.add(t & 0xFF);
      }
      return Uint8List.fromList(p);
    }

    test('decodes voltage, current, capacity, cycles, SOC', () {
      final frame = JbdParser.parse(response(0x03, 0x00, mainPayload())) as JbdMainFrame;
      expect(frame.packVoltage, closeTo(13.10, 0.001));
      expect(frame.currentAmps, closeTo(0.0, 0.001));
      expect(frame.remainingAh, closeTo(5.00, 0.001));
      expect(frame.nominalAh, closeTo(10.00, 0.001));
      expect(frame.cycleCount, equals(12));
      expect(frame.soc, closeTo(85.0, 0.001));
      expect(frame.cellCount, equals(4));
    });

    test('decodes signed current: positive is charging, negative is discharging', () {
      final charging = JbdParser.parse(response(0x03, 0x00, mainPayload(current: 550))) as JbdMainFrame;
      expect(charging.currentAmps, closeTo(5.5, 0.001));

      // -5.5A as two's-complement int16 = 0x10000 - 550 = 65_450 -> 0xFFAA... let's
      // just use the raw uint16 bit pattern for -550.
      final rawNeg = (0x10000 - 550) & 0xFFFF;
      final discharging = JbdParser.parse(response(0x03, 0x00, mainPayload(current: rawNeg))) as JbdMainFrame;
      expect(discharging.currentAmps, closeTo(-5.5, 0.001));
    });

    test('decodes MOSFET state bits (bit0=discharge, bit1=charge — reversed from common docs)', () {
      final bothOn = JbdParser.parse(response(0x03, 0x00, mainPayload(mosfet: 0x03))) as JbdMainFrame;
      expect(bothOn.chargeMosOn, isTrue);
      expect(bothOn.dischargeMosOn, isTrue);

      final bothOff = JbdParser.parse(response(0x03, 0x00, mainPayload(mosfet: 0x00))) as JbdMainFrame;
      expect(bothOff.chargeMosOn, isFalse);
      expect(bothOff.dischargeMosOn, isFalse);

      final dischargeOnly = JbdParser.parse(response(0x03, 0x00, mainPayload(mosfet: 0x01))) as JbdMainFrame;
      expect(dischargeOnly.chargeMosOn, isFalse);
      expect(dischargeOnly.dischargeMosOn, isTrue);

      final chargeOnly = JbdParser.parse(response(0x03, 0x00, mainPayload(mosfet: 0x02))) as JbdMainFrame;
      expect(chargeOnly.chargeMosOn, isTrue);
      expect(chargeOnly.dischargeMosOn, isFalse);
    });

    test('decodes NTC temperature from tenths-of-Kelvin to Celsius', () {
      // 2982 / 10 - 273.15 = 25.05, rounded to 1dp = 25.1.
      final frame = JbdParser.parse(response(0x03, 0x00, mainPayload(ntcRaw: [2982]))) as JbdMainFrame;
      expect(frame.ntcTempsC.single, closeTo(25.1, 0.01));
    });

    test('decodes multiple NTC sensors', () {
      final frame = JbdParser.parse(response(0x03, 0x00, mainPayload(ntcRaw: [2982, 3032]))) as JbdMainFrame;
      expect(frame.ntcTempsC.length, equals(2));
      expect(frame.ntcTempsC[0], closeTo(25.1, 0.01));
      expect(frame.ntcTempsC[1], closeTo(30.1, 0.01));
    });

    test('clamps an out-of-range SOC byte', () {
      final frame = JbdParser.parse(response(0x03, 0x00, mainPayload(soc: 250))) as JbdMainFrame;
      expect(frame.soc, equals(100.0));
    });

    test('rejects a too-short main payload', () {
      final f = response(0x03, 0x00, List.filled(10, 0));
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
    });
  });

  group('0x04 — cell voltages', () {
    test('decodes all cells from a single frame', () {
      final payload = [0x0c, 0xd1, 0x0c, 0xd0, 0x0c, 0xd2, 0x0c, 0xcf]; // 4 cells
      final frame = JbdParser.parse(response(0x04, 0x00, payload)) as JbdCellVoltageFrame;
      expect(frame.voltages, equals([3.281, 3.280, 3.282, 3.279]));
    });

    test('rejects an odd-length payload', () {
      final f = response(0x04, 0x00, [0x0c, 0xd1, 0x0c]);
      expect(() => JbdParser.parse(f), throwsA(isA<JbdParseException>()));
    });

    test('handles an empty cell list without crashing', () {
      final frame = JbdParser.parse(response(0x04, 0x00, [])) as JbdCellVoltageFrame;
      expect(frame.voltages, isEmpty);
    });
  });

  group('BmsSnapshot.mergeJbd', () {
    test('a main frame and a cell frame together produce a complete picture', () {
      var snap = const BmsSnapshot();
      expect(snap.hasCoreData, isFalse);

      final mainPayload = <int>[
        0x05, 0x1e, // 1310 -> 13.10V
        0x00, 0x00, // 0.00A
        0x01, 0xf4, // 500 -> 5.00Ah
        0x03, 0xe8, // 1000 -> 10.00Ah
        0x00, 0x0c, // 12 cycles
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // date/balance, unused
        0x00, 0x00, // protection
        0x10, // version
        85, // SOC
        0x03, // MOS both on
        4, // cell count
        1, // 1 NTC
        0x0b, 0xa6, // 2982 -> ~25.05C
      ];
      snap = snap.mergeJbd(JbdParser.parse(response(0x03, 0x00, mainPayload)));
      expect(snap.hasCoreData, isTrue);
      expect(snap.packVoltage, closeTo(13.10, 0.001));
      expect(snap.soc, closeTo(85.0, 0.001));
      expect(snap.chargeMosOn, isTrue);
      expect(snap.dischargeMosOn, isTrue);
      expect(snap.cellCount, equals(4));

      final cellPayload = [0x0c, 0xd1, 0x0c, 0xd0, 0x0c, 0xd2, 0x0c, 0xcf];
      snap = snap.mergeJbd(JbdParser.parse(response(0x04, 0x00, cellPayload)));
      expect(snap.cellVoltages, equals([3.281, 3.280, 3.282, 3.279]));

      // Same internal-consistency sanity check used for Daly: per-cell
      // voltages should sum close to the reported pack voltage.
      final sum = snap.cellVoltages.reduce((a, b) => a + b);
      expect(sum, closeTo(snap.packVoltage!, 0.05));
    });
  });
}
