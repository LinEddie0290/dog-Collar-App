// ignore_for_file: avoid_print
// このファイルは `dart run bin/demo.dart` で検証する CLI。
// print が出力そのものなので avoid_print はここでは適用しない。

/// Self-verifying test of the vitals pipeline.
///
/// Two kinds of check:
///
///   1. **Synthetic signals at known rates.** A ballistocardiogram-like burst
///      is repeated at an exact rate and buried under a respiratory component
///      50× larger plus noise. The analyzer has to recover the rate it was
///      given. Rates are chosen to span real canine physiology (80–170 bpm),
///      not just the human value we happened to measure — a small dog at
///      170 bpm is the case most likely to break a human-tuned pipeline.
///
///   2. **A real capture, if you pass one.** Give it the path to an
///      `onboard_imu.csv` produced by `./scripts/pet view` and it will run the
///      real thing. The 2026-09-12 chest recordings should come out at
///      78 bpm — that figure was established independently in SciPy with a
///      Hilbert envelope and template matching, so it is a genuine
///      cross-check, not this code agreeing with itself.
///
/// ```sh
/// dart run bin/demo.dart
/// dart run bin/demo.dart ~/Desktop/PET-main/captures/imu400/.../onboard_imu.csv
/// ```
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:collar_vitals/collar_vitals.dart';

int checks = 0;
int failures = 0;

void check(String what, bool ok, [String detail = '']) {
  checks++;
  if (ok) {
    print('  ok   $what');
  } else {
    failures++;
    print('  FAIL $what${detail.isEmpty ? '' : ' — $detail'}');
  }
}

/// A synthetic beat: a damped 20 Hz burst, which is roughly what the real
/// averaged beat waveform looked like (a sharp feature a few tens of ms wide).
double beatWave(double tSec) {
  if (tSec < 0 || tSec > 0.25) return 0;
  return math.exp(-tSec * 28) * math.sin(2 * math.pi * 20 * tSec);
}

List<double> synthesise({
  required double bpm,
  required double seconds,
  required double sampleRateHz,
  double breathsPerMin = 20,
  double noise = 0.05,
  int seed = 7,
}) {
  final math.Random rng = math.Random(seed);
  final int n = (seconds * sampleRateHz).round();
  final double beatPeriod = 60 / bpm;
  final List<double> out = List<double>.filled(n, 0.0);
  for (int i = 0; i < n; i++) {
    final double t = i / sampleRateHz;
    // Respiration: huge and slow, exactly the thing the band-pass must reject.
    double v = 2.5 * math.sin(2 * math.pi * (breathsPerMin / 60) * t);
    // Gravity, so the input looks like a real magnitude channel.
    v += 9.806;
    // Heartbeats.
    final double phase = t % beatPeriod;
    v += 0.05 * beatWave(phase);
    // Broadband noise.
    v += noise * (rng.nextDouble() - 0.5);
    out[i] = v;
  }
  return out;
}

void runSynthetic() {
  print('1. 合成信号 — 正解の心拍を復元できるか');
  print('   （呼吸成分を心拍の50倍の振幅で重ねた状態から抽出）\n');
  const VitalsAnalyzer analyzer = VitalsAnalyzer(range: HeartRateRange.dog);
  const double fs = 104.0;

  for (final double trueBpm in <double>[80, 100, 130, 170]) {
    final List<double> sig =
        synthesise(bpm: trueBpm, seconds: 60, sampleRateHz: fs);
    final VitalsResult r = analyzer.analyze(sig, sampleRateHz: fs);
    final double? got = r.heartRateBpm;
    final double err = got == null ? 999 : (got - trueBpm).abs();
    // 104 Hz quantises the lag, so the achievable resolution at 170 bpm is
    // about 4 bpm. Tolerance is set from that, not picked to pass.
    final double tol = math.max(3.0, trueBpm * trueBpm / (60 * fs) * 1.5);
    check(
      '正解 ${trueBpm.toStringAsFixed(0)} bpm → '
      '${got?.toStringAsFixed(1) ?? "検出不可"} bpm '
      '(許容 ±${tol.toStringAsFixed(1)}, 信頼度 ${r.heartRateConfidence.toStringAsFixed(2)})',
      err <= tol,
      'ずれ ${err.toStringAsFixed(1)} bpm',
    );
  }

  print('\n2. 呼吸も同時に取れるか');
  final List<double> sig =
      synthesise(bpm: 110, seconds: 60, sampleRateHz: fs, breathsPerMin: 24);
  final VitalsResult r = analyzer.analyze(sig, sampleRateHz: fs);
  check(
    '正解 24 回/分 → ${r.respirationPerMin?.toStringAsFixed(1) ?? "検出不可"} 回/分',
    r.respirationPerMin != null && (r.respirationPerMin! - 24).abs() <= 2.5,
  );

  print('\n3. 異常系 — 信号が無いときに数字を出さないか');
  final List<double> flat = List<double>.filled((60 * fs).round(), 9.806);
  final VitalsResult rf = analyzer.analyze(flat, sampleRateHz: fs);
  check('完全に平坦な入力は unusable になる',
      rf.quality == VitalsQuality.unusable && rf.heartRateBpm == null,
      '${rf.quality.name} / ${rf.heartRateBpm}');

  final math.Random rng = math.Random(1);
  final List<double> pure = List<double>.generate(
      (60 * fs).round(), (_) => 9.806 + 0.4 * (rng.nextDouble() - 0.5));
  final VitalsResult rn = analyzer.analyze(pure, sampleRateHz: fs);
  check('白色ノイズだけの入力から心拍を捏造しない',
      rn.quality != VitalsQuality.good,
      '${rn.quality.name}, 信頼度 ${rn.heartRateConfidence.toStringAsFixed(2)}');

  final List<double> tooShort =
      synthesise(bpm: 100, seconds: 8, sampleRateHz: fs);
  final VitalsResult rs = analyzer.analyze(tooShort, sampleRateHz: fs);
  check('15秒未満の入力は unusable になる',
      rs.quality == VitalsQuality.unusable);

  // 2026-09-13 に実機で起きた事故の再発防止。首輪が 26 Hz で動いていて、
  // ナイキスト 13 Hz に対して 8–40 Hz を通そうとしたため、フィルタが
  // 発振して 221.4 bpm を「good・信頼度0.93」として3回続けて出した。
  // 嘘の数字を自信たっぷりに出すのが、いちばん危険な壊れ方だった。
  const double lowFs = 26.0;
  final List<double> low =
      synthesise(bpm: 78, seconds: 60, sampleRateHz: lowFs);
  final VitalsResult rl = analyzer.analyze(low, sampleRateHz: lowFs);
  check('サンプリング 26 Hz では心拍を出さない（数字を捏造しない）',
      rl.quality == VitalsQuality.unusable &&
          rl.heartRateBpm == null &&
          rl.unusableReason == 'rate_too_low',
      '${rl.quality.name} / ${rl.heartRateBpm} / ${rl.unusableReason}');

  // 逆に、104 Hz なら帯域はナイキスト内に収まるので普通に出る。
  final VitalsResult rok = analyzer.analyze(
      synthesise(bpm: 78, seconds: 60, sampleRateHz: 104),
      sampleRateHz: 104);
  check('サンプリング 104 Hz なら 78 bpm を出せる',
      rok.heartRateBpm != null && (rok.heartRateBpm! - 78).abs() <= 6,
      '${rok.heartRateBpm?.toStringAsFixed(1)}');

  // 途中表示用の短い窓。8秒でも出せることを確かめる(画面の数字を早く出す道)。
  final VitalsResult rlive = analyzer.analyze(
      synthesise(bpm: 78, seconds: 9, sampleRateHz: 104),
      sampleRateHz: 104,
      minSeconds: 8);
  check('minSeconds: 8 を渡せば9秒の窓でも心拍を出す',
      rlive.heartRateBpm != null && (rlive.heartRateBpm! - 78).abs() <= 10,
      '${rlive.quality.name} / ${rlive.heartRateBpm?.toStringAsFixed(1)}');
}

void runRealCapture(String path) {
  print('\n4. 実測データ — ${path.split('/').last}');
  final File f = File(path);
  if (!f.existsSync()) {
    print('  … ファイルが見つかりません: $path');
    return;
  }
  final List<String> lines = f.readAsLinesSync();
  if (lines.length < 3) {
    print('  … 中身が足りません');
    return;
  }
  final List<String> header = lines.first.split(',');
  final int iUs = header.indexOf('device_us');
  final int iAx = header.indexOf('ax_m_s2');
  final int iAy = header.indexOf('ay_m_s2');
  final int iAz = header.indexOf('az_m_s2');
  if ([iUs, iAx, iAy, iAz].any((int i) => i < 0)) {
    print('  … 想定した列が見つかりません: ${header.join(",")}');
    return;
  }

  final List<double> us = <double>[];
  final List<double> mag = <double>[];
  for (final String line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final List<String> p = line.split(',');
    if (p.length <= iAz) continue;
    final double? t = double.tryParse(p[iUs]);
    final double? ax = double.tryParse(p[iAx]);
    final double? ay = double.tryParse(p[iAy]);
    final double? az = double.tryParse(p[iAz]);
    if (t == null || ax == null || ay == null || az == null) continue;
    us.add(t);
    mag.add(math.sqrt(ax * ax + ay * ay + az * az));
  }
  if (mag.length < 100) {
    print('  … 有効な行が足りません (${mag.length})');
    return;
  }

  // The device clock is monotonic microseconds; the median step is the true
  // sample interval (a mean would be skewed by any dropped record).
  final List<double> steps = <double>[];
  for (int i = 1; i < us.length; i++) {
    final double d = us[i] - us[i - 1];
    if (d > 0 && d < 1e6) steps.add(d);
  }
  steps.sort();
  final double fs = 1e6 / steps[steps.length ~/ 2];

  print('  標本 ${mag.length} 点、実効 ${fs.toStringAsFixed(1)} Hz、'
      '${(mag.length / fs).toStringAsFixed(1)} 秒');

  // Human subject, so use the narrower range for this cross-check.
  const VitalsAnalyzer analyzer = VitalsAnalyzer(range: HeartRateRange.human);
  final VitalsResult r = analyzer.analyze(mag, sampleRateHz: fs);
  print('  → $r');
  if (r.beatIntervalCvPercent != null) {
    print('     拍間隔のばらつき ${r.beatIntervalCvPercent!.toStringAsFixed(1)}%'
        '   SDNN ${r.sdnnMs?.toStringAsFixed(1) ?? "—"} ms'
        '   RMSSD ${r.rmssdMs?.toStringAsFixed(1) ?? "—"} ms');
  }
  check('SciPy で確立した 78 bpm と ±4 bpm 以内で一致',
      r.heartRateBpm != null && (r.heartRateBpm! - 78.0).abs() <= 4.0,
      '得られた値 ${r.heartRateBpm?.toStringAsFixed(1)}');
  check('品質が good と判定される', r.quality == VitalsQuality.good,
      r.quality.name);
}

void main(List<String> args) {
  print('collar_vitals self-test\n');
  runSynthetic();
  for (final String p in args) {
    runRealCapture(p);
  }
  if (args.isEmpty) {
    print('\n（実測データも試すには CSV のパスを引数に渡してください）');
  }
  print('\n${'=' * 56}');
  print(failures == 0 ? '全 $checks 件 通過' : '$checks 件中 $failures 件 失敗');
  print('=' * 56);
  if (failures > 0) exit(1);
}
