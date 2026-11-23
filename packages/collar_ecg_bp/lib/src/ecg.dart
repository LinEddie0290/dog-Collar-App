import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collar_pipeline/collar_pipeline.dart' show downsample, lowpass, sosfiltfilt, stdPop, Sos;

import 'rpeaks.dart';

/// 心電図（T37 → T44）：首輪の加速度 3 軸 → 汪磊先生のグループのモデルの入力（150 Hz・1 軸・1024 点・窓ごとに 0〜1）。
/// collar-pipeline の collar/ecg/convert.py・model.py と同じ手順（答えは test/fixtures/ecg_bp_golden.json）。
class EcgConfig {
  const EcgConfig({
    this.fs = 150.0,
    this.win = 1024,
    this.step = 256,
    this.highpassHz = 0.5,
    this.maxActivityMs2 = 0.15,
    this.gravityHz = 0.3,
  });

  final double fs; // ECG_FS
  final int win; // ECG_WIN
  final int step; // ECG_STEP
  final double highpassHz; // ECG_HIGHPASS_HZ
  final double maxActivityMs2; // ECG_MAX_ACTIVITY_MS2（null にはしない。App では動いた窓は必ず除く）
  final double gravityHz; // GRAVITY_HZ（窓の活動量の重力分け）
}

/// 1 つの組み合わせ。axis：x/y/z/mag（pca は App ではまだ使わない）、highpass：0.5 Hz の高域通過、sign：+1/−1。
class EcgSettings {
  const EcgSettings({this.axis = 'x', this.highpass = false, this.sign = -1});

  final String axis;
  final bool highpass;
  final int sign;

  static const List<String> axes = <String>['x', 'y', 'z', 'mag'];

  String get name => '${axis}_${highpass ? 'hp' : 'raw'}_${sign > 0 ? '+' : '-'}';
}

class EcgInput {
  EcgInput({required this.windows, required this.starts, required this.activity, required this.signal, required this.nAll});

  final List<Float32List> windows; // [W][1024]、0〜1（符号をかけたあと）
  final List<int> starts; // 窓の頭（150 Hz の点）
  final List<double> activity; // 使った窓の活動量
  final Float64List signal; // 150 Hz の 1 軸（0〜1 にする前）
  final int nAll; // 切った窓の数（除く前）
}

/// scipy.signal.butter(2, cutoff, btype='high', fs=fs, output='sos')。
Sos butterHigh2Sos(double cutoff, double fs) {
  final double wn = 2 * cutoff / fs;
  const double fs2 = 2.0, fs4 = 4.0;
  final double warped = 2 * fs2 * math.tan(math.pi * wn / fs2);
  // アナログの低域のもとの極（2 次）：exp(±i·3π/4)
  final double pr = -math.cos(math.pi / 4), pi = math.sin(math.pi / 4);
  // 低域 → 高域：p' = warped / p（共役の組）。|p| = 1 なので warped·conj(p)
  final double hr = warped * pr, hi = -warped * pi; // 1 つ目（もう 1 つはその共役）
  // k = real(1 / (p0·p1)) = 1（|p| = 1）
  double k = 1.0;
  // 双一次変換：z = (fs4 + p)/(fs4 − p)、k *= real(fs4² / ((fs4 − p0)(fs4 − p1)))
  final double ar = fs4 - hr, ai = -hi; // fs4 − p0
  final double den = ar * ar + ai * ai; // |fs4 − p0|²
  k *= fs4 * fs4 / den;
  // z0 = (fs4 + p0)/(fs4 − p0)
  final double nr = fs4 + hr, ni = hi;
  final double zr = (nr * ar + ni * ai) / den, zi = (ni * ar - nr * ai) / den;
  return <List<double>>[
    <double>[k, -2 * k, k, 1.0, -2 * zr, zr * zr + zi * zi],
  ];
}

Float64List highpass2(List<double> x, double fs, double cutoff) {
  final Sos sos = butterHigh2Sos(cutoff, fs);
  // scipy の既定の padlen：3·(2·区間の数 + 1 − 0) = 9
  return sosfiltfilt(sos, x, math.min(9, x.length - 1));
}

/// 3 軸（ax, ay, az：m/s²、fs Hz）→ 1 軸。
Float64List selectAxis(List<double> ax, List<double> ay, List<double> az, String axis) {
  switch (axis) {
    case 'x':
      return Float64List.fromList(ax);
    case 'y':
      return Float64List.fromList(ay);
    case 'z':
      return Float64List.fromList(az);
    case 'mag':
      return Float64List.fromList(<double>[
        for (int i = 0; i < ax.length; i++) math.sqrt(ax[i] * ax[i] + ay[i] * ay[i] + az[i] * az[i]),
      ]);
  }
  throw ArgumentError('使えない軸：$axis（${EcgSettings.axes}）');
}

List<int> windowStarts(int n, {int win = 1024, int step = 256}) =>
    n < win ? <int>[] : <int>[for (int s = 0; s <= n - win; s += step) s];

/// Python の round（0.5 は偶数へ）。
int roundHalfEvenInt(double x) {
  final double f = x.floorToDouble();
  final double d = x - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

/// 窓ごとの活動量：重力（0.3 Hz の低域）を引いた |運動| の標準偏差（collar/ecg/convert.py の window_activity）。
List<double> windowActivity(List<double> ax, List<double> ay, List<double> az, double fs, List<int> starts,
    {EcgConfig cfg = const EcgConfig()}) {
  final List<List<double>> a = <List<double>>[ax, ay, az];
  final List<Float64List> g = <Float64List>[for (final List<double> c in a) lowpass(c, fs, cfg.gravityHz, order: 4)];
  final int n = ax.length;
  final Float64List mag = Float64List(n);
  for (int i = 0; i < n; i++) {
    final double x = a[0][i] - g[0][i], y = a[1][i] - g[1][i], z = a[2][i] - g[2][i];
    mag[i] = math.sqrt(x * x + y * y + z * z);
  }
  final double ratio = fs / cfg.fs;
  return <double>[
    for (final int s in starts)
      stdPop(mag, roundHalfEvenInt(s * ratio), math.min(roundHalfEvenInt((s + cfg.win) * ratio), n)),
  ];
}

/// 1 回の測定（例：60 秒・400 Hz・3 軸）→ モデルの入力。
EcgInput ecgModelInput(List<double> ax, List<double> ay, List<double> az, double fs, EcgSettings st,
    {EcgConfig cfg = const EcgConfig()}) {
  if (fs < cfg.fs) throw ArgumentError('周波数 $fs Hz は ${cfg.fs} Hz より低い');
  Float64List x = selectAxis(ax, ay, az, st.axis);
  if (st.highpass) x = highpass2(x, fs, cfg.highpassHz);
  final Float64List sig = downsample(x, fs, cfg.fs);
  final List<int> starts = windowStarts(sig.length, win: cfg.win, step: cfg.step);
  final List<double> act = windowActivity(ax, ay, az, fs, starts, cfg: cfg);
  final List<Float32List> w = <Float32List>[];
  final List<int> ks = <int>[];
  final List<double> ka = <double>[];
  for (int k = 0; k < starts.length; k++) {
    if (act[k] > cfg.maxActivityMs2) continue;
    final int s = starts[k];
    double lo = double.infinity, hi = -double.infinity;
    for (int i = s; i < s + cfg.win; i++) {
      if (sig[i] < lo) lo = sig[i];
      if (sig[i] > hi) hi = sig[i];
    }
    if (hi - lo < 1e-12) continue;
    final Float32List v = Float32List(cfg.win);
    for (int i = 0; i < cfg.win; i++) {
      final double y = (sig[s + i] - lo) / (hi - lo);
      v[i] = st.sign > 0 ? y : 1.0 - y;
    }
    w.add(v);
    ks.add(s);
    ka.add(act[k]);
  }
  return EcgInput(windows: w, starts: ks, activity: ka, signal: sig, nAll: starts.length);
}

/// 窓の出力をつなぐ（重なりは平均）。どの窓もかからない所は nan。
Float64List stitchWindows(List<List<double>> outputs, List<int> starts, int n) {
  final Float64List acc = Float64List(n), cnt = Float64List(n);
  for (int k = 0; k < outputs.length; k++) {
    final int s = starts[k];
    final int e = math.min(s + outputs[k].length, n);
    for (int i = s; i < e; i++) {
      acc[i] += outputs[k][i - s];
      cnt[i] += 1;
    }
  }
  return Float64List.fromList(<double>[for (int i = 0; i < n; i++) cnt[i] > 0 ? acc[i] / cnt[i] : double.nan]);
}

/// 心電図の形の結果。
class EcgResult {
  EcgResult({required this.settings, required this.input, required this.ecg, required this.rPeaks, required this.heartRateBpm});

  final EcgSettings settings;
  final EcgInput input;
  final Float64List ecg; // 150 Hz、窓がかかる所だけつないだもの（nan を除いたもの）
  final List<int> rPeaks; // ecg の中の位置
  final double heartRateBpm; // nan なら出せない
  int get windowsUsed => input.windows.length;
}

/// モデル：[W][1024] → [W][1024]。
typedef EcgModel = Future<List<List<double>>> Function(List<Float32List> windows);

Future<EcgResult> estimateEcg(List<double> ax, List<double> ay, List<double> az, double fs, EcgModel model,
    {EcgSettings settings = const EcgSettings(), EcgConfig cfg = const EcgConfig()}) async {
  final EcgInput inp = ecgModelInput(ax, ay, az, fs, settings, cfg: cfg);
  final List<List<double>> out = inp.windows.isEmpty ? <List<double>>[] : await model(inp.windows);
  final Float64List all = stitchWindows(out, inp.starts, inp.signal.length);
  final Float64List ecg = Float64List.fromList(<double>[for (final double v in all) if (v.isFinite) v]);
  final List<int> pk = rPeaksNeurokit(ecg, cfg.fs);
  return EcgResult(settings: settings, input: inp, ecg: ecg, rPeaks: pk, heartRateBpm: heartRateFromPeaks(pk, cfg.fs));
}
