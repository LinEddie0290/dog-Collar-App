// T34-B：記録の中のデータから心拍を測る（D-050）。
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/pipeline/auto_vitals.dart';
import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter_test/flutter_test.dart';

const int _t0Ms = 1762041600000;
const int _t0Us = 1000000;

/// 計算の代わり（呼ばれた回数と長さを見る）。
class _FakeCompute {
  int calls = 0;
  int lastLen = 0;
  double lastFs = 0;
  VitalsResult call(List<double> m, double fs) {
    calls++;
    lastLen = m.length;
    lastFs = fs;
    return VitalsResult(
        sampleRateHz: fs,
        durationSeconds: m.length / fs,
        quality: VitalsQuality.good,
        heartRateBpm: 80,
        respirationPerMin: 20);
  }
}

ImuSample _s(double t, {String sensor = 'front'}) => ImuSample(
    sensor: sensor,
    tDevUs: _t0Us + (t * 1e6).round(),
    tMs: _t0Ms + (t * 1000).round(),
    ax: 0,
    ay: 0,
    az: 9.80665,
    gx: 0,
    gy: 0,
    gz: 0);

/// t 秒（窓の開始）の状態。measureOk だけ使う。
WindowState _w(int t, bool ok) => WindowState(
    tStartMs: _t0Ms + t * 1000,
    tStartDevUs: _t0Us + t * 1000000,
    activity: 0.01,
    rest: true,
    stillS: 0,
    quietS: ok ? 30 : 0,
    measureOk: ok);

/// [seconds] 秒分のサンプルを入れる（[skip] の秒はない）。状態は 15 秒遅れで 10 秒ごとに渡す。
void _run(AutoVitals av, int seconds, bool Function(int t) ok, {bool Function(double t)? skip}) {
  const double fs = 104;
  final List<WindowState> st = <WindowState>[];
  for (int i = 0; i < seconds * fs; i++) {
    final double t = i / fs;
    if (skip != null && skip(t)) continue;
    av.onSample(_s(t));
    if (i % (10 * fs) == 0) {
      final int upto = t.floor() - 15;
      while (st.length <= upto) {
        st.add(_w(st.length, ok(st.length)));
      }
      av.onStates(List<WindowState>.of(st));
    }
  }
}

void main() {
  test('静止 30 秒 → その窓から 60 秒を測る・10 分は次を測らない', () {
    final _FakeCompute fc = _FakeCompute();
    final AutoVitals av = AutoVitals(compute: fc.call);
    final List<VitalAttempt> done = <VitalAttempt>[];
    av.finishedListeners.add(done.add);
    _run(av, 300, (int t) => t >= 30);
    expect(done.length, 1);
    final VitalAttempt a = done.single;
    expect(a.trigger, 'auto');
    expect(a.status, AttemptStatus.done);
    expect(a.tStartDevUs, _t0Us + 30 * 1000000);
    expect(a.usable, isTrue);
    expect(fc.calls, 1);
    expect(fc.lastLen, closeTo(60 * 104, 2));
    expect(fc.lastFs, closeTo(104, 0.1));
    expect(av.cooldownLeftS, greaterThan(300), reason: '10 分から（300−90）秒を引いた残り');
  });

  test('途中で動いたら中止 → また 30 秒静止したら測る', () {
    final _FakeCompute fc = _FakeCompute();
    final AutoVitals av = AutoVitals(compute: fc.call);
    final List<VitalAttempt> done = <VitalAttempt>[];
    av.finishedListeners.add(done.add);
    _run(av, 300, (int t) => (t >= 30 && t < 61) || t >= 100);
    expect(done.map((VitalAttempt a) => a.status), <AttemptStatus>[AttemptStatus.aborted, AttemptStatus.done]);
    expect(done.first.reason, 'moved');
    expect(done[1].tStartDevUs, _t0Us + 100 * 1000000);
    expect(fc.calls, 1);
  });

  test('データが抜けていたら計算しない（data_gap）', () {
    final _FakeCompute fc = _FakeCompute();
    final AutoVitals av = AutoVitals(compute: fc.call);
    final List<VitalAttempt> done = <VitalAttempt>[];
    av.finishedListeners.add(done.add);
    _run(av, 200, (int t) => t >= 30, skip: (double t) => t >= 50 && t < 70);
    expect(done.first.reason, 'data_gap');
    expect(done.first.status, AttemptStatus.done);
    expect(fc.calls, 0);
  });

  test('手動：押してから 60 秒・選んだセンサー（BMI088）で', () {
    final _FakeCompute fc = _FakeCompute();
    final AutoVitals av = AutoVitals(compute: fc.call, enabled: false, sensor: 'side');
    final List<VitalAttempt> done = <VitalAttempt>[];
    av.finishedListeners.add(done.add);
    expect(av.measureNow(), isFalse, reason: 'まだデータがない');
    for (int i = 0; i < 100 * 10; i++) {
      av.onSample(_s(i / 100, sensor: 'side'));
      av.onSample(_s(i / 104, sensor: 'front'));
    }
    expect(av.measureNow(), isTrue);
    expect(av.measureNow(), isFalse, reason: '測っている間は押せない');
    for (int i = 100 * 10; i < 100 * 75; i++) {
      av.onSample(_s(i / 100, sensor: 'side'));
    }
    expect(done.single.trigger, 'manual');
    expect(done.single.sensor, 'side');
    expect(fc.lastFs, closeTo(100, 0.1));
  });

  test('選んだセンサー（BMI088）のデータがない（Unity・偽のデータ）→ 基板の IMU で測る', () {
    final _FakeCompute fc = _FakeCompute();
    final AutoVitals av = AutoVitals(compute: fc.call, sensor: 'side');
    final List<VitalAttempt> done = <VitalAttempt>[];
    av.finishedListeners.add(done.add);
    _run(av, 150, (int t) => t >= 30);
    expect(av.activeSensor, 'front');
    expect(done.single.sensor, 'front');
    expect(done.single.status, AttemptStatus.done);
    expect(fc.calls, 1);
  });

  test('記録（runner）の中で：静止 → 自動で測って、心拍・呼吸の行が残る', () async {
    final WindowClassifier clf = WindowClassifier.fromJson(
        jsonDecode(File('assets/models/cnn_imu_v1.json').readAsStringSync()) as Map<String, dynamic>);
    final _FakeCompute fc = _FakeCompute();
    final AutoVitals av = AutoVitals(compute: fc.call);
    final PipelineRunner r = PipelineRunner(
        loadClassifier: () async => clf,
        compute: (ChunkInput i) async => processChunk(i),
        autoVitals: av,
        nowMs: () => _t0Ms);
    final FakeImuGenerator g = FakeImuGenerator(
        t0Ms: _t0Ms, scenario: const <FakePhase>[FakePhase('still', 130), FakePhase('walk', 20), FakePhase('still', 50)]);
    for (int s = 1; s <= 200; s++) {
      for (final ImuSample x in g.until(s.toDouble())) {
        r.add(x);
      }
      await r.idle();
    }
    final PipelineSession session = r.session!;
    expect(fc.calls, 1);
    final List<VitalReading> hr = session.vitals.where((VitalReading v) => v.kind == 'hr').toList();
    expect(hr.length, 1);
    expect(hr.single.value, 80);
    expect(hr.single.valid, isTrue);
    // 30 秒静止した窓（約 30 秒）＋ 60 秒の真ん中
    expect((hr.single.tDevUs - 1000000) / 1e6, inInclusiveRange(55, 65));
    expect(session.vitals.where((VitalReading v) => v.kind == 'rr').single.value, 20);
    await r.flush();
  });
}
