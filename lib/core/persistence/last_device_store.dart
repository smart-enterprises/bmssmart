// lib/core/persistence/last_device_store.dart
//
// Remembers the last BMS the user connected to, so the app can offer to
// reconnect on launch instead of making them scan every time.

import 'package:shared_preferences/shared_preferences.dart';

class LastDevice {
  final String remoteId;
  final String name;
  const LastDevice({required this.remoteId, required this.name});
}

abstract final class LastDeviceStore {
  static const _kIdKey = 'last_device_id';
  static const _kNameKey = 'last_device_name';

  /// Persists the device just connected to. [name] may be empty.
  static Future<void> save(String remoteId, String name) async {
    if (remoteId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIdKey, remoteId);
    await prefs.setString(_kNameKey, name);
  }

  /// The remembered device, or null if none has been saved.
  static Future<LastDevice?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kIdKey);
    if (id == null || id.isEmpty) return null;
    return LastDevice(
      remoteId: id,
      name: prefs.getString(_kNameKey) ?? '',
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIdKey);
    await prefs.remove(_kNameKey);
  }
}
