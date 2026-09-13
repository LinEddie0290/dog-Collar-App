/// One heart-rate measurement, from tapping the button to a saved record.
///
/// The whole flow lives here so the UI stays a thin layer: connect, configure
/// the device, collect, analyse live, analyse finally, hand the result to the
/// history store.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collar_data/collar_data.dart';
import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter/foundation.dart';

import '../data/ble_collar_data_source.dart';
import '../data/measurement_record.dart';
import '../data/measurement_store.dart';
import 'collar_link.dart';

/// 測定そのものの段階。**接続の状態は含めない。**
///
/// 以前は connecting をここにも持っていたため、接続をキャンセルしても
/// セッション側が connecting のまま残り、ボタンが「しばらくお待ちください」で
/// 固まる不具合が出た。接続状態の持ち主は [CollarLink] だけにしている。
enum SessionPhase {
  idle,

  /// 接続を待っている段階。実際の接続状態は [CollarLink] を見る。
  preparing,

  /// Collecting. A live estimate appears once enough samples have arrived.
  measuring,

  /// Running the final analysis over the whole window.
  analyzing,
  done,
  failed,
}

class VitalsSession extends ChangeNotifier {
  VitalsSession({
    required this.store,
    required this.link,
    this.analyzer = const VitalsAnalyzer(range: HeartRateRange.dog),
    this.targetDuration = const Duration(seconds: 60),
    this.liveUpdateInterval = const Duration(seconds: 1),
    this.waveUpdateInterval = const Duration(milliseconds: 100),
    this.waveSeconds = 5.0,
    this.liveMinSeconds = 8.0,
    this.maxDuration = const Duration(minutes: 10),
  });

  final MeasurementStore store;

  /// The connection is owned elsewhere and outlives a measurement, so several
  /// measurements can run over one link without re-scanning.
  final CollarLink link;

  final VitalsAnalyzer analyzer;

  /// How long a measurement is meant to run. The button stays available so the
  /// user can stop early or let it run on — this is the point at which the UI
  /// says "done", not a hard cut-off.
  final Duration targetDuration;

  /// How often the live estimate is recomputed. Every 3 s rather than every
  /// frame: at 104 Hz the analysis would otherwise run 104 times a second for a
  /// number that cannot meaningfully change that fast.
  final Duration liveUpdateInterval;

  /// 波形の描き替え間隔。10 fps。心拍は 8–40 Hz なので波形そのものは
  /// もっと速く動くが、画面を 10 fps で横に流せば「動いている」ことは伝わる。
  /// これ以上速くしても、帯域通過フィルタを毎回かけ直すぶんが無駄になる。
  final Duration waveUpdateInterval;

  /// 画面に出す波形の長さ(秒)。5秒あれば安静時で6拍前後入る。
  final double waveSeconds;

  /// 途中の推定値を出し始める最短の長さ(秒)。保存する測定は
  /// [VitalsAnalyzer.minDurationSeconds] = 15秒だが、画面の数字は待たせたく
  /// ないので短くしてある。8秒 = 50 bpm でも約6周期。
  final double liveMinSeconds;

  /// Hard stop, so a forgotten measurement cannot fill memory. 10 minutes at
  /// 104 Hz is about 62,000 samples — a few hundred kilobytes, fine to hold.
  final Duration maxDuration;

  SessionPhase phase = SessionPhase.idle;
  String? errorMessage;

  StreamSubscription<PetImuSample>? _imuSub;
  Timer? _liveTimer;
  Timer? _waveTimer;
  Timer? _ticker;

  DateTime? _startedAt;

  /// Accelerometer magnitude, and the device's own microsecond timestamps.
  ///
  /// Both are kept because the *nominal* rate and the real one differ: the
  /// firmware reported 417 Hz against a nominal 416, and the effective rate is
  /// what the filters must be told. It is derived from these timestamps rather
  /// than assumed.
  final List<double> _magnitude = <double>[];
  final List<int> _deviceUs = <int>[];

  /// 直近 [waveSeconds] 秒の帯域通過後の波形。画面に流すためのもの。
  ///
  /// 生の加速度ではなく 8–40 Hz を通したあとの信号を出す。生のままだと
  /// 重力(9.8)と体の揺れが支配的で、心拍は線の太さに埋もれて見えない。
  List<double> liveWave = const <double>[];

  /// [liveWave] の中での拍の位置(インデックス)。丸を打つために使う。
  List<int> liveBeatIndices = const <int>[];

  /// [liveWave] が何秒ぶんか。軸の目盛りに使う。
  double liveWaveSeconds = 0;

  VitalsResult? liveResult;
  VitalsResult? finalResult;
  MeasurementRecord? savedRecord;

  /// Samples whose spacing was more than twice the median — a dropped BLE
  /// notification. Reported with the result: gaps break the beat intervals, so
  /// a measurement with many of them is not trustworthy.
  int gapCount = 0;

  int get sampleCount => _magnitude.length;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  bool get isBusy =>
      phase == SessionPhase.preparing ||
      phase == SessionPhase.measuring ||
      phase == SessionPhase.analyzing;

  /// Fraction of [targetDuration] collected, 0..1, for a progress ring.
  double get progress => _startedAt == null
      ? 0
      : (elapsed.inMilliseconds / targetDuration.inMilliseconds)
          .clamp(0.0, 1.0);

  /// The sampling rate actually observed, or null before enough samples.
  double? get effectiveSampleRateHz {
    if (_deviceUs.length < 32) return null;
    final List<int> steps = <int>[];
    for (int i = 1; i < _deviceUs.length; i++) {
      final int d = _deviceUs[i] - _deviceUs[i - 1];
      if (d > 0 && d < 1000000) steps.add(d);
    }
    if (steps.isEmpty) return null;
    steps.sort();
    final int median = steps[steps.length ~/ 2];
    return median <= 0 ? null : 1000000 / median;
  }

  /// 測定を開始する。未接続なら接続も行う。
  ///
  /// 中央のボタン1つで「接続 → 測定」まで進むのが望ましい操作なので、
  /// 接続の面倒もここで見る。ただし接続の*状態*は [CollarLink] が持ち、
  /// ここでは持たない。二重に持つと片方だけ取り残される。
  Future<void> start({String? remoteId}) async {
    if (isBusy) return;
    _reset();
    errorMessage = null;
    phase = SessionPhase.preparing;
    notifyListeners();

    // 既存の接続を使い回す。接続は最大15秒のスキャンを含むので、
    // 2回目の測定でそれを払う必要はない。
    if (!link.isConnected) {
      await link.connect(remoteId: remoteId);
      if (!link.isConnected) {
        // 失敗もキャンセルも、理由はリンクが持っている。
        errorMessage = link.errorMessage;
        phase = SessionPhase.idle;
        notifyListeners();
        return;
      }
    }

    final BleCollarDataSource? src = link.source;
    if (src == null) {
      errorMessage = 'link_lost';
      phase = SessionPhase.idle;
      notifyListeners();
      return;
    }

    try {
      // STOP → SET_CONFIG → START。接続しただけでは採取を始めないので、
      // 測定のたびに必要なセンサー構成を明示する。
      await src.startStreaming();
    } on Exception catch (e) {
      errorMessage = friendlyError(e);
      phase = SessionPhase.idle;
      notifyListeners();
      return;
    }

    _startedAt = DateTime.now();
    phase = SessionPhase.measuring;
    _imuSub = src.imuSamples.listen(_onSample);
    _liveTimer = Timer.periodic(liveUpdateInterval, (_) => _recomputeLive());
    _waveTimer = Timer.periodic(waveUpdateInterval, (_) => _recomputeWave());
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!link.isConnected) {
        // 測定中に首輪が離れた。取れた分は残して締める。
        stop();
        return;
      }
      if (elapsed >= maxDuration) {
        stop();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 中央ボタンの唯一の入口。押すたびに開始と停止が入れ替わる。
  ///
  /// 準備中（接続待ち）に押した場合は取りやめる。スキャンに最大15秒、
  /// 接続に最大20秒かかるので、待たされている最中に抜け出せることが要る。
  Future<void> toggle({String? remoteId}) async {
    switch (phase) {
      case SessionPhase.measuring:
        await stop();
      case SessionPhase.preparing:
        await abort();
      case SessionPhase.analyzing:
        return; // 解析は数十ミリ秒で終わるので触らせない
      case SessionPhase.idle:
      case SessionPhase.done:
      case SessionPhase.failed:
        await start(remoteId: remoteId);
    }
  }

  /// 準備中の取りやめ。接続も切る。
  Future<void> abort() async {
    _liveTimer?.cancel();
    _waveTimer?.cancel();
    _ticker?.cancel();
    await _imuSub?.cancel();
    _imuSub = null;
    await link.disconnect();
    phase = SessionPhase.idle;
    errorMessage = null;
    notifyListeners();
  }

  void _onSample(PetImuSample s) {
    final double m =
        math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    if (_deviceUs.isNotEmpty) {
      final int d = s.monotonicUs - _deviceUs.last;
      final double? fs = effectiveSampleRateHz;
      if (fs != null && d > 2 * (1000000 / fs)) gapCount++;
    }
    _magnitude.add(m);
    _deviceUs.add(s.monotonicUs);
  }

  void _recomputeLive() {
    final double? fs = effectiveSampleRateHz;
    if (fs == null) return;
    if (_magnitude.length < fs * liveMinSeconds) return;
    // Analyse the most recent 30 s: long enough for a stable estimate, short
    // enough that the number follows the animal instead of averaging away a
    // change that happened 5 minutes ago.
    final int window = (fs * 30).round();
    final List<double> slice = _magnitude.length > window
        ? _magnitude.sublist(_magnitude.length - window)
        : _magnitude;
    liveResult =
        analyzer.analyze(slice, sampleRateHz: fs, minSeconds: liveMinSeconds);
    notifyListeners();
  }

  /// 直近の窓だけを帯域通過させて、画面に流す波形を作る。
  ///
  /// 全区間を毎回フィルタし直すと 60 秒 × 104 Hz で 6240 点になり、10 fps
  /// では間に合わない。窓は 5 秒 = 520 点なので、10 fps でも十分軽い。
  void _recomputeWave() {
    final double? fs = effectiveSampleRateHz;
    if (fs == null || fs < VitalsAnalyzer.minSampleRateHz) return;
    final int window = (fs * waveSeconds).round();
    if (_magnitude.length < window ~/ 4) return; // 出せるほど溜まっていない

    final List<double> slice = _magnitude.length > window
        ? _magnitude.sublist(_magnitude.length - window)
        : List<double>.of(_magnitude);

    // 帯域はナイキスト内に収める。解析側と同じ決め方をする。
    final double nyquist = fs / 2;
    final double hi = math.min(40.0, nyquist * 0.9);
    final double lo = math.min(8.0, hi * 0.5);
    final List<double> band =
        bandPass(slice, sampleRateHz: fs, lowHz: lo, highHz: hi);

    // 拍の位置は包絡線の山。間隔の下限は、いま推定できている心拍から決める。
    // 推定がまだ無いときは 220 bpm 相当(=最短間隔)を使い、拾いすぎを防ぐ。
    final List<double> env = envelope(band, sampleRateHz: fs);
    double sumSq = 0;
    for (final double v in env) {
      sumSq += v * v;
    }
    final double rms = env.isEmpty ? 0 : math.sqrt(sumSq / env.length);
    final double? bpm = liveResult?.heartRateBpm;
    final int minDistance =
        ((60 / (bpm ?? 220.0)) * fs * 0.6).round().clamp(2, band.length);

    liveWave = band;
    liveWaveSeconds = band.length / fs;
    liveBeatIndices = rms <= 0
        ? const <int>[]
        : findPeaks(env, minDistance: minDistance, minProminence: rms * 0.5);
    notifyListeners();
  }

  /// Stops collecting, runs the final analysis and saves it.
  Future<void> stop({String? note, String? posture}) async {
    if (phase != SessionPhase.measuring) return;
    phase = SessionPhase.analyzing;
    _liveTimer?.cancel();
    _waveTimer?.cancel();
    _ticker?.cancel();
    notifyListeners();

    await _imuSub?.cancel();
    _imuSub = null;

    final double? fs = effectiveSampleRateHz;
    if (fs == null || _magnitude.length < fs * VitalsAnalyzer.minDurationSeconds) {
      errorMessage =
          'too_short|${VitalsAnalyzer.minDurationSeconds.toStringAsFixed(0)}';
      phase = SessionPhase.idle;
      notifyListeners();
      await _teardown();
      await link.disconnect();
      notifyListeners();
      return;
    }

    finalResult = analyzer.analyze(_magnitude, sampleRateHz: fs);

    savedRecord = MeasurementRecord.fromResult(
      startedAt: _startedAt!,
      result: finalResult!,
      gapCount: gapCount,
      sampleCount: _magnitude.length,
      imuRateHz: link.activeImuRateHz,
      receiveErrors: link.source?.receiveErrors ?? 0,
      note: note,
      posture: posture,
    );
    try {
      await store.save(savedRecord!);
    } on Exception catch (e) {
      // The measurement itself succeeded; surface the save failure without
      // throwing the result away.
      errorMessage = 'save_failed|$e';
    }

    phase = SessionPhase.done;
    notifyListeners();
    // ボタン1つで完結させるため、停止で接続も切る。繋いだままにしたい場合は
    // 首輪画面から改めて選ぶ。
    await _teardown();
    await link.disconnect();
    notifyListeners();
  }

  /// Stops the collar collecting but **keeps the connection**.
  ///
  /// Disconnecting is the user's decision, made on the devices screen — not a
  /// side effect of finishing a measurement.
  Future<void> _teardown() async {
    final BleCollarDataSource? src = link.source;
    if (src == null) return;
    try {
      if (src.isReady) await src.stopCollecting();
    } on Exception {
      // already stopped, or the link went away
    }
  }

  void _reset() {
    _magnitude.clear();
    _deviceUs.clear();
    gapCount = 0;
    liveResult = null;
    liveWave = const <double>[];
    liveBeatIndices = const <int>[];
    liveWaveSeconds = 0;
    finalResult = null;
    savedRecord = null;
    _startedAt = null;
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _waveTimer?.cancel();
    _ticker?.cancel();
    _imuSub?.cancel();
    super.dispose();
  }
}
