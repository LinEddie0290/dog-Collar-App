import 'dart:typed_data';

/// scipy.interpolate.CubicSpline(x, y)（bc_type='not-a-knot'、点は 4 つ以上）を xNew で評価する。
/// 傾き s を scipy と同じ 3 重対角の式で解き、区間ごとに 3 次式（scipy の PPoly と同じ係数）で計算する。
/// x は増える順。xNew は増える順（範囲の外は端の区間で外挿、scipy と同じ）。
Float64List cubicSplineNotAKnot(List<double> x, List<double> y, List<double> xNew) {
  final int n = x.length;
  if (y.length != n) throw ArgumentError('x と y の長さが違う');
  if (n < 4) throw ArgumentError('点が 4 つ以上要る：$n');
  final Float64List dx = Float64List(n - 1), sl = Float64List(n - 1);
  for (int i = 0; i < n - 1; i++) {
    dx[i] = x[i + 1] - x[i];
    sl[i] = (y[i + 1] - y[i]) / dx[i];
  }
  final Float64List lo = Float64List(n), di = Float64List(n), up = Float64List(n), b = Float64List(n);
  for (int i = 1; i < n - 1; i++) {
    di[i] = 2 * (dx[i - 1] + dx[i]);
    up[i] = dx[i - 1];
    lo[i] = dx[i];
    b[i] = 3 * (dx[i] * sl[i - 1] + dx[i - 1] * sl[i]);
  }
  double d = x[2] - x[0];
  di[0] = dx[1];
  up[0] = d;
  b[0] = ((dx[0] + 2 * d) * dx[1] * sl[0] + dx[0] * dx[0] * sl[1]) / d;
  d = x[n - 1] - x[n - 3];
  di[n - 1] = dx[n - 3];
  lo[n - 1] = d;
  b[n - 1] = (dx[n - 2] * dx[n - 2] * sl[n - 3] + (2 * d + dx[n - 2]) * dx[n - 3] * sl[n - 2]) / d;

  // 3 重対角（Thomas）
  final Float64List c = Float64List(n), dd = Float64List(n), s = Float64List(n);
  c[0] = up[0] / di[0];
  dd[0] = b[0] / di[0];
  for (int i = 1; i < n; i++) {
    final double m = di[i] - lo[i] * c[i - 1];
    c[i] = i < n - 1 ? up[i] / m : 0.0;
    dd[i] = (b[i] - lo[i] * dd[i - 1]) / m;
  }
  s[n - 1] = dd[n - 1];
  for (int i = n - 2; i >= 0; i--) {
    s[i] = dd[i] - c[i] * s[i + 1];
  }

  final Float64List out = Float64List(xNew.length);
  int j = 0;
  for (int k = 0; k < xNew.length; k++) {
    final double xv = xNew[k];
    while (j < n - 2 && xv >= x[j + 1]) {
      j++;
    }
    while (j > 0 && xv < x[j]) {
      j--;
    }
    final double h = dx[j], t = xv - x[j];
    final double c1 = s[j];
    final double c2 = (3 * sl[j] - 2 * s[j] - s[j + 1]) / h;
    final double c3 = (s[j] + s[j + 1] - 2 * sl[j]) / (h * h);
    out[k] = y[j] + t * (c1 + t * (c2 + t * c3));
  }
  return out;
}

/// numpy.linspace(a, b, n)（最後の点はちょうど b）。
Float64List linspace(double a, double b, int n) {
  final Float64List out = Float64List(n);
  if (n == 1) {
    out[0] = a;
    return out;
  }
  final double step = (b - a) / (n - 1);
  for (int i = 0; i < n; i++) {
    out[i] = a + i * step;
  }
  out[n - 1] = b;
  return out;
}
