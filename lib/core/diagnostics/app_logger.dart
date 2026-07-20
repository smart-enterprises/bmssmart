// lib/core/diagnostics/app_logger.dart
//
// In-app logger so the user can see what's happening on a phone without a
// laptop or terminal. Every BLE / connection / parsing event funnels through
// here and is exposed as a stream the debug screen subscribes to.

import 'dart:async';
import 'dart:collection';

enum LogLevel { info, warn, error, success, debug }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String get levelLabel => switch (level) {
    LogLevel.info => 'INFO',
    LogLevel.warn => 'WARN',
    LogLevel.error => 'ERR ',
    LogLevel.success => 'OK  ',
    LogLevel.debug => 'DBG ',
  };

  /// Plaintext format for clipboard / sharing.
  String toPlain() => '[$formattedTime] $levelLabel  [$tag]  $message';
}

/// Singleton logger. Use [AppLogger.instance] anywhere in the app.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  /// Ring buffer of the most recent N entries (capped to keep memory steady).
  static const int _maxEntries = 500;
  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>(_maxEntries);

  final StreamController<LogEntry> _ctrl =
  StreamController<LogEntry>.broadcast();

  /// Stream of new entries — debug screen listens to this.
  Stream<LogEntry> get stream => _ctrl.stream;

  /// All buffered entries, oldest first.
  List<LogEntry> get entries => _buffer.toList();

  void clear() {
    _buffer.clear();
    _ctrl.add(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'logger',
      message: '── log cleared ──',
    ));
  }

  void log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );

    if (_buffer.length >= _maxEntries) {
      _buffer.removeFirst();
    }
    _buffer.add(entry);
    if (!_ctrl.isClosed) _ctrl.add(entry);

    // Mirror to console too, so logcat output is identical to on-screen.
    // ignore: avoid_print
    print(entry.toPlain());
  }

  // Convenience methods.
  void i(String tag, String msg) => log(LogLevel.info, tag, msg);
  void w(String tag, String msg) => log(LogLevel.warn, tag, msg);
  void e(String tag, String msg) => log(LogLevel.error, tag, msg);
  void ok(String tag, String msg) => log(LogLevel.success, tag, msg);
  void d(String tag, String msg) => log(LogLevel.debug, tag, msg);

  /// Plaintext dump of all buffered entries for clipboard.
  String dumpAll() => entries.map((e) => e.toPlain()).join('\n');
}