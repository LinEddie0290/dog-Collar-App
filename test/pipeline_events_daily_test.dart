// T34-A：出来事・1 日の集計・1 日まとめ JSON・CNN が collar-pipeline（Python）と同じか。
// 答え：test/fixtures/pipeline/events_daily_golden.json.gz（collar-pipeline で作った）。
import 'dart:convert';
import 'dart:io';

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load() {
  final List<int> gz = File('test/fixtures/pipeline/events_daily_golden.json.gz').readAsBytesSync();
  return jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
}

List<double> _d(Object? v) => (v as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList();
List<int> _i(Object? v) => (v as List<dynamic>).map((dynamic e) => (e as num).toInt()).toList();
double? _n(Object? v) => v == null ? null : (v as num).toDouble();

void _sameEvents(List<BehaviorEvent> got, List<dynamic> want) {
  expect(got.length, want.length,
      reason: '出来事の数：${got.map((BehaviorEvent e) => '${e.type}:${e.sub}').toList()}');
  for (int i = 0; i < got.length; i++) {
    final Map<String, dynamic> w = want[i] as Map<String, dynamic>;
    final BehaviorEvent g = got[i];
    final String at = '$i 番目';
    expect(g.type, w['type'], reason: '$at type');
    expect(g.sub, w['sub'], reason: '$at sub');
    expect(g.tStartMs, (w['t_start_ms'] as num).toInt(), reason: '$at t_start_ms');
    expect(g.tEndMs, (w['t_end_ms'] as num).toInt(), reason: '$at t_end_ms');
    expect(g.tStartDevUs, (w['t_start_dev_us'] as num).toInt(), reason: '$at t_start_dev_us');
    expect(g.durationS, closeTo((w['duration_s'] as num).toDouble(), 1e-4), reason: '$at duration_s');
    expect(g.confidence, w['confidence'], reason: '$at confidence');
    expect(g.source, w['source'], reason: '$at source');
    final double? hr = _n(w['hr_median']), rr = _n(w['rr_median']);
    expect(g.hrMedian == null, hr == null, reason: '$at hr の有無');
    if (hr != null) expect(g.hrMedian!, closeTo(hr, 1e-3), reason: '$at hr');
    expect(g.rrMedian == null, rr == null, reason: '$at rr の有無');
    if (rr != null) expect(g.rrMedian!, closeTo(rr, 1e-3), reason: '$at rr');
  }
}

List<VitalReading> _vitals(Map<String, dynamic> v) {
  final List<int> tMs = _i(v['t_ms']), tUs = _i(v['t_us']);
  final List<dynamic> kind = v['kind'] as List<dynamic>, value = v['value'] as List<dynamic>,
      valid = v['valid'] as List<dynamic>;
  return <VitalReading>[
    for (int i = 0; i < tMs.length; i++)
      VitalReading(
          tMs: tMs[i], tDevUs: tUs[i], kind: kind[i] as String, value: _n(value[i]), valid: valid[i] as bool),
  ];
}

Object? _norm(Object? v) {
  // 1.0 と 1 を同じに比べる
  if (v is num) return v.toDouble();
  if (v is List) return v.map(_norm).toList();
  if (v is Map) return <String, Object?>{for (final MapEntry<dynamic, dynamic> e in v.entries) e.key as String: _norm(e.value)};
  return v;
}

void main() {
  final Map<String, dynamic> g = _load();

  int k = 0;
  for (final dynamic c in g['events_cases'] as List<dynamic>) {
    final Map<String, dynamic> cs = c as Map<String, dynamic>;
    test('出来事 ${k++}（override ${cs['override']}）', () {
      final Map<String, dynamic> s = cs['state'] as Map<String, dynamic>;
      final Map<String, dynamic> cn = cs['cnn'] as Map<String, dynamic>;
      final List<int> tMs = _i(s['t_ms']), tUs = _i(s['t_us']);
      final List<dynamic> rest = s['rest'] as List<dynamic>;
      final List<WindowState> st = <WindowState>[
        for (int i = 0; i < tUs.length; i++)
          WindowState(
              tStartMs: tMs[i],
              tStartDevUs: tUs[i],
              activity: 0,
              rest: rest[i] as bool,
              stillS: 0,
              quietS: 0,
              measureOk: false),
      ];
      final List<dynamic> lab = cn['label'] as List<dynamic>;
      final List<double> prob = _d(cn['prob']);
      final List<CnnWindow> cnn = <CnnWindow>[
        for (int i = 0; i < tUs.length; i++)
          CnnWindow(tStartMs: tMs[i], tStartDevUs: tUs[i], label: lab[i] as String, prob: prob[i]),
      ];
      final Map<String, double> ov = <String, double>{
        for (final MapEntry<String, dynamic> e in (cs['override'] as Map<String, dynamic>).entries)
          e.key: (e.value as num).toDouble(),
      };
      final EventsResult r = buildEvents(st, cnn,
          vitals: _vitals(cs['vitals'] as Map<String, dynamic>), ecfg: EventConfig(overrideRest: ov));
      _sameEvents(r.events, cs['events'] as List<dynamic>);
    });
  }

  test('通し：Unity の 74 秒（前処理 → 状態 → CNN → 出来事）', () {
    final Map<String, dynamic> ch = g['chain'] as Map<String, dynamic>;
    final Map<String, dynamic> inp = ch['input'] as Map<String, dynamic>;
    final List<int> t = _i(inp['t']), tms = _i(inp['tms']);
    final List<dynamic> v = inp['v'] as List<dynamic>, sensor = inp['sensor'] as List<dynamic>;
    final List<ImuSample> imu = <ImuSample>[
      for (int i = 0; i < t.length; i++)
        () {
          final List<double> r = _d(v[i]);
          return ImuSample(
              sensor: sensor[i] as String, tDevUs: t[i], tMs: tms[i], ax: r[0], ay: r[1], az: r[2], gx: r[3], gy: r[4], gz: r[5]);
        }(),
    ];
    final PreprocessResult pre = preprocessImu(imu);
    final List<WindowState> st = judgeState(pre.activity, pre.tStartDevUs, tStartMs: pre.tStartMs);

    // Dart の CNN と PyTorch の CNN
    final Map<String, dynamic> model =
        jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>;
    final WindowClassifier clf = WindowClassifier.fromJson(model);
    final List<CnnWindow> mine = clf.classify(pre);
    final Map<String, dynamic> pc = ch['cnn'] as Map<String, dynamic>;
    final List<dynamic> plab = pc['label'] as List<dynamic>;
    final List<double> pprob = _d(pc['prob']);
    expect(mine.length, plab.length, reason: 'CNN の窓の数');
    int same = 0;
    for (int i = 0; i < mine.length; i++) {
      if (mine[i].label == plab[i]) {
        same++;
        expect(mine[i].prob, closeTo(pprob[i], 2e-3), reason: '$i 番目の確率');
      }
    }
    expect(same, mine.length, reason: 'ラベルが同じ窓 $same / ${mine.length}');

    // 出来事は Python の CNN の結果で比べる（CNN の小さな差を混ぜない）
    final List<int> pus = _i(pc['t_us']);
    final List<CnnWindow> py = <CnnWindow>[
      for (int i = 0; i < pus.length; i++)
        CnnWindow(tStartMs: pre.tStartMs[i], tStartDevUs: pus[i], label: plab[i] as String, prob: pprob[i]),
    ];
    _sameEvents(buildEvents(st, py).events, ch['events'] as List<dynamic>);
  });

  group('1 日の集計とまとめ（14 日の模擬の犬）', () {
    final Map<String, dynamic> d = g['daily'] as Map<String, dynamic>;
    final List<BehaviorEvent> evs = <BehaviorEvent>[
      for (final dynamic e in d['events'] as List<dynamic>)
        () {
          final Map<String, dynamic> m = e as Map<String, dynamic>;
          return BehaviorEvent(
            type: m['type'] as String,
            sub: m['sub'] as String,
            tStartMs: (m['t_start_ms'] as num).toInt(),
            tEndMs: (m['t_end_ms'] as num).toInt(),
            durationS: (m['duration_s'] as num).toDouble(),
            tStartDevUs: (m['t_start_dev_us'] as num).toInt(),
            confidence: m['confidence'] as String,
            source: m['source'] as String,
            hrMedian: _n(m['hr_median']),
            rrMedian: _n(m['rr_median']),
          );
        }(),
    ];
    final Map<String, int> wins = <String, int>{
      for (final MapEntry<String, dynamic> e in (d['windows_by_date'] as Map<String, dynamic>).entries)
        e.key: (e.value as num).toInt(),
    };
    final List<DailyRow> rows = buildDaily(evs, wins, _vitals(d['vitals'] as Map<String, dynamic>));

    test('1 日の値・平時・比', () {
      final List<dynamic> want = d['rows'] as List<dynamic>;
      expect(rows.length, want.length);
      for (int i = 0; i < rows.length; i++) {
        final Map<String, dynamic> w = want[i] as Map<String, dynamic>;
        final DailyRow r = rows[i];
        final String at = '${w['date']} ${w['metric']}';
        expect(r.date, w['date'], reason: at);
        expect(r.metric, w['metric'], reason: at);
        expect(r.validDay, w['valid_day'], reason: '$at valid_day');
        expect(r.nDays, (w['n_days'] as num).toInt(), reason: '$at n_days');
        for (final List<Object?> col in <List<Object?>>[
          <Object?>['value', r.value],
          <Object?>['baseline', r.baseline],
          <Object?>['ratio', r.ratio],
          <Object?>['wear_min', r.wearMin],
        ]) {
          final double got = col[1]! as double;
          final double? exp = _n(w[col[0]]);
          if (exp == null) {
            expect(got.isNaN, isTrue, reason: '$at ${col[0]} は空のはず（$got）');
          } else {
            expect(got, closeTo(exp, 1e-4 * (1 + exp.abs())), reason: '$at ${col[0]}');
          }
        }
      }
    });

    test('1 日まとめ JSON と history', () {
      final String gen = d['generated_at'] as String;
      final Map<String, dynamic> sums = d['summaries'] as Map<String, dynamic>;
      for (final MapEntry<String, dynamic> e in sums.entries) {
        final Map<String, Object?> mine = buildSummary(rows, e.key, 'dog_sim01', generatedAt: gen);
        expect(_norm(jsonDecode(jsonEncode(mine))), _norm(e.value), reason: e.key);
      }
      final List<String> dates = sums.keys.toList()..sort();
      expect(_norm(jsonDecode(jsonEncode(buildHistory(rows, dates.last)))), _norm(d['history']));
    });
  });
}
