import 'dart:typed_data';

import 'fft.dart';

/// 汪磊先生のグループの前処理と同じ VMD（vmdpy 0.2 の VMD(f, alpha, tau=0, K, DC=0, init=1, tol)）で、
/// モード 0〜[keep]−1 を足したものを返す（元のコードは K=5・alpha=2000・tol=1e-7、モード 0〜2 の和）。
///
/// vmdpy と同じにしたところ：
/// - 長さが奇数なら最後の 1 点を捨てる。前後に半分ずつ折り返して 2 倍の長さにする
/// - 反復の最初の sum_uk の更新の式（u[n,:,K−1] + sum_uk − u[n,:,0]）
/// - 止まったあと、最後の 1 つ前の反復の結果を使う（vmdpy の Niter = min(500, n) → u_hat_plus[Niter−1]）
/// - 組み立て直し（共役の並べ方、0 番目）と、真ん中の半分だけ取り出す
///
/// 変えたところ（答えは同じ）：tau=0 なので λ はずっと 0。下半分の周波数はずっと 0 なので上半分だけ計算する。
/// 全部の反復を残さず、今と 1 つ前だけ持つ（vmdpy は 500 回分を持つのでメモリが大きい）。
/// モードの和は、逆 FFT の前に足す（線形なので同じ）。
({Float64List signal, int iterations}) vmdModeSum(
  List<double> f, {
  double alpha = 2000.0,
  int k = 5,
  double tol = 1e-7,
  int keep = 3,
  int maxIter = 500,
}) {
  final int len = f.length.isOdd ? f.length - 1 : f.length;
  final int lt = len ~/ 2;
  final int t = 2 * len; // 折り返したあとの長さ
  final int h = t ~/ 2;
  final Float64List mr = Float64List(t), mi = Float64List(t);
  for (int i = 0; i < lt; i++) {
    mr[i] = f[lt - 1 - i];
  }
  for (int i = 0; i < len; i++) {
    mr[lt + i] = f[i];
  }
  for (int i = 0; i < lt; i++) {
    mr[lt + len + i] = f[len - 1 - i];
  }
  fftInPlace(mr, mi);
  // fftshift した上半分（j = h..t−1）＝ もとの FFT の 0..h−1
  final Float64List fpr = Float64List(h), fpi = Float64List(h), freqs = Float64List(h);
  for (int j = 0; j < h; j++) {
    fpr[j] = mr[j];
    fpi[j] = mi[j];
    freqs[j] = (h + j + 1) / t - 0.5 - 1 / t;
  }
  Float64List om = Float64List(k);
  for (int i = 0; i < k; i++) {
    om[i] = (0.5 / k) * i;
  }
  List<Float64List> prevR = List<Float64List>.generate(k, (_) => Float64List(h));
  List<Float64List> prevI = List<Float64List>.generate(k, (_) => Float64List(h));
  List<Float64List> olderR = prevR, olderI = prevI;
  final Float64List sumR = Float64List(h), sumI = Float64List(h);
  const double eps = 2.220446049250313e-16; // np.spacing(1)
  int n = 0;
  double uDiff = tol + eps;
  while (uDiff > tol && n < maxIter - 1) {
    final List<Float64List> curR = List<Float64List>.generate(k, (_) => Float64List(h));
    final List<Float64List> curI = List<Float64List>.generate(k, (_) => Float64List(h));
    final Float64List newOm = Float64List(k);
    for (int j = 0; j < h; j++) {
      sumR[j] = prevR[k - 1][j] + sumR[j] - prevR[0][j];
      sumI[j] = prevI[k - 1][j] + sumI[j] - prevI[0][j];
    }
    for (int m = 0; m < k; m++) {
      if (m > 0) {
        final Float64List cr = curR[m - 1], ci = curI[m - 1], pr = prevR[m], pi = prevI[m];
        for (int j = 0; j < h; j++) {
          sumR[j] = cr[j] + sumR[j] - pr[j];
          sumI[j] = ci[j] + sumI[j] - pi[j];
        }
      }
      double num = 0, den = 0;
      final Float64List cr = curR[m], ci = curI[m];
      final double w = om[m];
      for (int j = 0; j < h; j++) {
        final double df = freqs[j] - w;
        final double d = 1.0 + alpha * df * df;
        final double vr = (fpr[j] - sumR[j]) / d;
        final double vi = (fpi[j] - sumI[j]) / d;
        cr[j] = vr;
        ci[j] = vi;
        final double a2 = vr * vr + vi * vi;
        num += freqs[j] * a2;
        den += a2;
      }
      newOm[m] = num / den;
    }
    n++;
    double u = eps;
    for (int m = 0; m < k; m++) {
      for (int j = 0; j < h; j++) {
        final double dr = curR[m][j] - prevR[m][j];
        final double di = curI[m][j] - prevI[m][j];
        u += (dr * dr + di * di) / t;
      }
    }
    uDiff = u.abs();
    olderR = prevR;
    olderI = prevI;
    prevR = curR;
    prevI = curI;
    om = newOm;
  }
  // 1 つ前の反復（vmdpy と同じ）
  final Float64List sr = Float64List(h), si = Float64List(h);
  for (int m = 0; m < keep && m < k; m++) {
    for (int j = 0; j < h; j++) {
      sr[j] += olderR[m][j];
      si[j] += olderI[m][j];
    }
  }
  // shift された u_hat を組む
  final Float64List ur = Float64List(t), ui = Float64List(t);
  for (int j = 0; j < h; j++) {
    ur[h + j] = sr[j];
    ui[h + j] = si[j];
  }
  for (int j = 0; j < h; j++) {
    ur[h - j] = sr[j];
    ui[h - j] = -si[j];
  }
  ur[0] = ur[t - 1];
  ui[0] = -ui[t - 1];
  // ifftshift → 逆 FFT
  final Float64List zr = Float64List(t), zi = Float64List(t);
  for (int m = 0; m < t; m++) {
    zr[m] = ur[(m + h) % t];
    zi[m] = ui[(m + h) % t];
  }
  fftInPlace(zr, zi, inverse: true);
  final int a = t ~/ 4;
  final Float64List out = Float64List(3 * t ~/ 4 - a);
  for (int i = 0; i < out.length; i++) {
    out[i] = zr[a + i] / t;
  }
  return (signal: out, iterations: n);
}
