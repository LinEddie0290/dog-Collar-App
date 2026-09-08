import 'dart:async';
import 'dart:math';

import 'collar_data_source.dart';
import 'conn_status.dart';
import 'raw_frame.dart';

/// Synthetic collar — the priority deliverable. It lets the UI teammate build
/// and run the whole app **today**, with no hardware and no real WebSocket.
///
/// It mimics the real device closely:
///   * ~10 Hz sensor frames, hr wandering 70–120, resp, noisy IMU (az≈+1g),
///     strictly increasing seq, slowly draining battery.
///   * Occasionally emits a frame with **no hr field**, so downstream code is
///     forced to handle the nullable case (see [SensorSample]).
///   * Simulates dropouts: every [outageEvery] it goes `reconnecting` for
///     [outageDuration] and emits no frames, then `connected` again — exactly
///     the flaky-WiFi behaviour the UI must tolerate.
class FakeCollarDataSource implements CollarDataSource {
  final Duration framePeriod;
  final Duration outageEvery;
  final Duration outageDuration;
  final int? seed;

  FakeCollarDataSource({
    this.framePeriod = const Duration(milliseconds: 100),
    this.outageEvery = const Duration(seconds: 8),
    this.outageDuration = const Duration(seconds: 3),
    this.seed,
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

    // ~1 in 8 frames has no HR reading -> exercises the nullable path.
    final hasHr = _seq % 8 != 0;
    final phase = _seq / 20.0;
    final hr = (95 + 20 * sin(phase) + _noise(3)).clamp(70, 120).round();
    final resp = (20 + 6 * sin(phase / 3) + _noise(1)).clamp(8, 40).round();

    final raw = <String, dynamic>{
      'v': 1,
      'type': 'sensor',
      'ts': now + _rng.nextInt(80) - 40, // device clock drifts a little
      'seq': _seq,
      if (hasHr) 'hr': hr,
      'resp': resp,
      'imu': {
        'ax': _round(_noise(0.05)),
        'ay': _round(_noise(0.05)),
        'az': _round(1.0 + _noise(0.05)), // gravity on one axis
      },
      'battery': _battery.round(),
    };

    _frames.add(RawFrame(now, raw));
    _seq++;
    _battery = max(0, _battery - 0.01);
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
