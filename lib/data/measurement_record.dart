/// One saved measurement.
///
/// This is designed to be handed to a veterinarian, which drives two choices
/// that would otherwise look like over-engineering:
///
///   * **Every quality figure is stored, not just the heart rate.** A number
///     without its provenance invites a clinical decision it cannot support.
///     Beat count, interval variability, dropped-packet count and the
///     analyser's own verdict all travel with the value.
///   * **Nothing is silently filled in.** An unusable measurement stores a null
///     heart rate rather than a plausible guess.
library;

import 'package:collar_vitals/collar_vitals.dart';

class MeasurementRecord {
  const MeasurementRecord({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.quality,
    this.heartRateBpm,
    this.heartRateConfidence = 0,
    this.respirationPerMin,
    this.bodyTempC,
    this.sdnnMs,
    this.rmssdMs,
    this.beatIntervalCvPercent,
    this.beatCount = 0,
    this.sampleCount = 0,
    this.gapCount = 0,
    this.receiveErrors = 0,
    this.imuRateHz,
    this.note,
    this.posture,
    this.beatIntervalsMs = const <double>[],
  });

  /// Start time in UTC millis, which doubles as a natural sort key and is
  /// unique in practice because two measurements cannot start in the same
  /// millisecond.
  final String id;

  final DateTime startedAt;
  final double durationSeconds;

  /// Stored as a string so an older app can still read a file written by a
  /// newer one that added a level.
  final String quality;

  /// Null when the measurement was unusable. **Do not default this to 0.**
  final double? heartRateBpm;
  final double heartRateConfidence;
  final double? respirationPerMin;

  /// From the infrared sensor, when it is connected. Null otherwise — as of
  /// 2026-09-12 the module was not being detected.
  final double? bodyTempC;

  final double? sdnnMs;
  final double? rmssdMs;
  final double? beatIntervalCvPercent;
  final int beatCount;

  // ---- provenance, so a vet can judge the number ----
  final int sampleCount;

  /// Dropped BLE notifications. Gaps break beat intervals, so a high count
  /// invalidates the variability figures even when the average rate looks fine.
  final int gapCount;
  final int receiveErrors;
  final int? imuRateHz;

  /// What the owner observed: "after a walk", "asleep", "at the clinic".
  /// Heart rate without context is close to meaningless — 140 bpm is alarming
  /// at rest and unremarkable after exercise.
  final String? note;

  /// Standing, sitting, lying. Posture shifts the baseline.
  final String? posture;

  /// Beat-to-beat intervals, kept so a rhythm strip can be redrawn later and
  /// so a future analysis can be re-run without the raw capture.
  final List<double> beatIntervalsMs;

  factory MeasurementRecord.fromResult({
    required DateTime startedAt,
    required VitalsResult result,
    int gapCount = 0,
    int sampleCount = 0,
    int? imuRateHz,
    int receiveErrors = 0,
    double? bodyTempC,
    String? note,
    String? posture,
  }) {
    return MeasurementRecord(
      id: startedAt.toUtc().millisecondsSinceEpoch.toString(),
      startedAt: startedAt,
      durationSeconds: result.durationSeconds,
      quality: result.quality.name,
      heartRateBpm: result.heartRateBpm,
      heartRateConfidence: result.heartRateConfidence,
      respirationPerMin: result.respirationPerMin,
      bodyTempC: bodyTempC,
      sdnnMs: result.sdnnMs,
      rmssdMs: result.rmssdMs,
      beatIntervalCvPercent: result.beatIntervalCvPercent,
      beatCount: result.beatCount,
      sampleCount: sampleCount,
      gapCount: gapCount,
      receiveErrors: receiveErrors,
      imuRateHz: imuRateHz,
      note: note,
      posture: posture,
      // Rounded to whole milliseconds: the source resolution is ~2.4 ms at
      // 417 Hz, so extra decimals would be false precision.
      beatIntervalsMs: result.beatIntervalsMs
          .map((double v) => v.roundToDouble())
          .toList(growable: false),
    );
  }

  bool get isUsable => quality != 'unusable' && heartRateBpm != null;

  /// A one-line caveat for the UI and for any export, derived from the stored
  /// provenance rather than from the reader's optimism.
  String? get caveat {
    switch (caveatCode) {
      case 'unusable':
        return '信号が不十分なため、心拍数は算出できませんでした。';
      case 'fair':
        return '信号が弱めです。参考値として扱ってください。';
      case 'gaps':
        return '通信の取りこぼしが多いため、拍間隔の指標は信頼できません。';
    }
    return null;
  }

  /// The same judgement as [caveat] but language-neutral, so the UI can show
  /// it in the user's language. [caveat] itself stays Japanese because the CSV
  /// export goes to a Japanese vet.
  String? get caveatCode {
    if (quality == 'unusable' || isIrregular) {
      return isIrregular ? 'irregular' : 'unusable';
    }
    if (rateDisagrees) return 'rate_disagrees';
    if (quality == 'fair') return 'fair';
    if (gapCount > beatCount * 0.1) return 'gaps';
    return null;
  }

  /// 拍の列が拍の列と呼べないほど乱れている。しきい値 35% の根拠は
  /// [VitalsAnalyzer] 側のコメントにある（両側の実測値から決めた）。
  bool get isIrregular {
    final double? rmad = beatIntervalRmadPercent;
    return rmad != null && rmad > 35;
  }

  /// 画面に出す品質。
  ///
  /// 保存されている [quality] は測定した時点の判定で、その後に判定の作りが
  /// 変わっても書き換わらない。保存済みの数値から今の基準で見直したものを
  /// 表示に使う。そうしないと、チップが「信頼できる」なのに注記が
  /// 「参考値です」と出る、という食い違いが起きる（実機で起きた）。
  ///
  /// 保存されている値は書き換えない。測定は起きた出来事の記録なので、
  /// あとから中身を書き換えるのは筋が違う。表示のときだけ読み替える。
  String get effectiveQuality {
    if (quality == 'unusable' || isIrregular) return 'unusable';
    if (rateDisagrees && quality == 'good') return 'fair';
    return quality;
  }

  /// 拍間隔のばらつき（中央値からのずれの中央値 ÷ 中央値、%）。
  ///
  /// 標準偏差の変動係数([beatIntervalCvPercent])は数個の飛び値で壊れる。
  /// 実測で、でたらめに並べた拍の変動係数 25% が正しい信号の 33〜50% より
  /// 小さくなり、大小が逆転した。画面に出すのはこちらを使う。
  double? get beatIntervalRmadPercent {
    if (beatIntervalsMs.length < 3) return null;
    final List<double> sorted = List<double>.of(beatIntervalsMs)..sort();
    final double median = sorted[sorted.length ~/ 2];
    if (median <= 0) return null;
    final List<double> dev = beatIntervalsMs
        .map((double v) => (v - median).abs())
        .toList(growable: false)
      ..sort();
    return dev[dev.length ~/ 2] / median * 100;
  }

  /// 拍が測定時間のどれだけを覆っているか（%）。
  /// 途切れ途切れにしか拾えていない測定を見つけるための物差し。
  double? get beatCoveragePercent {
    if (beatIntervalsMs.length < 3 || durationSeconds <= 0) return null;
    final List<double> sorted = List<double>.of(beatIntervalsMs)..sort();
    final double median = sorted[sorted.length ~/ 2];
    return beatIntervalsMs.length * median / 1000 / durationSeconds * 100;
  }

  /// 拍を1つずつ数えて出した心拍。保存済みの拍間隔から求めるので、
  /// 記録を作り直さなくても後から突き合わせられる。
  double? get beatRateBpm {
    if (beatIntervalsMs.length < 3) return null;
    final List<double> sorted = List<double>.of(beatIntervalsMs)..sort();
    final double median = sorted[sorted.length ~/ 2];
    return median > 0 ? 60000 / median : null;
  }

  /// [heartRateBpm] と [beatRateBpm] が 25% 以上ずれている。
  ///
  /// 波の周期(自己相関)と拍の数え上げは独立した2つの数え方で、一致して
  /// いれば強い裏付けになる。食い違うときは、心弾動の1拍の中にある2つ目の
  /// 山を拍として拾っている疑いがある。どちらが正しいかは信号を見ないと
  /// 決められないので、黙って選ばずに注記として出す。
  bool get rateDisagrees {
    final double? a = heartRateBpm;
    final double? b = beatRateBpm;
    if (a == null || b == null || a <= 0) return false;
    final double ratio = b / a;
    return ratio < 0.75 || ratio > 1.33;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': 1,
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'duration_s': durationSeconds,
        'quality': quality,
        'heart_rate_bpm': heartRateBpm,
        'heart_rate_confidence': heartRateConfidence,
        'respiration_per_min': respirationPerMin,
        'body_temp_c': bodyTempC,
        'sdnn_ms': sdnnMs,
        'rmssd_ms': rmssdMs,
        'beat_interval_cv_percent': beatIntervalCvPercent,
        'beat_count': beatCount,
        'sample_count': sampleCount,
        'gap_count': gapCount,
        'receive_errors': receiveErrors,
        'imu_rate_hz': imuRateHz,
        'note': note,
        'posture': posture,
        'beat_intervals_ms': beatIntervalsMs,
      };

  factory MeasurementRecord.fromJson(Map<String, dynamic> j) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    int i(Object? v) => v is num ? v.toInt() : 0;
    return MeasurementRecord(
      id: (j['id'] ?? '').toString(),
      startedAt:
          DateTime.tryParse((j['started_at'] ?? '').toString()) ?? DateTime(1970),
      durationSeconds: d(j['duration_s']) ?? 0,
      quality: (j['quality'] ?? 'unusable').toString(),
      heartRateBpm: d(j['heart_rate_bpm']),
      heartRateConfidence: d(j['heart_rate_confidence']) ?? 0,
      respirationPerMin: d(j['respiration_per_min']),
      bodyTempC: d(j['body_temp_c']),
      sdnnMs: d(j['sdnn_ms']),
      rmssdMs: d(j['rmssd_ms']),
      beatIntervalCvPercent: d(j['beat_interval_cv_percent']),
      beatCount: i(j['beat_count']),
      sampleCount: i(j['sample_count']),
      gapCount: i(j['gap_count']),
      receiveErrors: i(j['receive_errors']),
      imuRateHz: j['imu_rate_hz'] is num
          ? (j['imu_rate_hz'] as num).toInt()
          : null,
      note: j['note']?.toString(),
      posture: j['posture']?.toString(),
      beatIntervalsMs: (j['beat_intervals_ms'] is List)
          ? (j['beat_intervals_ms'] as List)
              .whereType<num>()
              .map((num v) => v.toDouble())
              .toList(growable: false)
          : const <double>[],
    );
  }
}
