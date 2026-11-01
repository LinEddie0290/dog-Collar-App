/// T34-F：首輪がなくても処理の流れを試すための入力。
///
/// * Unity（正轩の WebSocket、Q19・D-047）：collar-pipeline の collar/io/unity.py と同じ読み方。
/// * 偽のデータ：静止・歩く・走る・振る を決まった順にくり返す。答えが分かっているテスト用。
///
/// 首輪（BLE）は今までどおり [ContinuousMonitor] が CollarLink を使う。ここは BLE 以外。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/foundation.dart';

enum InputKind { collar, unity, fake }

/// Unity が送る正解のラベル（D の正解ラベルと同じところに入れる）。
class TruthMark {
  const TruthMark({required this.tDevUs, required this.tMs, required this.label});
  final int tDevUs;
  final int tMs;
  final String label;
}

/// BLE 以外の入力。サンプルは前処理の共通形式（m/s²・rad/s）で出す。
abstract class ImuInput extends ChangeNotifier {
  Stream<ImuSample> get samples;
  Stream<TruthMark> get marks => const Stream<TruthMark>.empty();
  Future<void> start();
  Future<void> stop();

  /// テスト画面とバーに出す 1 行。
  String get statusLine;

  /// 止まってしまった理由（なければ null）。
  String? get error;
}

// ---------------------------------------------------------------------------
// Unity

const double _g = 9.80665;
const Map<String, double> _accScale = <String, double>{'g': _g, 'm/s2': 1.0, 'm/s^2': 1.0};
const Map<String, double> _gyroScale = <String, double>{'deg/s': math.pi / 180, 'rad/s': 1.0};

/// collar/io/unity.py の UnityStream と同じ。ネットにはさわらない（テストしやすいように）。
///
/// 時刻：t_us は Unity の再生の時計 → そのまま tDevUs。UTC はスマホの時計から
/// （最初の行を受けたときの時刻＝その行の t_us）。再生が最初に戻ったら時計も合わせ直す。
class UnityStreamParser {
  UnityStreamParser({int Function()? nowMs}) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _nowMs;
  Map<String, dynamic>? hello;
  int nMsgs = 0;
  int nBad = 0;
  int seqGaps = 0;
  int rows = 0;
  int? lastSeq;
  bool ended = false;
  final List<String> errors = <String>[];
  int? _offsetUs; // UTC(µs) − t_us
  int? _lastTUs;
  final List<TruthMark> marks = <TruthMark>[];

  /// 1 つのメッセージ → サンプル（なければ空）。
  List<ImuSample> feed(String msg) {
    nMsgs++;
    try {
      final Object? j = jsonDecode(msg);
      if (j is! Map<String, dynamic>) throw const FormatException('JSON 的对象不是 {}');
      switch (j['type']) {
        case 'hello':
          final String acc = j['acc_unit'] as String? ?? 'g';
          final String gyr = j['gyro_unit'] as String? ?? 'deg/s';
          if (!_accScale.containsKey(acc)) throw FormatException('加速度的单位不认识：$acc');
          if (!_gyroScale.containsKey(gyr)) throw FormatException('角速度的单位不认识：$gyr');
          hello = j;
          lastSeq = null;
          return const <ImuSample>[];
        case 'imu':
          return _imu(j);
        case 'label':
          final int t = (j['t_us'] as num).toInt();
          marks.add(TruthMark(tDevUs: t, tMs: _tMs(t), label: j['label'].toString()));
          return const <ImuSample>[];
        case 'end':
          ended = true;
          return const <ImuSample>[];
        default:
          throw FormatException('不认识的 type：${j['type']}');
      }
    } on Object catch (e) {
      // FormatException・型の違い（TypeError）など、壊れたメッセージは数えて飛ばす
      nBad++;
      if (errors.length < 20) errors.add(e.toString());
      return const <ImuSample>[];
    }
  }

  int _tMs(int tUs) {
    _offsetUs ??= _nowMs() * 1000 - tUs;
    return (tUs + _offsetUs!) ~/ 1000;
  }

  List<ImuSample> _imu(Map<String, dynamic> m) {
    final Map<String, dynamic>? h = hello;
    if (h == null) throw const FormatException('hello 之前来了 imu');
    final int seq = (m['seq'] as num).toInt();
    final int? ls = lastSeq;
    if (ls != null && seq > ls + 1) seqGaps += seq - ls - 1;
    lastSeq = seq;
    final double accS = _accScale[h['acc_unit'] as String? ?? 'g']!;
    final double gyrS = _gyroScale[h['gyro_unit'] as String? ?? 'deg/s']!;
    final String sensor = h['sensor'] as String? ?? 'front';
    final List<dynamic> rs = m['rows'] as List<dynamic>;
    final List<ImuSample> out = <ImuSample>[];
    for (final dynamic r in rs) {
      final List<dynamic> v = r as List<dynamic>;
      if (v.length != 7) throw FormatException('一行应该是 7 个数，来了 ${v.length} 个');
      final int t = (v[0] as num).round();
      final int? last = _lastTUs;
      if (last != null && t < last - 1000000) _offsetUs = null; // 再生が最初に戻った
      _lastTUs = t;
      out.add(ImuSample(
        sensor: sensor,
        tDevUs: t,
        tMs: _tMs(t),
        ax: (v[1] as num).toDouble() * accS,
        ay: (v[2] as num).toDouble() * accS,
        az: (v[3] as num).toDouble() * accS,
        gx: (v[4] as num).toDouble() * gyrS,
        gy: (v[5] as num).toDouble() * gyrS,
        gz: (v[6] as num).toDouble() * gyrS,
      ));
    }
    rows += out.length;
    return out;
  }
}

/// 正轩の Unity（WebSocket サーバー）につなぐ。切れたら 2 秒おきにつなぎ直す（止めるまで）。
class UnityImuInput extends ImuInput {
  UnityImuInput(this.url, {this.retry = const Duration(seconds: 2), int Function()? nowMs})
      : parser = UnityStreamParser(nowMs: nowMs);

  final String url;
  final Duration retry;
  final UnityStreamParser parser;

  final StreamController<ImuSample> _out = StreamController<ImuSample>.broadcast();
  final StreamController<TruthMark> _marks = StreamController<TruthMark>.broadcast();
  WebSocket? _ws;
  bool _running = false;
  bool connected = false;
  bool _disposed = false;
  int reconnects = 0;
  String? _error;

  @override
  Stream<ImuSample> get samples => _out.stream;
  @override
  Stream<TruthMark> get marks => _marks.stream;
  @override
  String? get error => _error;

  @override
  String get statusLine {
    final String st = connected ? '已连接' : '连接中…';
    return 'Unity $st　${parser.rows} 行　缺 ${parser.seqGaps} 条　坏 ${parser.nBad} 条'
        '${reconnects > 0 ? '　重连 $reconnects 次' : ''}';
  }

  /// 最初の接続が成功するまで待つ。失敗したら例外（URL の間違いにすぐ気づけるように）。
  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _error = null;
    try {
      await _connect();
    } on Object catch (e) {
      _running = false;
      _error = 'Unity 连不上：$e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _connect() async {
    final WebSocket ws = await WebSocket.connect(url).timeout(const Duration(seconds: 5));
    if (_disposed || !_running) {
      await ws.close();
      return;
    }
    _ws = ws;
    connected = true;
    notifyListeners();
    ws.listen(
      (dynamic msg) {
        final String text = msg is String ? msg : utf8.decode(msg as List<int>);
        final int nMarks = parser.marks.length;
        for (final ImuSample s in parser.feed(text)) {
          _out.add(s);
        }
        for (int i = nMarks; i < parser.marks.length; i++) {
          _marks.add(parser.marks[i]);
        }
      },
      onDone: _onDropped,
      onError: (Object e) => _onDropped(),
      cancelOnError: true,
    );
  }

  void _onDropped() {
    connected = false;
    _ws = null;
    if (_disposed) return;
    notifyListeners();
    if (!_running) return;
    Future<void>.delayed(retry, () async {
      if (!_running || connected) return;
      reconnects++;
      try {
        await _connect();
      } on Object {
        _onDropped();
      }
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _ws?.close();
    _ws = null;
    connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _ws?.close();
    _out.close();
    _marks.close();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// 偽のデータ

/// 1 区切りの動き。
class FakePhase {
  const FakePhase(this.label, this.seconds);
  final String label; // still / walk / run / shake
  final double seconds;
}

/// 決まった順にくり返す（1 回 4 分 30 秒）。テスト計画の「静止 60 → 歩く 30 → 静止 60」を含む。
const List<FakePhase> defaultFakeScenario = <FakePhase>[
  FakePhase('still', 60),
  FakePhase('walk', 30),
  FakePhase('still', 60),
  FakePhase('run', 20),
  FakePhase('still', 40),
  FakePhase('shake', 4),
  FakePhase('still', 56),
];

/// 偽の IMU（104 Hz、首輪の基板の IMU と同じ速さ）。同じ seed なら同じ値。
class FakeImuGenerator {
  FakeImuGenerator({
    this.fs = 104,
    this.scenario = defaultFakeScenario,
    int seed = 1,
    required this.t0Ms,
    this.t0Us = 1000000,
  }) : _rng = math.Random(seed);

  final double fs;
  final List<FakePhase> scenario;
  final int t0Ms;
  final int t0Us;
  final math.Random _rng;
  int _i = 0;

  double get cycleS => scenario.fold(0.0, (double a, FakePhase p) => a + p.seconds);

  /// 時刻 t（秒、最初から）の動き。
  String labelAt(double t) {
    double x = t % cycleS;
    for (final FakePhase p in scenario) {
      if (x < p.seconds) return p.label;
      x -= p.seconds;
    }
    return scenario.last.label;
  }

  double _n() {
    final double u = math.max(_rng.nextDouble(), 1e-12), w = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * w);
  }

  /// 経った時間 [seconds] までのサンプルを全部出す。
  List<ImuSample> until(double seconds) {
    final List<ImuSample> out = <ImuSample>[];
    while (_i / fs < seconds) {
      out.add(_sample(_i));
      _i++;
    }
    return out;
  }

  ImuSample _sample(int i) {
    final double t = i / fs;
    final double w = 2 * math.pi * t;
    double ax = 0.02 * _n(), ay = 0.02 * _n(), az = _g + 0.02 * _n();
    double gx = 0.002 * _n(), gy = 0.002 * _n(), gz = 0.002 * _n();
    switch (labelAt(t)) {
      case 'walk':
        ax += 3.0 * math.sin(w + 0.3);
        ay += 1.5 * math.sin(2 * w + 1.0);
        az += 4.0 * math.sin(2 * w);
        gx += 0.5 * math.sin(w);
        gy += 0.8 * math.sin(2 * w);
      case 'run':
        ax += 6.0 * math.sin(1.5 * w + 0.3);
        ay += 3.0 * math.sin(3 * w + 1.0);
        az += 9.0 * math.sin(3 * w);
        gx += 1.2 * math.sin(1.5 * w);
        gy += 2.0 * math.sin(3 * w);
      case 'shake':
        ay += 12.0 * math.sin(5 * w);
        gx += 15.0 * math.sin(5 * w);
    }
    final int us = t0Us + (i * 1e6 / fs).round();
    return ImuSample(
      sensor: 'front',
      tDevUs: us,
      tMs: t0Ms + (us - t0Us) ~/ 1000,
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
    );
  }
}

/// 偽のデータを時計に合わせて流す。[speed] 倍で速く流せる（10 倍なら 1 日分が 2.4 時間）。
class FakeImuInput extends ImuInput {
  FakeImuInput({this.speed = 1, int? seed, int Function()? nowMs, this.tick = const Duration(milliseconds: 100)})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _seed = seed ?? 1;

  final double speed;
  final Duration tick;
  final int Function() _nowMs;
  final int _seed;

  final StreamController<ImuSample> _out = StreamController<ImuSample>.broadcast();
  final StreamController<TruthMark> _marks = StreamController<TruthMark>.broadcast();
  FakeImuGenerator? gen;
  Timer? _timer;
  int _startMs = 0;
  int sent = 0;
  String? _lastLabel;

  @override
  Stream<ImuSample> get samples => _out.stream;

  /// 偽のデータの答え（いつ何をしているか）。D の正解ラベルと同じ形。
  @override
  Stream<TruthMark> get marks => _marks.stream;
  @override
  String? get error => null;

  double get elapsedS => (_nowMs() - _startMs) / 1000 * speed;

  @override
  String get statusLine {
    final FakeImuGenerator? g = gen;
    final String now = g == null ? '' : '　现在：${g.labelAt(elapsedS)}';
    return '模拟数据 ×${speed.toStringAsFixed(speed < 10 ? 1 : 0)}　$sent 个样本$now';
  }

  @override
  Future<void> start() async {
    if (_timer != null) return;
    _startMs = _nowMs();
    gen = FakeImuGenerator(seed: _seed, t0Ms: _startMs);
    _timer = Timer.periodic(tick, (_) => pump());
    notifyListeners();
  }

  /// 今の時刻までのサンプルを出す（タイマーから。テストでは直接呼ぶ）。
  void pump() {
    final FakeImuGenerator? g = gen;
    if (g == null) return;
    final List<ImuSample> xs = g.until(elapsedS);
    for (final ImuSample s in xs) {
      final String label = g.labelAt((s.tDevUs - g.t0Us) / 1e6);
      if (label != _lastLabel) {
        _lastLabel = label;
        _marks.add(TruthMark(tDevUs: s.tDevUs, tMs: s.tMs ?? -1, label: label));
      }
      _out.add(s);
    }
    sent += xs.length;
    if (xs.isNotEmpty) notifyListeners();
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    pump();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _out.close();
    _marks.close();
    super.dispose();
  }
}
