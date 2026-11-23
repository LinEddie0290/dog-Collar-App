// T44（D-066）：心電図・血圧の App 側（モデルを呼ぶ順番・5 折の平均・测试画面のカード）。
// 本物の TFLite は flutter test では動かないので、にせのモデルで。本物は iPhone の测试画面で確かめる。
import 'dart:typed_data';

import 'package:collar_app/ecg_bp/ecg_bp_runner.dart';
import 'package:collar_app/ui/ecg_bp_test_card.dart';
import 'package:collar_ecg_bp/collar_ecg_bp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements EcgBpBackend {
  final List<String> calls = <String>[];

  @override
  Future<List<List<double>>> ecg(List<Float32List> windows) async {
    calls.add('ecg ${windows.length}');
    return <List<double>>[for (final Float32List w in windows) w.toList()];
  }

  @override
  Future<List<double>> bp(String target, int fold, List<Float32List> windows) async {
    calls.add('$target $fold ${windows.length}');
    return List<double>.filled(windows.length, target == 'sbp' ? 110.0 + fold : 70.0 + fold);
  }

  @override
  void close() {}
}

void main() {
  test('にせの信号：心電図は窓 28/32、血圧は 5 折 × 2 を 32 窓で呼んで平均', () async {
    final _FakeBackend b = _FakeBackend();
    final EcgBpOutcome o = await runEcgBpSynth(backend: b);
    expect(o.ecg.windowsUsed, 28);
    expect(o.ecg.input.nAll, 32);
    expect(b.calls.first, 'ecg 28');
    expect(b.calls.where((String c) => c.startsWith('sbp')).length, 5);
    expect(b.calls.where((String c) => c.startsWith('dbp')).length, 5);
    expect(b.calls.last, 'dbp 5 32');
    expect(o.bp!.sbp, closeTo(113.0, 1e-9));
    expect(o.bp!.dbp, closeTo(73.0, 1e-9));
    expect(o.bpError, isNull);
  });

  test('45 秒に足りないときは血圧だけ出さない（心電図は出す）', () async {
    final ({Float64List ax, Float64List ay, Float64List az}) s = synthCollarAcc(n: 400 * 30);
    final EcgBpOutcome o = await runEcgBp(s.ax, s.ay, s.az, 400.0, _FakeBackend());
    expect(o.bp, isNull);
    expect(o.bpError, contains('45'));
    expect(o.ecg.input.nAll, greaterThan(0));
  });

  testWidgets('测试画面のカード：押すと結果の行が出る', (WidgetTester tester) async {
    final ({Float64List ax, Float64List ay, Float64List az}) s = synthCollarAcc(n: 400 * 20);
    final EcgInput ein = ecgModelInput(s.ax, s.ay, s.az, 400.0, const EcgSettings());
    final EcgBpOutcome fake = EcgBpOutcome(
      ecg: EcgResult(settings: const EcgSettings(), input: ein, ecg: Float64List(0), rPeaks: <int>[1, 2], heartRateBpm: 88.0),
      bp: null,
      bpError: '45 秒に足りない',
      prepMs: 1200,
      modelMs: 3400,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: EcgBpTestCard(run: () async => fake))),
    ));
    expect(find.byKey(const ValueKey<String>('ecg-bp-test-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('ecg-bp-test-run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('R 波 2 个，心率 88.0 次/分'), findsOneWidget);
    expect(find.textContaining('血压：算不了'), findsOneWidget);
    expect(find.textContaining('前处理 1.2 秒，模型 3.4 秒'), findsOneWidget);
  });
}
