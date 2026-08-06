// lib/features/cloud/cloud_providers.dart
//
// Riverpod wiring for the cloud half of the app.
//
// The polling cadence deliberately differs from the BLE stream: BLE pushes as
// fast as the BMS answers, while the gateway only uploads every couple of
// seconds and only sweeps the inverter every 5 s. Polling faster than that
// spends battery and mobile data re-fetching a value that has not changed.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_api.dart';

const _kTokenKey = 'warrior_cloud_token';
const _kPhoneKey = 'warrior_cloud_phone';
const _kDeviceKey = 'warrior_cloud_device';

final cloudApiProvider = Provider<CloudApi>((ref) {
  final api = CloudApi();
  ref.onDispose(api.dispose);
  return api;
});

/// Whether a stored session was found and restored. Everything cloud-facing
/// waits on this rather than assuming signed-out on first frame, which would
/// flash the login screen at an already-signed-in user on every cold start.
class CloudSession {
  const CloudSession({this.token, this.phone, this.restored = false});
  final String? token;
  final String? phone;
  final bool restored;

  bool get isSignedIn => token != null;
}

class CloudSessionNotifier extends Notifier<CloudSession> {
  @override
  CloudSession build() {
    unawaited(_restore());
    return const CloudSession();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenKey);
    ref.read(cloudApiProvider).restoreSession(token);
    state = CloudSession(token: token, phone: prefs.getString(_kPhoneKey), restored: true);
  }

  Future<void> requestOtp(String phone) => ref.read(cloudApiProvider).requestOtp(phone);

  Future<void> verifyOtp(String phone, String otp) async {
    final token = await ref.read(cloudApiProvider).verifyOtp(phone, otp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    await prefs.setString(_kPhoneKey, phone);
    state = CloudSession(token: token, phone: phone, restored: true);
  }

  Future<void> signOut() async {
    ref.read(cloudApiProvider).signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kDeviceKey);
    state = const CloudSession(restored: true);
  }
}

final cloudSessionProvider =
    NotifierProvider<CloudSessionNotifier, CloudSession>(CloudSessionNotifier.new);

/// Which device the screens are showing. Persisted so the app opens on the
/// same unit it was last looking at.
class SelectedDeviceNotifier extends Notifier<String?> {
  @override
  String? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kDeviceKey);
  }

  Future<void> select(String deviceId) async {
    state = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceKey, deviceId);
  }
}

final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, String?>(SelectedDeviceNotifier.new);

final cloudDevicesProvider = FutureProvider<List<CloudDevice>>((ref) async {
  final session = ref.watch(cloudSessionProvider);
  if (!session.isSignedIn) return const [];
  final devices = await ref.watch(cloudApiProvider).devices();
  // Auto-select when there is exactly one unit, which is the common case —
  // making a single-inverter owner pick their only device is pure friction.
  if (devices.length == 1 && ref.read(selectedDeviceProvider) == null) {
    unawaited(ref.read(selectedDeviceProvider.notifier).select(devices.first.id));
  }
  return devices;
});

/// Re-emits on an interval so the screens stay live. A StreamProvider rather
/// than a Timer inside a widget, so the polling stops the moment nothing is
/// listening — a screen the user has navigated away from must not keep
/// spending data.
Stream<T> _poll<T>(Duration every, Future<T> Function() fetch) async* {
  while (true) {
    try {
      yield await fetch();
    } catch (_) {
      // Swallowed on purpose: one failed poll (a tunnel, a dropped packet)
      // must not tear down the stream and blank the screen. The NEXT
      // successful poll simply replaces the value, and staleness is visible
      // through InverterState.ageSeconds / DeviceHealth.secondsSinceSeen.
    }
    await Future<void>.delayed(every);
  }
}

/// The inverter + gateway snapshot behind Home, Energy and Alerts.
final deviceHealthProvider = StreamProvider.autoDispose<DeviceHealth>((ref) {
  final id = ref.watch(selectedDeviceProvider);
  final session = ref.watch(cloudSessionProvider);
  if (id == null || !session.isSignedIn) return const Stream.empty();
  final api = ref.watch(cloudApiProvider);
  return _poll(const Duration(seconds: 5), () => api.health(id));
});

/// The latest stored reading. Used where the cloud's copy of the battery is
/// needed (no BLE in range), and as the inverter source on Battery/Energy.
final latestReadingProvider = StreamProvider.autoDispose<CloudReading>((ref) {
  final id = ref.watch(selectedDeviceProvider);
  final session = ref.watch(cloudSessionProvider);
  if (id == null || !session.isSignedIn) return const Stream.empty();
  final api = ref.watch(cloudApiProvider);
  return _poll(const Duration(seconds: 5), () => api.latest(id));
});

/// History for the Energy and History screens. Polled slowly — it is a chart
/// of the last few hours, not a live value.
final cloudHistoryProvider = StreamProvider.autoDispose<List<CloudReading>>((ref) {
  final id = ref.watch(selectedDeviceProvider);
  final session = ref.watch(cloudSessionProvider);
  if (id == null || !session.isSignedIn) return const Stream.empty();
  final api = ref.watch(cloudApiProvider);
  return _poll(const Duration(seconds: 60), () => api.history(id, limit: 500));
});
