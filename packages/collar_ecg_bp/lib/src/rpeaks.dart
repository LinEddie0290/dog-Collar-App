import 'dart:math' as math;
import 'dart:typed_data';

/// neurokit2 0.3 の ecg_peaks(ecg, sampling_rate, method='neurokit')（clean しない、修正しない）と同じ R 波の位置。
/// collar/ecg/model.py の r_peaks と同じ：短すぎる・平ら・nan のときは空。
List<int> rPeaksNeurokit(List<double> sig, double fs) {
  final int n = sig.length;
  if (n < 2 * fs) return <int>[];
  double lo = double.infinity, hi = -double.infinity;
  for (final double v in sig) {
    if (!v.isFinite) return <int>[];
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo < 1e-12) return <int>[];

  // np.gradient（端は片側）
  final Float64List g = Float64List(n);
  g[0] = (sig[1] - sig[0]).abs();
  g[n - 1] = (sig[n - 1] - sig[n - 2]).abs();
  for (int i = 1; i < n - 1; i++) {
    g[i] = ((sig[i + 1] - sig[i - 1]) / 2).abs();
  }
  final int sk = _rint(0.1 * fs), ak = _rint(0.75 * fs);
  final Float64List sm = _uniformNearest(g, sk);
  final Float64List av = _uniformNearest(sm, ak);
  final int minDelay = _rint(fs * 0.3);
  final List<bool> q = <bool>[for (int i = 0; i < n; i++) sm[i] > 1.5 * av[i]];
  final List<int> beg = <int>[], endAll = <int>[];
  for (int i = 0; i < n - 1; i++) {
    if (!q[i] && q[i + 1]) beg.add(i);
    if (q[i] && !q[i + 1]) endAll.add(i);
  }
  if (beg.isEmpty) return <int>[];
  final List<int> end = endAll.where((int e) => e > beg[0]).toList();
  final int nq = math.min(beg.length, end.length);
  if (nq == 0) return <int>[];
  double meanLen = 0;
  for (int i = 0; i < nq; i++) {
    meanLen += end[i] - beg[i];
  }
  final double minLen = meanLen / nq * 0.4;
  final List<int> peaks = <int>[0];
  for (int i = 0; i < nq; i++) {
    final int b = beg[i], e = end[i];
    if (e - b < minLen) continue;
    final List<double> d = sig.sublist(b, e);
    final List<int> lm = _localMaxima(d);
    if (lm.isEmpty) continue;
    final List<double> pr = _prominences(d, lm);
    int best = 0;
    for (int k = 1; k < pr.length; k++) {
      if (pr[k] > pr[best]) best = k;
    }
    final int pk = b + lm[best];
    if (pk - peaks.last > minDelay) peaks.add(pk);
  }
  return peaks.sublist(1);
}

/// R 波 → 心拍数（bpm）＝ 60 / RR の中央値。R 波が 2 つ未満は nan。
double heartRateFromPeaks(List<int> peaks, double fs) {
  if (peaks.length < 2) return double.nan;
  final List<int> p = List<int>.of(peaks)..sort();
  final List<double> rr = <double>[];
  for (int i = 1; i < p.length; i++) {
    final double v = (p[i] - p[i - 1]) / fs;
    if (v > 0) rr.add(v);
  }
  if (rr.isEmpty) return double.nan;
  return 60.0 / median(rr);
}

/// numpy.median（偶数個は真ん中 2 つの平均）。
double median(List<double> v) {
  final List<double> s = List<double>.of(v)..sort();
  final int n = s.length;
  if (n == 0) return double.nan;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// numpy.rint（0.5 は偶数へ）。
int _rint(double x) {
  final double f = x.floorToDouble();
  final double d = x - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

/// scipy.ndimage.uniform_filter1d(x, size, mode='nearest')。
Float64List _uniformNearest(List<double> x, int size) {
  final int n = x.length;
  final Float64List out = Float64List(n);
  final int left = size ~/ 2;
  for (int i = 0; i < n; i++) {
    double s = 0;
    for (int k = i - left; k < i - left + size; k++) {
      s += x[k < 0 ? 0 : (k > n - 1 ? n - 1 : k)];
    }
    out[i] = s / size;
  }
  return out;
}

/// scipy.signal._peak_finding_utils._local_maxima_1d（平らな頂上は真ん中）。
List<int> _localMaxima(List<double> x) {
  final List<int> peaks = <int>[];
  final int n = x.length;
  int i = 1;
  while (i < n - 1) {
    if (x[i - 1] < x[i]) {
      int ia = i + 1;
      while (ia < n - 1 && x[ia] == x[i]) {
        ia++;
      }
      if (x[ia] < x[i]) {
        peaks.add((i + ia - 1) ~/ 2);
        i = ia;
      }
    }
    i++;
  }
  return peaks;
}

/// scipy.signal.peak_prominences（wlen なし）。
List<double> _prominences(List<double> x, List<int> peaks) {
  final int n = x.length;
  return <double>[
    for (final int p in peaks)
      () {
        double lmin = x[p], rmin = x[p];
        int i = p;
        while (i >= 0 && x[i] <= x[p]) {
          if (x[i] < lmin) lmin = x[i];
          i--;
        }
        i = p;
        while (i < n && x[i] <= x[p]) {
          if (x[i] < rmin) rmin = x[i];
          i++;
        }
        return x[p] - math.max(lmin, rmin);
      }(),
  ];
}
