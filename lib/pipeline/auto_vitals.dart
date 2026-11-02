/// T34-B：記録の中のデータから心拍・呼吸を測る（自動と、記録中の手動）。
///
/// 自動（D-050 B1）：処理の流れ（A）の状態で「測ってよい」（活動量 0.15 未満が 30 秒）窓が出たら、
/// その窓の開始から 60 秒を測る区間にする。状態は 15〜40 秒遅れて出るので「あとから」測る：
/// 受けた |a| を最近 3 分だけためておき、60 秒の窓が全部「測ってよい」のままなら計算する。
/// 途中で動いたら中止（理由 moved）。次の自動は、終わった測定から 10 分あける。
/// 手動（B4）：押した時刻から 60 秒。動いても止めない（品質は計算が決める）。
/// センサー（B2）：既定は基板の IMU（front）。BMI088（side）に切り替えられる（どちらに決まってもいいように）。
/// 計算は手動の測定と同じ collar_vitals の VitalsAnalyzer。
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter/foundation.dart';

typedef VitalsCompute = VitalsResult Function(List<double> magnitude, double sampleRateHz);

VitalsResult _defaultCompute(List<double> m, double fs) =>
    const VitalsAnalyzer(range: HeartRateRange.dog).analyze(m, sampleRateHz: fs);

enum AttemptStatus { measuring, done, aborted }

/// 1 回の測定。
class VitalAttempt {
  VitalAttempt({required this.trigger, required this.sensor, required this.tStartDevUs, required this.tStartMs});

  final String trigger; // auto / manual
  final String sensor; // front / side
  final int tStartDevUs;
  final int tStartMs;
  AttemptStatus status = AttemptStatus.measuring;
  VitalsResult? result;
  String? reason; // moved / data_gap / too_short / 計算の unusableReason
  int samples = 0;
  double? fs;

  double? get heartRateBpm => result?.heartRateBpm;
  double? get respirationPerMin => result?.respirationPerMin;
  bool get usable => result != null && result!.quality != VitalsQuality.unusable && result!.heartRateBpm != null;
}

class _Pt {
  const _Pt(this.tUs, this.tMs, this.mag);
  final int tUs;
  final int tMs;
  final double mag;
}

class AutoVitals extends ChangeNotifier {
  AutoVitals({
    this.sensor = 'front',
    this.enabled = true,
    this.measureS = 60,
    this.cooldown = const Duration(minutes: 10),
    this.bufferS = 180,
    this.minCoverage = 0.9,
    this.windowS = 2,
    VitalsCompute? compute,
  }) : _compute = compute ?? _defaultCompute;

  /// どのセンサーの |a| で測るか：front（基板の IMU）／side（BMI088）。
  String sensor;
  bool enabled;
  final double measureS;
  final Duration cooldown;
  final double bufferS;
  final double minCoverage;
  final double windowS;
  final VitalsCompute _compute;

  final Map<String, ListQueue<_Pt>> _buf = <String, ListQueue<_Pt>>{};
  VitalAttempt? current;
  final List<VitalAttempt> history = <VitalAttempt>[]; // 新しいものが後ろ（最大 20）
  int? _lastDoneUs; // 最後に終わった測定の終わり（首輪の時計）
  int _scannedUs = -1 << 62; // ここまでの窓は自動の候補として見た
  int _latestUs = -1 << 62;

  /// 測定が終わった（done・aborted）ときに呼ぶ。runner（記録）と履歴の保存がつなぐ。
  final List<void Function(VitalAttempt a)> finishedListeners = <void Function(VitalAttempt a)>[];

  int get _measureUs => (measureS * 1e6).round();

  /// 今の測定の進み（0〜1）。
  double get progress {
    final VitalAttempt? c = current;
    if (c == null) return 0;
    return ((_latestUs - c.tStartDevUs) / _measureUs).clamp(0.0, 1.0);
  }

  /// 次の自動測定ができるまでの秒（首輪の時計）。0 ならいつでも。
  double get cooldownLeftS {
    final int? d = _lastDoneUs;
    if (d == null) return 0;
    return math.max(0, (d + cooldown.inMicroseconds - _latestUs) / 1e6);
  }

  /// 新しいセッション（首輪の時計が変わる）。
  void reset() {
    _buf.clear();
    if (current != null) _finish(current!, AttemptStatus.aborted, 'session_end');
    current = null;
    _lastDoneUs = null;
    _scannedUs = -1 << 62;
    _latestUs = -1 << 62;
    notifyListeners();
  }

  void onSample(ImuSample x) {
    final double m = math.sqrt(x.ax * x.ax + x.ay * x.ay + x.az * x.az);
    if (m.isNaN) return;
    final ListQueue<_Pt> q = _buf.putIfAbsent(x.sensor, ListQueue<_Pt>.new);
    q.add(_Pt(x.tDevUs, x.tMs ?? -1, m));
    final int keepFrom = x.tDevUs - (bufferS * 1e6).round();
    while (q.isNotEmpty && q.first.tUs < keepFrom) {
      q.removeFirst();
    }
    if (x.tDevUs > _latestUs) _latestUs = x.tDevUs;
    final VitalAttempt? c = current;
    if (c != null && c.trigger == 'manual' && x.sensor == c.sensor && x.tDevUs >= c.tStartDevUs + _measureUs) {
      _complete(c);
    }
  }

  /// 手動（記録中）：今から 60 秒。記録していない・データがないなら false。
  bool measureNow() {
    if (current != null) return false;
    final ListQueue<_Pt>? q = _buf[sensor];
    if (q == null || q.isEmpty) return false;
    current = VitalAttempt(trigger: 'manual', sensor: sensor, tStartDevUs: q.last.tUs, tStartMs: q.last.tMs);
    notifyListeners();
    return true;
  }

  /// 状態が更新された（runner が窓を足すたびに、そのセッションの全部の窓で呼ぶ）。
  void onStates(List<WindowState> states) {
    if (states.isEmpty) return;
    final VitalAttempt? c = current;
    if (c != null && c.trigger == 'auto') {
      _checkAuto(c, states);
      return;
    }
    if (c != null || !enabled) return;
    final int? oldest = _buf[sensor]?.firstOrNull?.tUs;
    final int coolUntil = _lastDoneUs == null ? -1 << 62 : _lastDoneUs! + cooldown.inMicroseconds;
    for (final WindowState s in states) {
      if (s.tStartDevUs <= _scannedUs) continue;
      _scannedUs = s.tStartDevUs;
      if (!s.measureOk || s.tStartDevUs < coolUntil) continue;
      if (oldest == null || s.tStartDevUs < oldest) continue; // もう手元にないデータ
      final VitalAttempt a =
          VitalAttempt(trigger: 'auto', sensor: sensor, tStartDevUs: s.tStartDevUs, tStartMs: s.tStartMs);
      current = a;
      notifyListeners();
      _checkAuto(a, states);
      return;
    }
  }

  void _checkAuto(VitalAttempt a, List<WindowState> states) {
    final int lastStart = a.tStartDevUs + _measureUs - (windowS * 1e6).round();
    int covered = -1 << 62;
    for (final WindowState s in states) {
      if (s.tStartDevUs < a.tStartDevUs || s.tStartDevUs > lastStart) continue;
      if (!s.measureOk) {
        _scannedUs = s.tStartDevUs; // 動いたところより後から、また探す
        _finish(a, AttemptStatus.aborted, 'moved');
        return;
      }
      covered = s.tStartDevUs;
    }
    if (covered >= lastStart) _complete(a);
  }

  void _complete(VitalAttempt a) {
    final int t1 = a.tStartDevUs + _measureUs;
    final List<_Pt> pts = <_Pt>[
      for (final _Pt p in _buf[a.sensor] ?? ListQueue<_Pt>())
        if (p.tUs >= a.tStartDevUs && p.tUs < t1) p,
    ];
    a.samples = pts.length;
    final double? fs = estimateSampleRateHz(<int>[for (final _Pt p in pts) p.tUs]);
    a.fs = fs;
    if (fs == null || pts.length < minCoverage * fs * measureS) {
      _finish(a, AttemptStatus.done, 'data_gap');
      return;
    }
    final VitalsResult r = _compute(<double>[for (final _Pt p in pts) p.mag], fs);
    a.result = r;
    _finish(a, AttemptStatus.done, r.quality == VitalsQuality.unusable ? (r.unusableReason ?? 'unusable') : null);
  }

  void _finish(VitalAttempt a, AttemptStatus st, String? reason) {
    a.status = st;
    a.reason = reason;
    if (identical(current, a)) current = null;
    if (st == AttemptStatus.done) {
      _lastDoneUs = a.tStartDevUs + _measureUs;
      _scannedUs = math.max(_scannedUs, _lastDoneUs!);
    }
    history.add(a);
    if (history.length > 20) history.removeAt(0);
    for (final void Function(VitalAttempt a) f in List<void Function(VitalAttempt a)>.of(finishedListeners)) {
      f(a);
    }
    notifyListeners();
  }
}
