import 'dart:math' as math;
import 'dart:typed_data';

/// 複素数の FFT（どの長さでも。混合基数、numpy.fft.fft と同じ向き：exp(-2πi jk/n)）。
/// 血圧の VMD で使う長さは 45,000（= 2³·3²·5⁴）なので、小さい素因数だけで速く計算できる。
/// [inverse] = true のときは exp(+2πi jk/n)（1/n はかけない）。
void fftInPlace(Float64List re, Float64List im, {bool inverse = false}) {
  final int n = re.length;
  if (im.length != n) throw ArgumentError('re と im の長さが違う');
  if (n <= 1) return;
  final List<int> f = _factors(n);
  final Float64List outRe = Float64List(n), outIm = Float64List(n);
  final double sign = inverse ? 1.0 : -1.0;
  // 回転因子の表：exp(sign·2πi·m/n)
  final Float64List cw = Float64List(n), sw = Float64List(n);
  for (int m = 0; m < n; m++) {
    final double a = sign * 2 * math.pi * m / n;
    cw[m] = math.cos(a);
    sw[m] = math.sin(a);
  }

  void rec(int inOff, int stride, int len, int fi, int oOff) {
    if (len == 1) {
      outRe[oOff] = re[inOff];
      outIm[oOff] = im[inOff];
      return;
    }
    final int p = f[fi];
    final int m = len ~/ p;
    for (int q = 0; q < p; q++) {
      rec(inOff + q * stride, stride * p, m, fi + 1, oOff + q * m);
    }
    final int tw = n ~/ len; // exp(sign·2πi·q·k/len) = 表[(q·k·tw) mod n]
    final Float64List tr = Float64List(p), ti = Float64List(p);
    for (int k = 0; k < m; k++) {
      for (int q = 0; q < p; q++) {
        final int idx = (q * k * tw) % n;
        final double c = cw[idx], s = sw[idx];
        final double xr = outRe[oOff + q * m + k], xi = outIm[oOff + q * m + k];
        tr[q] = xr * c - xi * s;
        ti[q] = xr * s + xi * c;
      }
      for (int r = 0; r < p; r++) {
        double sr = 0, si = 0;
        for (int q = 0; q < p; q++) {
          final int idx = ((q * r) % p) * (n ~/ p);
          final double c = cw[idx], s = sw[idx];
          sr += tr[q] * c - ti[q] * s;
          si += tr[q] * s + ti[q] * c;
        }
        outRe[oOff + r * m + k] = sr;
        outIm[oOff + r * m + k] = si;
      }
    }
  }

  rec(0, 1, n, 0, 0);
  re.setAll(0, outRe);
  im.setAll(0, outIm);
}

List<int> _factors(int n) {
  final List<int> f = <int>[];
  for (final int p in <int>[4, 2, 3, 5]) {
    while (n % p == 0) {
      f.add(p);
      n ~/= p;
    }
  }
  int p = 7;
  while (n > 1) {
    while (n % p == 0) {
      f.add(p);
      n ~/= p;
    }
    p += 2;
  }
  return f;
}
