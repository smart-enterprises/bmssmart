// lib/features/cloud/cloud_api.dart
//
// The Warrior cloud backend, as this app sees it.
//
// WHY THIS EXISTS AT ALL. The app reads the battery over BLE, directly from
// the Daly BMS. That covers SOC, cells, current, temperature — but it says
// nothing about the INVERTER: mains voltage, load, charger state, output mode.
// That half of the design is fed by the ESP32 gateway (firmware >= 2.1.0),
// which reads the inverter's own STM32 over a second UART and uploads it. So
// the two halves of every screen come from two different places on purpose.
//
// The consequence to keep in mind everywhere downstream: BLE can be live while
// the cloud is unreachable, and vice versa. Neither failure may blank the
// other's data, so every model here carries its own freshness and no screen
// treats "no cloud" as "no readings".

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL of the backend. Overridable at build time
/// (`--dart-define=WARRIOR_API=https://…`) so a staging build does not need a
/// code change.
///
/// **cloud.**warriorpower.in, NOT api.warriorpower.in. Both exist on the same
/// VPS and both answer /health with a 200, which makes the wrong one look
/// right: `api.` is the separate inverter-management-api, and it rejects
/// everything here with 401 `ERR_UNAUTHORIZED` because it wants a bearer token
/// this app has no way to obtain. Only `cloud.` proxies to the bms-cloud
/// backend on :8080 (see /etc/nginx/sites-available/cloud). The tell is the
/// error shape — this backend returns `{"error":"…"}`, the other returns
/// `{"success":false,"name":"UnauthorizedException",…}`.
const kWarriorApiBase = String.fromEnvironment(
  'WARRIOR_API',
  defaultValue: 'https://cloud.warriorpower.in',
);

/// The inverter object the gateway attaches to every reading and heartbeat.
///
/// Every field is nullable by design and that is not defensive padding: the
/// inverter's own protocol legitimately answers some commands with nothing at
/// all, so a missing value means "not reported this sweep". Substituting 0
/// would be indistinguishable from a real reading of zero volts.
class InverterState {
  const InverterState({
    required this.ok,
    this.ageSeconds,
    this.battVolts,
    this.solarVolts,
    this.inverterOn,
    this.outputVolts,
    this.loadPercent,
    this.mainsVolts,
    this.inverterHeatC,
    this.mpptHeatC,
    this.priority,
    this.chargeState,
    this.chargeAmps,
    this.chargeDelaySeconds,
    this.standby,
    this.rxBytes,
  });

  /// False when the gateway is running but the inverter UART is not answering
  /// — a different thing from having no inverter data at all, which is
  /// represented by a null [InverterState].
  final bool ok;

  /// Seconds since the sweep that produced these values. The gateway polls the
  /// inverter about four times slower than the BMS, so without this a stale
  /// reading rides along on every fast upload looking as fresh as the pack.
  final int? ageSeconds;

  final double? battVolts;
  final int? solarVolts;
  final bool? inverterOn;
  final int? outputVolts;
  final int? loadPercent;
  final int? mainsVolts;
  final int? inverterHeatC;
  final int? mpptHeatC;

  /// 'mains' | 'solar'
  final String? priority;

  /// 'off' | 'delay' | 'bulk' | 'float' | 'charged' | 'reserve'
  final String? chargeState;
  final int? chargeAmps;
  final int? chargeDelaySeconds;

  /// 'running' | 'ups_standby' | 'inv_standby'
  final String? standby;

  /// Lifetime bytes seen on the inverter UART. Only meaningful when [ok] is
  /// false: zero means nothing is wired or the wires are swapped, non-zero
  /// means the link is alive but the replies are not parsing.
  final int? rxBytes;

  /// True when mains is present. The inverter reports 0 V rather than omitting
  /// the field when the grid is down, so null (not reported) and 0 (measured
  /// zero) are deliberately different answers here.
  bool? get onGrid => mainsVolts == null ? null : mainsVolts! > 50;

  /// Watts, derived from the load percentage against the unit's rating. The
  /// inverter reports only a percentage, so this is exact only if [ratedVa] is.
  int? loadWatts(int ratedVa) => loadPercent == null ? null : (loadPercent! * ratedVa / 100).round();

  /// True when the reading is too old to present as live.
  bool get stale => (ageSeconds ?? 0) > 60;

  static double? _d(Object? v) => v is num ? v.toDouble() : null;
  static int? _i(Object? v) => v is num ? v.toInt() : null;
  static String? _s(Object? v) => v is String ? v : null;
  static bool? _b(Object? v) => v is bool ? v : null;

  /// Returns null when the field is absent entirely — that means gateway
  /// firmware older than 2.1.0, which is NOT the same as ok:false.
  static InverterState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['ok'] != true) {
      return InverterState(ok: false, rxBytes: _i(raw['rx_bytes']));
    }
    return InverterState(
      ok: true,
      ageSeconds: _i(raw['age_s']),
      battVolts: _d(raw['batt_v']),
      solarVolts: _i(raw['solar_v']),
      inverterOn: _b(raw['inv_on']),
      outputVolts: _i(raw['inv_v']),
      loadPercent: _i(raw['load_pct']),
      mainsVolts: _i(raw['mains_v']),
      inverterHeatC: _i(raw['inv_heat_c']),
      mpptHeatC: _i(raw['mppt_heat_c']),
      priority: _s(raw['priority']),
      chargeState: _s(raw['charge_state']),
      chargeAmps: _i(raw['charge_a']),
      chargeDelaySeconds: _i(raw['charge_delay_s']),
      standby: _s(raw['standby']),
    );
  }
}

/// One stored reading. The battery fields duplicate what BLE gives us — they
/// are the cloud's copy, used for history and when BLE is out of range.
class CloudReading {
  const CloudReading({
    required this.timestamp,
    this.voltage,
    this.current,
    this.soc,
    this.temperature,
    this.remainingAh,
    this.cycles,
    this.cells = const [],
    this.cellMin,
    this.cellMax,
    this.cellDeltaMv,
    this.chargeMosOn,
    this.dischargeMosOn,
    this.inverter,
  });

  final DateTime timestamp;
  final double? voltage;
  final double? current;
  final double? soc;
  final int? temperature;
  final double? remainingAh;
  final int? cycles;

  /// Per-cell volts. The gateway uploads these, so the cloud is a complete
  /// substitute for BLE rather than a summary of it — which is what lets the
  /// Battery screen show a full cell breakdown with no pack in range.
  final List<double> cells;
  final double? cellMin;
  final double? cellMax;
  final int? cellDeltaMv;
  final bool? chargeMosOn;
  final bool? dischargeMosOn;
  final InverterState? inverter;

  /// How old this reading is. The battery view refuses to present a stale
  /// cloud reading as live and falls back to BLE instead.
  Duration get age => DateTime.now().difference(timestamp);

  static CloudReading fromJson(Map<String, dynamic> j) => CloudReading(
    timestamp: DateTime.tryParse('${j['ts']}')?.toLocal() ?? DateTime.now(),
    voltage: InverterState._d(j['voltage']),
    current: InverterState._d(j['current']),
    soc: InverterState._d(j['soc']),
    temperature: InverterState._i(j['temperature']),
    remainingAh: InverterState._d(j['remaining_ah']),
    cycles: InverterState._i(j['cycles']),
    cells: (j['cells'] as List?)?.whereType<num>().map((v) => v.toDouble()).toList() ?? const [],
    cellMin: InverterState._d(j['cell_min']),
    cellMax: InverterState._d(j['cell_max']),
    cellDeltaMv: InverterState._i(j['cell_delta_mv']),
    chargeMosOn: InverterState._b(j['charge_mos']),
    dischargeMosOn: InverterState._b(j['discharge_mos']),
    inverter: InverterState.fromJson(j['inverter']),
  );
}

/// An entry in the gateway's own event log — crashes, boots, and BMS
/// silent/recovered transitions. This is what the Alerts screen lists: real
/// recorded events, not a synthesised feed.
class DeviceEvent {
  const DeviceEvent({
    required this.timestamp,
    required this.kind,
    required this.title,
    required this.body,
    required this.severity,
  });

  final DateTime timestamp;
  final String kind;
  final String title;
  final String body;

  /// 'fault' | 'warn' | 'info'
  final String severity;

  static DeviceEvent fromJson(Map<String, dynamic> j) {
    final kind = '${j['kind']}';
    final ts = DateTime.tryParse('${j['ts']}')?.toLocal() ?? DateTime.now();
    return switch (kind) {
      'crash' => DeviceEvent(
        timestamp: ts,
        kind: 'FAULT',
        title: 'Gateway restarted unexpectedly',
        body: '${j['reason'] ?? 'unknown'} during "${j['stage'] ?? 'unknown'}"'
            '${j['uptime_s'] != null ? ' after ${j['uptime_s']}s running' : ''}.',
        severity: 'fault',
      ),
      'bms_silent' => DeviceEvent(
        timestamp: ts,
        kind: 'FAULT',
        title: 'Battery stopped answering',
        body: 'The gateway is online but the BMS is not replying '
            '(${j['bms_fault'] ?? 'unknown fault'}).',
        severity: 'fault',
      ),
      'bms_recovered' => DeviceEvent(
        timestamp: ts,
        kind: 'INFO',
        title: 'Battery link restored',
        body: 'The BMS started answering the gateway again.',
        severity: 'info',
      ),
      'boot' => DeviceEvent(
        timestamp: ts,
        kind: 'INFO',
        title: 'Gateway started',
        body: 'Reset reason: ${j['reason'] ?? 'unknown'}.',
        severity: j['was_crash'] == true ? 'warn' : 'info',
      ),
      _ => DeviceEvent(
        timestamp: ts,
        kind: kind.toUpperCase(),
        title: kind,
        body: '',
        severity: 'info',
      ),
    };
  }
}

/// The one-call answer to "why is this device not reporting", plus the latest
/// inverter snapshot.
class DeviceHealth {
  const DeviceHealth({
    required this.state,
    required this.detail,
    required this.gatewayOnline,
    required this.bmsOk,
    this.network,
    this.rssi,
    this.signal,
    this.secondsSinceSeen,
    this.inverter,
    this.events = const [],
  });

  /// 'ok' | 'bms-silent' | 'gateway-offline' | 'never-seen'
  final String state;
  final String detail;
  final bool gatewayOnline;
  final bool bmsOk;
  final String? network;
  final int? rssi;
  final String? signal;
  final int? secondsSinceSeen;
  final InverterState? inverter;
  final List<DeviceEvent> events;

  static DeviceHealth fromJson(Map<String, dynamic> j) => DeviceHealth(
    state: '${j['state'] ?? 'never-seen'}',
    detail: '${j['detail'] ?? ''}',
    gatewayOnline: j['gateway_online'] == true,
    bmsOk: j['bms_ok'] != false,
    network: InverterState._s(j['network']),
    rssi: InverterState._i(j['rssi']),
    signal: InverterState._s(j['signal']),
    secondsSinceSeen: InverterState._i(j['seconds_since_seen']),
    inverter: InverterState.fromJson(j['inverter']),
    events: (j['recent_events'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(DeviceEvent.fromJson)
            .toList() ??
        const [],
  );
}

/// A device on the owner's account.
class CloudDevice {
  const CloudDevice({required this.id, required this.name, this.state});

  final String id;
  final String name;
  final String? state;

  static CloudDevice fromJson(Map<String, dynamic> j) => CloudDevice(
    id: '${j['device_id']}',
    name: '${j['name'] ?? j['device_id']}',
    state: j['health'] is Map ? '${(j['health'] as Map)['state']}' : null,
  );
}

/// Raised for any non-2xx response, carrying the server's own message so the
/// UI can show what actually went wrong instead of "something failed".
class CloudException implements Exception {
  CloudException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'CloudException($statusCode): $message';
}

/// Thin client. Holds the session token; knows nothing about widgets.
class CloudApi {
  CloudApi({http.Client? client, this.baseUrl = kWarriorApiBase})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  String? _token;

  /// The logged-in session token, or null when signed out.
  String? get token => _token;
  bool get isSignedIn => _token != null;

  void restoreSession(String? token) => _token = token;
  void signOut() => _token = null;

  static const _timeout = Duration(seconds: 15);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<dynamic> _get(String path) async {
    final r = await _client.get(Uri.parse('$baseUrl$path'), headers: _headers).timeout(_timeout);
    return _decode(r);
  }

  Future<dynamic> _post(String path, Map<String, Object?> body) async {
    final r = await _client
        .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return _decode(r);
  }

  dynamic _decode(http.Response r) {
    dynamic parsed;
    try {
      parsed = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      parsed = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return parsed;
    final msg = parsed is Map && parsed['error'] != null
        ? '${parsed['error']}'
        : 'Request failed (${r.statusCode})';
    throw CloudException(r.statusCode, msg);
  }

  /// Step 1 of login. The backend sends the code out of band.
  Future<void> requestOtp(String phone) => _post('/api/v1/auth/request-otp', {'phone': phone});

  /// Step 2. Returns the session token, which the caller should persist.
  Future<String> verifyOtp(String phone, String otp) async {
    final res = await _post('/api/v1/auth/verify-otp', {'phone': phone, 'otp': otp});
    final t = (res is Map ? res['token'] : null)?.toString();
    if (t == null || t.isEmpty) throw CloudException(500, 'No token in response');
    _token = t;
    return t;
  }

  Future<List<CloudDevice>> devices() async {
    final res = await _get('/api/v1/my/devices');
    return (res as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CloudDevice.fromJson)
        .toList();
  }

  Future<CloudReading> latest(String deviceId) async =>
      CloudReading.fromJson((await _get('/api/v1/my/devices/$deviceId/latest')) as Map<String, dynamic>);

  Future<List<CloudReading>> history(String deviceId, {int limit = 200}) async {
    final res = await _get('/api/v1/my/devices/$deviceId/history?limit=$limit');
    return (res as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CloudReading.fromJson)
        .toList();
  }

  Future<DeviceHealth> health(String deviceId) async =>
      DeviceHealth.fromJson((await _get('/api/v1/my/devices/$deviceId/health')) as Map<String, dynamic>);

  void dispose() => _client.close();
}
