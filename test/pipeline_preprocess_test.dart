// T34-A：Dart の前処理・状態判断が collar-pipeline（Python）と同じ数字を出すか。
// 答えのファイルは collar-pipeline で作った test/fixtures/pipeline/preprocess_golden.json.gz
// （作り方：首輪開発計画 03_設計メモ/T34 の「テスト」）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load() {
  final List<int> gz = File('test/fixtures/pipeline/preprocess_golden.json.gz').readAsBytesSync();
  return jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
}

List<double> _d(Object? v) => (v as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList();
List<int> _i(Object? v) => (v as List<dynamic>).map((dynamic e) => (e as num).toInt()).toList();

void _close(List<double> got, List<double> want, double tol, String what) {
  expect(got.length, want.length, reason: '$what の長さ');
  double worst = 0;
  int at = -1;
  for (int i = 0; i < got.length; i++) {
    final double d = (got[i] - want[i]).abs() / (1 + want[i].abs());
    if (d > worst) {
      worst = d;
      at = i;
    }
  }
  expect(worst, lessThan(tol), reason: '$what：$at 番目で差 $worst（${at >= 0 ? got[at] : ''} vs ${at >= 0 ? want[at] : ''}）');
}

List<ImuSample> _samples(Map<String, dynamic> inp) {
  final List<dynamic> sensor = inp['sensor'] as List<dynamic>;
  final List<int> t = _i(inp['t']);
  final List<dynamic> tms = inp['tms'] as List<dynamic>;
  final List<dynamic> v = inp['v'] as List<dynamic>;
  return <ImuSample>[
    for (int i = 0; i < t.length; i++)
      () {
        final List<double> r = (v[i] as List<dynamic>)
            .map((dynamic e) => e == null ? double.nan : (e as num).toDouble())
            .toList();
        return ImuSample(
          sensor: sensor[i] as String,
          tDevUs: t[i],
          tMs: tms[i] == null ? null : (tms[i] as num).toInt(),
          ax: r[0],
          ay: r[1],
          az: r[2],
          gx: r[3],
          gy: r[4],
          gz: r[5],
        );
      }(),
  ];
}

void main() {
  final Map<String, dynamic> g = _load();

  group('DSP（SciPy と同じ）', () {
    final Map<String, dynamic> dsp = g['dsp'] as Map<String, dynamic>;
    final List<double> x = _d(dsp['x']);
    test('butter の係数', () {
      for (final dynamic c in dsp['sos'] as List<dynamic>) {
        final Map<String, dynamic> m = c as Map<String, dynamic>;
        final Sos got = butterLowSos(m['order'] as int, (m['cut'] as num).toDouble(), (m['fs'] as num).toDouble());
        final List<double> want = (m['sos'] as List<dynamic>).expand((dynamic r) => _d(r)).toList();
        _close(got.expand((List<double> r) => r).toList(), want, 1e-9, 'sos ${m['order']} ${m['cut']} ${m['fs']}');
      }
    });
    test('lowpass（sosfiltfilt）', () {
      for (final dynamic c in dsp['lowpass'] as List<dynamic>) {
        final Map<String, dynamic> m = c as Map<String, dynamic>;
        final Float64List y = lowpass(x, (m['fs'] as num).toDouble(), (m['cut'] as num).toDouble(), order: m['order'] as int);
        _close(y, _d(m['y']), 1e-8, 'lowpass ${m['order']} ${m['cut']} ${m['fs']}');
      }
    });
    test('downsample（resample_poly）', () {
      for (final dynamic c in dsp['resample'] as List<dynamic>) {
        final Map<String, dynamic> m = c as Map<String, dynamic>;
        final Float64List y = downsample(x, (m['fs_in'] as num).toDouble(), (m['fs_out'] as num).toDouble());
        _close(y, _d(m['y']), 1e-8, 'downsample ${m['fs_in']}→${m['fs_out']}');
      }
    });
  });

  for (final dynamic c in g['cases'] as List<dynamic>) {
    final Map<String, dynamic> cs = c as Map<String, dynamic>;
    final Map<String, dynamic> e = cs['expect'] as Map<String, dynamic>;
    test('前処理と状態：${cs['name']}', () {
      final PreprocessResult r = preprocessImu(_samples(cs['input'] as Map<String, dynamic>));
      expect(r.fsGrid, (e['fs'] as num).toDouble());
      expect(r.nWindows, e['n'] as int, reason: '窓の数');
      expect(r.tStartDevUs, _i(e['t_start_dev_us']));
      expect(r.tStartMs, _i(e['t_start_ms']));
      expect(r.warnings.length, (e['warnings'] as List<dynamic>).length, reason: '警告：${r.warnings}');
      _close(r.activity, _d(e['activity']), 1e-5, 'activity');
      _close(r.gravity.expand((Float32List v) => v).toList(),
          (e['gravity'] as List<dynamic>).expand((dynamic v) => _d(v)).toList(), 1e-5, 'gravity');
      final List<double> sums = <double>[], abss = <double>[];
      for (final Float32List w in r.x) {
        for (int ch = 0; ch < 6; ch++) {
          double s = 0, a = 0;
          for (int t = 0; t < r.windowLen; t++) {
            s += w[ch * r.windowLen + t];
            a += w[ch * r.windowLen + t].abs();
          }
          sums.add(s);
          abss.add(a);
        }
      }
      _close(sums, (e['x_sum'] as List<dynamic>).expand((dynamic v) => _d(v)).toList(), 1e-3, 'X の合計');
      _close(abss, (e['x_abs'] as List<dynamic>).expand((dynamic v) => _d(v)).toList(), 1e-4, 'X の絶対値の合計');
      if (r.nWindows > 0) {
        _close(r.x.first, (e['x_first'] as List<dynamic>).expand((dynamic v) => _d(v)).toList(), 1e-5, '最初の窓');
        _close(r.x[r.nWindows ~/ 2], (e['x_mid'] as List<dynamic>).expand((dynamic v) => _d(v)).toList(), 1e-5,
            '真ん中の窓');
      }
      expect(r.vitalsAMag.length, e['vitals_n'] as int);
      _close(r.vitalsAMag.sublist(0, 20), _d(e['vitals_first']), 1e-6, '|a| の最初');
      double vs = 0;
      for (final double v in r.vitalsAMag) {
        vs += v;
      }
      _close(<double>[vs], <double>[(e['vitals_sum'] as num).toDouble()], 1e-5, '|a| の合計');

      final List<WindowState> st = judgeState(r.activity, r.tStartDevUs, tStartMs: r.tStartMs);
      final Map<String, dynamic> es = e['state'] as Map<String, dynamic>;
      expect(<bool>[for (final WindowState s in st) s.rest], (es['rest'] as List<dynamic>).cast<bool>());
      expect(<bool>[for (final WindowState s in st) s.measureOk], (es['measure_ok'] as List<dynamic>).cast<bool>());
      _close(<double>[for (final WindowState s in st) s.stillS], _d(es['still_s']), 1e-9, 'still_s');
      _close(<double>[for (final WindowState s in st) s.quietS], _d(es['quiet_s']), 1e-9, 'quiet_s');
    });
  }

  test('状態だけ（抜け・短い動き）', () {
    final Map<String, dynamic> s = g['state_only'] as Map<String, dynamic>;
    final List<WindowState> st = judgeState(_d(s['activity']), _i(s['t']));
    expect(<bool>[for (final WindowState w in st) w.rest], (s['rest'] as List<dynamic>).cast<bool>());
    expect(<bool>[for (final WindowState w in st) w.measureOk], (s['measure_ok'] as List<dynamic>).cast<bool>());
    _close(<double>[for (final WindowState w in st) w.stillS], _d(s['still_s']), 1e-9, 'still_s');
    _close(<double>[for (final WindowState w in st) w.quietS], _d(s['quiet_s']), 1e-9, 'quiet_s');
  });
}
