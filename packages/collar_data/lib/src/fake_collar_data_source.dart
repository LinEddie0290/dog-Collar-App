import 'dart:async';
import 'dart:math';

import 'collar_data_source.dart';
import 'conn_status.dart';
import 'raw_frame.dart';

/// Synthetic collar — the priority deliverable. It lets the UI teammate build
/// and run the whole app **today**, with no hardware and no real WebSocket.
///
/// It mimics the real device closely:
///   * ~10 Hz sensor frames, body temperature wandering around 38.5 °C, resp,
///     noisy IMU (az≈+1g),
///     strictly increasing seq, slowly draining battery.
///   * Occasionally emits a frame with **no temperature field**, so downstream code is
///     forced to handle the nullable case (see [SensorSample]).
///   * Simulates dropouts: every [outageEvery] it goes `reconnecting` for
///     [outageDuration] and emits no frames, then `connected` again — exactly
///     the flaky-WiFi behaviour the UI must tolerate.
///   * GPS fixes are added at a much lower rate than IMU/HR (real GPS chips
///     draw far more power than an accelerometer, so the collar is not
///     expected to report a fix on every 100ms frame) — see [gpsFixEvery].
///     The fake fix does a small random walk around [gpsOrigin], the kind of
///     drift you'd see standing roughly still, so geofence logic has
///     something realistic to react to.
class FakeCollarDataSource implements CollarDataSource {
  final Duration framePeriod;
  final Duration outageEvery;
  final Duration outageDuration;
  final int? seed;

  /// Roughly how often a GPS fix is included in a frame, in units of
  /// [framePeriod] ticks. Default 10 ticks * 100ms = ~1 fix/second, which is
  /// already generous for a battery-powered collar — real firmware will
  /// likely be slower. Adjust once real behaviour is known.
  final int gpsFixEvery;

  /// Center point the fake GPS walk wanders around (WGS84). Defaults to a
  /// placeholder point; pass a real "home" location for more realistic
  /// geofence testing.
  final ({double lat, double lng}) gpsOrigin;

  FakeCollarDataSource({
    this.framePeriod = const Duration(milliseconds: 100),
    this.outageEvery = const Duration(seconds: 8),
    this.outageDuration = const Duration(seconds: 3),
    this.seed,
    this.gpsFixEvery = 10,
    this.gpsOrigin = (lat: 31.2304, lng: 121.4737),
  }) : _rng = Random(seed);

  final Random _rng;
  final _frames = StreamController<RawFrame>.broadcast();
  final _status = StreamController<ConnStatus>.broadcast();

  Timer? _frameTimer;
  Timer? _outageTimer;
  int _seq = 0;
  double _battery = 100;
  bool _online = false;
  bool _closed = false;

  double _gpsLat = 0;
  double _gpsLng = 0;
  bool _gpsInitialized = false;

  @override
  Stream<RawFrame> get frames => _frames.stream;

  @override
  Stream<ConnStatus> get status => _status.stream;

  @override
  Future<void> connect() async {
    if (_closed) throw StateError('source is closed');
    _status.add(ConnStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _goOnline();
    _frameTimer = Timer.periodic(framePeriod, (_) => _tick());
    _outageTimer = Timer.periodic(outageEvery, (_) => _simulateOutage());
  }

  void _goOnline() {
    _online = true;
    _status.add(ConnStatus.connected);
  }

  void _tick() {
    if (!_online) return; // silent during a simulated outage
    final now = DateTime.now().millisecondsSinceEpoch;

    // ~1 in 8 frames has no temperature reading -> exercises the nullable
    // path. On the real collar this happens for a different reason than the
    // original HR case: temperature arrives at 2 Hz while the IMU runs at
    // 104 Hz, so most merged snapshots carry no fresh temperature at all.
    final hasTemp = _seq % 8 != 0;
    final phase = _seq / 20.0;
    final bodyTemp = 38.5 + 0.4 * sin(phase) + _noise(0.08);
    final ambient = 25.0 + _noise(0.5);
    final resp = (20 + 6 * sin(phase / 3) + _noise(1)).clamp(8, 40).round();

    final raw = <String, dynamic>{
      'v': 1,
      'type': 'sensor',
      'ts': now + _rng.nextInt(80) - 40, // device clock drifts a little
      'seq': _seq,
      if (hasTemp) 'body_temp_c': _round(bodyTemp),
      if (hasTemp) 'ambient_temp_c': _round(ambient),
      // The real hardware has no respiration sensor, so this field is always
      // absent on the BLE link. The fake keeps producing it on purpose: it is
      // how we check the UI still renders when a field it used to rely on
      // turns into a permanent null.
      'resp': resp,
      'imu': {
        'ax': _round(_noise(0.05)),
        'ay': _round(_noise(0.05)),
        'az': _round(1.0 + _noise(0.05)), // gravity on one axis
      },
      'battery': _battery.round(),
      ...(_maybeGpsFields()),
    };

    _frames.add(RawFrame(now, raw));
    _seq++;
    _battery = max(0, _battery - 0.01);
  }

  /// Returns the GPS fields on ticks where a fix "arrives" (see [gpsFixEvery]),
  /// or an empty map otherwise. The real collar sends GPS in its own frames
  /// rather than as extra fields, and reports fix quality / satellites / HDOP
  /// instead of an accuracy in metres — it has no accuracy figure to give.
  Map<String, dynamic> _maybeGpsFields() {
    if (_seq % gpsFixEvery != 0) return const <String, dynamic>{};

    if (!_gpsInitialized) {
      _gpsLat = gpsOrigin.lat;
      _gpsLng = gpsOrigin.lng;
      _gpsInitialized = true;
    } else {
      // Small random walk: roughly a few meters per fix, the kind of drift
      // a stationary GPS chip shows, not the dog actually running around.
      const double stepDegrees = 0.00003; // ~3m at these latitudes
      _gpsLat += (_rng.nextDouble() - 0.5) * stepDegrees;
      _gpsLng += (_rng.nextDouble() - 0.5) * stepDegrees;
    }

    return <String, dynamic>{
      'lat': _round6(_gpsLat),
      'lng': _round6(_gpsLng),
      'fix_quality': 1,
      'satellites': 8 + _rng.nextInt(4),
      'hdop': _round(0.8 + _rng.nextDouble() * 0.8),
    };
  }

  Future<void> _simulateOutage() async {
    if (!_online || _closed) return;
    _online = false;
    _status.add(ConnStatus.reconnecting);
    await Future<void>.delayed(outageDuration);
    if (_closed) return;
    _goOnline();
  }

  double _noise(double amp) => (_rng.nextDouble() * 2 - 1) * amp;
  double _round(double v) => (v * 1000).round() / 1000;
  double _round6(double v) => (v * 1000000).round() / 1000000;

  @override
  Future<void> disconnect() async {
    _closed = true;
    _online = false;
    _frameTimer?.cancel();
    _outageTimer?.cancel();
    _status.add(ConnStatus.disconnected);
    await _frames.close();
    await _status.close();
  }
}
