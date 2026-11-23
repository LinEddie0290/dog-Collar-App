import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collar_pipeline/collar_pipeline.dart' show resamplePoly, stdPop;

import 'spline.dart';
import 'vmd.dart';

/// 血圧（T38 → T44）：首輪の加速度 3 軸 → 汪磊先生のグループのモデルの入力 [32][3][900]。
/// collar-pipeline の collar/bp/convert.py（中で元の scg-drease(vmd).py を呼ぶ）と同じ手順。
class BpConfig {
  const BpConfig({
    this.recordS = 45.0,
    this.origFs = 500,
    this.len = 4000,
    this.win = 900,
    this.step = 100,
    this.splineDrop = 114,
    this.splineFs = 100,
  });

  final double recordS; // BP_RECORD_S
  final int origFs; // BP_ORIG_FS
  final int len; // BP_LEN
  final int win; // BP_WIN
  final int step; // BP_STEP
  final int splineDrop; // 元のコードで前の 114 点を捨てる
  final int splineFs; // 元のコードの 100 Hz
}

/// 動きの一番少ない [seconds] 秒の頭（点）。動き＝1 秒ごとの |a| の標準偏差、その合計が一番小さい所。
int quietestStart(List<double> ax, List<double> ay, List<double> az, double fs, {double seconds = 45.0}) {
  final int n = (seconds * fs).round();
  if (ax.length < n) throw ArgumentError('${seconds.toStringAsFixed(0)} 秒に足りない：${(ax.length / fs).toStringAsFixed(1)} 秒');
  final int per = fs.round();
  final Float64List mag = Float64List(ax.length);
  for (int i = 0; i < ax.length; i++) {
    mag[i] = math.sqrt(ax[i] * ax[i] + ay[i] * ay[i] + az[i] * az[i]);
  }
  final int nsec = mag.length ~/ per;
  final List<double> act = <double>[for (int i = 0; i < nsec; i++) stdPop(mag, i * per, (i + 1) * per)];
  final int k = seconds.round();
  if (nsec <= k) return 0;
  int best = 0;
  double bestSum = double.infinity;
  for (int s = 0; s + k <= nsec; s++) {
    double sum = 0;
    for (int i = s; i < s + k; i++) {
      sum += act[i];
    }
    if (sum < bestSum) {
      bestSum = sum;
      best = s;
    }
  }
  return best * per;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// 平均を引いて 500 Hz に（resample_poly）。fs は整数の Hz（400 など）。
List<Float64List> to500Hz(List<List<double>> axes, double fs, {int origFs = 500}) {
  final int f = fs.round();
  if ((fs - f).abs() > 1e-9) throw ArgumentError('周波数は整数の Hz にそろえてから：$fs');
  final int g = _gcd(origFs, f);
  return <Float64List>[
    for (final List<double> c in axes)
      () {
        double m = 0;
        for (final double v in c) {
          m += v;
        }
        m /= c.length;
        final List<double> z = <double>[for (final double v in c) v - m];
        return (origFs == f) ? Float64List.fromList(z) : resamplePoly(z, origFs ~/ g, f ~/ g);
      }(),
  ];
}

/// 元の spline_data_496：前の 114 点を捨て、x = 1..n のスプラインで 500 → 100 Hz。
Float64List spline496(List<double> d, {BpConfig cfg = const BpConfig()}) {
  final List<double> y = d.sublist(cfg.splineDrop);
  final int n = y.length;
  final Float64List x = Float64List.fromList(<double>[for (int i = 1; i <= n; i++) i.toDouble()]);
  final int m = (n * cfg.splineFs) ~/ cfg.origFs;
  return cubicSplineNotAKnot(x, y, linspace(1, n.toDouble(), m));
}

/// 元の resample_to_fixed_length：0〜1 の位置で、スプラインで target 点に。
Float64List resampleFixed(List<double> s, int target) {
  if (s.length == target) return Float64List.fromList(s);
  return cubicSplineNotAKnot(linspace(0, 1, s.length), s, linspace(0, 1, target));
}

/// 1 本まるごと 0〜1（最大＝最小なら全部 0）。
Float64List normalizeRecord(List<double> x) {
  double lo = double.infinity, hi = -double.infinity;
  for (final double v in x) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  final double r = hi - lo;
  return Float64List.fromList(<double>[for (final double v in x) r > 0 ? (v - lo) / r : 0.0]);
}

class BpInput {
  BpInput({required this.quietStart, required this.x4000, required this.windows, required this.vmdIterations});

  final int quietStart; // 選んだ 45 秒の頭（入力の点）
  final List<Float64List> x4000; // 3 軸 × 4000（0〜1 にする前）
  final List<Float32List> windows; // [W]（3 × 900 を軸ごとに並べたもの＝ [1,3,900] の順）
  final List<int> vmdIterations;
}

/// 1 回の測定（45 秒以上・3 軸）→ モデルの入力。重い所（VMD）は 3 軸で数秒。
BpInput bpModelInput(List<double> ax, List<double> ay, List<double> az, double fs, {BpConfig cfg = const BpConfig()}) {
  final int s0 = quietestStart(ax, ay, az, fs, seconds: cfg.recordS);
  final int n = (cfg.recordS * fs).round();
  final List<List<double>> seg = <List<double>>[
    ax.sublist(s0, s0 + n),
    ay.sublist(s0, s0 + n),
    az.sublist(s0, s0 + n),
  ];
  final List<Float64List> a500 = to500Hz(seg, fs, origFs: cfg.origFs);
  final List<int> iters = <int>[];
  final List<Float64List> x4000 = <Float64List>[];
  for (final Float64List c in a500) {
    final ({Float64List signal, int iterations}) v = vmdModeSum(c);
    iters.add(v.iterations);
    x4000.add(resampleFixed(spline496(v.signal, cfg: cfg), cfg.len));
  }
  final List<Float64List> x01 = <Float64List>[for (final Float64List c in x4000) normalizeRecord(c)];
  final List<Float32List> w = <Float32List>[];
  for (int s = 0; s <= cfg.len - cfg.win; s += cfg.step) {
    final Float32List v = Float32List(3 * cfg.win);
    for (int c = 0; c < 3; c++) {
      for (int i = 0; i < cfg.win; i++) {
        v[c * cfg.win + i] = x01[c][s + i];
      }
    }
    w.add(v);
  }
  return BpInput(quietStart: s0, x4000: x4000, windows: w, vmdIterations: iters);
}

/// モデル（1 つ）：[W] の窓 → [W] の値（mmHg）。
typedef BpModel = Future<List<double>> Function(List<Float32List> windows);

class BpResult {
  BpResult({required this.input, required this.sbp, required this.dbp, required this.sbpPerModel, required this.dbpPerModel});

  final BpInput input;
  final double sbp; // 5 分割 × 32 窓の平均
  final double dbp;
  final List<double> sbpPerModel; // 分割ごとの窓の平均
  final List<double> dbpPerModel;
}

double _mean(List<double> v) => v.isEmpty ? double.nan : v.reduce((double a, double b) => a + b) / v.length;

/// SBP・DBP（各 5 分割の平均、collar/bp/model.py の ensemble と同じ）。
Future<BpResult> estimateBp(List<double> ax, List<double> ay, List<double> az, double fs,
    {required List<BpModel> sbpModels, required List<BpModel> dbpModels, BpConfig cfg = const BpConfig()}) async {
  final BpInput inp = bpModelInput(ax, ay, az, fs, cfg: cfg);
  Future<List<List<double>>> run(List<BpModel> ms) async =>
      <List<double>>[for (final BpModel m in ms) await m(inp.windows)];
  final List<List<double>> s = await run(sbpModels), d = await run(dbpModels);
  return BpResult(
    input: inp,
    sbp: _mean(<double>[for (final List<double> r in s) ...r]),
    dbp: _mean(<double>[for (final List<double> r in d) ...r]),
    sbpPerModel: <double>[for (final List<double> r in s) _mean(r)],
    dbpPerModel: <double>[for (final List<double> r in d) _mean(r)],
  );
}
