import 'dart:math' as math;
import 'dart:typed_data';

/// SciPy と同じ結果になる信号処理（butter・sosfiltfilt・firwin・resample_poly）。
/// 作り方は SciPy 1.17 のソースに合わせた。Python の参考実装（同じ手順）で
/// SciPy との差が 1e-10 以下なのを確かめてある。

/// 2 次の区間 1 つ：[b0, b1, b2, a0, a1, a2]（a0 = 1）。
typedef Sos = List<List<double>>;

class _C {
  const _C(this.re, this.im);
  final double re;
  final double im;
  _C operator +(_C o) => _C(re + o.re, im + o.im);
  _C operator -(_C o) => _C(re - o.re, im - o.im);
  _C operator *(_C o) => _C(re * o.re - im * o.im, re * o.im + im * o.re);
  _C operator /(_C o) {
    final double d = o.re * o.re + o.im * o.im;
    return _C((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }

  _C scale(double k) => _C(re * k, im * k);
  double get abs => math.sqrt(re * re + im * im);
}

/// scipy.signal.butter(order, cutoff, btype='low', fs=fs, output='sos')
Sos butterLowSos(int order, double cutoff, double fs) {
  final double wn = 2.0 * cutoff / fs;
  const double fs2 = 2.0;
  final double warped = 2.0 * fs2 * math.tan(math.pi * wn / fs2);
  final List<_C> poles = <_C>[];
  for (int m = -order + 1; m < order; m += 2) {
    final double ang = math.pi * m / (2 * order);
    poles.add(_C(-math.cos(ang) * warped, -math.sin(ang) * warped));
  }
  double k = math.pow(warped, order).toDouble();
  const double fs4 = 2.0 * fs2;
  final List<_C> pd = <_C>[];
  _C den = const _C(1, 0);
  for (final _C p in poles) {
    pd.add((const _C(fs4, 0) + p) / (const _C(fs4, 0) - p));
    den = den * (const _C(fs4, 0) - p);
  }
  k = (const _C(1, 0) / den).scale(k).re;

  final List<_C> upper = pd.where((_C p) => p.im > 1e-14).toList();
  final List<_C> reals = pd.where((_C p) => p.im.abs() <= 1e-14).toList();
  // 単位円に一番近い極を最後の区間に（SciPy の zpk2sos と同じ並び）
  upper.sort((_C a, _C b) => (b.abs - 1).abs().compareTo((a.abs - 1).abs()));
  final Sos secs = <List<double>>[
    for (final _C p in upper) <double>[1.0, 2.0, 1.0, 1.0, -2.0 * p.re, p.abs * p.abs],
  ];
  if (reals.isNotEmpty) {
    secs.insert(0, <double>[1.0, 1.0, 0.0, 1.0, -reals.first.re, 0.0]);
  }
  secs[0] = <double>[secs[0][0] * k, secs[0][1] * k, secs[0][2] * k, secs[0][3], secs[0][4], secs[0][5]];
  return secs;
}

/// scipy.signal.sosfilt_zi
List<List<double>> sosfiltZi(Sos sos) {
  final List<List<double>> zis = <List<double>>[];
  double scale = 1.0;
  for (final List<double> s in sos) {
    final double b0 = s[0], b1 = s[1], b2 = s[2], a0 = s[3], a1 = s[4], a2 = s[5];
    final double bb0 = b1 - a1 * b0;
    final double bb1 = b2 - a2 * b0;
    final double det = (1 + a1) + a2;
    final double z0 = (bb0 + bb1) / det;
    final double z1 = ((1 + a1) * bb1 - a2 * bb0) / det;
    zis.add(<double>[z0 * scale, z1 * scale]);
    scale *= (b0 + b1 + b2) / (a0 + a1 + a2);
  }
  return zis;
}

void _sosfiltInPlace(Sos sos, Float64List y, List<List<double>> zi, double z0Scale) {
  for (int k = 0; k < sos.length; k++) {
    final List<double> s = sos[k];
    final double b0 = s[0], b1 = s[1], b2 = s[2], a1 = s[4], a2 = s[5];
    double z0 = zi[k][0] * z0Scale;
    double z1 = zi[k][1] * z0Scale;
    for (int n = 0; n < y.length; n++) {
      final double xn = y[n];
      final double yn = b0 * xn + z0;
      z0 = b1 * xn - a1 * yn + z1;
      z1 = b2 * xn - a2 * yn;
      y[n] = yn;
    }
  }
}

/// scipy.signal.sosfiltfilt(sos, x, padlen=padlen)（padtype='odd'）
Float64List sosfiltfilt(Sos sos, List<double> x, int padlen) {
  final int n = x.length;
  final int edge = padlen;
  final Float64List ext = Float64List(n + 2 * edge);
  for (int i = 0; i < edge; i++) {
    ext[i] = 2 * x[0] - x[edge - i];
  }
  for (int i = 0; i < n; i++) {
    ext[edge + i] = x[i];
  }
  for (int i = 0; i < edge; i++) {
    ext[edge + n + i] = 2 * x[n - 1] - x[n - 2 - i];
  }
  final List<List<double>> zi = sosfiltZi(sos);
  _sosfiltInPlace(sos, ext, zi, ext[0]);
  // 逆向き
  final Float64List rev = Float64List(ext.length);
  for (int i = 0; i < ext.length; i++) {
    rev[i] = ext[ext.length - 1 - i];
  }
  _sosfiltInPlace(sos, rev, zi, rev[0]);
  final Float64List out = Float64List(n);
  for (int i = 0; i < n; i++) {
    out[i] = rev[rev.length - 1 - (edge + i)];
  }
  return out;
}

/// collar/preprocess/imu.py の lowpass（1 本の列）。
Float64List lowpass(List<double> x, double fs, double cutoff, {int order = 4}) {
  if (cutoff >= 0.95 * fs / 2) return Float64List.fromList(x);
  final Sos sos = butterLowSos(order, cutoff, fs);
  int padlen = math.min(x.length - 1, 3 * (2 * sos.length + 1) * 10);
  if (padlen < 0) padlen = 0;
  return sosfiltfilt(sos, x, padlen);
}

/// 第 1 種変形ベッセル関数 I0（級数）。
double besselI0(double x) {
  double s = 1.0, t = 1.0;
  final double q = x * x / 4.0;
  for (int k = 1; k < 500; k++) {
    t *= q / (k * k);
    s += t;
    if (t < 1e-17 * s) break;
  }
  return s;
}

/// scipy.signal.firwin(numtaps, fC, window=('kaiser', beta))（低域、scale=True）
Float64List firwinKaiser(int numtaps, double fC, {double beta = 5.0}) {
  final double alpha = 0.5 * (numtaps - 1);
  final Float64List h = Float64List(numtaps);
  final double i0b = besselI0(beta);
  double sum = 0;
  for (int i = 0; i < numtaps; i++) {
    final double m = i - alpha;
    final double xx = fC * m;
    final double sinc = xx == 0 ? 1.0 : math.sin(math.pi * xx) / (math.pi * xx);
    final double r = 2.0 * i / (numtaps - 1) - 1.0;
    final double w = besselI0(beta * math.sqrt(math.max(0.0, 1 - r * r))) / i0b;
    h[i] = fC * sinc * w;
    sum += h[i];
  }
  for (int i = 0; i < numtaps; i++) {
    h[i] /= sum;
  }
  return h;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// scipy.signal.resample_poly(x, up, down)（window=('kaiser', 5.0)、padtype='constant'）
Float64List resamplePoly(List<double> x, int up, int down) {
  final int g = _gcd(up, down);
  up ~/= g;
  down ~/= g;
  if (up == 1 && down == 1) return Float64List.fromList(x);
  final int nIn = x.length;
  int nOut = nIn * up;
  nOut = nOut ~/ down + (nOut % down != 0 ? 1 : 0);
  final int maxRate = math.max(up, down);
  final int halfLen = 10 * maxRate;
  final Float64List base = firwinKaiser(2 * halfLen + 1, 1.0 / maxRate);
  final int nPrePad = down - halfLen % down;
  int nPostPad = 0;
  final int nPreRemove = (halfLen + nPrePad) ~/ down;
  int outLen(int lh) => ((nIn - 1) * up + lh - 1) ~/ down + 1;
  while (outLen(base.length + nPrePad + nPostPad) < nOut + nPreRemove) {
    nPostPad++;
  }
  final int lh = nPrePad + base.length + nPostPad;
  final Float64List h = Float64List(lh);
  for (int i = 0; i < base.length; i++) {
    h[nPrePad + i] = base[i] * up;
  }
  final int nUp = (nIn - 1) * up + 1;
  final Float64List y = Float64List(nOut);
  for (int o = 0; o < nOut; o++) {
    final int t = (nPreRemove + o) * down;
    final int jmin = math.max(0, t - (lh - 1));
    final int jmax = math.min(t, nUp - 1);
    int j = jmin + ((-jmin) % up + up) % up;
    double acc = 0;
    while (j <= jmax) {
      acc += h[t - j] * x[j ~/ up];
      j += up;
    }
    y[o] = acc;
  }
  return y;
}

/// fractions.Fraction(r).limit_denominator(1000) の近似：分母 1000 までで一番近い分数。
/// 使う比（1/4、1/2、1 など）はぴったり表せるので Python と同じになる。
List<int> limitDenominator(double r, {int maxDen = 1000}) {
  int bestP = r.round(), bestQ = 1;
  double bestErr = (r - bestP).abs();
  for (int q = 2; q <= maxDen && bestErr > 1e-12; q++) {
    final int p = (r * q).round();
    final double err = (r - p / q).abs();
    if (err < bestErr - 1e-15) {
      bestErr = err;
      bestP = p;
      bestQ = q;
    }
  }
  return <int>[bestP, bestQ];
}

/// collar/preprocess/imu.py の downsample（1 本の列）。
Float64List downsample(List<double> x, double fsIn, double fsOut) {
  if ((fsIn - fsOut).abs() < 1e-9) return Float64List.fromList(x);
  if (fsOut > fsIn) throw ArgumentError('不升频：$fsIn → $fsOut');
  final Float64List f = lowpass(x, fsIn, 0.4 * fsOut, order: 8);
  final List<int> r = limitDenominator(fsOut / fsIn);
  return resamplePoly(f, r[0], r[1]);
}

/// numpy の標準偏差（ddof=0）。
double stdPop(List<double> v, [int start = 0, int? end]) {
  final int e = end ?? v.length;
  final int n = e - start;
  if (n <= 0) return double.nan;
  double m = 0;
  for (int i = start; i < e; i++) {
    m += v[i];
  }
  m /= n;
  double s = 0;
  for (int i = start; i < e; i++) {
    final double d = v[i] - m;
    s += d * d;
  }
  return math.sqrt(s / n);
}
