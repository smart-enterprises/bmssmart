// Tests for replayLatest — the fix for a late subscriber never observing a
// status that was emitted before it attached.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbms/core/ble/replay_stream.dart';

void main() {
  group('replayLatest', () {
    test('a late subscriber still receives the current value', () async {
      final ctrl = StreamController<String>.broadcast();
      var latest = 'disconnected';

      // Emitted before anyone is listening — a plain broadcast stream drops
      // this, which is exactly the dashboard's "stuck on Connecting..." bug.
      latest = 'connected';
      ctrl.add(latest);

      final stream = replayLatest(ctrl, () => latest);
      expect(await stream.first, equals('connected'));

      await ctrl.close();
    });

    test('a plain broadcast stream drops it — the bug this guards against',
        () async {
      final ctrl = StreamController<String>.broadcast();
      ctrl.add('connected');

      // Nothing was listening, so the value is gone: first() only completes
      // if a *later* event arrives.
      final first = ctrl.stream.first.timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => 'never-arrived',
      );
      expect(await first, equals('never-arrived'));

      await ctrl.close();
    });

    test('forwards live events after the seed', () async {
      final ctrl = StreamController<String>.broadcast();
      var latest = 'connecting';

      final received = <String>[];
      final sub = replayLatest(ctrl, () => latest).listen(received.add);
      await Future<void>.delayed(Duration.zero);

      ctrl.add('connected');
      ctrl.add('disconnected');
      await Future<void>.delayed(Duration.zero);

      expect(received, equals(['connecting', 'connected', 'disconnected']));
      await sub.cancel();
      await ctrl.close();
    });

    test('does not lose an event emitted immediately after subscribing',
        () async {
      final ctrl = StreamController<String>.broadcast();
      var latest = 'seed';

      final received = <String>[];
      final sub = replayLatest(ctrl, () => latest).listen(received.add);

      // No await between subscribe and emit: the inner listen must already be
      // registered, or this event falls into the gap and is lost.
      ctrl.add('immediate');
      await Future<void>.delayed(Duration.zero);

      expect(received, equals(['seed', 'immediate']));
      await sub.cancel();
      await ctrl.close();
    });

    test('each subscriber gets its own replay of the latest value', () async {
      final ctrl = StreamController<String>.broadcast();
      var latest = 'first';

      final a = <String>[];
      final subA = replayLatest(ctrl, () => latest).listen(a.add);
      await Future<void>.delayed(Duration.zero);

      latest = 'second';
      ctrl.add(latest);
      await Future<void>.delayed(Duration.zero);

      // A second subscriber arriving now must see 'second', not 'first'.
      final b = <String>[];
      final subB = replayLatest(ctrl, () => latest).listen(b.add);
      await Future<void>.delayed(Duration.zero);

      expect(a, equals(['first', 'second']));
      expect(b, equals(['second']));

      await subA.cancel();
      await subB.cancel();
      await ctrl.close();
    });

    test('a subscriber to an already-closed controller gets the seed then done',
        () async {
      final ctrl = StreamController<String>.broadcast();
      await ctrl.close();

      final received = await replayLatest(ctrl, () => 'final').toList();
      expect(received, equals(['final']));
    });

    test('closes when the source closes', () async {
      final ctrl = StreamController<String>.broadcast();
      var done = false;

      replayLatest(ctrl, () => 'seed').listen((_) {}, onDone: () => done = true);
      await Future<void>.delayed(Duration.zero);

      await ctrl.close();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
    });
  });
}
