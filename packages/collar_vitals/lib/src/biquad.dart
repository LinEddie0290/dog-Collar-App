/// Second-order IIR (biquad) filters, hand-rolled.
///
/// Why not an FFT library: the whole vital-sign pipeline needs band-pass
/// filtering, an envelope, and an autocorrelation over a *limited* lag range.
/// All three are cheap in the time domain — a 60-second measurement at 104 Hz
/// is 6,240 samples, and the autocorrelation only probes ~120 lags. Bringing in
/// an FFT dependency would add build weight for no gain, and would break this
/// package's "runs with a bare `dart` SDK" property.
///
/// Coefficients follow the Audio EQ Cookbook (Robert Bristow-Johnson), which is
/// the same formulation every audio DSP text uses, so they can be checked
/// against any reference.
library;

import 'dart:math' as math;

/// One biquad stage: `y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] − a1·y[n-1] − a2·y[n-2]`
/// with all coefficients already normalised by a0.
class Biquad {
  const Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;

  /// Band-pass with constant 0 dB peak gain.
  ///
  /// [centreHz] is the geometric centre of the band and [q] its sharpness;
  /// [bandPass] below derives both from the edges you actually care about.
  factory Biquad.bandPass({
    required double sampleRateHz,
    required double centreHz,
    required double q,
  }) {
    final double w0 = 2 * math.pi * centreHz / sampleRateHz;
    final double alpha = math.sin(w0) / (2 * q);
    final double cosW0 = math.cos(w0);
    final double a0 = 1 + alpha;
    return Biquad(
      alpha / a0,
      0.0,
      -alpha / a0,
      (-2 * cosW0) / a0,
      (1 - alpha) / a0,
    );
  }

  /// Low-pass, Butterworth-ish by default (q = 1/√2).
  factory Biquad.lowPass({
    required double sampleRateHz,
    required double cutoffHz,
    double q = 0.70710678,
  }) {
    final double w0 = 2 * math.pi * cutoffHz / sampleRateHz;
    final double alpha = math.sin(w0) / (2 * q);
    final double cosW0 = math.cos(w0);
    final double a0 = 1 + alpha;
    return Biquad(
      ((1 - cosW0) / 2) / a0,
      (1 - cosW0) / a0,
      ((1 - cosW0) / 2) / a0,
      (-2 * cosW0) / a0,
      (1 - alpha) / a0,
    );
  }

  /// High-pass.
  factory Biquad.highPass({
    required double sampleRateHz,
    required double cutoffHz,
    double q = 0.70710678,
  }) {
    final double w0 = 2 * math.pi * cutoffHz / sampleRateHz;
    final double alpha = math.sin(w0) / (2 * q);
    final double cosW0 = math.cos(w0);
    final double a0 = 1 + alpha;
    return Biquad(
      ((1 + cosW0) / 2) / a0,
      (-(1 + cosW0)) / a0,
      ((1 + cosW0) / 2) / a0,
      (-2 * cosW0) / a0,
      (1 - alpha) / a0,
    );
  }

  /// Runs the filter forward once. Phase is shifted; use [filtfilt] when the
  /// timing of features matters, which it does for beat detection.
  List<double> filter(List<double> input) {
    final List<double> out = List<double>.filled(input.length, 0.0);
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (int i = 0; i < input.length; i++) {
      final double x = input[i];
      final double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x;
      y2 = y1;
      y1 = y;
      out[i] = y;
    }
    return out;
  }

  /// Forward then backward, which cancels the phase shift exactly (the
  /// equivalent of SciPy's `sosfiltfilt`). Magnitude response is squared, so
  /// the effective filter is steeper than one pass.
  ///
  /// Beat positions would otherwise be offset by the filter's group delay —
  /// tens of milliseconds at these cutoffs, which matters when the whole beat
  /// interval is ~770 ms and we report its variability.
  List<double> filtfilt(List<double> input) {
    final List<double> forward = filter(input);
    final List<double> reversed = forward.reversed.toList(growable: false);
    final List<double> back = filter(reversed);
    return back.reversed.toList(growable: false);
  }
}

/// Band-pass between two edge frequencies, as a cascade of [stages] biquads.
///
/// One biquad is a gentle band-pass; cascading two gives the roll-off needed to
/// separate the heartbeat band (8–40 Hz) from the far larger respiratory motion
/// below 1 Hz. The DC component is removed first because an un-centred input
/// makes the first samples ring.
List<double> bandPass(
  List<double> x, {
  required double sampleRateHz,
  required double lowHz,
  required double highHz,
  int stages = 2,
}) {
  if (x.length < 16) return List<double>.filled(x.length, 0.0);
  final double nyquist = sampleRateHz / 2;
  final double hi = math.min(highHz, nyquist * 0.9);
  if (hi <= lowHz) {
    throw ArgumentError(
        'band $lowHz–$highHz Hz does not fit under Nyquist (${nyquist.toStringAsFixed(1)} Hz)');
  }
  final double centre = math.sqrt(lowHz * hi);
  final double q = centre / (hi - lowHz);

  final double mean = x.reduce((a, b) => a + b) / x.length;
  List<double> y = x.map((double v) => v - mean).toList(growable: false);
  final Biquad stage = Biquad.bandPass(
      sampleRateHz: sampleRateHz, centreHz: centre, q: q);
  for (int i = 0; i < stages; i++) {
    y = stage.filtfilt(y);
  }
  return y;
}

/// Envelope by rectify-and-smooth: `|x|` low-passed.
///
/// The textbook choice is the Hilbert transform, which needs an FFT. Rectifying
/// and low-passing gives a coarser envelope but requires neither, and for this
/// job it is enough: what matters is that the *periodicity* survives, not the
/// envelope's exact shape.
///
/// The envelope is what makes the heart rate unambiguous. One heartbeat
/// produces several peaks in the raw band (the I, J and K waves of the
/// ballistocardiogram), so counting raw peaks reports roughly double the true
/// rate. Taking the envelope merges each burst into a single bump.
List<double> envelope(
  List<double> x, {
  required double sampleRateHz,
  double cutoffHz = 3.0,
}) {
  final List<double> rect =
      x.map((double v) => v < 0 ? -v : v).toList(growable: false);
  final double mean = rect.reduce((a, b) => a + b) / rect.length;
  final List<double> centred =
      rect.map((double v) => v - mean).toList(growable: false);
  final double nyquist = sampleRateHz / 2;
  return Biquad.lowPass(
    sampleRateHz: sampleRateHz,
    cutoffHz: math.min(cutoffHz, nyquist * 0.9),
  ).filtfilt(centred);
}

/// Normalised autocorrelation over a bounded lag range, plus the winning lag.
///
/// Only lags inside the plausible physiological range are evaluated, which is
/// what keeps this cheap: for a 60 s / 104 Hz recording and a 40–220 bpm
/// search, that is about 120 lags over 6,000 samples — well under a million
/// multiply-adds, i.e. milliseconds on a phone.
class AutocorrResult {
  const AutocorrResult({
    required this.bestLagSamples,
    required this.bestValue,
    required this.values,
    required this.firstLagSamples,
  });

  final int bestLagSamples;

  /// Correlation at the winning lag, 0..1. Below about 0.15 there is no
  /// convincing periodicity and the rate should be reported as unknown.
  final double bestValue;

  /// The whole curve, for plotting. `values[i]` is the lag
  /// `firstLagSamples + i`.
  final List<double> values;
  final int firstLagSamples;

  /// Correlation at an absolute lag, or -1 if outside the searched range.
  double valueAtLag(int lag) {
    final int i = lag - firstLagSamples;
    if (i < 0 || i >= values.length) return -1;
    return values[i];
  }

  /// Is this lag a genuine local maximum, rather than a point part-way up a
  /// slope? Checked over a small neighbourhood so a single noisy sample cannot
  /// create or destroy a peak.
  bool isLocalMax(int lag, {int halfWidth = 2}) {
    final double v = valueAtLag(lag);
    if (v < 0) return false;
    for (int d = -halfWidth; d <= halfWidth; d++) {
      if (d == 0) continue;
      if (valueAtLag(lag + d) > v) return false;
    }
    return true;
  }

  /// The lag of the strongest **interior local maximum**.
  ///
  /// [bestLagSamples] is a plain arg-max, and that is not the same thing: if the
  /// correlation is still climbing when the search range runs out, the arg-max
  /// lands on the boundary, which is an artefact of where we stopped looking
  /// rather than a period in the signal. Measured on a synthetic 100 bpm case,
  /// the curve rose monotonically to the 50 bpm boundary and the arg-max sat
  /// there, reporting 49.9 bpm for a 100 bpm input — while the true period was
  /// a clean local maximum further in. Only interior maxima are real candidates.
  ///
  /// Returns -1 when the curve has no interior maximum at all.
  int strongestInteriorPeak() {
    int best = -1;
    double bestVal = -2;
    for (int i = 1; i < values.length - 1; i++) {
      if (values[i] >= values[i - 1] &&
          values[i] >= values[i + 1] &&
          values[i] > bestVal) {
        bestVal = values[i];
        best = firstLagSamples + i;
      }
    }
    return best;
  }

  /// The lag of the **fundamental** period, guarding against sub-harmonics.
  ///
  /// A periodic signal correlates with itself not only at one period but at
  /// every multiple of it, and the peak at 2× or 3× can win outright — the
  /// classic "octave error" of pitch detection. Reporting it would halve or
  /// third the heart rate, which for an animal is not a rounding error but a
  /// different diagnosis: a dog at 120 bpm reported as 60 looks profoundly
  /// bradycardic.
  ///
  /// So: divide the winning lag by 4, 3 and 2, and take the shortest one whose
  /// neighbourhood holds a correlation within [tolerance] of the winner. The
  /// search is over a *window* around each candidate rather than the rounded
  /// point itself — dividing an integer lag rarely lands exactly on the
  /// fundamental, and on a 170 bpm test the rounded candidate was one sample
  /// off the true maximum, which was enough to reject it.
  int fundamentalLag({double tolerance = 0.72, int? minLagSamples}) {
    final int start = strongestInteriorPeak();
    if (start < 0) return bestLagSamples;
    final int floor = minLagSamples ?? firstLagSamples;
    final double startVal = valueAtLag(start);

    for (final int divisor in <int>[4, 3, 2]) {
      final double candidate = start / divisor;
      if (candidate < floor) continue;
      final int width = math.max(2, (candidate * 0.08).round());
      int bestLag = -1;
      double bestVal = -2;
      for (int lag = (candidate - width).round();
          lag <= (candidate + width).round();
          lag++) {
        final double v = valueAtLag(lag);
        if (v > bestVal) {
          bestVal = v;
          bestLag = lag;
        }
      }
      if (bestLag > 0 && bestVal >= startVal * tolerance) {
        // divisors run high to low, so this is the shortest period that holds
        return bestLag;
      }
    }
    return start;
  }

  /// Sub-sample lag by fitting a parabola through the peak and its neighbours.
  ///
  /// Lag is quantised to whole samples, and that quantisation is what limits
  /// accuracy at high rates: at 104 Hz a 170 bpm beat is only 37 samples, so
  /// one sample of error is already 4.6 bpm. Interpolating recovers most of it
  /// at no cost.
  double refinedLag(int lag) {
    final double ym = valueAtLag(lag - 1);
    final double y0 = valueAtLag(lag);
    final double yp = valueAtLag(lag + 1);
    if (ym < 0 || yp < 0) return lag.toDouble();
    final double denom = ym - 2 * y0 + yp;
    if (denom == 0) return lag.toDouble();
    final double delta = 0.5 * (ym - yp) / denom;
    if (delta.abs() > 1) return lag.toDouble();
    return lag + delta;
  }
}

AutocorrResult autocorrelate(
  List<double> x, {
  required int minLagSamples,
  required int maxLagSamples,
}) {
  final int n = x.length;
  final double mean = x.reduce((a, b) => a + b) / n;
  final List<double> c = x.map((double v) => v - mean).toList(growable: false);

  double energy = 0;
  for (final double v in c) {
    energy += v * v;
  }
  if (energy <= 0) {
    return const AutocorrResult(
        bestLagSamples: -1, bestValue: 0, values: <double>[], firstLagSamples: 0);
  }

  final int hi = math.min(maxLagSamples, n - 1);
  final List<double> values = <double>[];
  int bestLag = -1;
  double bestValue = -2;
  for (int lag = minLagSamples; lag <= hi; lag++) {
    double sum = 0;
    final int limit = n - lag;
    for (int i = 0; i < limit; i++) {
      sum += c[i] * c[i + lag];
    }
    final double v = sum / energy;
    values.add(v);
    if (v > bestValue) {
      bestValue = v;
      bestLag = lag;
    }
  }
  return AutocorrResult(
    bestLagSamples: bestLag,
    bestValue: bestValue,
    values: values,
    firstLagSamples: minLagSamples,
  );
}

/// Peaks that clear a prominence threshold and are at least [minDistance]
/// samples apart, keeping the taller one when two are too close.
///
/// Used for beat-to-beat intervals, which is what heart-rate variability is
/// computed from — the autocorrelation gives the average rate, but not the
/// individual beats.
List<int> findPeaks(
  List<double> x, {
  required int minDistance,
  required double minProminence,
}) {
  final List<int> candidates = <int>[];
  for (int i = 1; i < x.length - 1; i++) {
    if (x[i] > x[i - 1] && x[i] >= x[i + 1] && x[i] >= minProminence) {
      candidates.add(i);
    }
  }
  candidates.sort((int a, int b) => x[b].compareTo(x[a]));

  final List<int> kept = <int>[];
  for (final int c in candidates) {
    bool tooClose = false;
    for (final int k in kept) {
      if ((c - k).abs() < minDistance) {
        tooClose = true;
        break;
      }
    }
    if (!tooClose) kept.add(c);
  }
  kept.sort();
  return kept;
}
