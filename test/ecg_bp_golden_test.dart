// T44（D-066）：心電図・血圧の前処理（Dart）が Python（collar-pipeline・元の VMD／スプライン・neurokit2）と同じか。
// 答え：test/fixtures/ecg_bp_golden.json（scripts/make_ecg_bp_golden.py、にせの信号 synth_v1 から。人のデータは入っていない）。
// モデルの推論（TFLite）は flutter test では動かないので、ここでは前処理・つなぎ方・R 波まで。モデルは iPhone の测试画面で確かめる。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collar_ecg_bp/collar_ecg_bp.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _golden() =>
    jsonDecode(File('test/fixtures/ecg_bp_golden.json').readAsStringSync()) as Map<String, dynamic>;

List<double> _d(dynamic v) => (v as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList();
List<int> _i(dynamic v) => (v as List<dynamic>).map((dynamic e) => (e as num).toInt()).toList();

List<double> _every(List<double> x, int step) => <double>[for (int i = 0; i < x.length; i += step) x[i]];

/// 最大の差（相手の大きさで割る）。
double _relMax(List<double> a, List<double> b) {
  expect(a.length, b.length);
  double m = 0, s = 1e-12;
  for (int i = 0; i < a.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
    s = math.max(s, b[i].abs());
  }
  return m / s;
}

void main() {
  final Map<String, dynamic> g = _golden();
  final ({Float64List ax, Float64List ay, Float64List az}) acc = synthCollarAcc();
  const double fs = 400.0;

  test('にせの信号が Python と同じ（synth_v1）', () {
    final List<double> sums = _d(g['input']['sum']);
    double sx = 0, sy = 0, sz = 0;
    for (int i = 0; i < acc.ax.length; i++) {
      sx += acc.ax[i];
      sy += acc.ay[i];
      sz += acc.az[i];
    }
    expect((sx - sums[0]).abs() / sums[0].abs(), lessThan(1e-12));
    expect((sy - sums[1]).abs() / sums[1].abs(), lessThan(1e-12));
    expect((sz - sums[2]).abs() / sums[2].abs(), lessThan(1e-12));
  });

  group('心電図', () {
    for (final MapEntry<String, dynamic> e in (g['ecg'] as Map<String, dynamic>).entries) {
      final Map<String, dynamic> c = e.value as Map<String, dynamic>;
      final EcgSettings st = EcgSettings(axis: c['axis'] as String, highpass: c['highpass'] as bool, sign: c['sign'] as int);

      test('${e.key}：150 Hz・窓・活動量・0〜1 が同じ', () {
        expect(st.name, e.key);
        final EcgInput inp = ecgModelInput(acc.ax, acc.ay, acc.az, fs, st);
        expect(inp.signal.length, c['sig150_len']);
        expect(_relMax(_every(inp.signal, 5), _d(c['sig150_every5'])), lessThan(1e-9));
        final List<int> all = windowStarts(inp.signal.length);
        expect(all, _i(c['starts_all']));
        final List<double> act = windowActivity(acc.ax, acc.ay, acc.az, fs, all);
        // 活動量は「加速度 − 重力（0.3 Hz の低域）」の小さい残り（約 0.004 m/s²、元は約 10 m/s²）なので、
        // 計算の丸めの差が数千倍に見える（Mac の M チップで 5e-8）。窓を捨てる線は 0.15 なので 1e-6 で十分。
        expect(_relMax(act, _d(c['activity_all'])), lessThan(1e-6));
        expect(inp.starts, _i(c['kept_starts']));
        expect(_relMax(_every(inp.windows[0], 4), _d(c['window0_every4'])), lessThan(1e-6));
      });

      test('${e.key}：R 波・心拍数が neurokit2 と同じ（モデルの出力は golden のもの）', () {
        final List<double> ecg = _d(c['stitched']);
        expect(ecg.length, c['stitched_len']);
        final List<int> pk = rPeaksNeurokit(ecg, 150);
        expect(pk, _i(c['r_peaks']));
        final double hr = heartRateFromPeaks(pk, 150);
        final num? want = c['hr_bpm'] as num?;
        if (want == null || want.isNaN) {
          expect(hr.isNaN, isTrue);
        } else {
          expect((hr - want).abs(), lessThan(1e-9));
        }
      });
    }

    test('窓をつなぐ（重なりは平均・かからない所は nan）', () {
      final Float64List s = stitchWindows(<List<double>>[
        <double>[1, 1, 1, 1],
        <double>[3, 3, 3, 3],
      ], <int>[0, 2], 8);
      expect(s.sublist(0, 6), <double>[1, 1, 2, 2, 3, 3]);
      expect(s[6].isNaN && s[7].isNaN, isTrue);
    });

    test('R 波：にせの心電図（150 Hz・20 秒）で neurokit2 と同じ', () {
      final Map<String, dynamic> r = g['rpeaks_case'] as Map<String, dynamic>;
      final List<int> pk = rPeaksNeurokit(_d(r['signal']), 150);
      expect(pk, _i(r['r_peaks']));
      expect((heartRateFromPeaks(pk, 150) - (r['hr_bpm'] as num)).abs(), lessThan(1e-9));
    });
  });

  group('血圧', () {
    final Map<String, dynamic> b = g['bp'] as Map<String, dynamic>;

    test('いちばん静かな 45 秒・500 Hz・VMD・スプライン・4000 点・0〜1・窓が同じ', () {
      final int s0 = quietestStart(acc.ax, acc.ay, acc.az, fs);
      expect(s0, b['quiet_start']);
      final int n = (45 * fs).round();
      final List<List<double>> seg = <List<double>>[
        acc.ax.sublist(s0, s0 + n),
        acc.ay.sublist(s0, s0 + n),
        acc.az.sublist(s0, s0 + n),
      ];
      final List<Float64List> a500 = to500Hz(seg, fs);
      expect(a500[0].length, b['a500_len']);
      for (int c = 0; c < 3; c++) {
        expect(_relMax(_every(a500[c], 25), _d(b['a500_every25'][c])), lessThan(1e-9), reason: '500 Hz 軸 $c');
        final Float64List v = vmdModeSum(a500[c]).signal;
        expect(_relMax(_every(v, 25), _d(b['vmd_every25'][c])), lessThan(1e-6), reason: 'VMD 軸 $c');
        final Float64List spl = spline496(v);
        expect(spl.length, b['spl_len']);
        expect(_relMax(_every(spl, 5), _d(b['spl_every5'][c])), lessThan(1e-6), reason: 'スプライン 軸 $c');
        final Float64List x4 = resampleFixed(spl, 4000);
        expect(_relMax(_every(x4, 2), _d(b['x4000_every2'][c])), lessThan(1e-6), reason: '4000 点 軸 $c');
        expect(_relMax(_every(normalizeRecord(x4), 2), _d(b['x01_every2'][c])), lessThan(1e-6), reason: '0〜1 軸 $c');
      }
      final BpInput inp = bpModelInput(acc.ax, acc.ay, acc.az, fs);
      expect(inp.windows.length, b['n_windows']);
      expect(inp.windows[0].length, 3 * 900);
    });

    test('5 分割の平均（窓 × 分割）の出し方', () async {
      Future<List<double>> fake(List<Float32List> w, double v) async => List<double>.filled(w.length, v);
      final BpResult r = await estimateBp(acc.ax, acc.ay, acc.az, fs,
          sbpModels: <BpModel>[for (int k = 1; k <= 5; k++) (List<Float32List> w) => fake(w, 100.0 + k)],
          dbpModels: <BpModel>[for (int k = 1; k <= 5; k++) (List<Float32List> w) => fake(w, 60.0 + k)]);
      expect(r.sbp, closeTo(103.0, 1e-9));
      expect(r.dbp, closeTo(63.0, 1e-9));
      expect(r.sbpPerModel, <double>[101, 102, 103, 104, 105]);
    });
  });

  group('部品', () {
    test('FFT：長さ 12・45 で、ふつうの DFT と同じ', () {
      for (final int n in <int>[12, 45, 7]) {
        final Float64List re = Float64List(n), im = Float64List(n);
        for (int i = 0; i < n; i++) {
          re[i] = math.sin(i * 1.3) + i * 0.1;
          im[i] = math.cos(i * 0.7);
        }
        final Float64List r0 = Float64List.fromList(re), i0 = Float64List.fromList(im);
        fftInPlace(re, im);
        for (int k = 0; k < n; k++) {
          double sr = 0, si = 0;
          for (int j = 0; j < n; j++) {
            final double a = -2 * math.pi * j * k / n;
            sr += r0[j] * math.cos(a) - i0[j] * math.sin(a);
            si += r0[j] * math.sin(a) + i0[j] * math.cos(a);
          }
          expect((re[k] - sr).abs(), lessThan(1e-9));
          expect((im[k] - si).abs(), lessThan(1e-9));
        }
      }
    });

    test('スプライン：3 次式はそのまま通る（not-a-knot）', () {
      final List<double> x = <double>[for (int i = 0; i < 10; i++) i * 0.7];
      final List<double> y = <double>[for (final double v in x) 2 * v * v * v - v + 3];
      final Float64List out = cubicSplineNotAKnot(x, y, <double>[0.35, 2.0, 6.0]);
      for (final (int i, double v) in <(int, double)>[(0, 0.35), (1, 2.0), (2, 6.0)]) {
        expect(out[i], closeTo(2 * v * v * v - v + 3, 1e-9));
      }
    });

    test('高域通過のフィルタの係数が scipy と同じ（2 次・0.5 Hz・400 Hz）', () {
      final List<double> s = butterHigh2Sos(0.5, 400)[0];
      const List<double> want = <double>[0.9944617889581948, -1.9889235779163896, 0.9944617889581948, 1, -1.988892905899653, 0.9889542499331264];
      for (int i = 0; i < 6; i++) {
        expect(s[i], closeTo(want[i], 1e-12));
      }
    });
  });
}
