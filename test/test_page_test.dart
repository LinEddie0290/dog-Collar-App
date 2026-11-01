// T34-C：テスト画面と、正解のラベルと CNN の比べ方。
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/pipeline/truth_compare.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/continuous_monitor.dart';
import 'package:collar_app/ui/test_page.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WindowResult _w(int tUs, String label) =>
    WindowResult(tDevUs: tUs, tMs: tUs ~/ 1000, activity: 0.1, label: label, prob: 0.9);

void main() {
  group('正解のラベル → CNN v1 のクラス', () {
    test('collar-pipeline の対応と同じ', () {
      expect(truthToCnnClass('Walking'), 'walk');
      expect(truthToCnnClass('Galloping'), 'run');
      expect(truthToCnnClass('Lying chest'), 'still');
      expect(truthToCnnClass('sit'), 'still');
      expect(truthToCnnClass('shake'), 'other'); // 偽のデータの「振る」
      expect(truthToCnnClass('Sniffing'), 'other');
      expect(truthToCnnClass('????'), isNull);
    });

    test('時刻の正解と、一致の割合', () {
      const List<TruthMark> marks = <TruthMark>[
        TruthMark(tDevUs: 0, tMs: 0, label: 'still'),
        TruthMark(tDevUs: 10000000, tMs: 10000, label: 'walk'),
        TruthMark(tDevUs: 20000000, tMs: 20000, label: '????'),
      ];
      expect(truthAt(marks, -1), isNull);
      expect(truthAt(marks, 9999999)!.label, 'still');
      expect(truthAt(marks, 10000000)!.label, 'walk');
      // 窓の真ん中（+1 秒）で比べる：8 秒の窓は 9 秒＝still、9 秒の窓は 10 秒＝walk
      final Agreement a = agreement(<WindowResult>[
        _w(0, 'still'),
        _w(8000000, 'still'),
        _w(9000000, 'still'), // 違う
        _w(12000000, 'walk'),
        _w(25000000, 'walk'), // 知らないラベルは数えない
      ], marks);
      expect(a.n, 4);
      expect(a.same, 3);
      expect(a.rate, 0.75);
    });
  });

  testWidgets('テスト画面：模拟で記録した結果が出る', (WidgetTester tester) async {
    late ContinuousMonitor m;
    await tester.runAsync(() async {
      final WindowClassifier clf = WindowClassifier.fromJson(
          jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>);
      int now = DateTime.utc(2026, 11, 1, 2).millisecondsSinceEpoch;
      final PipelineRunner runner = PipelineRunner(
        loadClassifier: () async => clf,
        compute: (ChunkInput i) async => processChunk(i),
        nowMs: () => now,
      );
      final FakeImuInput fake = FakeImuInput(nowMs: () => now, tick: const Duration(hours: 1));
      m = ContinuousMonitor(link: CollarLink(), runner: runner, inputFactory: (InputKind k, ContinuousMonitor _) => fake);
      m.kind = InputKind.fake;
      await m.start();
      for (int s = 0; s < 100; s++) {
        now += 1000;
        fake.pump();
        await Future<void>.delayed(Duration.zero);
        await runner.idle();
      }
    });

    await tester.pumpWidget(MaterialApp(home: TestPage(monitor: m)));
    await tester.pump();
    expect(find.text('测试画面'), findsOneWidget);
    expect(find.textContaining('模拟数据'), findsWidgets);
    expect(find.textContaining('CNN：'), findsOneWidget);
    expect(find.textContaining('CNN 和正确答案一致'), findsOneWidget);
    expect(find.textContaining('front：'), findsOneWidget);
    expect(find.textContaining('缺口 0 次'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('test-timeline')), findsOneWidget);

    // 1 秒ごとの更新が動く（タイマーは画面を閉じると止まる）
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('个/秒'), findsOneWidget);

    await tester.runAsync(() => m.stop());
    await tester.pumpWidget(const SizedBox());
  });
}
