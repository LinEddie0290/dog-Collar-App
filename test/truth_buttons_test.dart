// T34-D：正解のラベルのボタンと、手で数えた心拍・呼吸。
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/continuous_monitor.dart';
import 'package:collar_app/ui/test_page.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final WindowClassifier _clf = WindowClassifier.fromJson(
    jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>);

const int _t0Ms = 1761962400000;

ImuSample _s(int tUs, int tMs) =>
    ImuSample(sensor: 'front', tDevUs: tUs, tMs: tMs, ax: 0, ay: 0, az: 9.80665, gx: 0, gy: 0, gz: 0);

void main() {
  test('押した時刻：最後のサンプル＋スマホの時計（0〜2 秒）', () {
    int now = _t0Ms;
    final PipelineRunner r = PipelineRunner(loadClassifier: () async => _clf, nowMs: () => now);
    expect(r.markNow('walk'), isFalse, reason: '記録していない');
    r.add(_s(5000000, _t0Ms));
    now = _t0Ms + 300; // 受信の遅れ 0.3 秒
    expect(r.markNow('walk'), isTrue);
    now = _t0Ms + 10000; // 10 秒サンプルが来ていない → 2 秒まで
    expect(r.markNow('sit'), isTrue);
    now = _t0Ms - 5000; // 偽のデータを速く流しているとき（サンプルの UTC が先）→ 進めない
    expect(r.markNow('lie'), isTrue);
    final List<TruthMark> t = r.session!.truth;
    expect(t.map((TruthMark m) => m.tDevUs), <int>[5300000, 7000000, 5000000]);
    expect(t.map((TruthMark m) => m.tMs), <int>[_t0Ms + 300, _t0Ms + 2000, _t0Ms]);
    expect(t.every((TruthMark m) => m.source == 'button'), isTrue);
  });

  test('取り消しはボタンの印だけ・保存して読み直しても消えている・手で数えた心拍は集計に入れない', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('truth_btn_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    final PipelineRunner r = PipelineRunner(loadClassifier: () async => _clf, store: store, nowMs: () => _t0Ms);
    r.add(_s(5000000, _t0Ms));
    r.addTruth(const TruthMark(tDevUs: 4000000, tMs: _t0Ms - 1000, label: 'Walking', source: 'unity'));
    r.markNow('walk');
    r.markNow('scratch'); // 押し間違い
    expect(r.undoLastButton()!.label, 'scratch');
    expect(r.session!.truth.map((TruthMark m) => m.label), <String>['Walking', 'walk']);
    expect(r.addManualVitals(hr: 88, rr: 24), isTrue);
    expect(r.addManualVitals(), isFalse);
    final String id = r.session!.id;
    await store.idle();

    final StoredSession got = (await store.loadAll()).single;
    expect(got.id, id);
    expect(got.truth.map((TruthMark m) => '${m.label}/${m.source}'), <String>['Walking/unity', 'walk/button']);
    expect(got.vitals.map((VitalReading v) => '${v.kind}=${v.value}'), <String>['hr_truth=88.0', 'rr_truth=24.0']);

    // 出来事・1 日の集計の心拍は 'hr' だけを見る → 手で数えたものは入らない
    final List<WindowResult> wins = <WindowResult>[
      for (int i = 0; i < 60; i++)
        WindowResult(tDevUs: 4000000 + i * 1000000, tMs: _t0Ms - 1000 + i * 1000, activity: 0.01, label: 'still', prob: 0.9),
    ];
    final EventsSnapshot ev = computeEvents(wins, got.vitals);
    expect(ev.events, isNotEmpty);
    expect(ev.events.every((BehaviorEvent e) => e.hrMedian == null && e.rrMedian == null), isTrue);
  });

  testWidgets('テスト画面のボタン：押す・数を記す・取り消す', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late ContinuousMonitor m;
    late PipelineRunner runner;
    await tester.runAsync(() async {
      int now = DateTime.utc(2026, 11, 2, 2).millisecondsSinceEpoch;
      runner = PipelineRunner(
          loadClassifier: () async => _clf, compute: (ChunkInput i) async => processChunk(i), nowMs: () => now);
      final FakeImuInput fake = FakeImuInput(nowMs: () => now, tick: const Duration(hours: 1));
      m = ContinuousMonitor(link: CollarLink(), runner: runner, inputFactory: (InputKind k, ContinuousMonitor _) => fake);
      m.kind = InputKind.fake;
      await m.start();
      for (int s = 0; s < 5; s++) {
        now += 1000;
        fake.pump();
        await Future<void>.delayed(Duration.zero);
      }
    });

    await tester.pumpWidget(MaterialApp(home: TestPage(monitor: m)));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('truth-buttons')), findsOneWidget);
    expect(find.text('趴下'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('truth-walk')));
    await tester.pump();
    List<TruthMark> buttons() =>
        runner.session!.truth.where((TruthMark x) => x.source == 'button').toList();
    expect(buttons().map((TruthMark x) => x.label), <String>['walk']);
    expect(find.textContaining('按过的'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('truth-hr')), '92');
    await tester.tap(find.byKey(const ValueKey<String>('truth-vitals-save')));
    await tester.pump();
    expect(runner.session!.vitals.single.kind, 'hr_truth');
    expect(runner.session!.vitals.single.value, 92);
    expect(find.textContaining('记下了：心率 92'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('truth-undo')));
    await tester.pump();
    expect(buttons(), isEmpty);
    expect(find.textContaining('撤销了'), findsOneWidget);

    await tester.runAsync(() => m.stop());
    await tester.pumpWidget(const SizedBox());
  });
}
