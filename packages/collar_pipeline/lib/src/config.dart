/// collar-pipeline の collar/config.py と同じ数字（仮の値も同じ）。
/// 数字を変えるときは Python と両方を変えること（golden テストで同じかを見る）。
class PipelineConfig {
  const PipelineConfig({
    this.resampleFs = 400,
    this.resampleMinFs = 380,
    this.cnnFs = 100,
    this.windowS = 2.0,
    this.windowStepS = 1.0,
    this.edgeDropS = 1.0,
    this.maxGapMs = 50,
    this.rebootBackUs = 1000000,
    this.biasStillS = 5.0,
    this.stillAccStd = 0.05,
    this.stillGyroStd = 0.03,
    this.accCheckTol = 0.03,
    this.lpfHz = 25.0,
    this.lpfOrder = 4,
    this.gravityHz = 0.3,
    this.restThreshold = 0.4,
    this.measureThreshold = 0.15,
    this.stillSeconds = 30,
    this.allowBlipS = 2.0,
  });

  final double resampleFs; // RESAMPLE_FS
  final double resampleMinFs; // RESAMPLE_MIN_FS
  final double cnnFs; // CNN_FS
  final double windowS; // WINDOW_S
  final double windowStepS; // WINDOW_STEP_S
  final double edgeDropS; // EDGE_DROP_S
  final int maxGapMs; // MAX_GAP_MS
  final int rebootBackUs; // REBOOT_BACK_US
  final double biasStillS; // BIAS_STILL_S
  final double stillAccStd; // STILL_ACC_STD
  final double stillGyroStd; // STILL_GYRO_STD
  final double accCheckTol; // ACC_CHECK_TOL
  final double lpfHz; // LPF_HZ
  final int lpfOrder; // LPF_ORDER
  final double gravityHz; // GRAVITY_HZ
  final double restThreshold; // REST_THRESHOLD_MS2
  final double measureThreshold; // MEASURE_THRESHOLD_MS2
  final double stillSeconds; // STILL_SECONDS
  final double allowBlipS; // ALLOW_BLIP_S

  PipelineConfig copyWith({double? lpfHz, double? gravityHz, double? cnnFs, double? restThreshold,
      double? measureThreshold, double? stillSeconds}) {
    return PipelineConfig(
      resampleFs: resampleFs,
      resampleMinFs: resampleMinFs,
      cnnFs: cnnFs ?? this.cnnFs,
      windowS: windowS,
      windowStepS: windowStepS,
      edgeDropS: edgeDropS,
      maxGapMs: maxGapMs,
      rebootBackUs: rebootBackUs,
      biasStillS: biasStillS,
      stillAccStd: stillAccStd,
      stillGyroStd: stillGyroStd,
      accCheckTol: accCheckTol,
      lpfHz: lpfHz ?? this.lpfHz,
      lpfOrder: lpfOrder,
      gravityHz: gravityHz ?? this.gravityHz,
      restThreshold: restThreshold ?? this.restThreshold,
      measureThreshold: measureThreshold ?? this.measureThreshold,
      stillSeconds: stillSeconds ?? this.stillSeconds,
      allowBlipS: allowBlipS,
    );
  }
}

/// Python の round()（偶数への丸め）。np.round も同じ。
int roundHalfEven(double x) {
  final double f = x.floorToDouble();
  final double diff = x - f;
  if (diff > 0.5) return f.toInt() + 1;
  if (diff < 0.5) return f.toInt();
  final int fi = f.toInt();
  return fi.isEven ? fi : fi + 1;
}
