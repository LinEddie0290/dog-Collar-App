// T34-E：試験の記録（犬の情報・生の IMU・正解・スマホの結果）と書き出し。
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/pipeline/session_export.dart';
import 'package:collar_app/pipeline/test_subject.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/continuous_monitor.dart';
import 'package:collar_app/ui/test_page_sessions.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final WindowClassifier _clf = WindowClassifier.fromJson(
    jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>);

const TestSubject _dog = TestSubject(name: 'momo', breed: '柴犬', weightKg: 9.5, position: 'neck_ventral', note: '试验');

/// 模拟の 100 秒を記録して止める。記録のフォルダと、書いた生のサンプルの数を返す。
Future<(Directory, int, String)> _record({int seconds = 100}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final Directory tmp = Directory.systemTemp.createTempSync('export_');
  final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
  int now = DateTime.utc(2026, 11, 2, 2).millisecondsSinceEpoch;
  final PipelineRunner runner = PipelineRunner(
    loadClassifier: () async => _clf,
    compute: (ChunkInput i) async => processChunk(i),
    store: store,
    nowMs: () => now,
  );
  final FakeImuInput fake = FakeImuInput(nowMs: () => now, tick: const Duration(hours: 1));
  final ContinuousMonitor m =
      ContinuousMonitor(link: CollarLink(), runner: runner, inputFactory: (InputKind k, ContinuousMonitor _) => fake);
  m.kind = InputKind.fake;
  await m.setSubject(_dog);
  await m.start();
  for (int s = 0; s < seconds; s++) {
    now += 1000;
    fake.pump();
    await Future<void>.delayed(Duration.zero);
    await runner.idle();
    if (s == 70) {
      runner.markNow('walk');
      runner.addManualVitals(hr: 90);
      await m.setSubject(const TestSubject(name: 'momo', breed: '柴犬', weightKg: 9.6, note: '体重を量り直した'));
    }
  }
  final String id = runner.session!.id;
  await m.stop();
  await store.idle();
  return ((await store.dir()), runner.samplesIn, id);
}

List<Map<String, dynamic>> _readGz(File f) => utf8
    .decode(gzip.decode(f.readAsBytesSync()))
    .split('\n')
    .where((String l) => l.isNotEmpty)
    .map((String l) => jsonDecode(l) as Map<String, dynamic>)
    .toList();

void main() {
  test('記録：生の IMU（CSV）・犬の情報・途中の変更', () async {
    final (Directory dir, int n, String id) = await _record();
    addTearDown(() => dir.parent.deleteSync(recursive: true));
    final List<String> csv = File('${dir.path}/$id.imu.csv').readAsLinesSync();
    expect(csv.first, 't_dev_us,t_ms,sensor,ax,ay,az,gx,gy,gz');
    expect(csv.length - 1, n, reason: '受けたサンプルが全部残る');
    expect(csv[1].split(',').length, 9);
    expect(csv[1].split(',')[2], 'front');

    final List<Map<String, dynamic>> rows =
        File('${dir.path}/$id.jsonl').readAsLinesSync().map((String l) => jsonDecode(l) as Map<String, dynamic>).toList();
    final Map<String, dynamic> h = rows.first;
    expect(h['rec'], 'header');
    expect(h['input'], 'fake');
    expect((h['subject'] as Map<String, dynamic>)['breed'], '柴犬');
    final Map<String, dynamic> info = rows.lastWhere((Map<String, dynamic> r) => r['rec'] == 'info');
    expect((info['subject'] as Map<String, dynamic>)['weight_kg'], 9.6);
  });

  test('書き出し：1 つの gz にまとまり、一覧に出る', () async {
    final (Directory dir, int n, String id) = await _record();
    addTearDown(() => dir.parent.deleteSync(recursive: true));
    final List<SessionListing> list = listSessions(dir.path);
    expect(list.single.id, id);
    expect(list.single.subjectName, 'momo');
    expect(list.single.input, 'fake');
    expect(list.single.rawBytes, greaterThan(0));

    final File f = await exportSession(dir.path, id, '${dir.parent.path}/out', rowsPerLine: 3000, nowMs: 1);
    expect(f.path, endsWith('$id.collar-session.jsonl.gz'));
    final List<Map<String, dynamic>> rows = _readGz(f);
    expect(rows.first['rec'], 'export');
    expect(rows.first['schema'], appExportSchema);
    expect(rows[1]['rec'], 'header');
    final Set<String> kinds = rows.map((Map<String, dynamic> r) => r['rec'] as String).toSet();
    expect(kinds, containsAll(<String>['windows', 'truth', 'vital', 'info', 'imu']));
    final List<Map<String, dynamic>> imu = rows.where((Map<String, dynamic> r) => r['rec'] == 'imu').toList();
    expect(imu.first['columns'], rawImuColumns);
    final int rowsOut = imu.fold(0, (int a, Map<String, dynamic> r) => a + (r['csv'] as String).split('\n').where((String l) => l.isNotEmpty).length);
    expect(rowsOut, n);
    expect(imu.length, (n / 3000).ceil());
    final Map<String, dynamic> btn = rows.firstWhere((Map<String, dynamic> r) => r['rec'] == 'truth' && r['source'] == 'button');
    expect(btn['label'], 'walk');
    expect(rows.any((Map<String, dynamic> r) => r['rec'] == 'vital' && r['kind'] == 'hr_truth' && r['value'] == 90), isTrue);
  });

  testWidgets('テスト画面の一覧から書き出して共有に渡す', (WidgetTester tester) async {
    late Directory dir;
    late String id;
    late PipelineStore store;
    await tester.runAsync(() async {
      final (Directory d, int _, String i) = await _record(seconds: 40);
      dir = d;
      id = i;
      store = PipelineStore(baseDir: () async => d.parent.path);
    });
    addTearDown(() => dir.parent.deleteSync(recursive: true));
    final PipelineRunner runner = PipelineRunner(loadClassifier: () async => _clf, store: store);
    File? shared;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionsCard(
          runner: runner,
          share: (BuildContext _, File f) async => shared = f,
          exportDir: () async => '${dir.parent.path}/out',
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.textContaining('momo'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>('export-$id')));
      for (int i = 0; i < 100 && shared == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(shared, isNotNull);
    expect(shared!.existsSync(), isTrue);
    expect(find.textContaining('做好了'), findsOneWidget);
  });
}
