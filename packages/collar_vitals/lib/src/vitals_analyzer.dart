/// Heart rate and respiration from one accelerometer stream.
///
/// The method was validated on 2026-09-12 against 60-second recordings from the
/// collar's own IMUs, cross-checked against SciPy with a Hilbert envelope and
/// template matching. Six independent measurements agreed at 77.1 ± 1.63 bpm,
/// and this FFT-free pipeline reproduces the same 78.0 bpm at 104 Hz — which is
/// the highest rate the BLE link offers, so nothing faster is required.
///
/// What the sensor actually measures is *ballistocardiography*: the mechanical
/// recoil of the body as the heart ejects blood. It is not an ECG. It gives a
/// rate and its variability, never a rhythm diagnosis.
library;

import 'dart:math' as math;

import 'biquad.dart';

/// Plausible heart-rate range to search.
///
/// **Dogs are not people.** Resting canine heart rate runs roughly 60–120 bpm
/// in large breeds and 100–180 bpm in small ones, against 60–100 for an adult
/// human — and puppies go higher still. A range tuned to humans would clip a
/// small dog's true rate and silently report its sub-harmonic, so the default
/// here is deliberately wide.
class HeartRateRange {
  const HeartRateRange({required this.minBpm, required this.maxBpm});

  /// Wide enough for any dog from a resting Great Dane to an excited puppy.
  static const HeartRateRange dog =
      HeartRateRange(minBpm: 50, maxBpm: 220);

  /// Narrower, for validating the pipeline on a human subject.
  static const HeartRateRange human =
      HeartRateRange(minBpm: 40, maxBpm: 180);

  final double minBpm;
  final double maxBpm;
}

/// How much to trust a measurement. This exists because the result may be shown
/// to a veterinarian, and an unreliable number presented without qualification
/// is worse than no number.
enum VitalsQuality {
  /// Clear periodicity, beat intervals consistent. Usable as a reference.
  good,

  /// Periodicity present but noisy — the animal probably moved. Treat the rate
  /// as approximate.
  fair,

  /// No convincing periodicity. The rate must not be reported as a measurement.
  unusable,
}

class VitalsResult {
  const VitalsResult({
    required this.sampleRateHz,
    required this.durationSeconds,
    required this.quality,
    this.heartRateBpm,
    this.heartRateConfidence = 0,
    this.beatTimesSeconds = const <double>[],
    this.beatIntervalsMs = const <double>[],
    this.sdnnMs,
    this.rmssdMs,
    this.respirationPerMin,
    this.respirationConfidence = 0,
    this.beatBand = const <double>[],
    this.beatEnvelope = const <double>[],
    this.respirationWave = const <double>[],
    this.unusableReason,
  });

  final double sampleRateHz;
  final double durationSeconds;
  final VitalsQuality quality;

  /// Null when [quality] is [VitalsQuality.unusable].
  final double? heartRateBpm;

  /// なぜ算出できなかったのか。言語に依存しないコード
  /// (`too_short` / `rate_too_low` / `no_periodicity`) で、文言は UI 側で選ぶ。
  /// 「測れなかった」だけでは次に何をすればいいか分からないので、理由を残す。
  final String? unusableReason;

  /// Peak autocorrelation, 0..1.
  final double heartRateConfidence;

  /// Individual beat times, for plotting and for variability.
  final List<double> beatTimesSeconds;
  final List<double> beatIntervalsMs;

  /// Standard deviation of beat intervals — the common heart-rate variability
  /// summary. Reported in ms.
  ///
  /// ⚠️ Clinical HRV is measured from an ECG's R waves. These intervals come
  /// from a mechanical signal and carry more jitter, so the absolute value is
  /// not comparable to published ECG norms. It is still useful for comparing
  /// one measurement against the same animal's own history.
  final double? sdnnMs;

  /// Root mean square of successive interval differences, ms. Same caveat as
  /// [sdnnMs].
  final double? rmssdMs;

  final double? respirationPerMin;
  final double respirationConfidence;

  /// Filtered waveforms, kept so the UI can draw what was actually analysed
  /// rather than a decorative line.
  final List<double> beatBand;
  final List<double> beatEnvelope;
  final List<double> respirationWave;

  /// Coefficient of variation of the beat intervals, as a percentage. A tight
  /// value (a few percent at rest) is the clearest sign the detection locked
  /// onto a real beat rather than noise.
  double? get beatIntervalCvPercent {
    if (beatIntervalsMs.length < 3) return null;
    final double mean =
        beatIntervalsMs.reduce((a, b) => a + b) / beatIntervalsMs.length;
    if (mean <= 0) return null;
    double s = 0;
    for (final double v in beatIntervalsMs) {
      s += (v - mean) * (v - mean);
    }
    return math.sqrt(s / beatIntervalsMs.length) / mean * 100;
  }

  /// Beats actually detected, for the record shown to a vet.
  int get beatCount => beatTimesSeconds.length;

  @override
  String toString() => 'VitalsResult(${quality.name}, '
      'HR=${heartRateBpm?.toStringAsFixed(1) ?? "—"} bpm '
      '(conf ${heartRateConfidence.toStringAsFixed(2)}), '
      'RR=${respirationPerMin?.toStringAsFixed(1) ?? "—"} /min, '
      'beats=$beatCount)';
}

/// Turns a window of accelerometer magnitude into vital signs.
///
/// Feed it the *magnitude* `√(ax²+ay²+az²)`, not a single axis: magnitude is
/// invariant to how the collar happens to be rotated, which matters because a
/// collar's orientation on an animal is never controlled.
class VitalsAnalyzer {
  const VitalsAnalyzer({
    this.range = HeartRateRange.dog,
    this.beatBandLowHz = 8.0,
    this.beatBandHighHz = 40.0,
    this.respirationLowHz = 0.12,
    this.respirationHighHz = 0.7,
    this.minConfidenceGood = 0.30,
    this.minConfidenceFair = 0.15,
  });

  final HeartRateRange range;

  /// 8–40 Hz. Chosen empirically on 2026-09-12: of the bands tried
  /// (0.7–12, 1–20, 2–25, 4–30, 5–40, 8–40 Hz) this gave the sharpest
  /// beat peaks, a 6.2:1 peak-to-background ratio against 2.9:1 for the
  /// lowest band. Respiratory motion is orders of magnitude larger and lives
  /// below 1 Hz, so starting at 8 Hz rejects it outright.
  final double beatBandLowHz;
  final double beatBandHighHz;

  final double respirationLowHz;
  final double respirationHighHz;

  final double minConfidenceGood;
  final double minConfidenceFair;

  /// Shortest window worth analysing. At 50 bpm the slowest plausible beat is
  /// 1.2 s, and the autocorrelation needs several cycles to be meaningful.
  static const double minDurationSeconds = 15.0;

  /// これ未満のサンプリングでは 8 Hz 以上の心弾動成分がほとんど残らないので、
  /// 心拍は「算出不可」とする。LSM6DS3TR-C の設定値で言えば 52 Hz 以上。
  static const double minSampleRateHz = 40.0;

  /// [minSeconds] は「この長さに足りなければ算出しない」境界。既定は
  /// [minDurationSeconds]（保存する測定の基準）。画面に出す途中の推定値は
  /// もっと早く見せたいので、呼ぶ側が短い値を渡せるようにしてある。
  /// 自己相関は最低3周期ぶんあれば立つので、8秒でも 50 bpm までは足りる。
  VitalsResult analyze(
    List<double> magnitude, {
    required double sampleRateHz,
    double? minSeconds,
  }) {
    final double minLen = minSeconds ?? minDurationSeconds;
    final double duration = magnitude.length / sampleRateHz;
    if (duration < minLen) {
      return VitalsResult(
        sampleRateHz: sampleRateHz,
        durationSeconds: duration,
        quality: VitalsQuality.unusable,
        unusableReason: 'too_short',
      );
    }

    // サンプリングが低すぎるときは「測れない」と言う。数字を出してはいけない。
    //
    // 2026-09-13、実機が 26 Hz で動いていたときに 221.4 bpm を3回続けて
    // 返した。ナイキスト周波数 13 Hz に対して 8–40 Hz の帯域通過を指定した
    // ため、biquad の係数が壊れて出力が発振していたのが原因。エラーにも
    // ならず「good・信頼度0.93」と表示されたので、いちばん危険な壊れ方だった。
    if (sampleRateHz < minSampleRateHz) {
      return VitalsResult(
        sampleRateHz: sampleRateHz,
        durationSeconds: duration,
        quality: VitalsQuality.unusable,
        unusableReason: 'rate_too_low',
      );
    }

    // ---- heartbeat ----
    // 帯域はナイキスト周波数の中に収める。収まらないときは切り詰めて解析を
    // 続けるが、心弾動の高い成分が落ちるぶん信頼度は下がる。実測(400 Hz の
    // 実データを間引いて検証、2026-09-13):
    //   416 Hz → 77.7 bpm 信頼度0.59 / 208 Hz → 77.9 0.33
    //   104 Hz → 77.8 bpm 信頼度0.25 /  52 Hz → 78.7 0.19
    final double nyquist = sampleRateHz / 2;
    final double bandHigh = math.min(beatBandHighHz, nyquist * 0.9);
    final double bandLow = math.min(beatBandLowHz, bandHigh * 0.5);

    final List<double> band = bandPass(
      magnitude,
      sampleRateHz: sampleRateHz,
      lowHz: bandLow,
      highHz: bandHigh,
    );
    final List<double> env = envelope(band, sampleRateHz: sampleRateHz);

    final int minLag = (sampleRateHz * 60 / range.maxBpm).floor();
    final int maxLag = (sampleRateHz * 60 / range.minBpm).ceil();
    final AutocorrResult ac =
        autocorrelate(env, minLagSamples: minLag, maxLagSamples: maxLag);

    // Pick the lag carefully: reject the search boundary (not a real period),
    // guard against 2×/3× sub-harmonics, then interpolate below one-sample
    // resolution. Skipping the first two steps reported 50 bpm for a 100 bpm
    // input and 57 bpm for 170 bpm during development.
    double? bpm;
    int beatLag = -1;
    if (ac.bestLagSamples > 0) {
      beatLag = ac.fundamentalLag(minLagSamples: minLag);
      bpm = 60 * sampleRateHz / ac.refinedLag(beatLag);
    }
    // Confidence must describe the rate we are actually reporting, so read it
    // at the chosen lag rather than at the raw arg-max.
    final double confidence =
        beatLag > 0 ? ac.valueAtLag(beatLag).clamp(0.0, 1.0) : 0.0;

    final VitalsQuality quality = confidence >= minConfidenceGood
        ? VitalsQuality.good
        : confidence >= minConfidenceFair
            ? VitalsQuality.fair
            : VitalsQuality.unusable;

    // ---- individual beats, for variability ----
    List<double> beatTimes = const <double>[];
    List<double> intervals = const <double>[];
    double? sdnn, rmssd;
    if (bpm != null && quality != VitalsQuality.unusable) {
      double sumSq = 0;
      for (final double v in env) {
        sumSq += v * v;
      }
      final double rms = math.sqrt(sumSq / env.length);
      // Beats can never be closer than 60% of the detected interval; that
      // guard is what stops one beat's secondary wave being counted twice.
      final List<int> peaks = findPeaks(
        env,
        minDistance: (beatLag * 0.6).round(),
        minProminence: rms * 0.5,
      );
      beatTimes = peaks
          .map((int i) => i / sampleRateHz)
          .toList(growable: false);
      if (beatTimes.length >= 3) {
        final List<double> iv = <double>[];
        for (int i = 1; i < beatTimes.length; i++) {
          iv.add((beatTimes[i] - beatTimes[i - 1]) * 1000);
        }
        intervals = iv;
        final double mean = iv.reduce((a, b) => a + b) / iv.length;
        double s = 0;
        for (final double v in iv) {
          s += (v - mean) * (v - mean);
        }
        sdnn = math.sqrt(s / iv.length);
        double d = 0;
        for (int i = 1; i < iv.length; i++) {
          final double diff = iv[i] - iv[i - 1];
          d += diff * diff;
        }
        rmssd = iv.length > 1 ? math.sqrt(d / (iv.length - 1)) : null;
      }
    }

    // ---- respiration ----
    final List<double> resp = bandPass(
      magnitude,
      sampleRateHz: sampleRateHz,
      lowHz: respirationLowHz,
      highHz: respirationHighHz,
      stages: 1,
    );
    final AutocorrResult respAc = autocorrelate(
      resp,
      minLagSamples: (sampleRateHz * 60 / 60).floor(), // 60 /min
      maxLagSamples: (sampleRateHz * 60 / 6).ceil(), //  6 /min
    );
    double? rr;
    if (respAc.bestLagSamples > 0 && respAc.bestValue >= minConfidenceFair) {
      final int respLag = respAc.fundamentalLag(
          minLagSamples: (sampleRateHz * 60 / 60).floor());
      rr = 60 * sampleRateHz / respAc.refinedLag(respLag);
    }

    return VitalsResult(
      sampleRateHz: sampleRateHz,
      durationSeconds: duration,
      quality: quality,
      heartRateBpm: quality == VitalsQuality.unusable ? null : bpm,
      unusableReason:
          quality == VitalsQuality.unusable ? 'no_periodicity' : null,
      heartRateConfidence: confidence,
      beatTimesSeconds: beatTimes,
      beatIntervalsMs: intervals,
      sdnnMs: sdnn,
      rmssdMs: rmssd,
      respirationPerMin: rr,
      respirationConfidence: respAc.bestValue.clamp(0.0, 1.0),
      beatBand: band,
      beatEnvelope: env,
      respirationWave: resp,
    );
  }
}
