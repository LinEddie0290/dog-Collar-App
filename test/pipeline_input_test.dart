// T34-F：首輪がないときの入力（Unity・偽のデータ）→ 処理の流れ。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/continuous_monitor.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

final WindowClassifier _clf = WindowClassifier.fromJson(
    jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>);

const String _hello = '{"v":1,"type":"hello","data":"dogmovedata","fs_hz":100,"sensor":"front",'
    '"acc_unit":"g","gyro_unit":"deg/s"}';

String _imuMsg(int seq, int firstRow, int n, {double ax = 0, double gx = 0}) => jsonEncode(<String, Object?>{
      'v': 1,
      'type': 'imu',
      'seq': seq,
      'pc_ms': 1761100000000 + seq * 1000,
      'rows': <List<num>>[
        for (int j = 0; j < n; j++) <num>[(firstRow + j) * 10000, ax, 0, 1, gx, 0, 0],
      ],
    });

void main() {
  group('Unity のメッセージ（collar/io/unity.py と同じ読み方）', () {
    test('単位・時刻・抜け・壊れたメッセージ・ラベル', () {
      final UnityStreamParser p = UnityStreamParser(nowMs: () => 1000000);
      expect(p.feed(_imuMsg(0, 0, 3)), isEmpty, reason: 'hello の前の imu は数えて捨てる');
      expect(p.nBad, 1);
      p.feed(_hello);
      final List<ImuSample> a = p.feed(_imuMsg(0, 0, 3, ax: 1, gx: 180));
      expect(a.length, 3);
      expect(a.first.sensor, 'front');
      expect(a.first.ax, closeTo(9.80665, 1e-9));
      expect(a.first.az, closeTo(9.80665, 1e-9));
      expect(a.first.gx, closeTo(math.pi, 1e-12));
      expect(a.map((ImuSample s) => s.tDevUs), <int>[0, 10000, 20000]);
      expect(a.map((ImuSample s) => s.tMs), <int>[1000000, 1000010, 1000020], reason: 'UTC はスマホの時計から');
      p.feed(_imuMsg(3, 3, 2)); // seq 1・2 が抜けた
      expect(p.seqGaps, 2);
      p.feed('{"v":1,"type":"label","t_us":20000,"label":"walk"}');
      expect(p.marks.single.label, 'walk');
      expect(p.marks.single.tMs, 1000020);
      p.feed('not json');
      p.feed('{"v":1,"type":"imu","seq":4,"rows":[[1,2,3]]}');
      expect(p.nBad, 3);
      p.feed('{"v":1,"type":"end"}');
      expect(p.ended, isTrue);
      expect(p.rows, 5);
    });

    test('WebSocket で受ける・切れたらつなぎ直す', () async {
      int conns = 0;
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest req) async {
        final WebSocket ws = await WebSocketTransformer.upgrade(req);
        conns++;
        ws.add(_hello);
        for (int k = 0; k < 10; k++) {
          ws.add(_imuMsg(k, k * 100, 100));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await ws.close(); // 正轩の Unity が止まった
      });

      final UnityImuInput input =
          UnityImuInput('ws://127.0.0.1:${server.port}/imu', retry: const Duration(milliseconds: 100));
      final List<ImuSample> got = <ImuSample>[];
      final StreamSubscription<ImuSample> sub = input.samples.listen(got.add);
      await input.start();
      final DateTime until = DateTime.now().add(const Duration(seconds: 10));
      while (got.length < 2000 && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await input.stop();
      await sub.cancel();
      input.dispose();
      expect(got.length, greaterThanOrEqualTo(2000), reason: '2 回分（つなぎ直した）');
      expect(conns, greaterThanOrEqualTo(2));
      expect(input.reconnects, greaterThanOrEqualTo(1));
      expect(input.parser.nBad, 0);
    });

    test('つながらない URL はすぐ分かる', () async {
      final UnityImuInput input = UnityImuInput('ws://127.0.0.1:1/imu');
      await expectLater(input.start(), throwsA(anything));
      expect(input.error, contains('Unity 连不上'));
      input.dispose();
    });
  });

  group('偽のデータ', () {
    test('104 Hz・決まった順・同じ seed なら同じ値', () {
      final FakeImuGenerator a = FakeImuGenerator(t0Ms: 0, seed: 3), b = FakeImuGenerator(t0Ms: 0, seed: 3);
      final List<ImuSample> xa = a.until(10), xb = b.until(10);
      expect(xa.length, 1040);
      expect(xa.last.ax, xb.last.ax);
      expect(a.cycleS, 270);
      expect(<String>[for (final double t in <double>[0, 59.9, 60, 89.9, 90, 150, 170, 210, 214, 269.9, 270]) a.labelAt(t)],
          <String>['still', 'still', 'walk', 'walk', 'still', 'run', 'still', 'shake', 'still', 'still', 'still']);
    });

    test('記録バーから：模拟を選んで記録 → 状態と正解のラベルが残る', () async {
      int now = DateTime.utc(2026, 11, 1, 2).millisecondsSinceEpoch;
      final PipelineRunner runner = PipelineRunner(
        loadClassifier: () async => _clf,
        compute: (ChunkInput i) async => processChunk(i),
        nowMs: () => now,
      );
      // タイマーは使わない（テストで時計を進める）
      final FakeImuInput fake = FakeImuInput(nowMs: () => now, tick: const Duration(hours: 1));
      final ContinuousMonitor m =
          ContinuousMonitor(link: CollarLink(), runner: runner, inputFactory: (InputKind k, ContinuousMonitor _) => fake);
      m.kind = InputKind.fake;
      await m.start();
      expect(m.running, isTrue);
      expect(m.errorMessage, isNull);
      for (int s = 0; s < 148; s++) { // 150 秒から走るので、その前まで
        now += 1000;
        fake.pump();
        // broadcast の Stream は 1 件ずつ microtask で届けるので、タイマー 1 回分待って全部届ける
        await Future<void>.delayed(Duration.zero);
        await runner.idle();
      }
      final PipelineSession session = runner.session!;
      await m.stop();
      expect(m.running, isFalse);
      expect(runner.session, isNull);

      expect(session.windows.length, greaterThan(135));
      final List<double> active = <double>[
        for (final WindowState x in session.states)
          if (!x.rest) (x.tStartDevUs - 1000000) / 1e6,
      ];
      expect(active.first, inInclusiveRange(56, 62));
      expect(active.last + 2, inInclusiveRange(88, 92));
      expect(session.truth.map((TruthMark t) => t.label).toList(), <String>['still', 'walk', 'still']);
      expect(session.truth[1].tDevUs, 1000000 + 60000000);
    });
  });
}
