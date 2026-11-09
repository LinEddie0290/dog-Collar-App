// T35 安全タブ：緊急の 4 項目・示例の記録・今の状態の文。
import 'package:collar_app/data/health_series.dart' show lastDates;
import 'package:collar_app/data/safety.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('緊急の 4 項目：enum の順・全部の欄がある', () {
    expect(emergencySpecs.map((EmergencySpec s) => s.kind).toList(), EmergencyKind.values);
    for (final EmergencySpec s in emergencySpecs) {
      for (final String t in <String>[s.name, s.how, s.what, s.why, s.source]) {
        expect(t, isNotEmpty, reason: s.kind.name);
      }
      expect(emergencySpec(s.kind).name, s.name);
    }
  });

  test('示例の記録：同じ日なら同じ・新しい順・期間の中・ときどき出る', () {
    final List<EmergencyEvent> a = demoEmergencyEvents('2026-11-05');
    final List<EmergencyEvent> b = demoEmergencyEvents('2026-11-05');
    expect(a.map((EmergencyEvent e) => '${e.date} ${e.timeText} ${e.kind.name} ${e.detail} ${e.outcome}').toList(),
        b.map((EmergencyEvent e) => '${e.date} ${e.timeText} ${e.kind.name} ${e.detail} ${e.outcome}').toList());
    // 2026-11-05 までの 7 日：11-01 の冲击、10-30 の走失（並びは新しい順）
    expect(a.map((EmergencyEvent e) => '${e.date}/${e.kind.name}').toList(),
        <String>['2026-11-01/impact', '2026-10-30/lost']);
    final Set<String> week = lastDates('2026-11-05', 7).toSet();
    for (final EmergencyEvent e in a) {
      expect(week, contains(e.date));
      expect(e.demo, isTrue);
      expect(e.minuteOfDay, inInclusiveRange(0, 1439));
      expect(e.detail, isNotEmpty);
      expect(e.outcome, isNotEmpty);
      expect(e.timeText, matches(RegExp(r'^\d\d:\d\d$')));
    }
    final List<EmergencyEvent> many = demoEmergencyEvents('2026-11-05', days: 120);
    expect(many.length, 22); // 120 日・4 項目で 22 件（1/23 くらい）
    for (int i = 1; i < many.length; i++) {
      final EmergencyEvent p = many[i - 1], q = many[i];
      expect(p.date.compareTo(q.date) > 0 || (p.date == q.date && p.minuteOfDay >= q.minuteOfDay), isTrue);
    }
  });

  test('首輪の 1 行', () {
    const int now = 1762300000000;
    expect(collarStatusLine(connected: true, recording: false, nowMs: now), '项圈已连接・没有在记录');
    expect(collarStatusLine(connected: null, recording: false, nowMs: now), '没有在记录');
    expect(collarStatusLine(connected: false, recording: true, nowMs: now), '项圈未连接・记录中・还没有收到数据');
    expect(collarStatusLine(connected: true, recording: true, lastReceivedMs: now - 5000, nowMs: now), '项圈已连接・最后收到数据：刚刚');
    expect(collarStatusLine(connected: null, recording: true, lastReceivedMs: now - 30000, nowMs: now), '最后收到数据：30 秒前');
    expect(collarStatusLine(connected: true, recording: true, lastReceivedMs: now - 125000, nowMs: now), '项圈已连接・最后收到数据：2 分钟前');
    expect(dataStale(recording: true, lastReceivedMs: now - 59999, nowMs: now), isFalse);
    expect(dataStale(recording: true, lastReceivedMs: now - 60000, nowMs: now), isTrue);
    expect(dataStale(recording: false, lastReceivedMs: now - 600000, nowMs: now), isFalse);
  });

  test('記録：サンプルを受けた時刻（スマホの時計）を覚える', () {
    int now = 1762300000000;
    final PipelineRunner r = PipelineRunner(loadClassifier: () async => throw StateError('使わない'), nowMs: () => now);
    expect(r.lastReceivedMs, isNull);
    r.add(const ImuSample(sensor: 'front', tDevUs: 1000000, tMs: 5, ax: 0, ay: 0, az: 9.8, gx: 0, gy: 0, gz: 0));
    expect(r.lastReceivedMs, now);
    now += 1234;
    r.add(const ImuSample(sensor: 'front', tDevUs: 1010000, tMs: 15, ax: 0, ay: 0, az: 9.8, gx: 0, gy: 0, gz: 0));
    expect(r.lastReceivedMs, now);
  });
}
