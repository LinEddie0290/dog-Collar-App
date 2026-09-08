import 'sensor_sample.dart';

/// Simple, dependency-free denoising. Deliberately basic — a sane default you
/// can tune once real data shows up (or swap for a Kalman filter later).
///
/// Null handling is honest: a null input (no reading) produces a null output.
/// We do NOT carry forward or invent a value — missing stays missing, and the
/// filter's internal state is left untouched so smoothing resumes cleanly when
/// data comes back.

/// Exponential moving average (a one-line low-pass): y = a*x + (1-a)*y_prev.
/// Smaller [alpha] = smoother but more lag.
class Ema {
  final double alpha;
  double? _y;
  Ema(this.alpha);

  double? add(double? x) {
    if (x == null) return null;
    _y = _y == null ? x : alpha * x + (1 - alpha) * _y!;
    return _y;
  }
}

/// Median over a sliding window — kills isolated spikes/毛刺 that an EMA would
/// only smear. Odd [window] recommended.
class MedianFilter {
  final int window;
  final _buf = <double>[];
  MedianFilter(this.window);

  double? add(double? x) {
    if (x == null) return null;
    _buf.add(x);
    if (_buf.length > window) _buf.removeAt(0);
    final sorted = List<double>.from(_buf)..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Per-signal filter chain applied to each incoming sample.
///   * hr / resp : median (despike) -> EMA (smooth). Slow physiological signals.
///   * IMU axes  : EMA low-pass to shed high-frequency jitter.
///   * battery   : untouched (already slow).
class SampleFilter {
  final MedianFilter _hrMedian;
  final Ema _hrEma;
  final MedianFilter _respMedian;
  final Ema _respEma;
  final Ema _axEma;
  final Ema _ayEma;
  final Ema _azEma;

  SampleFilter({
    int hrMedianWindow = 5,
    double hrAlpha = 0.2,
    int respMedianWindow = 5,
    double respAlpha = 0.2,
    double imuAlpha = 0.3,
  })  : _hrMedian = MedianFilter(hrMedianWindow),
        _hrEma = Ema(hrAlpha),
        _respMedian = MedianFilter(respMedianWindow),
        _respEma = Ema(respAlpha),
        _axEma = Ema(imuAlpha),
        _ayEma = Ema(imuAlpha),
        _azEma = Ema(imuAlpha);

  SensorSample apply(SensorSample s) {
    return s.copyWith(
      hr: _hrEma.add(_hrMedian.add(s.hr)),
      resp: _respEma.add(_respMedian.add(s.resp)),
      ax: _axEma.add(s.ax),
      ay: _ayEma.add(s.ay),
      az: _azEma.add(s.az),
    );
  }
}
