// T11・T12（D-063）：アプリの中の流れ（模拟の温度・記録ファイル・1 日まとめ・健康タブ・安全タブ）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/data/health_series.dart';
import 'package:collar_app/data/safe_zone.dart';
import 'package:collar_app/data/temp_judge.dart';
import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart' show WindowResult;
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/pipeline/pipeline_summary_repository.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/location_controller.dart';
import 'package:collar_app/ui/health/health_text.dart';
import 'package:collar_app/ui/health/item_page.dart';
import 'package:collar_data/collar_data.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _t0 = 1762650000000; // 2025-11-09 01:00 UTC（当地 09:00）
const GeoPoint _home = GeoPoint(31.2304, 121.4737);

void main() {
  test('模拟：温度は 1 秒に 1 回、走っている間は皮膚に向かない（物体≒環境）、「模拟发烧」で +1.5℃', () async {
    int now = _t0;
    final FakeImuInput fake = FakeImuInput(nowMs: () => now, tick: const Duration(hours: 1));
    final List<TempReading> got = <TempReading>[];
    final StreamSubscription<TempReading> sub = fake.temps.listen(got.add);
    await fake.start();
    now += 200000; // 200 秒（150〜170 秒は走る）
    fake.pump();
    await Future<void>.delayed(Duration.zero);
    expect(got.length, 201);
    expect(got[10].objC, closeTo(36.8, 0.05));
    expect(got[160].objC - got[160].ambC, closeTo(1.0, 1e-9)); // ずれている
    final int ok = stableTempBlocks(got).length;
    expect(ok, greaterThanOrEqualTo(2));
    fake.setFever(true);
    now += 2000;
    fake.pump();
    await Future<void>.delayed(Duration.zero);
    expect(got.last.objC, closeTo(38.3, 0.05));
    await sub.cancel();
    await fake.stop();
    fake.dispose();
  });

  test('首輪（BLE）：両方の値があるときだけ、同じ値は 1 秒に 1 回', () async {
    final StreamController<RawFrame> c = StreamController<RawFrame>();
    final List<TempReading> got = <TempReading>[];
    final StreamSubscription<TempReading> sub = tempsFromFrames(c.stream).listen(got.add);
    c.add(RawFrame(0, <String, dynamic>{'body_temp_c': 36.8})); // 環境がない
    c.add(RawFrame(250, <String, dynamic>{'body_temp_c': 36.8, 'ambient_temp_c': 26.0}));
    c.add(RawFrame(500, <String, dynamic>{'body_temp_c': 36.8, 'ambient_temp_c': 26.0}));
    c.add(RawFrame(1300, <String, dynamic>{'body_temp_c': 36.8, 'ambient_temp_c': 26.0}));
    c.add(RawFrame(1550, <String, dynamic>{'body_temp_c': 36.9, 'ambient_temp_c': 26.0}));
    await c.close();
    await Future<void>.delayed(Duration.zero);
    expect(got.map((TempReading r) => r.tMs).toList(), <int>[250, 1300, 1550]);
    expect(got.first.source, 'collar');
    await sub.cancel();
  });

  test('記録ファイル → 1 日まとめ：皮膚の温度（temp_c）と屋外の距離・時間', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('t11');
    addTearDown(() => tmp.delete(recursive: true));
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    await store.startSession('s1', <String, Object?>{'started_ms': _t0});
    // 窓（その日の装着を作る）
    await store.appendWindows('s1', <WindowResult>[
      for (int i = 0; i < 60; i++)
        WindowResult(tDevUs: i * 1000000, tMs: _t0 + i * 1000, activity: 0.01, label: 'still', prob: 0.9),
    ]);
    for (int s = 0; s < 300; s++) {
      await store.appendTemp('s1', TempReading(tMs: _t0 + s * 1000, objC: 36.8, ambC: 26.0));
    }
    for (int s = 0; s <= 100; s++) {
      await store.appendGps('s1', LocationFix(point: offsetPoint(_home, 1.1 * s, 0), tMs: _t0 + s * 1000, accuracyM: 5));
    }
    await store.idle();
    final List<StoredSession> ss = loadSessionsFrom((await store.dir()).path);
    expect(ss.single.temps.length, 300);
    expect(ss.single.gps.length, 101);
    expect(ss.single.gps.first.hdop, 1.0);

    final Map<String, dynamic> j =
        jsonDecode(buildSummaryData((await store.dir()).path, 'my_dog', 'gen')) as Map<String, dynamic>;
    final Map<String, dynamic> raw = (j['raw'] as Map<String, dynamic>)['2025-11-09'] as Map<String, dynamic>;
    expect((raw['temp_c'] as num).toDouble(), closeTo(36.8, 1e-9)); // 5 段・安定
    expect((raw['outdoor_m'] as num).toDouble(), closeTo(110, 1.0)); // offsetPoint は近似（±1%）
    expect((raw['outdoor_min'] as num).toDouble(), closeTo(100 / 60, 1e-9));
  });

  SummaryBundle bundle(Map<String, double> temps) => SummaryBundle(
        dogId: 'my_dog',
        days: const <DayEntry>[],
        history: const <HistoryDay>[],
        raw: <String, Map<String, double>>{
          for (final MapEntry<String, double> e in temps.entries) e.key: <String, double>{'temp_c': e.value},
        },
      );

  test('健康タブの体温：平時は 3 日から、帯は ±1.0℃、文は「平时 ±X℃」', () {
    final ItemSeries two = buildItemSeries('temp',
        today: '2025-11-13', real: bundle(<String, double>{'2025-11-11': 36.8, '2025-11-12': 36.9, '2025-11-13': 37.0}));
    expect(two.demo, isFalse);
    expect(two.usual, isNull);
    expect(diffText(two), '平时还在收集（还要 1 天）');

    final ItemSeries four = buildItemSeries('temp',
        today: '2025-11-13',
        real: bundle(<String, double>{'2025-11-09': 36.8, '2025-11-10': 36.7, '2025-11-11': 36.9, '2025-11-12': 36.8, '2025-11-13': 38.3}));
    expect(four.usual, closeTo(36.8, 1e-9));
    expect(four.diffAbs, closeTo(1.5, 1e-9));
    expect(four.inBand, isFalse);
    expect(diffText(four), '比平时高（+1.5℃）');
    final ItemSeries same = buildItemSeries('temp',
        today: '2025-11-13',
        real: bundle(<String, double>{'2025-11-10': 36.8, '2025-11-11': 36.9, '2025-11-12': 36.8, '2025-11-13': 36.5}));
    expect(diffText(same), '和平时差不多（−0.3℃）');
  });

  testWidgets('体温のページ：大きく「平时 +1.5℃」、小さく皮膚の温度（参考）、平時は暂定', (WidgetTester tester) async {
    final ItemSeries s = buildItemSeries('temp',
        today: '2025-11-13',
        real: bundle(<String, double>{'2025-11-09': 36.8, '2025-11-10': 36.7, '2025-11-11': 36.9, '2025-11-12': 36.8, '2025-11-13': 38.3}));
    await tester.pumpWidget(MaterialApp(home: ItemPage(series: s)));
    await tester.pumpAndSettle();
    expect(find.text('平时 +1.5℃'), findsOneWidget);
    expect(find.text('皮肤温度 38.3 ℃（参考）　比平时高'), findsOneWidget);
    expect(find.textContaining('带子是 ±1.0℃，不满 14 天，是暂定的'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('运动量のページに今日の屋外（GPS）', () {
    final ItemSeries a = buildItemSeries('activity',
        today: '2025-11-13',
        real: SummaryBundle(
          dogId: 'my_dog',
          days: const <DayEntry>[],
          history: const <HistoryDay>[],
          raw: <String, Map<String, double>>{
            '2025-11-13': <String, double>{'outdoor_m': 1234, 'outdoor_min': 25},
          },
        ));
    expect(a.note, '今天户外 1.23 km・25 分钟（GPS）');
    expect(buildItemSeries('activity', today: '2025-11-13', real: bundle(<String, double>{})).note, isNull);
  });

  test('安全タブ：今日の屋外の距離・時間（1 日まとめと同じ計算）。日付が変わったら 0 から', () {
    int now = _t0 + 100000;
    final LocationController lc = LocationController(nowMs: () => now, tick: null);
    expect(lc.todayOutdoorLine, isNull);
    for (int s = 0; s <= 100; s++) {
      lc.addFix(LocationFix(point: offsetPoint(_home, 1.1 * s, 0), tMs: _t0 + s * 1000, accuracyM: 5));
    }
    expect(lc.todayOutdoorM, closeTo(110, 1.0));
    expect(lc.todayOutdoorLine, '今天户外：110 m・2 分钟');
    now += 86400000; // 次の日：今日の位置がまだない
    expect(lc.todayOutdoorLine, isNull);
    lc.addFix(LocationFix(point: _home, tMs: now, accuracyM: 5));
    expect(lc.todayOutdoorM, 0);
    lc.dispose();
  });
}
