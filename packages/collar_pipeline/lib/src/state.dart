import 'dart:typed_data';

import 'config.dart';

/// collar/judge/state.py の judge_state と同じ。
/// 2 つの境目（D-030）：
/// - 休息／活動：activity < restThreshold（0.4）
/// - 心拍・呼吸を測ってよい：activity < measureThreshold（0.15）の「安静」が stillSeconds 以上続く
class WindowState {
  const WindowState({
    required this.tStartMs,
    required this.tStartDevUs,
    required this.activity,
    required this.rest,
    required this.stillS,
    required this.quietS,
    required this.measureOk,
  });

  final int tStartMs;
  final int tStartDevUs;
  final double activity;
  final bool rest; // true＝'rest'、false＝'active'
  final double stillS; // 休息が続いている秒数（休息でなければ 0）
  final double quietS; // 安静が続いている秒数
  final bool measureOk;

  String get state => rest ? 'rest' : 'active';
}

double _f32(double v) => (Float32List(1)..[0] = v)[0];

List<List<int>> _runs(List<bool> mask, int a, int b) {
  final List<List<int>> out = <List<int>>[];
  int i = a;
  while (i < b) {
    if (!mask[i]) {
      i++;
      continue;
    }
    final int s = i;
    while (i < b && mask[i]) {
      i++;
    }
    out.add(<int>[s, i]);
  }
  return out;
}

class _Held {
  _Held(this.held, this.blip, this.secs);
  final List<bool> held;
  final List<bool> blip;
  final Float32List secs;
}

_Held _hold(List<bool> raw, List<int> breaks, PipelineConfig cfg) {
  final int n = raw.length;
  final double stepS = cfg.windowStepS;
  final int maxBlip = roundHalfEven(cfg.allowBlipS / stepS);
  final List<bool> held = List<bool>.of(raw);
  final List<bool> blip = List<bool>.filled(n, false);
  final Float32List secs = Float32List(n);
  final List<bool> notRaw = <bool>[for (final bool v in raw) !v];
  for (int k = 0; k + 1 < breaks.length; k++) {
    final int a = breaks[k], b = breaks[k + 1];
    // ③ はさまれた短い動き → 静止とみなす（その窓は測らない）
    for (final List<int> r in _runs(notRaw, a, b)) {
      final int s = r[0], e = r[1];
      if (s > a && e < b && (e - s) <= maxBlip) {
        for (int i = s; i < e; i++) {
          held[i] = true;
          blip[i] = true;
        }
      }
    }
    // ④ 続いている長さ：その段の始まりから、この窓の終わりまで
    for (final List<int> r in _runs(held, a, b)) {
      for (int i = r[0]; i < r[1]; i++) {
        secs[i] = (i - r[0]) * stepS + cfg.windowS;
      }
    }
  }
  return _Held(held, blip, secs);
}

List<WindowState> judgeState(List<double> activity, List<int> tStartDevUs,
    {List<int>? tStartMs, PipelineConfig cfg = const PipelineConfig(), double? threshold, double? measureThreshold,
    double? stillSeconds}) {
  final double th = _f32(threshold ?? cfg.restThreshold);
  final double mth = _f32(measureThreshold ?? cfg.measureThreshold);
  final double stillS = stillSeconds ?? cfg.stillSeconds;
  final int n = activity.length;
  final List<double> act = <double>[for (final double v in activity) _f32(v)];
  final List<int> tMs = tStartMs ?? List<int>.filled(n, -1);

  // ① 時刻が続いていない所（抜け）で分ける
  final int stepUs = roundHalfEven(cfg.windowStepS * 1e6);
  final List<int> breaks = <int>[0];
  for (int i = 0; i + 1 < n; i++) {
    if (tStartDevUs[i + 1] - tStartDevUs[i] != stepUs) breaks.add(i + 1);
  }
  breaks.add(n);

  final _Held rest = _hold(<bool>[for (final double v in act) v < th], breaks, cfg); // ② 未満が休息
  final _Held quiet = _hold(<bool>[for (final double v in act) v < mth], breaks, cfg);
  return <WindowState>[
    for (int i = 0; i < n; i++)
      WindowState(
        tStartMs: tMs[i],
        tStartDevUs: tStartDevUs[i],
        activity: act[i],
        rest: rest.held[i],
        stillS: rest.held[i] ? rest.secs[i] : 0,
        quietS: quiet.held[i] ? quiet.secs[i] : 0,
        measureOk: quiet.held[i] && !quiet.blip[i] && quiet.secs[i] >= stillS, // ⑤
      ),
  ];
}
