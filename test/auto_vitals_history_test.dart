// T34-B：自動測定を履歴に入れる（波形の画像つき）。
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collar_app/data/measurement_record.dart';
import 'package:collar_app/pipeline/auto_vitals.dart';
import 'package:collar_app/pipeline/auto_vitals_history.dart';
import 'package:collar_app/ui/rhythm_strip_renderer.dart';
import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter_test/flutter_test.dart';

const int _t0Ms = 1762041600000;

VitalAttempt _done({String trigger = 'auto', AttemptStatus status = AttemptStatus.done, bool withResult = true}) {
  final VitalAttempt a = VitalAttempt(trigger: trigger, sensor: 'front', tStartDevUs: 31000000, tStartMs: _t0Ms);
  a.status = status;
  a.fs = 100;
  a.samples = 6000;
  if (withResult) {
    a.result = VitalsResult(
      sampleRateHz: 100,
      durationSeconds: 60,
      quality: VitalsQuality.good,
      heartRateBpm: 80,
      respirationPerMin: 20,
      beatTimesSeconds: const <double>[0.5, 1.25, 2.0],
      beatBand: List<double>.generate(6000, (int i) => math.sin(i / 10)),
    );
  }
  return a;
}

void main() {
  test('測れたら：波形の画像を作って、履歴に入れる', () async {
    Map<String, Object>? renderArgs;
    String? stripId;
    MeasurementRecord? saved;
    final AttemptHistorySaver s = AttemptHistorySaver(
      render: ({required List<double> wave, required List<int> beatIndices, required double sampleRateHz}) async {
        renderArgs = <String, Object>{'n': wave.length, 'beats': beatIndices, 'fs': sampleRateHz};
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
      saveStrip: (String id, Uint8List png) async {
        stripId = id;
        return 'rhythm_strips/$id.png';
      },
      saveRecord: (MeasurementRecord r) async => saved = r,
    );
    final VitalAttempt a = _done();
    final MeasurementRecord? r = await s.save(a);
    expect(r, isNotNull);
    expect(renderArgs!['n'], 6000);
    expect(renderArgs!['beats'], <int>[50, 125, 200]);
    expect(renderArgs!['fs'], 100);
    expect(stripId, '$_t0Ms');
    expect(saved!.rhythmStripFile, 'rhythm_strips/$_t0Ms.png');
    expect(saved!.heartRateBpm, 80);
    expect(saved!.note, contains('自动测量'));
    expect(a.rhythmStripFile, 'rhythm_strips/$_t0Ms.png');
    expect(a.recordId, saved!.id);
  });

  test('画像が作れなくても測定は保存・中止は保存しない', () async {
    final List<MeasurementRecord> saved = <MeasurementRecord>[];
    final AttemptHistorySaver s = AttemptHistorySaver(
      render: ({required List<double> wave, required List<int> beatIndices, required double sampleRateHz}) async =>
          throw StateError('描けない'),
      saveStrip: (String id, Uint8List png) async => 'x',
      saveRecord: (MeasurementRecord r) async => saved.add(r),
    );
    await s.save(_done(trigger: 'manual'));
    expect(saved.single.rhythmStripFile, isNull);
    expect(saved.single.note, contains('记录中手动'));
    expect(await s.save(_done(status: AttemptStatus.aborted, withResult: false)), isNull);
    expect(saved.length, 1);
  });

  testWidgets('本物の描き方で PNG ができる', (WidgetTester tester) async {
    Uint8List? png;
    await tester.runAsync(() async {
      png = await renderRhythmStripPng(
        wave: List<double>.generate(1000, (int i) => math.sin(i / 8)),
        beatIndices: const <int>[100, 300, 500],
        sampleRateHz: 100,
      );
    });
    expect(png, isNotNull);
    expect(png!.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]); // PNG の頭
  });
}
