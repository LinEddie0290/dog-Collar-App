/// T34-A：受けた IMU を少しずつ collar_pipeline（Python と同じ数字が出る Dart 版）に通す。
///
/// 流れ：IMU のサンプルをためる → 約 30 秒ごとに「前の 15 秒＋新しい分」をまとめて
/// 前処理 → CNN（別の isolate で）→ 窓（2 秒・1 秒ずらし）を足す → 状態判断と出来事を
/// その接続（セッション）の全部の窓でやり直す → 保存（[PipelineStore]）。
///
/// 区切りの境目の扱い：
/// * 区切りごとに窓の位置（1 秒の中のどこから始まるか）が少しずれるので、最初の窓を
///   基準に **1 秒の格子に丸める**（ずれは 0.5 秒以内）。出来事の処理は窓がちょうど
///   1 秒おきに並んでいることを前提にしている（events.dart の _segments）。
/// * 区切りの最後の 10 秒の窓はまだ使わない（フィルターの端の影響があるため）。次の区切りで
///   前の 15 秒をつけて計算し直してから使う。止めるとき（[flush]）は最後まで使う。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:collar_data/collar_data.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'imu_input.dart';
import 'pipeline_store.dart';

/// 1 つの窓の結果（保存する形）。
class WindowResult {
  const WindowResult({
    required this.tDevUs,
    required this.tMs,
    required this.activity,
    required this.label,
    required this.prob,
  });

  final int tDevUs; // 首輪の時計（1 秒の格子に丸めたあと）
  final int tMs; // UTC ミリ秒。分からなければ -1
  final double activity; // m/s²
  final String label; // CNN のラベル
  final double prob; // CNN の確率
}

/// 別の isolate に渡す入力。中身はただのデータだけ（isolate の間で送れる）。
class ChunkInput {
  const ChunkInput({required this.samples, required this.classifier, this.fs, this.cfg = const PipelineConfig()});
  final List<ImuSample> samples;
  final WindowClassifier classifier;
  final double? fs;
  final PipelineConfig cfg;
}

class ChunkOutput {
  const ChunkOutput({required this.fsGrid, required this.windows, required this.warnings});
  final double fsGrid;
  final List<WindowResult> windows; // まだ丸めていない
  final List<String> warnings;
}

/// 1 つの区切りの計算（前処理 → CNN）。isolate の中で動く。
ChunkOutput processChunk(ChunkInput input) {
  final PreprocessResult pre = preprocessImu(input.samples, cfg: input.cfg, fs: input.fs);
  final List<CnnWindow> cnn = input.classifier.classify(pre);
  return ChunkOutput(
    fsGrid: pre.fsGrid,
    windows: <WindowResult>[
      for (int i = 0; i < pre.nWindows; i++)
        WindowResult(
          tDevUs: pre.tStartDevUs[i],
          tMs: pre.tStartMs[i],
          activity: pre.activity[i],
          label: cnn[i].label,
          prob: cnn[i].prob,
        ),
    ],
    warnings: pre.warnings,
  );
}

typedef ChunkCompute = Future<ChunkOutput> Function(ChunkInput input);

Future<ChunkOutput> _computeInIsolate(ChunkInput input) => Isolate.run(() => processChunk(input));

/// アプリに入っている CNN v1（3 軸）を読む。
Future<WindowClassifier> loadBundledClassifier() async {
  final String text = await rootBundle.loadString('assets/models/cnn_imu_v1.json');
  return WindowClassifier.fromJson(jsonDecode(text) as Map<String, dynamic>);
}

const int _unsetUs = -1 << 62;

/// 受信の様子（テスト画面 C 用）。センサーごと、首輪の時計で数える。
class SensorStats {
  int count = 0;

  /// 抜け（間が maxGapMs＝50 ms より長い）の数と、抜けた時間の合計（秒）。
  int gaps = 0;
  double gapSeconds = 0;
  double? _emaDtUs;

  /// 首輪の時計での周波数（抜けを除いた間の平均から）。
  double? get rateHz {
    final double? d = _emaDtUs;
    return d == null || d <= 0 ? null : 1e6 / d;
  }

  void _add(int dtUs, int maxGapUs) {
    count++;
    if (dtUs > maxGapUs) {
      gaps++;
      gapSeconds += dtUs / 1e6;
      return;
    }
    final double? e = _emaDtUs;
    _emaDtUs = e == null ? dtUs.toDouble() : e * 0.98 + dtUs * 0.02;
  }
}

/// 1 回の接続（首輪の時計がつながっている間）の記録。
class PipelineSession {
  PipelineSession(this.id, this.startedMs);

  final String id;
  final int startedMs;

  final List<ImuSample> _buf = <ImuSample>[];
  final Map<String, int> _lastUs = <String, int>{};
  int? _clockOffsetUs; // スマホの時計 − 首輪の時計（PetImuSample 用）
  int _latestUs = _unsetUs;
  int _processedToUs = _unsetUs;
  double? fs;
  int? anchorUs;
  int lastK = -1;
  bool _busy = false;

  final List<WindowResult> windows = <WindowResult>[];
  final List<VitalReading> vitals = <VitalReading>[];
  final List<TruthMark> truth = <TruthMark>[]; // 正解のラベル（Unity・偽のデータ・D のボタン）
  List<WindowState> states = const <WindowState>[];
  List<BehaviorEvent> events = const <BehaviorEvent>[];
}

/// 処理の流れの持ち主。UI（テスト画面・毎日のページ）はこれを見る。
class PipelineRunner extends ChangeNotifier {
  PipelineRunner({
    Future<WindowClassifier> Function()? loadClassifier,
    this.store,
    ChunkCompute? compute,
    this.cfg = const PipelineConfig(),
    this.ecfg = const EventConfig(),
    this.chunkNewS = 30,
    this.contextS = 15,
    this.tailS = 10,
    this.recentKeep = 300,
    this.dataVersionEvery = const Duration(minutes: 5),
    int Function()? nowMs,
  })  : _loadClassifier = loadClassifier ?? loadBundledClassifier,
        _compute = compute ?? _computeInIsolate,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Future<WindowClassifier> Function() _loadClassifier;
  final ChunkCompute _compute;
  final int Function() _nowMs;
  final PipelineStore? store;
  final PipelineConfig cfg;
  final EventConfig ecfg;

  /// 新しいデータがこれだけたまったら計算する（秒）。
  final double chunkNewS;

  /// 計算するときに前につける秒数（フィルターの端の影響を避ける）。
  final double contextS;

  /// 区切りの最後のこれだけの秒の窓は次の区切りまで使わない。
  final double tailS;

  /// テスト画面に出す最近の窓の数。
  final int recentKeep;

  /// 毎日のページに「読み直して」と知らせる間隔（止めたときはすぐ）。
  final Duration dataVersionEvery;

  Future<WindowClassifier>? _clf;
  Future<void> _chain = Future<void>.value();

  PipelineSession? _session;
  PipelineSession? get session => _session;

  /// 毎日のページが読み直す合図。保存した窓がまとまるたびに増える。
  final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
  DateTime _lastDataBump = DateTime.fromMillisecondsSinceEpoch(0);

  // テスト画面（C）用の数字
  int samplesIn = 0;
  int chunksDone = 0;
  int windowsTotal = 0;
  Duration lastComputeTime = Duration.zero;
  String? lastError;
  final Set<String> warnings = <String>{};
  final List<WindowResult> recent = <WindowResult>[];
  WindowState? get lastState {
    final List<WindowState> s = _session?.states ?? const <WindowState>[];
    return s.isEmpty ? null : s.last;
  }

  bool get isRunning => _session != null;

  /// センサーごとの受信の様子（今のセッション）。
  final Map<String, SensorStats> sensorStats = <String, SensorStats>{};

  /// まだ計算していない（ためている）サンプルの数。
  int get bufferedSamples => _session?._buf.length ?? 0;

  /// 首輪（BLE）のサンプルを入れる。onboardImu → front、BMI088 → side。
  /// UTC は最初のサンプルを受けたときのスマホの時計から決める。
  void addPet(PetImuSample p) {
    final String sensor = p.sensor == PetSensor.onboardImu ? 'front' : 'side';
    PipelineSession s = _session ?? startSession();
    final int? last = s._lastUs[sensor];
    if (last != null && p.monotonicUs < last - 1000000) {
      warnings.add('首輪的时钟倒退了（重启？），开始新的记录');
      unawaited(flush());
      s = startSession();
    }
    s._clockOffsetUs ??= _nowMs() * 1000 - p.monotonicUs;
    add(ImuSample(
      sensor: sensor,
      tDevUs: p.monotonicUs,
      tMs: (p.monotonicUs + s._clockOffsetUs!) ~/ 1000,
      ax: p.ax,
      ay: p.ay,
      az: p.az,
      gx: p.gx,
      gy: p.gy,
      gz: p.gz,
    ));
  }

  PipelineSession startSession() {
    final int now = _nowMs();
    final PipelineSession s = PipelineSession('s$now', now);
    _session = s;
    sensorStats.clear();
    unawaited(store?.startSession(s.id, <String, Object?>{'started_ms': now}));
    notifyListeners();
    return s;
  }

  /// 前処理の共通形式のサンプルを入れる（Unity・偽のデータもここ）。
  void add(ImuSample x) {
    PipelineSession s = _session ?? startSession();
    int? last = s._lastUs[x.sensor];
    if (last != null && x.tDevUs < last - 1000000) {
      // 首輪の時計が戻った＝再起動。今までの分を締めて新しいセッションにする。
      warnings.add('首輪的时钟倒退了（重启？），开始新的记录');
      unawaited(flush());
      s = startSession();
      last = null;
    }
    if (last != null && x.tDevUs <= last) return; // 同じ時刻・順番の入れ替わりは捨てる
    final SensorStats st = sensorStats.putIfAbsent(x.sensor, SensorStats.new);
    if (last == null) {
      st.count++;
    } else {
      st._add(x.tDevUs - last, cfg.maxGapMs * 1000);
    }
    s._lastUs[x.sensor] = x.tDevUs;
    if (s._buf.isEmpty && s.windows.isEmpty && s._processedToUs == _unsetUs) s._processedToUs = x.tDevUs;
    s._buf.add(x);
    samplesIn++;
    if (x.tDevUs > s._latestUs) s._latestUs = x.tDevUs;
    if (!s._busy && s._latestUs - s._processedToUs >= chunkNewS * 1e6 && _spanUs(s) >= _minSpanUs) {
      s._busy = true;
      _enqueue(() => _process(s, flush: false));
    }
  }

  /// 心拍・呼吸の結果を入れる（B の自動測定から）。tDevUs は首輪の時計。
  void addVital(VitalReading v) {
    final PipelineSession s = _session ?? startSession();
    s.vitals.add(v);
    unawaited(store?.appendVital(s.id, v));
  }

  /// 正解のラベル（その時刻からこの動き）。Unity・偽のデータの答え、D のボタンから。
  void addTruth(TruthMark m) {
    final PipelineSession s = _session ?? startSession();
    s.truth.add(m);
    unawaited(store?.appendTruth(s.id, m));
    notifyListeners();
  }

  /// 残りを全部計算して、このセッションを閉じる。
  Future<void> flush() {
    final PipelineSession? s = _session;
    _session = null;
    if (s == null) return _chain;
    _enqueue(() => _process(s, flush: true));
    final Future<void> done = _chain.then((_) {
      dataVersion.value++;
      _lastDataBump = DateTime.now();
      notifyListeners();
    });
    _chain = done;
    return done;
  }

  /// 計算が全部終わるまで待つ（テスト用）。
  Future<void> idle() => _chain;

  int get _minSpanUs => ((cfg.windowS + 2 * cfg.edgeDropS + 1) * 1e6).round();

  int _spanUs(PipelineSession s) => s._buf.isEmpty ? 0 : s._latestUs - s._buf.first.tDevUs;

  void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) => job()).catchError((Object e, StackTrace st) {
      lastError = e.toString();
      debugPrint('PipelineRunner：$e\n$st');
    });
  }

  Future<void> _process(PipelineSession s, {required bool flush}) async {
    try {
      final List<ImuSample> samples = List<ImuSample>.of(s._buf);
      final int latestUs = s._latestUs;
      if (samples.isEmpty || _spanUs(s) < _minSpanUs) return;
      _clf ??= _loadClassifier();
      final WindowClassifier clf = await _clf!;
      final Stopwatch sw = Stopwatch()..start();
      ChunkOutput out;
      try {
        out = await _compute(ChunkInput(samples: samples, classifier: clf, fs: s.fs, cfg: cfg));
      } on ArgumentError catch (e) {
        // 前と後ろのセンサーが重ならない・データが短いなど。次の区切りでもう一度。
        lastError = e.message.toString();
        s._processedToUs = latestUs;
        return;
      }
      lastComputeTime = sw.elapsed;
      chunksDone++;
      warnings.addAll(out.warnings.where((String w) => !w.startsWith('太短')));
      s.fs ??= out.fsGrid;

      final int windowUs = (cfg.windowS * 1e6).round();
      final int tailUs = (tailS * 1e6).round();
      final List<WindowResult> added = <WindowResult>[];
      for (final WindowResult w in out.windows) {
        s.anchorUs ??= w.tDevUs;
        final int a = s.anchorUs!;
        final int k = ((w.tDevUs - a) / 1e6).round();
        if (k <= s.lastK) continue;
        if (!flush && w.tDevUs + windowUs > latestUs - tailUs) break;
        final int t = a + k * 1000000;
        final int deltaMs = ((t - w.tDevUs) / 1000).round();
        final WindowResult snapped = WindowResult(
          tDevUs: t,
          tMs: w.tMs >= 0 ? w.tMs + deltaMs : -1,
          activity: w.activity,
          label: w.label,
          prob: w.prob,
        );
        added.add(snapped);
        s.lastK = k;
      }
      s._processedToUs = latestUs;

      // 次の区切りに要るところだけ残す
      final int contextUs = (contextS * 1e6).round();
      int keepFrom = latestUs - tailUs - windowUs - contextUs - 1000000;
      if (s.anchorUs != null) {
        final int fromAnchor = s.anchorUs! + (s.lastK + 1) * 1000000 - contextUs;
        if (fromAnchor > keepFrom) keepFrom = fromAnchor;
      }
      s._buf.removeWhere((ImuSample x) => x.tDevUs < keepFrom);

      if (added.isNotEmpty) {
        s.windows.addAll(added);
        windowsTotal += added.length;
        recent.addAll(added);
        if (recent.length > recentKeep) recent.removeRange(0, recent.length - recentKeep);
        _recomputeEvents(s);
        await store?.appendWindows(s.id, added);
      }
    } finally {
      s._busy = false;
    }
    final DateTime now = DateTime.now();
    if (!flush && now.difference(_lastDataBump) >= dataVersionEvery) {
      _lastDataBump = now;
      dataVersion.value++;
    }
    notifyListeners();
    // 計算している間にたまった分
    if (!flush && identical(_session, s) && !s._busy && s._latestUs - s._processedToUs >= chunkNewS * 1e6) {
      s._busy = true;
      _enqueue(() => _process(s, flush: false));
    }
  }

  void _recomputeEvents(PipelineSession s) {
    final EventsSnapshot r = computeEvents(s.windows, s.vitals, cfg: cfg, ecfg: ecfg);
    s.states = r.states;
    s.events = r.events;
  }

  @override
  void dispose() {
    dataVersion.dispose();
    super.dispose();
  }
}

class EventsSnapshot {
  const EventsSnapshot(this.states, this.events);
  final List<WindowState> states;
  final List<BehaviorEvent> events;
}

/// 保存した窓から状態と出来事を出す（毎日のページも同じものを使う）。
EventsSnapshot computeEvents(List<WindowResult> windows, List<VitalReading> vitals,
    {PipelineConfig cfg = const PipelineConfig(), EventConfig ecfg = const EventConfig()}) {
  if (windows.isEmpty) return const EventsSnapshot(<WindowState>[], <BehaviorEvent>[]);
  final List<int> tUs = <int>[for (final WindowResult w in windows) w.tDevUs];
  final List<int> tMs = <int>[for (final WindowResult w in windows) w.tMs];
  final List<WindowState> st =
      judgeState(<double>[for (final WindowResult w in windows) w.activity], tUs, tStartMs: tMs, cfg: cfg);
  final List<CnnWindow> cnn = <CnnWindow>[
    for (final WindowResult w in windows) CnnWindow(tStartMs: w.tMs, tStartDevUs: w.tDevUs, label: w.label, prob: w.prob),
  ];
  final EventsResult r = buildEvents(st, cnn, vitals: vitals, cfg: cfg, ecfg: ecfg);
  return EventsSnapshot(st, r.events);
}
