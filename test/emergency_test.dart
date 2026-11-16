// T34-G：緊急（冲击・倒下・心率异常）の判定・見張り・安全タブ・記録ファイル（D-060）。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:collar_app/data/emergency_watch.dart';
import 'package:collar_app/data/safety.dart';
import 'package:collar_app/pipeline/auto_vitals.dart';
import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/state/app_notifier.dart';
import 'package:collar_app/state/emergency_controller.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter_test/flutter_test.dart';

const int _t0Ms = 1762041600000; // 2025-11-02 00:00 UTC
const double _fs = 100;

typedef _Acc = (double, double, double);

/// [from] 秒から [seconds] 秒ぶんのサンプル（100 Hz）。[f] は時刻 → 加速度（m/s²）。ぶれ 0.02 m/s² つき。
List<ImuSample> _gen(double from, double seconds, _Acc Function(double t) f, {int seed = 1}) {
  final math.Random r = math.Random(seed + from.round());
  double n() => (r.nextDouble() - 0.5) * 0.07; // 標準偏差 約 0.02
  final List<ImuSample> out = <ImuSample>[];
  final int i0 = (from * _fs).round(), i1 = ((from + seconds) * _fs).round();
  for (int i = i0; i < i1; i++) {
    final double t = i / _fs;
    final _Acc a = f(t);
    final int us = 1000000 + (i * 1e6 / _fs).round();
    out.add(ImuSample(
        sensor: 'front', tDevUs: us, tMs: _t0Ms + (us - 1000000) ~/ 1000, ax: a.$1 + n(), ay: a.$2 + n(), az: a.$3 + n(),
        gx: 0, gy: 0, gz: 0));
  }
  return out;
}

_Acc _rest(double t) => (0, 0, gravity);
_Acc _side(double t) => (gravity, 0, 0); // 横倒し（重力が x へ）
_Acc _walk(double t) {
  final double w = 2 * math.pi * t;
  return (3 * math.sin(w), 1.5 * math.sin(2 * w), gravity + 4 * math.sin(2 * w));
}

/// 角度 [deg] だけ倒した重力。
_Acc _tilt(double deg) {
  final double th = deg * math.pi / 180;
  return (gravity * math.sin(th), 0, gravity * math.cos(th));
}

/// 倒れる：[at] 秒にぶつかり（0.3 秒、約 [peakG] g）と同時に横倒し。
_Acc Function(double) _fallAt(double at, {double peakG = 3}) => (double t) {
      if (t < at) return _rest(t);
      if (t < at + 0.3) return (gravity + (peakG - 1) * gravity, 0, 0);
      return _side(t);
    };

List<EmergencyHit> _run(MotionWatcher w, Iterable<ImuSample> xs) => <EmergencyHit>[for (final ImuSample s in xs) ...w.add(s)];

void main() {
  group('冲击・倒下（MotionWatcher）', () {
    test('冲击：1 g の中に 5 g が 1 回 → 冲击 1 件（通知しない種類）', () {
      final MotionWatcher w = MotionWatcher();
      final List<EmergencyHit> hits = _run(w, _gen(0, 10, (double t) => (t >= 5 && t < 5.01) ? (0, 0, 5 * gravity) : _rest(t)));
      expect(hits.map((EmergencyHit h) => h.kind), <EmergencyKind>[EmergencyKind.impact]);
      expect(hits.single.notify, isFalse);
      expect(hits.single.value, closeTo(5, 0.1));
      expect(hits.single.tMs, _t0Ms + 5000);
      expect(hits.single.detail, '很大的冲击（约 5.0 g）');
    });

    test('倒下：3 g ＋ 横倒し → 2 分ほぼ動かない → 1 件（倒れた時刻、判定は 2 分 3 秒あと）', () {
      final MotionWatcher w = MotionWatcher();
      final List<ImuSample> xs = _gen(0, 140, _fallAt(5));
      int? firedAt;
      final List<EmergencyHit> hits = <EmergencyHit>[];
      for (final ImuSample s in xs) {
        final List<EmergencyHit> h = w.add(s);
        if (h.isNotEmpty) firedAt ??= s.tMs;
        hits.addAll(h);
      }
      expect(hits.map((EmergencyHit h) => h.kind), <EmergencyKind>[EmergencyKind.fall]);
      final EmergencyHit h = hits.single;
      expect(h.notify, isTrue);
      expect(h.tMs, _t0Ms + 5000);
      expect(firedAt! - _t0Ms, inInclusiveRange(127000, 129000));
      expect(h.value, closeTo(3, 0.1));
      expect(h.detail, startsWith('突然倒下（约 3.0 g，方向变了'));
      expect(h.detail, endsWith('之后 2 分钟几乎不动'));
      expect(w.pending, isFalse);
    });

    test('倒れて 30 秒で起きて歩く → 0 件', () {
      final MotionWatcher w = MotionWatcher();
      final List<EmergencyHit> hits = _run(w, <ImuSample>[
        ..._gen(0, 35, _fallAt(5)),
        ..._gen(35, 3, (double t) => _tilt(90 - (t - 35) * 30)), // 3 秒で起き上がる
        ..._gen(38, 200, _walk),
      ]);
      expect(hits, isEmpty);
    });

    test('ゆっくり横になる（10 秒で 90°）→ 10 分静止 → 0 件（寝るのと同じ）', () {
      final MotionWatcher w = MotionWatcher();
      final List<EmergencyHit> hits = _run(w, <ImuSample>[
        ..._gen(0, 5, _rest),
        ..._gen(5, 10, (double t) => _tilt((t - 5) * 9)),
        ..._gen(15, 600, _side),
      ]);
      expect(hits, isEmpty);
    });

    test('倒れたあとデータが 5 秒途切れた → 分からないので出さない', () {
      final MotionWatcher w = MotionWatcher();
      final List<EmergencyHit> hits = _run(w, <ImuSample>[..._gen(0, 20, _fallAt(5)), ..._gen(25, 200, _side)]);
      expect(hits, isEmpty);
    });

    test('ほかのセンサー（side）は見ない', () {
      final MotionWatcher w = MotionWatcher();
      final List<EmergencyHit> hits = _run(w, <ImuSample>[
        for (final ImuSample s in _gen(0, 10, (double t) => (t >= 5 && t < 5.01) ? (0, 0, 6 * gravity) : _rest(t)))
          ImuSample(sensor: 'side', tDevUs: s.tDevUs, tMs: s.tMs, ax: s.ax, ay: s.ay, az: s.az, gx: 0, gy: 0, gz: 0),
      ]);
      expect(hits, isEmpty);
    });

    test('模拟のデータ：歩く・走る・甩身体 を 2 周（9 分）→ 0 件。走るだけ 10 分 → 0 件', () {
      final FakeImuGenerator g = FakeImuGenerator(t0Ms: _t0Ms);
      expect(_run(MotionWatcher(), g.until(540)), isEmpty);
      final FakeImuGenerator r = FakeImuGenerator(t0Ms: _t0Ms, scenario: const <FakePhase>[FakePhase('run', 600)]);
      expect(_run(MotionWatcher(), r.until(600)), isEmpty);
    });

    test('「模拟摔倒」の波形：倒下 1 件（冲击なし）、起き上がりでは出ない', () {
      final FakeImuGenerator g = FakeImuGenerator(t0Ms: _t0Ms)..fallFromS = 100;
      final List<EmergencyHit> hits = _run(MotionWatcher(), g.until(400));
      expect(hits.map((EmergencyHit h) => h.kind), <EmergencyKind>[EmergencyKind.fall]);
      expect(hits.single.tMs - _t0Ms, inInclusiveRange(100000, 100100));
      expect(g.labelAt(150), 'fall');
      expect(g.labelAt(260), isNot('fall'));
    });
  });

  group('心率异常（HeartWatcher）', () {
    test('good が 2 回続けて 180 より上 → 1 件。続けて 3 回目は数え直し', () {
      final HeartWatcher h = HeartWatcher();
      expect(h.add(tMs: 1, bpm: 190, good: true), isNull);
      final EmergencyHit? e = h.add(tMs: 2, bpm: 195, good: true);
      expect(e!.kind, EmergencyKind.heart);
      expect(e.tMs, 2);
      expect(e.detail, '安静时心率 195 次/分（连续 2 次在 50〜180 外面）');
      expect(h.add(tMs: 3, bpm: 200, good: true), isNull);
    });

    test('低すぎる（45・40）も 1 件', () {
      final HeartWatcher h = HeartWatcher();
      h.add(tMs: 1, bpm: 45, good: true);
      expect(h.add(tMs: 2, bpm: 40, good: true), isNotNull);
    });

    test('1 回だけ外・品質が good でない → 0 件', () {
      final HeartWatcher h = HeartWatcher();
      expect(h.add(tMs: 1, bpm: 190, good: true), isNull);
      expect(h.add(tMs: 2, bpm: 90, good: true), isNull); // 戻った：数え直し
      expect(h.add(tMs: 3, bpm: 190, good: true), isNull);
      expect(h.add(tMs: 4, bpm: 200, good: false), isNull); // fair は数えない（リセットもしない）
      expect(h.add(tMs: 5, bpm: 200, good: false), isNull);
      expect(h.add(tMs: 6, bpm: 185, good: true), isNotNull); // 3 と 6 で 2 回
    });
  });

  group('見張り（EmergencyController）', () {
    test('倒下が 3 分おきに 3 回 → 記録 3 件・通知 1 回。冲击は記録だけ', () {
      final MemoryNotifier n = MemoryNotifier();
      final EmergencyController c = EmergencyController(notifier: n);
      final List<EmergencyHit> got = <EmergencyHit>[];
      c.hitListeners.add(got.add);
      final List<ImuSample> xs = <ImuSample>[
        ..._gen(0, 180, _fallAt(5)),
        ..._gen(180, 180, _fallAt(185)),
        ..._gen(360, 180, _fallAt(365)),
        ..._gen(540, 10, (double t) => (t >= 545 && t < 545.01) ? (0, 0, 5 * gravity) : _rest(t)),
      ];
      xs.forEach(c.addSample);
      expect(c.hits.map((EmergencyHit h) => h.kind).toList(),
          <EmergencyKind>[EmergencyKind.impact, EmergencyKind.fall, EmergencyKind.fall, EmergencyKind.fall]);
      expect(c.hits.map((EmergencyHit h) => h.notified).toList(), <bool>[false, false, false, true]);
      expect(n.shown.length, 1);
      expect(n.shown.single.title, '可能倒下了');
      expect(n.shown.single.key, 'emergency-fall');
      expect(got.length, 4);
      c.dispose();
    });

    test('10 分たてばまた通知する', () {
      final MemoryNotifier n = MemoryNotifier();
      final EmergencyController c = EmergencyController(notifier: n);
      c.addHeart(tMs: 0, bpm: 190, good: true);
      c.addHeart(tMs: 60000, bpm: 190, good: true);
      c.addHeart(tMs: 120000, bpm: 190, good: true);
      c.addHeart(tMs: 180000, bpm: 190, good: true); // 2 件目：3 分後なので通知しない
      c.addHeart(tMs: 700000, bpm: 190, good: true);
      c.addHeart(tMs: 760000, bpm: 190, good: true); // 3 件目：前の通知から 10 分以上
      expect(c.hits.length, 3);
      expect(n.shown.map((({String key, String title, String body}) s) => s.title).toList(), <String>['心率异常（试用）', '心率异常（试用）']);
      c.dispose();
    });

    VitalAttempt attempt(String trigger, double bpm, VitalsQuality q, int tMs) =>
        VitalAttempt(trigger: trigger, sensor: 'front', tStartDevUs: 0, tStartMs: tMs)
          ..status = AttemptStatus.done
          ..result = VitalsResult(sampleRateHz: 400, durationSeconds: 60, quality: q, heartRateBpm: bpm);

    test('自動の心拍測定から：auto・done・good だけ数える', () {
      final EmergencyController c = EmergencyController();
      c.addAttempt(attempt('manual', 190, VitalsQuality.good, 1)); // 手動は見ない
      c.addAttempt(attempt('auto', 190, VitalsQuality.good, 2));
      expect(c.hits, isEmpty);
      c.addAttempt(attempt('auto', 195, VitalsQuality.good, 3));
      expect(c.hits.single.kind, EmergencyKind.heart);
      expect(c.hits.single.tMs, 3);
      c.dispose();
    });

    test('安全タブの記録の形：通知した・しなかった・記録だけ', () {
      final List<EmergencyHit> hits = <EmergencyHit>[
        EmergencyHit(kind: EmergencyKind.impact, tMs: _t0Ms, value: 5, detail: 'a', notify: false),
        EmergencyHit(kind: EmergencyKind.fall, tMs: _t0Ms + 60000, value: 3, detail: 'b')..notified = true,
        EmergencyHit(kind: EmergencyKind.fall, tMs: _t0Ms + 120000, value: 3, detail: 'c'),
      ];
      final List<EmergencyEvent> rows = hitEmergencyEvents(hits, '2025-11-02');
      expect(rows.map((EmergencyEvent e) => e.outcome).toList(),
          <String>['只记录（不通知）', '已通知', '10 分钟内已经通知过，这次没有再通知']);
      expect(rows[1].minuteOfDay, 8 * 60 + 1); // UTC＋8
      expect(rows.every((EmergencyEvent e) => !e.demo), isTrue);
      expect(rows.map((EmergencyEvent e) => e.id).toSet().length, 3);
      expect(hitEmergencyEvents(hits, '2025-11-20'), isEmpty); // 7 日より前は出さない
    });
  });

  test('記録ファイル：emergency の行', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('emg');
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    await store.appendEmergency(
        's1', EmergencyHit(kind: EmergencyKind.fall, tMs: 123, value: 2.83456, detail: '突然倒下')..notified = true);
    await store.idle();
    final Map<String, dynamic> row =
        jsonDecode(File('${tmp.path}/pipeline_sessions/s1.jsonl').readAsStringSync().trim()) as Map<String, dynamic>;
    expect(row, <String, dynamic>{
      'rec': 'emergency',
      'kind': 'fall',
      't_ms': 123,
      'value': 2.835,
      'detail': '突然倒下',
      'notified': true,
    });
    await tmp.delete(recursive: true);
  });
}
