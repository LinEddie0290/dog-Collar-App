// T34-A：少しずつ流れてくる IMU を処理する PipelineRunner。
// 1 回で全部計算したときと同じ結果になるか、状態の切り替わり（±2 秒）、保存 → 每天のページのデータ。
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/pipeline/pipeline_summary_repository.dart';
import 'package:collar_data/collar_data.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

final WindowClassifier _clf = WindowClassifier.fromJson(
    jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>);

const int _t0Us = 5000000;
final int _t0Ms = DateTime.utc(2026, 10, 30, 2).millisecondsSinceEpoch; // 現地（+8）10:00

/// 静止 60 秒 → 歩く 30 秒 → 静止 60 秒（偽のデータ）。
bool _moving(double t) => t >= 60 && t < 90;

class _Raw {
  _Raw(this.tUs, this.v);
  final int tUs;
  final List<double> v;
}

List<_Raw> _synth({double seconds = 150, double fs = 104, int seed = 1, int t0Us = _t0Us}) {
  final math.Random rng = math.Random(seed);
  double g() {
    // ガウスの雑音
    final double u = rng.nextDouble().clamp(1e-12, 1.0), w = rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * w);
  }

  final int n = (seconds * fs).round();
  return <_Raw>[
    for (int i = 0; i < n; i++)
      () {
        final double t = i / fs;
        final bool m = _moving(t);
        final double w = 2 * math.pi * t;
        return _Raw(t0Us + (i * 1e6 / fs).round(), <double>[
          0.02 * g() + (m ? 3.0 * math.sin(w * 1 + 0.3) : 0),
          0.02 * g() + (m ? 1.5 * math.sin(w * 2 + 1.0) : 0),
          9.80665 + 0.02 * g() + (m ? 4.0 * math.sin(w * 2) : 0),
          0.002 * g() + (m ? 0.5 * math.sin(w * 1) : 0),
          0.002 * g() + (m ? 0.8 * math.sin(w * 2) : 0),
          0.002 * g(),
        ]);
      }(),
  ];
}

List<ImuSample> _imu(List<_Raw> raw) => <ImuSample>[
      for (final _Raw r in raw)
        ImuSample(
          sensor: 'front',
          tDevUs: r.tUs,
          tMs: _t0Ms + (r.tUs - _t0Us) ~/ 1000,
          ax: r.v[0],
          ay: r.v[1],
          az: r.v[2],
          gx: r.v[3],
          gy: r.v[4],
          gz: r.v[5],
        ),
    ];

PipelineRunner _runner({PipelineStore? store, int Function()? nowMs}) => PipelineRunner(
      loadClassifier: () async => _clf,
      compute: (ChunkInput i) async => processChunk(i),
      store: store,
      nowMs: nowMs ?? () => _t0Ms,
    );

/// 1 秒分ずつ入れて、そのたびに計算が終わるのを待つ（スマホで流れてくるのと同じ）。
Future<void> _feed(PipelineRunner r, List<ImuSample> xs, {int per = 104}) async {
  for (int i = 0; i < xs.length; i++) {
    r.add(xs[i]);
    if (i % per == per - 1) await r.idle();
  }
}

double _rel(int tUs) => (tUs - _t0Us) / 1e6;

void main() {
  test('少しずつ処理しても、全部を 1 回で処理したときと同じ', () async {
    final List<ImuSample> xs = _imu(_synth());
    final PipelineRunner r = _runner();
    await _feed(r, xs);
    final PipelineSession s = r.session!;
    await r.flush();
    expect(r.lastError, isNull);
    expect(r.chunksDone, greaterThanOrEqualTo(4), reason: '何回かに分けて計算したはず');

    final ChunkOutput whole = processChunk(ChunkInput(samples: xs, classifier: _clf));
    expect(s.windows.length, inInclusiveRange(whole.windows.length - 2, whole.windows.length + 2));

    // 窓はちょうど 1 秒おき（出来事の処理の前提）
    for (int i = 1; i < s.windows.length; i++) {
      expect(s.windows[i].tDevUs - s.windows[i - 1].tDevUs, 1000000, reason: '$i 番目');
      expect(s.windows[i].tMs - s.windows[i - 1].tMs, 1000, reason: '$i 番目の UTC');
    }

    // 変わり目から離れたところは、活動量がほぼ同じ
    int checked = 0;
    for (final WindowResult w in s.windows) {
      final double t = _rel(w.tDevUs);
      if ((t > 56 && t < 62) || (t > 86 && t < 92)) continue;
      final WindowResult o = whole.windows.reduce(
          (WindowResult a, WindowResult b) => (a.tDevUs - w.tDevUs).abs() <= (b.tDevUs - w.tDevUs).abs() ? a : b);
      expect((o.tDevUs - w.tDevUs).abs(), lessThanOrEqualTo(500000));
      expect((w.activity - o.activity).abs(), lessThan(0.05), reason: 't=$t：${w.activity} と ${o.activity}');
      checked++;
    }
    expect(checked, greaterThan(120));
  });

  test('状態の切り替わり（±2 秒）と、安静 30 秒で測ってよい', () async {
    final PipelineRunner r = _runner();
    await _feed(r, _imu(_synth()));
    final PipelineSession s = r.session!;
    await r.flush();
    final List<WindowState> st = s.states;
    expect(st.length, s.windows.length);

    final List<double> active = <double>[
      for (final WindowState x in st)
        if (!x.rest) _rel(x.tStartDevUs),
    ];
    expect(active, isNotEmpty);
    expect(active.first, inInclusiveRange(58 - 2, 60 + 2), reason: '動き始め（窓は 2 秒）');
    expect(active.last + 2, inInclusiveRange(90 - 2, 90 + 2), reason: '動き終わり');

    for (final WindowState x in st) {
      final double t = _rel(x.tStartDevUs);
      if (t > 35 && t < 55) expect(x.measureOk, isTrue, reason: 't=$t 静止して 30 秒たった');
      if (t > 62 && t < 118) expect(x.measureOk, isFalse, reason: 't=$t 動いている／静止から 30 秒たっていない');
      if (t > 125 && t < 145) expect(x.measureOk, isTrue, reason: 't=$t もう一度静止して 30 秒');
    }
    // 出来事：最後は休息（状態から）
    expect(s.events, isNotEmpty);
    expect(s.events.last.type, anyOf('rest_lie', 'long_still'));
  });

  test('保存 → 每天のページのデータ（本物）', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('pipe_store_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    final PipelineRunner r = _runner(store: store);
    await _feed(r, _imu(_synth()));
    final PipelineSession s = r.session!;
    await r.flush();
    final int n = s.windows.length; // flush で残りの窓も足される

    final List<StoredSession> got = await store.loadAll();
    expect(got.length, 1);
    expect(got.first.header['schema'], appSessionSchema);
    expect(got.first.windows.length, n);

    final SummaryBundle b = await PipelineSummaryRepository(store: store, dogId: 'dog_t', inIsolate: false).load();
    expect(b.days.length, 1);
    expect(b.days.first.date, '2026-10-30');
    expect(b.days.first.summary, isNotNull, reason: '${b.days.first.error}');
    expect(b.days.first.summary!.categories.length, 4);
    expect(b.dogId, 'dog_t');
    final Map<String, double> raw = b.raw['2026-10-30']!;
    expect(raw['wear_min'], closeTo(n / 60, 1e-9));
    final double evMin = raw.entries
        .where((MapEntry<String, double> e) => e.key != 'wear_min')
        .fold(0.0, (double a, MapEntry<String, double> e) => a + e.value);
    expect(evMin, greaterThan(1), reason: '出来事の分：$raw');
  });

  test('首輪（BLE）のサンプル：時計の対応と、再起動で新しいセッション', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('pipe_reboot_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    int now = _t0Ms;
    final PipelineRunner r = _runner(store: store, nowMs: () => now);
    int seq = 0;
    Future<void> run(List<_Raw> raw) async {
      for (int i = 0; i < raw.length; i++) {
        final _Raw x = raw[i];
        r.addPet(PetImuSample(
          configId: 1,
          sensor: PetSensor.onboardImu,
          sequence: seq++,
          monotonicUs: x.tUs,
          ax: x.v[0],
          ay: x.v[1],
          az: x.v[2],
          gx: x.v[3],
          gy: x.v[4],
          gz: x.v[5],
        ));
        if (i % 104 == 103) {
          now += 1000;
          await r.idle();
        }
      }
    }

    await run(_synth(seconds: 45));
    final PipelineSession first = r.session!;
    now += 5000;
    await run(_synth(seconds: 45, seed: 2, t0Us: 1000000)); // 首輪の時計が 1 秒からやり直し
    final PipelineSession second = r.session!;
    await r.flush();

    expect(identical(first, second), isFalse);
    expect(first.windows, isNotEmpty);
    expect(second.windows, isNotEmpty);
    // UTC：最初のサンプルを受けたときのスマホの時計（_t0Ms）＋首輪の時間
    final WindowResult w = first.windows.first;
    expect(w.tMs, closeTo(_t0Ms + (w.tDevUs - _t0Us) / 1000, 1));
    expect(second.windows.first.tMs, greaterThan(first.windows.last.tMs));
    expect((await store.loadAll()).length, 2);
    expect(r.warnings.any((String x) => x.contains('重启')), isTrue);
  });

  test('別の isolate でも同じ（CNN の重みを送れる）', () async {
    final List<ImuSample> xs = _imu(_synth(seconds: 20));
    final ChunkInput input = ChunkInput(samples: xs, classifier: _clf);
    final ChunkOutput a = processChunk(input);
    final ChunkOutput b = await Isolate.run(() => processChunk(input));
    expect(b.windows.length, a.windows.length);
    for (int i = 0; i < a.windows.length; i++) {
      expect(b.windows[i].label, a.windows[i].label);
      expect(b.windows[i].activity, a.windows[i].activity);
    }
  });
}
