import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'dsp.dart';
import 'imu_sample.dart';

/// collar/preprocess/imu.py の preprocess_imu と同じ処理。
///
/// ① 時刻をそろえる（等間隔の格子に線形補間、角速度の零点）
/// ② 雑音を落とす（Butterworth ローパス、往復）
/// ③ 重力と動きを分ける
/// ④ 窓ごとに重力を +z に回す
/// ⑥ 2 秒の窓を 1 秒ごとに切り、CNN_FS に落とす
class PreprocessResult {
  PreprocessResult({
    required this.fsGrid,
    required this.cnnFs,
    required this.windowLen,
    required this.x,
    required this.tStartMs,
    required this.tStartDevUs,
    required this.activity,
    required this.gravity,
    required this.vitalsTMs,
    required this.vitalsTDevUs,
    required this.vitalsAMag,
    required this.validFraction,
    required this.warnings,
  });

  final double fsGrid;
  final double cnnFs;
  final int windowLen; // 窓の長さ（サンプル数、CNN_FS で）
  /// 窓ごとの [6][windowLen]（チャンネルごとに並ぶ）。ax ay az gx gy gz（重力を +z に回したあと）
  final List<Float32List> x;
  final List<int> tStartMs; // UTC がなければ -1
  final List<int> tStartDevUs;
  final Float32List activity; // 窓の動きの強さ（m/s²）
  final List<Float32List> gravity; // 窓の平均の重力 [3]
  final List<int> vitalsTMs; // 心拍・呼吸用：格子の時刻（有効な点だけ）
  final List<int> vitalsTDevUs;
  final Float32List vitalsAMag; // |a|（フィルタなし）
  final double validFraction;
  final List<String> warnings;

  int get nWindows => x.length;
}

class _Rows {
  _Rows(this.t, this.tMs, this.v);
  final List<int> t;
  final List<int?> tMs;
  final List<List<double>> v; // [n][6]
}

_Rows _firstBoot(List<ImuSample> rows, PipelineConfig cfg, List<String> warnings, String name) {
  List<ImuSample> df = rows;
  final int nNa = df.where((ImuSample s) => s.tMs == null).length;
  if (nNa > 0) {
    if (nNa == df.length) {
      return _dedup(df); // UTC がまったくない（相対時刻だけ）：そのまま
    }
    warnings.add('$name：有 $nNa 行没有 UTC 时刻（重启后），只用重启前的部分');
    df = df.where((ImuSample s) => s.tMs != null).toList();
  }
  int big = -1;
  for (int i = 0; i + 1 < df.length; i++) {
    if (df[i + 1].tDevUs - df[i].tDevUs < -cfg.rebootBackUs) {
      big = i;
      break;
    }
  }
  if (big >= 0) {
    warnings.add('$name：首轮时钟在第 ${big + 1} 行倒回（重启），只用重启前的部分');
    df = df.sublist(0, big + 1);
  }
  int nBack = 0;
  for (int i = 0; i + 1 < df.length; i++) {
    if (df[i + 1].tDevUs - df[i].tDevUs < 0) nBack++;
  }
  if (nBack > 0) {
    warnings.add('$name：时刻有 $nBack 处稍微倒回（顺序调换），已按时刻重新排序');
    final List<int> idx = List<int>.generate(df.length, (int i) => i);
    idx.sort((int a, int b) {
      final int c = df[a].tDevUs.compareTo(df[b].tDevUs);
      return c != 0 ? c : a.compareTo(b); // 安定
    });
    df = <ImuSample>[for (final int i in idx) df[i]];
  }
  final List<ImuSample> good = df.where((ImuSample s) => s.values.every((double v) => v.isFinite)).toList();
  if (good.length != df.length) {
    warnings.add('$name：有 ${df.length - good.length} 行的值是 NaN 或无穷大，已去掉');
  }
  return _dedup(good);
}

_Rows _dedup(List<ImuSample> df) {
  final Set<int> seen = <int>{};
  final List<int> t = <int>[];
  final List<int?> tMs = <int?>[];
  final List<List<double>> v = <List<double>>[];
  for (final ImuSample s in df) {
    if (seen.add(s.tDevUs)) {
      t.add(s.tDevUs);
      tMs.add(s.tMs);
      v.add(s.values);
    }
  }
  return _Rows(t, tMs, v);
}

double _nativeFs(List<int> t, PipelineConfig cfg) {
  double sum = 0;
  int n = 0;
  for (int i = 0; i + 1 < t.length; i++) {
    final int d = t[i + 1] - t[i];
    if (d > 0 && d <= cfg.maxGapMs * 1000) {
      sum += d;
      n++;
    }
  }
  return n == 0 ? double.nan : 1e6 / (sum / n);
}

double _gridFs(double fsNative, PipelineConfig cfg) =>
    fsNative >= cfg.resampleMinFs ? cfg.resampleFs : roundHalfEven(fsNative).toDouble();

/// np.interp(xq, xp, fp)：xp は増加、xq も増加（格子）。
Float64List _interp(List<int> xq, List<int> xp, List<double> fp) {
  final Float64List out = Float64List(xq.length);
  int j = 0;
  final int n = xp.length;
  for (int i = 0; i < xq.length; i++) {
    final int q = xq[i];
    if (q <= xp[0]) {
      out[i] = fp[0];
      continue;
    }
    if (q >= xp[n - 1]) {
      out[i] = fp[n - 1];
      continue;
    }
    while (j + 1 < n && xp[j + 1] <= q) {
      j++;
    }
    // xp[j] <= q < xp[j+1]
    final double x0 = xp[j].toDouble(), x1 = xp[j + 1].toDouble();
    final double slope = (fp[j + 1] - fp[j]) / (x1 - x0);
    out[i] = slope * (q - x0) + fp[j];
  }
  return out;
}

class _Grid {
  _Grid(this.fs, this.tDevUs, this.tMs, this.front, this.valid);
  final double fs;
  final List<int> tDevUs;
  final List<int> tMs;
  final List<Float64List> front; // [6][n]（列ごと）
  final List<bool> valid;
}

_Grid _align(List<ImuSample> imu, PipelineConfig cfg, List<String> warnings, {double? fs}) {
  final Map<String, List<ImuSample>> groups = <String, List<ImuSample>>{};
  for (final ImuSample s in imu) {
    groups.putIfAbsent(s.sensor, () => <ImuSample>[]).add(s);
  }
  Map<String, _Rows> sensors = <String, _Rows>{
    for (final MapEntry<String, List<ImuSample>> e in groups.entries) e.key: _firstBoot(e.value, cfg, warnings, e.key),
  };
  if (!sensors.containsKey('front') && sensors.containsKey('side')) {
    warnings.add('没有 front 的数据，改用 side 继续（质量可能下降）');
    final _Rows side = sensors.remove('side')!;
    sensors = <String, _Rows>{'front': side, ...sensors};
  }
  if (!sensors.containsKey('front')) {
    throw ArgumentError('imu 里没有 front 和 side 的数据');
  }
  final _Rows front = sensors['front']!;
  final double gfs = fs ?? _gridFs(_nativeFs(front.t, cfg), cfg);
  int start = -1 << 62, end = 1 << 62;
  for (final _Rows r in sensors.values) {
    start = math.max(start, r.t.first);
    end = math.min(end, r.t.last);
  }
  if (end <= start) throw ArgumentError('传感器之间没有重叠的时间');
  final double stepUs = 1e6 / gfs;
  final int n = ((end - start) / stepUs).truncate() + 1;
  final List<int> grid = List<int>.generate(n, (int i) => start + roundHalfEven(i * stepUs));

  final List<bool> valid = List<bool>.filled(n, true);
  final int gapUs = cfg.maxGapMs * 1000;
  List<Float64List>? frontCols;
  for (final MapEntry<String, _Rows> e in sensors.entries) {
    final _Rows r = e.value;
    if (e.key == 'front') {
      frontCols = <Float64List>[
        for (int k = 0; k < 6; k++) _interp(grid, r.t, <double>[for (final List<double> v in r.v) v[k]]),
      ];
    }
    // 大きな抜けの中の格子点は使えない
    int idx = 0;
    final int m = r.t.length;
    for (int i = 0; i < n; i++) {
      while (idx < m && r.t[idx] <= grid[i]) {
        idx++;
      }
      final int c = math.min(math.max(idx, 1), m - 1);
      if (r.t[c] - r.t[c - 1] > gapUs) valid[i] = false;
    }
  }

  final List<int> tMs = front.tMs.every((int? v) => v != null)
      ? <int>[
          for (final double v in _interp(grid, front.t, <double>[for (final int? v in front.tMs) v!.toDouble()]))
            roundHalfEven(v),
        ]
      : List<int>.filled(n, -1);
  return _Grid(gfs, grid, tMs, frontCols!, valid);
}

List<List<int>> validSegments(List<bool> valid) {
  final List<List<int>> out = <List<int>>[];
  int i = 0;
  while (i < valid.length) {
    if (!valid[i]) {
      i++;
      continue;
    }
    final int a = i;
    while (i < valid.length && valid[i]) {
      i++;
    }
    out.add(<int>[a, i]);
  }
  return out;
}

double _norm3(double a, double b, double c) => math.sqrt(a * a + b * b + c * c);

List<int>? _findStill(List<Float64List> x, double fs, List<bool> valid, PipelineConfig cfg) {
  final int n1 = roundHalfEven(fs);
  final int need = cfg.biasStillS.ceil();
  final int len = x[0].length;
  int run = 0;
  for (int k = 0; k < len ~/ n1; k++) {
    final int a = k * n1, b = (k + 1) * n1;
    bool still = true;
    for (int i = a; i < b; i++) {
      if (!valid[i]) {
        still = false;
        break;
      }
    }
    if (still) {
      final List<double> mag = <double>[for (int i = a; i < b; i++) _norm3(x[0][i], x[1][i], x[2][i])];
      still = stdPop(mag) < cfg.stillAccStd;
    }
    if (still) {
      double mx = 0;
      for (int c = 3; c < 6; c++) {
        mx = math.max(mx, stdPop(x[c], a, b));
      }
      still = mx < cfg.stillGyroStd;
    }
    run = still ? run + 1 : 0;
    if (run >= need) return <int>[(k + 1 - run) * n1, (k + 1) * n1];
  }
  return null;
}

List<List<double>> rotationToZ(List<double> g) {
  final double n = _norm3(g[0], g[1], g[2]);
  if (n < 1e-9) {
    return <List<double>>[
      <double>[1, 0, 0],
      <double>[0, 1, 0],
      <double>[0, 0, 1],
    ];
  }
  final double ux = g[0] / n, uy = g[1] / n, uz = g[2] / n;
  final double v0 = uy, v1 = -ux, v2 = 0.0; // u × z
  final double c = uz;
  if (c < -1 + 1e-9) {
    return <List<double>>[
      <double>[1, 0, 0],
      <double>[0, -1, 0],
      <double>[0, 0, -1],
    ];
  }
  final List<List<double>> vx = <List<double>>[
    <double>[0, -v2, v1],
    <double>[v2, 0, -v0],
    <double>[-v1, v0, 0],
  ];
  final List<List<double>> r = <List<double>>[
    for (int i = 0; i < 3; i++) List<double>.filled(3, 0),
  ];
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      double vv = 0;
      for (int k = 0; k < 3; k++) {
        vv += vx[i][k] * vx[k][j];
      }
      r[i][j] = (i == j ? 1.0 : 0.0) + vx[i][j] + vv / (1 + c);
    }
  }
  return r;
}

/// imu：首輪から来たサンプル（front・side）。何も渡さなければ config と同じ数字。
PreprocessResult preprocessImu(List<ImuSample> imu,
    {PipelineConfig cfg = const PipelineConfig(), double? cnnFs, double? fs, double? lpfHz, double? gravityHz}) {
  final double cfs = cnnFs ?? cfg.cnnFs;
  final double lpf = lpfHz ?? cfg.lpfHz;
  final double gHz = gravityHz ?? cfg.gravityHz;
  final List<String> warnings = <String>[];
  final _Grid grid = _align(imu, cfg, warnings, fs: fs);
  final double gfs = grid.fs;
  if (cfs > gfs) throw ArgumentError('CNN_FS（$cfs）比数据的频率（$gfs）高');

  final List<Float64List> x = grid.front;
  final int n = grid.tDevUs.length;
  final List<int>? still = _findStill(x, gfs, grid.valid, cfg);
  if (still == null) {
    warnings.add('没有连续静止 ${_g(cfg.biasStillS)} 秒的区间，角速度零点没有修正');
  } else {
    for (int c = 3; c < 6; c++) {
      double m = 0;
      for (int i = still[0]; i < still[1]; i++) {
        m += x[c][i];
      }
      m /= (still[1] - still[0]);
      for (int i = 0; i < n; i++) {
        x[c][i] -= m;
      }
    }
    final List<double> mags = <double>[for (int i = still[0]; i < still[1]; i++) _norm3(x[0][i], x[1][i], x[2][i])]
      ..sort();
    final int mm = mags.length;
    final double med = mm.isOdd ? mags[mm ~/ 2] : (mags[mm ~/ 2 - 1] + mags[mm ~/ 2]) / 2;
    if ((med / 9.80665 - 1).abs() > cfg.accCheckTol) {
      warnings.add('静止时 |a| 的中位数是 ${med.toStringAsFixed(2)} m/s²，不在 9.81 ±${(cfg.accCheckTol * 100).round()}% 以内（单位或校准有问题？）');
    }
  }

  // 心拍・呼吸用：①のあとの |a|（フィルタなし）
  final List<int> vTMs = <int>[], vTUs = <int>[];
  final List<double> vMag = <double>[];
  int nValid = 0;
  for (int i = 0; i < n; i++) {
    if (!grid.valid[i]) continue;
    nValid++;
    vTMs.add(grid.tMs[i]);
    vTUs.add(grid.tDevUs[i]);
    vMag.add(_norm3(x[0][i], x[1][i], x[2][i]));
  }

  final int win = roundHalfEven(cfg.windowS * cfs);
  final int step = roundHalfEven(cfg.windowStepS * cfs);
  final int edge = roundHalfEven(cfg.edgeDropS * cfs);
  final double ratio = gfs / cfs;
  final List<Float32List> xs = <Float32List>[];
  final List<int> t0Ms = <int>[], t0Us = <int>[];
  final List<double> act = <double>[];
  final List<Float32List> grav = <Float32List>[];
  for (final List<int> seg in validSegments(grid.valid)) {
    final int a = seg[0], b = seg[1];
    if ((b - a) < (cfg.windowS + 2 * cfg.edgeDropS) * gfs) continue;
    final List<Float64List> filt = <Float64List>[
      for (int c = 0; c < 6; c++) lowpass(Float64List.sublistView(x[c], a, b), gfs, lpf, order: cfg.lpfOrder),
    ];
    final List<Float64List> gravity = <Float64List>[
      for (int c = 0; c < 3; c++) lowpass(filt[c], gfs, gHz, order: cfg.lpfOrder),
    ];
    final List<Float64List> motion = <Float64List>[
      for (int c = 0; c < 3; c++)
        Float64List.fromList(<double>[for (int i = 0; i < b - a; i++) filt[c][i] - gravity[c][i]]),
    ];
    final List<Float64List> low = <Float64List>[
      for (int c = 0; c < 3; c++) downsample(motion[c], gfs, cfs),
      for (int c = 3; c < 6; c++) downsample(filt[c], gfs, cfs),
    ];
    final int nLow = low[0].length;
    for (int s = edge; s < nLow - win - edge + 1; s += step) {
      final int hiA = a + roundHalfEven(s * ratio);
      final int h0 = roundHalfEven(s * ratio), h1 = roundHalfEven((s + win) * ratio);
      final List<double> gMean = List<double>.filled(3, 0);
      for (int c = 0; c < 3; c++) {
        double m = 0;
        for (int i = h0; i < h1; i++) {
          m += gravity[c][i];
        }
        gMean[c] = m / (h1 - h0);
      }
      final List<List<double>> r = rotationToZ(gMean);
      final Float32List w = Float32List(6 * win);
      for (int t = 0; t < win; t++) {
        for (int c = 0; c < 3; c++) {
          double ac = 0, gy = 0;
          for (int j = 0; j < 3; j++) {
            ac += r[c][j] * low[j][s + t];
            gy += r[c][j] * low[3 + j][s + t];
          }
          w[c * win + t] = ac;
          w[(3 + c) * win + t] = gy;
        }
      }
      xs.add(w);
      t0Ms.add(grid.tMs[hiA]);
      t0Us.add(grid.tDevUs[hiA]);
      final List<double> mag = <double>[
        for (int i = h0; i < h1; i++) _norm3(motion[0][i], motion[1][i], motion[2][i]),
      ];
      act.add(stdPop(mag));
      grav.add(Float32List.fromList(gMean));
    }
  }
  if (xs.isEmpty) warnings.add('太短，没有可以用的窗口');
  return PreprocessResult(
    fsGrid: gfs,
    cnnFs: cfs,
    windowLen: win,
    x: xs,
    tStartMs: t0Ms,
    tStartDevUs: t0Us,
    activity: Float32List.fromList(act),
    gravity: grav,
    vitalsTMs: vTMs,
    vitalsTDevUs: vTUs,
    vitalsAMag: Float32List.fromList(vMag),
    validFraction: n == 0 ? 0 : nValid / n,
    warnings: warnings,
  );
}

String _g(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
