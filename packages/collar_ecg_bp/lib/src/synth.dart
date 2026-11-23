import 'dart:math' as math;
import 'dart:typed_data';

/// golden 用のにせの信号 synth_v1（collar-pipeline の scripts/make_ecg_bp_golden.py の synth と同じ式）。
/// 60 秒・400 Hz・3 軸（m/s²）：心拍の振動（90 bpm）＋呼吸（15 回/分）＋小さい雑音＋50〜54 秒に動き。
/// 人のデータは git に入れられないので、iPhone の確認もこれで行う（D-066 H3）。
({Float64List ax, Float64List ay, Float64List az}) synthCollarAcc({int n = 24000, double fs = 400.0}) {
  final Float64List ax = Float64List(n), ay = Float64List(n), az = Float64List(n);
  for (int i = 0; i < n; i++) {
    final double t = i / fs;
    final double u = t * 1.5 + 0.7;
    final double tb = (u - u.floorToDouble()) / 1.5;
    final double p = math.exp(-math.pow((tb - 0.05) / 0.012, 2)) * math.sin(2 * math.pi * 30 * (tb - 0.05)) +
        0.6 * math.exp(-math.pow((tb - 0.35) / 0.02, 2)) * math.sin(2 * math.pi * 18 * (tb - 0.35));
    final double b = 2 * math.pi * 0.25 * t;
    double x = 0.30 + 0.020 * p + 0.010 * math.sin(b) + 0.003 * math.sin(2 * math.pi * 47.3 * t);
    double y = 1.10 + 0.012 * p + 0.015 * math.sin(b + 1.0) + 0.003 * math.sin(2 * math.pi * 61.1 * t + 0.5);
    double z = 9.70 + 0.030 * p + 0.020 * math.sin(b + 2.0) + 0.003 * math.sin(2 * math.pi * 23.7 * t + 1.0);
    if (t >= 50.0 && t < 54.0) {
      final double e = math.sin(math.pi * (t - 50.0) / 4.0);
      final double m = math.sin(2 * math.pi * 2.5 * t) * e;
      x += 0.6 * m;
      y += 0.4 * m;
      z += 0.5 * m;
    }
    ax[i] = x;
    ay[i] = y;
    az[i] = z;
  }
  return (ax: ax, ay: ay, az: az);
}
