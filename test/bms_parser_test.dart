// Daly BMS parser tests. Pure Dart — no widgets, no BLE.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbms/features/bms/data/models/bms_models.dart';
import 'package:smartbms/features/bms/data/parser/bms_parser.dart';

/// Builds a 13-byte response frame with a correct checksum.
/// [data] must be exactly 8 bytes.
Uint8List response(int cmd, List<int> data, {int addr = 0x01}) {
  assert(data.length == 8, 'Daly data payload is always 8 bytes');
  final f = Uint8List.fromList([0xA5, addr, cmd, 0x08, ...data, 0x00]);
  f[12] = BmsParser.checksumOf(f);
  return f;
}

void main() {
  group('buildRequest', () {
    test('produces the same 0x90 UART frame as the working Python reader', () {
      // Golden: daly_read.py builds [0xA5, 0x40, cmd, 0x08] + 8 zeros, with
      // checksum = sum & 0xFF. For 0x90 that is 0xA5+0x40+0x90+0x08 = 0x17D,
      // low byte 0x7D.
      final frame = BmsParser.buildRequest(0x90, hostAddr: 0x40);
      expect(
        frame,
        equals([0xA5, 0x40, 0x90, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0x7D]),
      );
    });

    test('uses the Bluetooth host address by default', () {
      final frame = BmsParser.buildRequest(0x90);
      expect(frame[1], equals(0x80));
      // 0xA5+0x80+0x90+0x08 = 0x1BD, low byte 0xBD.
      expect(frame[12], equals(0xBD));
    });

    test('every request frame is 13 bytes and self-consistent', () {
      for (final cmd in [0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x50]) {
        final frame = BmsParser.buildRequest(cmd);
        expect(frame.length, equals(13), reason: 'cmd 0x${cmd.toRadixString(16)}');
        expect(BmsParser.isValidFrame(frame), isTrue,
            reason: 'cmd 0x${cmd.toRadixString(16)}');
      }
    });
  });

  group('MOSFET control frames', () {
    // Opcode↔MOSFET mapping verified against the real pack over UART
    // 2026-07-19: 0xDA = charge, 0xD9 = discharge (reverse of the usual cite).
    test('charge control uses opcode 0xDA', () {
      expect(BmsParser.cmdSetChargeMos, equals(0xDA));
    });

    test('discharge control uses opcode 0xD9', () {
      expect(BmsParser.cmdSetDischargeMos, equals(0xD9));
    });

    test('builds a charge-MOS-on frame with the right bytes', () {
      // 0xA5+0x80+0xDA+0x08+0x01 = 0x208, low byte 0x08.
      final frame =
          BmsParser.buildMosControl(BmsParser.cmdSetChargeMos, on: true);
      expect(
        frame,
        equals([0xA5, 0x80, 0xDA, 0x08, 0x01, 0, 0, 0, 0, 0, 0, 0, 0x08]),
      );
    });

    test('builds a discharge-MOS-off frame with the right bytes', () {
      // 0xA5+0x80+0xD9+0x08+0x00 = 0x206, low byte 0x06.
      final frame =
          BmsParser.buildMosControl(BmsParser.cmdSetDischargeMos, on: false);
      expect(
        frame,
        equals([0xA5, 0x80, 0xD9, 0x08, 0x00, 0, 0, 0, 0, 0, 0, 0, 0x06]),
      );
    });

    test('on and off differ only in the payload byte and checksum', () {
      final on = BmsParser.buildMosControl(0xDA, on: true);
      final off = BmsParser.buildMosControl(0xDA, on: false);

      expect(on[4], equals(0x01));
      expect(off[4], equals(0x00));
      expect(on.sublist(0, 4), equals(off.sublist(0, 4)));
      expect(BmsParser.isValidFrame(on), isTrue);
      expect(BmsParser.isValidFrame(off), isTrue);
    });

    test('honours the UART host address', () {
      // 0xA5+0x40+0xD9+0x08+0x01 = 0x1C7, low byte 0xC7.
      final frame = BmsParser.buildMosControl(0xD9, on: true, hostAddr: 0x40);
      expect(frame[1], equals(0x40));
      expect(frame[12], equals(0xC7));
      expect(BmsParser.isValidFrame(frame), isTrue);
    });

    test('rejects an oversized payload', () {
      expect(
        () => BmsParser.buildRequest(0xD9, data: List.filled(9, 0)),
        throwsArgumentError,
      );
    });

    test('parses the acknowledgement the BMS echoes back', () {
      // 0xDA = charge on this unit.
      final ack = BmsParser.parse(
              response(0xDA, [0x00, 0, 0, 0, 0, 0, 0, 0]))
          as DalyMosAckFrame;
      expect(ack.isCharge, isTrue);
      expect(ack.requestedOn, isFalse);

      // 0xD9 = discharge on this unit.
      final ackOn = BmsParser.parse(
              response(0xD9, [0x01, 0, 0, 0, 0, 0, 0, 0]))
          as DalyMosAckFrame;
      expect(ackOn.isCharge, isFalse);
      expect(ackOn.requestedOn, isTrue);
    });

    test('an ack does not move the displayed MOSFET state', () {
      // The BMS reports both MOSFETs on via 0x93...
      var snap = const BmsSnapshot().merge(BmsParser.parse(
          response(0x93, [0x02, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])));
      expect(snap.dischargeMosOn, isTrue);

      // ...and acks a request to switch discharge off. The ack alone must not
      // flip the UI: a BMS under protection acks and then refuses. Only the
      // next 0x93 is trusted.
      snap = snap.merge(BmsParser.parse(
          response(0xDA, [0x00, 0, 0, 0, 0, 0, 0, 0])));
      expect(snap.dischargeMosOn, isTrue,
          reason: 'an ack is not evidence the MOSFET actually changed');

      // The next real poll reports it off — now the UI follows.
      snap = snap.merge(BmsParser.parse(
          response(0x93, [0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])));
      expect(snap.dischargeMosOn, isFalse);
    });
  });

  group('validation', () {
    test('rejects a bad start byte', () {
      final f = response(0x90, List.filled(8, 0));
      f[0] = 0xDD; // JBD's start byte — must not be accepted here.
      expect(() => BmsParser.parse(f), throwsA(isA<BmsParseException>()));
      expect(BmsParser.isValidFrame(f), isFalse);
    });

    test('rejects a corrupted checksum', () {
      final f = response(0x90, List.filled(8, 0));
      f[12] = f[12] ^ 0xFF;
      expect(() => BmsParser.parse(f), throwsA(isA<BmsParseException>()));
      expect(BmsParser.isValidFrame(f), isFalse);
    });

    test('rejects a short frame', () {
      final f = Uint8List.fromList([0xA5, 0x01, 0x90, 0x08]);
      expect(() => BmsParser.parse(f), throwsA(isA<BmsParseException>()));
      expect(BmsParser.isValidFrame(f), isFalse);
    });

    test('rejects an unsupported command', () {
      final f = response(0x7F, List.filled(8, 0));
      expect(() => BmsParser.parse(f), throwsA(isA<BmsParseException>()));
    });

    test('accepts a reply from any BMS address', () {
      final f = response(0x90, [0x00, 0x83, 0x00, 0x83, 0x75, 0x30, 0x03, 0x57],
          addr: 0x02);
      expect(() => BmsParser.parse(f), returnsNormally);
    });
  });

  group('0x90 — SOC / voltage / current', () {
    test('decodes a resting 4S pack', () {
      // 13.1 V → 131; current 0.0 A → 30000 (0x7530); SOC 85.5% → 855 (0x0357).
      final f = response(0x90, [0x00, 0x83, 0x00, 0x83, 0x75, 0x30, 0x03, 0x57]);
      final frame = BmsParser.parse(f) as DalySocFrame;

      expect(frame.packVoltage, closeTo(13.1, 0.001));
      expect(frame.currentAmps, closeTo(0.0, 0.001));
      expect(frame.soc, closeTo(85.5, 0.001));
    });

    test('decodes discharge as negative current via the 30000 offset', () {
      // 29900 → (29900 - 30000) / 10 = -10.0 A
      final f = response(0x90, [0x00, 0x83, 0x00, 0x83, 0x74, 0xCC, 0x03, 0x57]);
      final frame = BmsParser.parse(f) as DalySocFrame;

      expect(frame.currentAmps, closeTo(-10.0, 0.001));
      expect(resolveStatus(frame.currentAmps), equals(ChargeStatus.discharging));
    });

    test('decodes charge as positive current', () {
      // 30055 → +5.5 A
      final f = response(0x90, [0x00, 0x83, 0x00, 0x83, 0x75, 0x67, 0x03, 0x57]);
      final frame = BmsParser.parse(f) as DalySocFrame;

      expect(frame.currentAmps, closeTo(5.5, 0.001));
      expect(resolveStatus(frame.currentAmps), equals(ChargeStatus.charging));
    });

    test('clamps an out-of-range SOC', () {
      // 1200 → 120.0%, which is not physical.
      final f = response(0x90, [0x00, 0x83, 0x00, 0x83, 0x75, 0x30, 0x04, 0xB0]);
      final frame = BmsParser.parse(f) as DalySocFrame;
      expect(frame.soc, equals(100.0));
    });
  });

  group('0x91 — cell extremes', () {
    test('decodes max/min cell voltage and cell numbers', () {
      final f = response(0x91, [0x0C, 0xD2, 0x02, 0x0C, 0xC6, 0x04, 0x00, 0x00]);
      final frame = BmsParser.parse(f) as DalyMinMaxCellFrame;

      expect(frame.maxCellMv, equals(3282));
      expect(frame.maxCellNumber, equals(2));
      expect(frame.minCellMv, equals(3270));
      expect(frame.minCellNumber, equals(4));
      expect(frame.deltaMv, equals(12));
    });
  });

  group('0x92 — temperatures', () {
    test('decodes temperature using the 40-degree offset', () {
      // 65 - 40 = 25 °C, 60 - 40 = 20 °C
      final f = response(0x92, [65, 1, 60, 2, 0, 0, 0, 0]);
      final frame = BmsParser.parse(f) as DalyTempFrame;

      expect(frame.maxTempC, equals(25));
      expect(frame.minTempC, equals(20));
    });

    test('decodes sub-zero temperature', () {
      // 35 - 40 = -5 °C
      final f = response(0x92, [35, 1, 35, 1, 0, 0, 0, 0]);
      final frame = BmsParser.parse(f) as DalyTempFrame;
      expect(frame.maxTempC, equals(-5));
    });
  });

  group('0x93 — MOSFET state', () {
    test('decodes MOS flags and remaining capacity', () {
      // 50000 mAh → 50.0 Ah  (0x0000C350)
      final f = response(0x93, [0x02, 0x01, 0x01, 0x2A, 0x00, 0x00, 0xC3, 0x50]);
      final frame = BmsParser.parse(f) as DalyMosFrame;

      expect(frame.stateByte, equals(2));
      expect(frame.chargeMosOn, isTrue);
      expect(frame.dischargeMosOn, isTrue);
      expect(frame.bmsLife, equals(42));
      expect(frame.remainingAh, closeTo(50.0, 0.001));
    });

    test('decodes MOSFETs off', () {
      final f = response(0x93, [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]);
      final frame = BmsParser.parse(f) as DalyMosFrame;
      expect(frame.chargeMosOn, isFalse);
      expect(frame.dischargeMosOn, isFalse);
    });
  });

  group('0x94 — pack configuration', () {
    test('decodes cell count, sensors and cycles', () {
      final f = response(0x94, [0x04, 0x01, 0x01, 0x00, 0x00, 0x00, 0x11, 0x00]);
      final frame = BmsParser.parse(f) as DalyStatusFrame;

      expect(frame.cellCount, equals(4));
      expect(frame.tempSensorCount, equals(1));
      expect(frame.chargerConnected, isTrue);
      expect(frame.loadConnected, isFalse);
      expect(frame.cycleCount, equals(17));
    });
  });

  group('0x95 — cell voltages', () {
    test('decodes three cells per sub-frame', () {
      final f = response(0x95, [0x01, 0x0C, 0xD1, 0x0C, 0xD0, 0x0C, 0xD2, 0x00]);
      final frame = BmsParser.parse(f) as DalyCellVoltageFrame;

      expect(frame.frameNumber, equals(1));
      expect(frame.millivolts, equals([3281, 3280, 3282]));
      expect(frame.firstCellNumber, equals(1));
    });

    test('maps the second sub-frame to cells 4-6', () {
      final f = response(0x95, [0x02, 0x0C, 0xCF, 0x00, 0x00, 0x00, 0x00, 0x00]);
      final frame = BmsParser.parse(f) as DalyCellVoltageFrame;
      expect(frame.firstCellNumber, equals(4));
    });

    test('rejects a zero frame number', () {
      final f = response(0x95, [0x00, 0x0C, 0xD1, 0x0C, 0xD0, 0x0C, 0xD2, 0x00]);
      expect(() => BmsParser.parse(f), throwsA(isA<BmsParseException>()));
    });
  });

  group('0x96 — cell temperatures', () {
    test('decodes real single-sensor frame captured from the pack', () {
      // Real bytes: a5 01 96 08  01 44 ff ff ff ff ff 00 — 1 sensor at 0x44.
      final frame = BmsParser.parse(
              response(0x96, [0x01, 0x44, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]))
          as DalyCellTempFrame;
      expect(frame.frameNumber, equals(1));
      expect(frame.temps, equals([28])); // 0x44 - 40
    });

    test('decodes multiple sensors and stops at the 0xFF padding', () {
      final frame = BmsParser.parse(
              response(0x96, [0x01, 0x44, 0x46, 0x42, 0xff, 0xff, 0xff, 0x00]))
          as DalyCellTempFrame;
      expect(frame.temps, equals([28, 30, 26]));
    });

    test('decodes sub-zero temperatures', () {
      final frame = BmsParser.parse(
              response(0x96, [0x01, 0x23, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]))
          as DalyCellTempFrame;
      expect(frame.temps, equals([-5])); // 0x23 = 35, 35 - 40
    });
  });

  group('0x97 — cell balancing', () {
    test('decodes all-clear (captured from pack, nothing balancing)', () {
      final frame = BmsParser.parse(
              response(0x97, [0, 0, 0, 0, 0, 0, 0, 0]))
          as DalyBalanceFrame;
      expect(frame.balancingCells, isEmpty);
    });

    test('decodes the bitmask: byte 0 bit 0 = cell 1', () {
      // 0x0D = bits 0,2,3 -> cells 1, 3, 4.
      final frame = BmsParser.parse(
              response(0x97, [0x0D, 0, 0, 0, 0, 0, 0, 0]))
          as DalyBalanceFrame;
      expect(frame.balancingCells, equals({1, 3, 4}));
    });

    test('spans into the second byte: byte 1 bit 0 = cell 9', () {
      final frame = BmsParser.parse(
              response(0x97, [0x00, 0x01, 0, 0, 0, 0, 0, 0]))
          as DalyBalanceFrame;
      expect(frame.balancingCells, equals({9}));
    });
  });

  group('0x98 — protection / alarm flags', () {
    test('decodes all-clear (captured from pack, no faults)', () {
      final frame = BmsParser.parse(
              response(0x98, [0, 0, 0, 0, 0, 0, 0, 0]))
          as DalyFaultFrame;
      expect(frame.activeFaults, isEmpty);
      expect(frame.hasFault, isFalse);
      expect(frame.faultCount, equals(0));
    });

    test('decodes a cell-overvoltage protection alarm', () {
      // byte 0 bit 1 = cell voltage high (protect).
      final frame = BmsParser.parse(
              response(0x98, [0x02, 0, 0, 0, 0, 0, 0, 0x01]))
          as DalyFaultFrame;
      expect(frame.hasFault, isTrue);
      expect(frame.activeFaults, contains('Cell voltage high (protect)'));
      expect(frame.faultCount, equals(1));
    });

    test('decodes multiple simultaneous alarms across bytes', () {
      // byte 1 bit 4 = discharge temp high (warn); byte 2 bit 3 = discharge
      // overcurrent (protect).
      final frame = BmsParser.parse(
              response(0x98, [0, 0x10, 0x08, 0, 0, 0, 0, 0x02]))
          as DalyFaultFrame;
      expect(
        frame.activeFaults,
        containsAll(<String>[
          'Discharge temp high (warn)',
          'Discharge overcurrent (protect)',
        ]),
      );
    });

    test('surfaces undocumented bits rather than hiding them', () {
      // byte 6 has no documented labels; a set bit must still appear.
      final frame = BmsParser.parse(
              response(0x98, [0, 0, 0, 0, 0, 0, 0x01, 0]))
          as DalyFaultFrame;
      expect(frame.activeFaults.single, contains('byte 6 bit 0'));
    });
  });

  group('snapshot merges the new frames', () {
    test('faults, balancing and temps land in the snapshot', () {
      var snap = const BmsSnapshot();
      expect(snap.activeFaults, isNull); // not yet answered
      expect(snap.hasFault, isFalse);

      snap = snap
          .merge(BmsParser.parse(
              response(0x94, [0x04, 0x01, 0, 0, 0, 0, 0, 0])))
          .merge(BmsParser.parse(
              response(0x98, [0, 0, 0, 0, 0, 0, 0, 0])))
          .merge(BmsParser.parse(
              response(0x97, [0x05, 0, 0, 0, 0, 0, 0, 0]))) // cells 1,3
          .merge(BmsParser.parse(
              response(0x96, [0x01, 0x44, 0xff, 0xff, 0xff, 0xff, 0xff, 0])));

      expect(snap.activeFaults, isEmpty); // answered, nothing wrong
      expect(snap.hasFault, isFalse);
      expect(snap.balancingCells, equals({1, 3}));
      expect(snap.cellTemps, equals([28]));
    });
  });

  group('maxObservedTempC (drives the temp alert)', () {
    test('is null before any temperature arrives', () {
      expect(const BmsSnapshot().maxObservedTempC, isNull);
    });

    test('prefers per-sensor readings and takes the hottest', () {
      final snap = const BmsSnapshot()
          .merge(BmsParser.parse(
              response(0x94, [0x03, 0x03, 0, 0, 0, 0, 0, 0])))
          .merge(BmsParser.parse(
              response(0x96, [0x01, 0x44, 0x50, 0x46, 0xff, 0xff, 0xff, 0])));
      // 0x44=28, 0x50=40, 0x46=30 -> hottest 40.
      expect(snap.maxObservedTempC, equals(40));
    });

    test('falls back to the 0x92 max when no per-sensor data', () {
      final snap = const BmsSnapshot().merge(BmsParser.parse(
          response(0x92, [0x50, 1, 0x44, 1, 0, 0, 0, 0])));
      expect(snap.maxObservedTempC, equals(40)); // 0x50 - 40
    });

    test('crosses a 35°C alert threshold exactly at 35', () {
      final below = const BmsSnapshot().merge(BmsParser.parse(
          response(0x96, [0x01, 0x42, 0xff, 0xff, 0xff, 0xff, 0xff, 0]))); // 26
      final at = const BmsSnapshot().merge(BmsParser.parse(
          response(0x96, [0x01, 0x4b, 0xff, 0xff, 0xff, 0xff, 0xff, 0]))); // 35
      const threshold = 35;
      expect(below.maxObservedTempC! >= threshold, isFalse);
      expect(at.maxObservedTempC! >= threshold, isTrue);
    });
  });

  group('0x50 — rated capacity', () {
    test('decodes rated capacity and nominal cell voltage', () {
      // 100000 mAh → 100.0 Ah (0x000186A0); 3200 mV → 3.2 V (0x00000C80)
      final f = response(0x50, [0x00, 0x01, 0x86, 0xA0, 0x00, 0x00, 0x0C, 0x80]);
      final frame = BmsParser.parse(f) as DalyRatedFrame;

      expect(frame.ratedAh, closeTo(100.0, 0.001));
      expect(frame.ratedCellVolts, closeTo(3.2, 0.001));
    });
  });

  group('BmsSnapshot.merge', () {
    test('assembles a full 4S picture from separate command replies', () {
      var snap = const BmsSnapshot();
      expect(snap.hasCoreData, isFalse);

      snap = snap.merge(BmsParser.parse(
          response(0x90, [0x00, 0x83, 0x00, 0x83, 0x75, 0x30, 0x03, 0x57])));
      expect(snap.hasCoreData, isTrue);
      expect(snap.packVoltage, closeTo(13.1, 0.001));
      expect(snap.soc, closeTo(85.5, 0.001));
      expect(snap.status, equals(ChargeStatus.idle));

      snap = snap.merge(BmsParser.parse(
          response(0x94, [0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x11, 0x00])));
      expect(snap.cellCount, equals(4));
      expect(snap.cycleCount, equals(17));

      snap = snap.merge(BmsParser.parse(
          response(0x92, [65, 1, 60, 2, 0, 0, 0, 0])));
      expect(snap.maxTempC, equals(25));

      // Two sub-frames for a 4-cell pack; the second is zero-padded.
      snap = snap.merge(BmsParser.parse(
          response(0x95, [0x01, 0x0C, 0xD1, 0x0C, 0xD0, 0x0C, 0xD2, 0x00])));
      snap = snap.merge(BmsParser.parse(
          response(0x95, [0x02, 0x0C, 0xCF, 0x00, 0x00, 0x00, 0x00, 0x00])));

      expect(snap.cellVoltages.length, equals(4),
          reason: 'padding cells in the last sub-frame must be trimmed');
      expect(snap.cellVoltages,
          equals([3.281, 3.280, 3.282, 3.279]));

      // Sanity check borrowed from the UART work: per-cell voltages must sum
      // to roughly the reported pack voltage. An echo or a misparse cannot
      // produce that internal consistency.
      final sum = snap.cellVoltages.reduce((a, b) => a + b);
      expect(sum, closeTo(snap.packVoltage!, 0.05));
    });

    test('merges cell sub-frames positionally, not by appending', () {
      var snap = const BmsSnapshot()
          .merge(BmsParser.parse(
              response(0x94, [0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])))
          // Sub-frame 2 arrives first — cells 4-6.
          .merge(BmsParser.parse(
              response(0x95, [0x02, 0x0C, 0xC0, 0x0C, 0xC1, 0x0C, 0xC2, 0x00])));

      expect(snap.cellVoltages.length, equals(6));
      expect(snap.cellVoltages[3], closeTo(3.264, 0.0001));

      // Now sub-frame 1 lands; it must fill cells 1-3 without displacing 4-6.
      snap = snap.merge(BmsParser.parse(
          response(0x95, [0x01, 0x0C, 0xD1, 0x0C, 0xD0, 0x0C, 0xD2, 0x00])));

      expect(snap.cellVoltages.length, equals(6));
      expect(snap.cellVoltages[0], closeTo(3.281, 0.0001));
      expect(snap.cellVoltages[3], closeTo(3.264, 0.0001),
          reason: 'a later sub-frame must not be shifted by an earlier one');
    });

    test('a later reply supersedes an earlier value', () {
      var snap = const BmsSnapshot().merge(BmsParser.parse(
          response(0x90, [0x00, 0x83, 0x00, 0x83, 0x75, 0x30, 0x03, 0x57])));
      expect(snap.soc, closeTo(85.5, 0.001));

      snap = snap.merge(BmsParser.parse(
          response(0x90, [0x00, 0x84, 0x00, 0x84, 0x75, 0x67, 0x03, 0xE8])));
      expect(snap.soc, closeTo(100.0, 0.001));
      expect(snap.packVoltage, closeTo(13.2, 0.001));
      expect(snap.status, equals(ChargeStatus.charging));
    });

    test('exposes cell statistics once voltages are known', () {
      final snap = const BmsSnapshot()
          .merge(BmsParser.parse(
              response(0x94, [0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])))
          .merge(BmsParser.parse(
              response(0x95, [0x01, 0x0C, 0xD1, 0x0C, 0xD0, 0x0C, 0xD2, 0x00])));

      expect(snap.minCellVolts, closeTo(3.280, 0.0001));
      expect(snap.maxCellVolts, closeTo(3.282, 0.0001));
      expect(snap.deltaCellVolts, closeTo(0.002, 0.0001));
      expect(snap.averageCellVolts, closeTo(3.281, 0.0001));
    });
  });

  group('resolveStatus', () {
    test('applies a dead band around zero', () {
      expect(resolveStatus(0.0), equals(ChargeStatus.idle));
      expect(resolveStatus(0.05), equals(ChargeStatus.idle));
      expect(resolveStatus(-0.05), equals(ChargeStatus.idle));
      expect(resolveStatus(0.5), equals(ChargeStatus.charging));
      expect(resolveStatus(-0.5), equals(ChargeStatus.discharging));
    });
  });

  group('TempThresholds', () {
    const t = TempThresholds(warningC: 70, criticalC: 85);

    test('classifies below warning as normal', () {
      expect(t.classify(69.9), equals(TempSeverity.normal));
      expect(t.classify(20), equals(TempSeverity.normal));
    });

    test('classifies at/above warning but below critical as warning', () {
      expect(t.classify(70), equals(TempSeverity.warning));
      expect(t.classify(84.9), equals(TempSeverity.warning));
    });

    test('classifies at/above critical as critical', () {
      expect(t.classify(85), equals(TempSeverity.critical));
      expect(t.classify(120), equals(TempSeverity.critical));
    });

    test('kTempThresholds is fixed at warn=70°C, crit=85°C', () {
      expect(kTempThresholds.warningC, equals(70));
      expect(kTempThresholds.criticalC, equals(85));
    });
  });

  group('estimateRuntimeHours', () {
    test('divides remaining capacity by load', () {
      final h = estimateRuntimeHours(remainingAh: 25.0, loadAmps: 5.0);
      expect(h, closeTo(5.0, 0.001));
    });

    test('returns null for zero or negligible load', () {
      expect(estimateRuntimeHours(remainingAh: 25.0, loadAmps: 0.0), isNull);
      expect(estimateRuntimeHours(remainingAh: 25.0, loadAmps: 0.02), isNull);
    });

    test('returns null for negative load (shouldn\'t happen, but no NaN either)', () {
      expect(estimateRuntimeHours(remainingAh: 25.0, loadAmps: -3.0), isNull);
    });
  });

  group('estimateTimeToFullHours', () {
    test('divides the gap to full by the charge current', () {
      // 10 Ah still needed at 5 A -> 2 hours.
      final h = estimateTimeToFullHours(remainingAh: 40.0, nominalAh: 50.0, chargeAmps: 5.0);
      expect(h, closeTo(2.0, 0.001));
    });

    test('returns 0 when already at or effectively at full', () {
      expect(estimateTimeToFullHours(remainingAh: 50.0, nominalAh: 50.0, chargeAmps: 2.0), equals(0));
      // Within the 0.05 Ah near-full tolerance.
      expect(estimateTimeToFullHours(remainingAh: 49.98, nominalAh: 50.0, chargeAmps: 2.0), equals(0));
    });

    test('clamps an overshoot (remaining slightly above nominal) to 0, not negative', () {
      expect(estimateTimeToFullHours(remainingAh: 50.5, nominalAh: 50.0, chargeAmps: 2.0), equals(0));
    });

    test('returns null when charge current is negligible', () {
      expect(estimateTimeToFullHours(remainingAh: 10.0, nominalAh: 50.0, chargeAmps: 0.0), isNull);
      expect(estimateTimeToFullHours(remainingAh: 10.0, nominalAh: 50.0, chargeAmps: 0.02), isNull);
    });
  });

  group('formatDuration', () {
    test('formats sub-hour durations as minutes only', () {
      expect(formatDuration(0.5), equals('30m'));
      expect(formatDuration(0.0167), equals('1m'));
    });

    test('formats whole hours without a minutes component', () {
      expect(formatDuration(3.0), equals('3h'));
    });

    test('formats mixed hours and minutes', () {
      expect(formatDuration(2.5), equals('2h 30m'));
    });

    test('returns an em dash for null, NaN, infinite, or negative input', () {
      expect(formatDuration(null), equals('—'));
      expect(formatDuration(double.nan), equals('—'));
      expect(formatDuration(double.infinity), equals('—'));
      expect(formatDuration(-1.0), equals('—'));
    });

    test('rounds to the nearest minute at a boundary', () {
      // 1h 29m59s rounds up to 1h 30m, not 1h 29m.
      expect(formatDuration(1 + 29.99 / 60), equals('1h 30m'));
    });
  });
}
