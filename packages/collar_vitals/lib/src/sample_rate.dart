/// 首輪の時刻（マイクロ秒）から、本当の周波数を出す（T22、D-032）。
///
/// 以前は「隣どうしの時刻の差の中央値」から出していた。ところが首輪の時刻は
/// 間隔が偏ってばらつく（2026-09-12：1.7〜2.9 ms）ので、中央値は 2.50 ms
/// → 401 Hz と出る。実際は 25,021 個 ÷ 60 秒 ＝ 417 Hz。周波数を低く入れると
/// 時間が伸びたことになり、心拍・呼吸が約 4% 低く出ていた。
///
/// ここでは「数 ÷ 時間」（＝平均の間隔の逆数）で出す。ただし BLE のパケット
/// 落ちなどの大きな抜けは、時間に数えない（中央値の [gapFactor] 倍より長い差）。
/// collar-pipeline の Python（`native_fs`、平均の間隔）と同じ考え方。
library;

/// [deviceUs]：首輪の時刻（単調増加のマイクロ秒）。[minSamples] 個未満なら null。
double? estimateSampleRateHz(List<num> deviceUs,
    {int minSamples = 32, double gapFactor = 3.0}) {
  if (deviceUs.length < minSamples) return null;
  final List<double> steps = <double>[];
  for (int i = 1; i < deviceUs.length; i++) {
    final double d = (deviceUs[i] - deviceUs[i - 1]).toDouble();
    if (d > 0) steps.add(d);
  }
  if (steps.isEmpty) return null;
  final List<double> sorted = List<double>.of(steps)..sort();
  final double median = sorted[sorted.length ~/ 2];
  final double limit = median * gapFactor;
  double total = 0;
  int count = 0;
  for (final double d in steps) {
    if (d <= limit) {
      total += d;
      count++;
    }
  }
  if (count == 0 || total <= 0) return null;
  return count * 1e6 / total;
}

/// 比べるための旧い出し方（中央値）。新しいコードでは使わない。
double? medianSampleRateHz(List<num> deviceUs, {int minSamples = 32}) {
  if (deviceUs.length < minSamples) return null;
  final List<double> steps = <double>[];
  for (int i = 1; i < deviceUs.length; i++) {
    final double d = (deviceUs[i] - deviceUs[i - 1]).toDouble();
    if (d > 0 && d < 1e6) steps.add(d);
  }
  if (steps.isEmpty) return null;
  steps.sort();
  return 1e6 / steps[steps.length ~/ 2];
}
