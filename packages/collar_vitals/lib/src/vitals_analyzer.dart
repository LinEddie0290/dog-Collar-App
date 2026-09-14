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
    this.beatRateBpm,
    this.rateDisagrees = false,
    this.rateFromBeats = false,
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

  /// 拍を1つずつ数えて出した心拍。[heartRateBpm] は自己相関（信号全体の
  /// 周期性）から、こちらは検出した拍の間隔の中央値から求めている。
  ///
  /// 2つを並べて持つのは、食い違ったときに気づけるようにするため。
  /// 心弾動は1拍の中に I 波・J 波と拡張期の波があり、センサーの当て方に
  /// よっては信号が「半分の周期でも周期的」に見える。そうなると自己相関は
  /// 2倍の心拍を返すが、拍を数えるほうは正しいままのことがある。
  /// 2026-09-13 の実機で、拍のしるしが 72 /分なのに数字が 137 bpm と
  /// 出たのがこれ。どちらが正しいかは信号を見ないと決められないので、
  /// 黙ってどちらかを選ぶのではなく [rateDisagrees] で告げる。
  final double? beatRateBpm;

  /// [heartRateBpm] と [beatRateBpm] が 25% 以上ずれている。
  ///
  /// このとき品質は [VitalsQuality.good] にはしない。2つの独立した数え方が
  /// 一致しないものを「信頼できる」と表示してはいけない。
  final bool rateDisagrees;

  /// [heartRateBpm] が自己相関ではなく拍の数え上げから来ている。
  ///
  /// 2つが食い違ったときは拍を数えた値を採る。理由は実機で2回続けて
  /// 確かめられたため(2026-09-13): 画面の拍のしるしが 72 /分のときに
  /// 自己相関は 137 bpm、別の記録では拍が 70 bpm のときに 224 bpm。
  /// 224 は探索範囲の上限 220 に張り付いた値で、自己相関が失敗したときの
  /// 典型的な形。400 Hz の実測データでは両者が一致する(77〜78 bpm)ので、
  /// 検証できている場合にこの選び方が害になることはない。
  final bool rateFromBeats;

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

  /// 拍間隔のばらつき（中央値からのずれの中央値 ÷ 中央値、%）。
  /// [beatIntervalCvPercent] より飛び値に強く、画面に出すのはこちら。
  double? get beatIntervalRmadPercent => beatIntervalsMs.length < 3
      ? null
      : VitalsAnalyzer._rmadPercent(beatIntervalsMs);

  /// 拍が測定時間のどれだけを覆っているか（%）。
  double? get beatCoveragePercent => beatIntervalsMs.length < 3
      ? null
      : VitalsAnalyzer._coveragePercent(beatIntervalsMs, durationSeconds);

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

  /// 拍間隔のばらつき。中央値からのずれの中央値 ÷ 中央値（%）。
  ///
  /// 標準偏差ではなく中央値を使うのは、拍を1つ数え落とすと間隔が2倍の値に
  /// なり、それが数個混ざるだけで標準偏差が壊れるから。中央値なら半分以上が
  /// 正しければ保たれる。
  static double _rmadPercent(List<double> intervals) {
    final List<double> sorted = List<double>.of(intervals)..sort();
    final double median = sorted[sorted.length ~/ 2];
    if (median <= 0) return 999;
    final List<double> dev = intervals
        .map((double v) => (v - median).abs())
        .toList(growable: false)
      ..sort();
    return dev[dev.length ~/ 2] / median * 100;
  }

  /// 拍が測定時間のどれだけを覆っているか（%）。
  ///
  /// 拍の数 × 間隔の中央値 ÷ 測定時間。途切れ途切れにしか拾えていない
  /// 測定を見つけるための物差し。間隔のばらつきだけでは、拾えた区間が
  /// 揃っていれば通ってしまう。
  static double _coveragePercent(List<double> intervals, double seconds) {
    if (seconds <= 0) return 0;
    final List<double> sorted = List<double>.of(intervals)..sort();
    final double median = sorted[sorted.length ~/ 2];
    return intervals.length * median / 1000 / seconds * 100;
  }

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

    VitalsQuality quality = confidence >= minConfidenceGood
        ? VitalsQuality.good
        : confidence >= minConfidenceFair
            ? VitalsQuality.fair
            : VitalsQuality.unusable;

    // ---- individual beats, for variability ----
    List<double> beatTimes = const <double>[];
    List<double> intervals = const <double>[];
    double? sdnn, rmssd;
    if (bpm != null && quality != VitalsQuality.unusable) {
      // しきい値は二乗平均ではなく、正の値の中央値を使う。二乗平均は
      // 突発的な大きな山（体の動き、フィルタの立ち上がり）に引っ張られて
      // 跳ね上がり、そうなると本物の拍まで閾値を下回って数え落とす。
      // 実機で拍のしるしが1拍おきになっていたのがこれ。
      final List<double> positive =
          env.where((double v) => v > 0).toList(growable: false);
      double level;
      if (positive.isEmpty) {
        level = 0;
      } else {
        final List<double> sorted = List<double>.of(positive)..sort();
        level = sorted[sorted.length ~/ 2];
      }
      // Beats can never be closer than 60% of the detected interval; that
      // guard is what stops one beat's secondary wave being counted twice.
      final List<int> peaks = findPeaks(
        env,
        minDistance: (beatLag * 0.6).round(),
        minProminence: level,
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

    // 拍の間隔の中央値から出した心拍。自己相関の答えと突き合わせる。
    // 中央値なので、数え落としで1つ2つ長い間隔が混ざっても崩れない。
    double? beatRate;
    if (intervals.length >= 3) {
      final List<double> sorted = List<double>.of(intervals)..sort();
      final double median = sorted[sorted.length ~/ 2];
      if (median > 0) beatRate = 60000 / median;
    }
    bool disagrees = false;
    bool fromBeats = false;
    bool irregular = false;
    if (bpm != null && beatRate != null && bpm > 0) {
      final double ratio = beatRate / bpm;
      disagrees = ratio < 0.75 || ratio > 1.33;
      if (disagrees &&
          beatRate >= range.minBpm &&
          beatRate <= range.maxBpm) {
        // 食い違ったら拍を数えた値を採る。拍は1つずつ数えられるので
        // 確かめようがあるが、自己相関の周期は確かめようがない。
        bpm = beatRate;
        fromBeats = true;
      }
      if (disagrees && quality == VitalsQuality.good) {
        // 2つの独立した数え方が一致しないものを「信頼できる」とは言わない。
        // 条件に disagrees を入れ忘れると、拍が数えられた測定が全部
        // 参考値に落ちて good が一切出なくなる(2026-09-13 にやった)。
        quality = VitalsQuality.fair;
      }
    }

    // 「その拍の列は本当に拍の列か」の関門。
    //
    // 物差しは rMAD（中央値からのずれの中央値 ÷ 中央値）。標準偏差の変動
    // 係数は使えない。でたらめに並べた拍の変動係数 25% が正しい信号の
    // 33〜50% より小さく、大小が逆転していた。
    //
    // しきい値 35% は、同じ実装で測った両側の実測値から決めた
    // (2026-09-13、すべて Dart 側の値):
    //
    //   通したい側 — 合成信号 80/100/130/170 bpm → 9.2 / 13.7 / 18.3 / 26.8%
    //   棄却したい側 — 実機の記録8件（いずれも2つの数え方が食い違った）
    //                  → 43.9 / 44.7 / 47.4 / 50.6 / 53.1 / 54.3 / 54.5 / 57.5%
    //
    // 26.8 と 43.9 の間に隙間がある。35% はその真ん中。
    //
    // 網羅率（拍の数 × 間隔の中央値 ÷ 測定時間）は関門にしない。実機の
    // 記録が 13〜86% で、合成信号の 62〜79% と重なって分離しないため。
    // 数値としては意味があるので表示と CSV には残す。
    //
    // Python で測った値(合成 80 bpm で 3.8%)を根拠にしようとして失敗した。
    // 実装が違えば値も違う。しきい値は必ず同じ実装の値から決める。
    if (intervals.length >= 3 &&
        quality != VitalsQuality.unusable &&
        _rmadPercent(intervals) > 35) {
      quality = VitalsQuality.unusable;
      irregular = true;
    }
    return VitalsResult(
      sampleRateHz: sampleRateHz,
      durationSeconds: duration,
      quality: quality,
      beatRateBpm: beatRate,
      rateDisagrees: disagrees,
      rateFromBeats: fromBeats,
      heartRateBpm: quality == VitalsQuality.unusable ? null : bpm,
      unusableReason: quality != VitalsQuality.unusable
          ? null
          : (irregular ? 'irregular' : 'no_periodicity'),
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
