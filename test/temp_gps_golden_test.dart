// T11・T12（D-063）：体温・GPS の計算が Python（collar-pipeline）と同じ答えになるか。
// test/fixtures/temp_gps_golden.json は collar-pipeline の scripts/make_temp_gps_golden.py が作ったもの。
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/data/gps_track.dart';
import 'package:collar_app/data/temp_judge.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _g() =>
    jsonDecode(File('test/fixtures/temp_gps_golden.json').readAsStringSync()) as Map<String, dynamic>;

List<T> _l<T>(dynamic x) => (x as List<dynamic>).cast<T>();
List<double> _d(dynamic x) => <double>[for (final dynamic v in x as List<dynamic>) (v as num).toDouble()];

void main() {
  final Map<String, dynamic> g = _g();

  test('体温：安定した段・1 日の値・平時との差が Python と同じ', () {
    final Map<String, dynamic> i = g['temp_in'] as Map<String, dynamic>;
    final List<int> t = _l<int>(i['t_ms']);
    final List<double> o = _d(i['obj_c']), a = _d(i['amb_c']);
    final List<TempBlock> b = stableTempBlocks(<TempReading>[
      for (int k = 0; k < t.length; k++) TempReading(tMs: t[k], objC: o[k], ambC: a[k]),
    ]);
    final Map<String, dynamic> eb = g['temp_blocks'] as Map<String, dynamic>;
    expect(b.map((TempBlock x) => x.tMs).toList(), _l<int>(eb['t_ms']));
    final List<double> ev = _d(eb['value']);
    for (int k = 0; k < b.length; k++) {
      expect(b[k].value, closeTo(ev[k], 1e-9));
    }
    final Map<String, ({double value, int nBlocks})> days = dailyTemp(b);
    final Map<String, dynamic> ed = g['temp_daily'] as Map<String, dynamic>;
    expect(days.keys.toList(), _l<String>(ed['date']));
    expect(days.values.map((({double value, int nBlocks}) v) => v.nBlocks).toList(), _l<int>(ed['n_blocks']));
    final List<double> edv = _d(ed['value']);
    for (int k = 0; k < edv.length; k++) {
      expect(days.values.elementAt(k).value, closeTo(edv[k], 1e-9));
    }
    final Map<String, dynamic> es = g['temp_status'] as Map<String, dynamic>;
    final TempStatus st = tempStatus(<String, double>{for (final MapEntry<String, ({double value, int nBlocks})> e in days.entries) e.key: e.value.value},
        es['date'] as String);
    expect(st.usual, closeTo((es['usual'] as num).toDouble(), 1e-9));
    expect(st.usualDays, es['usual_days']);
    expect(st.delta, closeTo((es['delta'] as num).toDouble(), 1e-9));
    expect(st.state.name, es['state']);
    expect(st.flag, 1); // high
  });

  test('GPS：残す点・距離・屋外の時間が Python と同じ', () {
    final Map<String, dynamic> i = g['gps_in'] as Map<String, dynamic>;
    final List<int> t = _l<int>(i['t_ms']);
    final List<double> lat = _d(i['lat']), lon = _d(i['lon']), hdop = _d(i['hdop']);
    final List<int> sats = <int>[for (final dynamic v in i['sats'] as List<dynamic>) (v as num).toInt()];
    final List<int> fix = <int>[for (final dynamic v in i['fix'] as List<dynamic>) (v as num).toInt()];
    final List<TrackPoint> tr = trackGps(<GpsPoint>[
      for (int k = 0; k < t.length; k++)
        GpsPoint(tMs: t[k], lat: lat[k], lng: lon[k], hdop: hdop[k], sats: sats[k], fix: fix[k]),
    ]);
    final Map<String, dynamic> et = g['gps_track'] as Map<String, dynamic>;
    expect(tr.map((TrackPoint p) => p.tMs).toList(), _l<int>(et['t_ms']));
    expect(tr.map((TrackPoint p) => p.outdoor).toList(), _l<bool>(et['outdoor']));
    final List<double> es = _d(et['step_m']), edt = _d(et['dt_s']);
    for (int k = 0; k < tr.length; k++) {
      expect(tr[k].stepM, closeTo(es[k], 1e-6), reason: '$k');
      expect(tr[k].dtS, closeTo(edt[k], 1e-9));
    }
    final Map<String, ({double outdoorM, double outdoorMin})> d = dailyOutdoor(tr);
    final Map<String, dynamic> ed = g['gps_daily'] as Map<String, dynamic>;
    expect(d.keys.toList(), _l<String>(ed['date']));
    final List<double> em = _d(ed['outdoor_m']), emin = _d(ed['outdoor_min']);
    for (int k = 0; k < em.length; k++) {
      expect(d.values.elementAt(k).outdoorM, closeTo(em[k], 1e-4));
      expect(d.values.elementAt(k).outdoorMin, closeTo(emin[k], 1e-9));
    }
  });

  test('1 点ずつ（GpsTracker）とまとめて（trackGps）は同じ。HDOP が分からない点も使う', () {
    final List<GpsPoint> ps = <GpsPoint>[
      for (int k = 0; k < 30; k++) GpsPoint(tMs: 1000 * k, lat: 31.2304 + k * 2e-5, lng: 121.4737),
    ];
    final GpsTracker g1 = GpsTracker();
    final List<TrackPoint> one = <TrackPoint>[for (final GpsPoint p in ps) if (g1.add(p) case final TrackPoint x) x];
    final List<TrackPoint> all = trackGps(ps);
    expect(one.length, all.length);
    expect(one.fold<double>(0, (double s, TrackPoint p) => s + p.stepM),
        closeTo(all.fold<double>(0, (double s, TrackPoint p) => s + p.stepM), 1e-9));
    expect(all.fold<double>(0, (double s, TrackPoint p) => s + p.stepM), closeTo(29 * 2.2239, 0.05)); // 2e-5° ≈ 2.22 m
    expect(outdoorText(420, 7.6), '420 m・8 分钟');
    expect(outdoorText(1234, 25), '1.23 km・25 分钟');
  });

  test('体温：平時は 3 日から（それまでは收集中）、14 日で暂定がとれる', () {
    final Map<String, double> d = <String, double>{'2025-11-01': 36.8, '2025-11-02': 36.9};
    final TempStatus s1 = tempStatus(<String, double>{...d, '2025-11-03': 37.0}, '2025-11-03');
    expect(s1.state, TempState.collecting);
    expect(s1.daysToGo, 1);
    expect(s1.delta, isNull);
    final Map<String, double> many = <String, double>{
      for (int k = 1; k <= 15; k++) '2025-11-${k.toString().padLeft(2, '0')}': k == 15 ? 35.6 : 36.8,
    };
    final TempStatus s2 = tempStatus(many, '2025-11-15');
    expect(s2.state, TempState.ok);
    expect(s2.delta, closeTo(-1.2, 1e-9));
    expect(s2.flag, -1);
  });
}
