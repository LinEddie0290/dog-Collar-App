import 'dart:math' as math;
import 'dart:typed_data';

/// 畳み込み 1 段(BatchNorm まとめ済み)。そのあと ReLU → MaxPool(2)。
class CnnConv {
  CnnConv({
    required this.inCh,
    required this.outCh,
    required this.k,
    required this.pad,
    required this.w,
    required this.b,
  });

  final int inCh;
  final int outCh;
  final int k;
  final int pad;
  final Float32List w; // [out][in][k]
  final Float32List b; // [out]
}

class CnnPrediction {
  const CnnPrediction(this.label, this.className, this.prob);

  final int label;
  final String className;
  final Float32List prob;
}

/// 入力 [inCh][length](正規化まえ)→ クラスの確率。
/// 作業用の配列は 1 回だけ作って使い回す(1 秒に 1 回呼ぶので)。
/// 1 つのインスタンスを同時に 2 か所から呼ばないこと。
class CnnImuModel {
  CnnImuModel._({
    required this.name,
    required this.classes,
    required this.inCh,
    required this.length,
    required this.mean,
    required this.std,
    required this.useGravity,
    required this.g,
    required this.convs,
    required this.headIn,
    required this.headW,
    required this.headB,
  }) {
    int n = length;
    int biggest = 0;
    for (final CnnConv c in convs) {
      n ~/= 2;
      biggest = math.max(biggest, c.outCh * n);
    }
    _in = Float32List(inCh * length);
    _a = Float32List(biggest);
    _b = Float32List(biggest);
    _feat = Float32List(headIn);
  }

  final String name;
  final List<String> classes;
  final int inCh;
  final int length;
  final Float32List mean;
  final Float32List std;
  final bool useGravity;
  final double g;
  final List<CnnConv> convs;
  final int headIn;
  final Float32List headW; // [nClasses][headIn]
  final Float32List headB;

  late final Float32List _in;
  late final Float32List _a;
  late final Float32List _b;
  late final Float32List _feat;

  int get nClasses => classes.length;

  /// パラメータの数。
  int get params =>
      convs.fold<int>(0, (int s, CnnConv c) => s + c.w.length + c.b.length) + headW.length + headB.length;

  static Float32List _f32(Object? v) =>
      Float32List.fromList((v as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList());

  /// `scripts/export_cnn.py` の JSON(collar.cnn_imu_export/0.1)から作る。
  factory CnnImuModel.fromJson(Map<String, dynamic> j) {
    final List<CnnConv> convs = (j['convs'] as List<dynamic>).map((dynamic c) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      return CnnConv(
        inCh: m['in'] as int,
        outCh: m['out'] as int,
        k: m['k'] as int,
        pad: m['pad'] as int,
        w: _f32(m['w']),
        b: _f32(m['b']),
      );
    }).toList();
    final Map<String, dynamic> head = j['head'] as Map<String, dynamic>;
    final CnnImuModel model = CnnImuModel._(
      name: j['name'] as String? ?? 'cnn',
      classes: (j['classes'] as List<dynamic>).cast<String>(),
      inCh: j['in_ch'] as int,
      length: j['length'] as int,
      mean: _f32(j['mean']),
      std: _f32(j['std']),
      useGravity: j['use_gravity'] as bool? ?? false,
      g: (j['g'] as num?)?.toDouble() ?? 9.80665,
      convs: convs,
      headIn: head['in'] as int,
      headW: _f32(head['w']),
      headB: _f32(head['b']),
    );
    model._checkShapes();
    return model;
  }

  void _checkShapes() {
    int ch = inCh;
    for (final CnnConv c in convs) {
      if (c.inCh != ch || c.w.length != c.outCh * c.inCh * c.k || c.b.length != c.outCh) {
        throw FormatException('conv の形が合わない($ch → ${c.inCh}x${c.outCh}x${c.k})');
      }
      ch = c.outCh;
    }
    if (headIn != ch + (useGravity ? 3 : 0) || headW.length != headIn * nClasses || headB.length != nClasses) {
      throw const FormatException('全結合の形が合わない');
    }
  }

  /// x:長さ inCh*length(チャンネルごとに並ぶ)。gravity:重力の 3 軸(m/s²)、useGravity のときだけ使う。
  CnnPrediction predict(Float32List x, {List<double>? gravity}) {
    if (x.length != inCh * length) {
      throw ArgumentError('入力の長さ ${x.length}、必要なのは ${inCh * length}');
    }
    int n = length;
    for (int i = 0; i < inCh; i++) {
      final double m = mean[i];
      final double s = std[i];
      final int o = i * n;
      for (int t = 0; t < n; t++) {
        _in[o + t] = (x[o + t] - m) / s;
      }
    }

    Float32List cur = _in;
    int ch = inCh;
    for (int l = 0; l < convs.length; l++) {
      final CnnConv c = convs[l];
      final Float32List dst = (l & 1) == 0 ? _a : _b;
      final int half = n ~/ 2;
      for (int o = 0; o < c.outCh; o++) {
        for (int p = 0; p < half; p++) {
          final double a = _convAt(c, cur, n, o, 2 * p);
          final double b = _convAt(c, cur, n, o, 2 * p + 1);
          final double v = a > b ? a : b; // max(relu(a), relu(b)) = relu(max(a, b))
          dst[o * half + p] = v > 0 ? v : 0;
        }
      }
      cur = dst;
      n = half;
      ch = c.outCh;
    }

    for (int o = 0; o < ch; o++) {
      double s = 0;
      final int base = o * n;
      for (int t = 0; t < n; t++) {
        s += cur[base + t];
      }
      _feat[o] = s / n;
    }
    if (useGravity) {
      for (int k = 0; k < 3; k++) {
        _feat[ch + k] = gravity == null ? 0 : gravity[k] / g;
      }
    }

    final Float32List prob = Float32List(nClasses);
    int best = 0;
    double zmax = double.negativeInfinity;
    for (int k = 0; k < nClasses; k++) {
      double z = headB[k];
      final int base = k * headIn;
      for (int i = 0; i < headIn; i++) {
        z += headW[base + i] * _feat[i];
      }
      prob[k] = z;
      if (z > zmax) {
        zmax = z;
        best = k;
      }
    }
    double sum = 0;
    for (int k = 0; k < nClasses; k++) {
      final double e = math.exp(prob[k] - zmax);
      prob[k] = e;
      sum += e;
    }
    for (int k = 0; k < nClasses; k++) {
      prob[k] = prob[k] / sum;
    }
    return CnnPrediction(best, classes[best], prob);
  }

  /// 畳み込み 1 点(ゼロ埋め)。
  static double _convAt(CnnConv c, Float32List x, int n, int o, int t) {
    double acc = c.b[o];
    int j0 = c.pad - t;
    int j1 = n + c.pad - t;
    if (j0 < 0) j0 = 0;
    if (j1 > c.k) j1 = c.k;
    final int off = t - c.pad;
    final int wo = o * c.inCh * c.k;
    for (int i = 0; i < c.inCh; i++) {
      final int wi = wo + i * c.k;
      final int xi = i * n + off;
      for (int j = j0; j < j1; j++) {
        acc += c.w[wi + j] * x[xi + j];
      }
    }
    return acc;
  }
}

/// 確かめ用の窓(`check_windows.json`)で、答えの一致と速さを測る。
/// アプリの「推理速度」画面と `bin/check.dart` の両方で使う。
class CnnCheckResult {
  const CnnCheckResult({
    required this.windows,
    required this.sameLabel,
    required this.maxProbDiff,
    required this.medianMs,
    required this.maxMs,
    required this.meanMs,
    required this.reps,
  });

  final int windows;
  final int sameLabel;
  final double maxProbDiff;
  final double medianMs; // 1 窓
  final double maxMs;
  final double meanMs;
  final int reps;

  bool get ok => sameLabel == windows && maxProbDiff < 1e-4;

  @override
  String toString() => 'windows $windows  label same $sameLabel/$windows  '
      'max prob diff ${maxProbDiff.toStringAsExponential(2)}  '
      'median ${medianMs.toStringAsFixed(4)} ms  mean ${meanMs.toStringAsFixed(4)} ms  '
      'max ${maxMs.toStringAsFixed(4)} ms/window  (x$reps)';
}

CnnCheckResult runCnnCheck(CnnImuModel model, Map<String, dynamic> check, {int reps = 5}) {
  final List<dynamic> xs = check['X'] as List<dynamic>;
  final List<dynamic>? gs = check['gravity'] as List<dynamic>?;
  final List<dynamic> ps = check['prob'] as List<dynamic>;
  final int n = xs.length;
  final List<Float32List> wins = <Float32List>[
    for (final dynamic x in xs) Float32List.fromList((x as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList()),
  ];
  final List<List<double>?> grav = <List<double>?>[
    for (int i = 0; i < n; i++)
      gs == null ? null : (gs[i] as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList(),
  ];

  int same = 0;
  double maxDiff = 0;
  for (int i = 0; i < n; i++) {
    final CnnPrediction p = model.predict(wins[i], gravity: grav[i]);
    final List<double> ref = (ps[i] as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList();
    int kr = 0;
    for (int k = 0; k < ref.length; k++) {
      maxDiff = math.max(maxDiff, (p.prob[k] - ref[k]).abs());
      if (ref[k] > ref[kr]) kr = k;
    }
    if (kr == p.label) same++;
  }

  final List<double> times = <double>[];
  final Stopwatch sw = Stopwatch();
  for (int r = 0; r < reps; r++) {
    for (int i = 0; i < n; i++) {
      sw
        ..reset()
        ..start();
      model.predict(wins[i], gravity: grav[i]);
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1000.0);
    }
  }
  times.sort();
  final double mean = times.reduce((double a, double b) => a + b) / times.length;
  return CnnCheckResult(
    windows: n,
    sameLabel: same,
    maxProbDiff: maxDiff,
    medianMs: times[times.length ~/ 2],
    maxMs: times.last,
    meanMs: mean,
    reps: reps,
  );
}
