// lib/core/ble/replay_stream.dart
//
// Pure Dart — no Flutter, no BLE.

import 'dart:async';

/// Wraps [ctrl] so each new subscriber first receives the current value from
/// [seed], then every subsequent live event.
///
/// Broadcast controllers drop anything emitted before a listener attaches,
/// which loses state for any subscriber that arrives late — the BMS dashboard
/// subscribes only after the connection handshake has already reported its
/// result, so without a replay it would never see it.
///
/// The inner listen is registered synchronously alongside the seed, so no
/// event can slip through the gap between the two.
Stream<T> replayLatest<T>(StreamController<T> ctrl, T Function() seed) =>
    Stream<T>.multi((controller) {
      controller.add(seed());
      if (ctrl.isClosed) {
        controller.close();
        return;
      }
      final sub = ctrl.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
