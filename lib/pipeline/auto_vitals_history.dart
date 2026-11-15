/// T34-B：自動・記録中の手動の測定を、今の測定の履歴に入れる（波形の画像つき）。
///
/// 手動の測定（VitalsSession.stop）と同じ作り方：拍の帯域の波形（VitalsResult.beatBand）と
/// 拍の位置を 1 枚の PNG にして保存し、MeasurementRecord.rhythmStripFile に相対パスを書く。
/// → 「測定」タブの履歴から、手動と同じように「波形と検出した拍」が見られる。
/// 画像が作れなくても、測定そのものは保存する（波形は付加情報）。
library;

import 'dart:typed_data';

import 'package:collar_vitals/collar_vitals.dart';

import '../data/measurement_record.dart';
import '../ui/rhythm_strip_renderer.dart';
import 'auto_vitals.dart';

typedef StripRenderer = Future<Uint8List?> Function({
  required List<double> wave,
  required List<int> beatIndices,
  required double sampleRateHz,
});

class AttemptHistorySaver {
  AttemptHistorySaver({required this.saveStrip, required this.saveRecord, this.render = renderRhythmStripPng});

  /// MeasurementStore.saveRhythmStripPng（相対パスを返す）。
  final Future<String> Function(String id, Uint8List png) saveStrip;

  /// MeasurementStore.save。
  final Future<void> Function(MeasurementRecord r) saveRecord;
  final StripRenderer render;

  /// 測れた（品質が悪いのも含む）ものだけ保存する。中止・データの抜けは保存しない（記録の方には残る）。
  Future<MeasurementRecord?> save(VitalAttempt a) async {
    final VitalsResult? r = a.result;
    final double? fs = a.fs;
    if (a.status != AttemptStatus.done || r == null || fs == null) return null;
    final DateTime startedAt = DateTime.fromMillisecondsSinceEpoch(a.tStartMs);
    final String id = startedAt.toUtc().millisecondsSinceEpoch.toString();

    String? strip;
    try {
      final Uint8List? png = await render(
        wave: r.beatBand,
        beatIndices: <int>[for (final double t in r.beatTimesSeconds) (t * fs).round()],
        sampleRateHz: fs,
      );
      if (png != null) strip = await saveStrip(id, png);
    } on Object {
      // 画像が作れなくても測定は保存する
    }
    a.rhythmStripFile = strip;

    final MeasurementRecord rec = MeasurementRecord.fromResult(
      startedAt: startedAt,
      result: r,
      sampleCount: a.samples,
      imuRateHz: fs.round(),
      note: '${a.trigger == 'auto' ? '自动测量（记录中，安静 30 秒后）' : '记录中手动测量'}・${a.sensor}',
      rhythmStripFile: strip,
    );
    try {
      await saveRecord(rec);
      a.recordId = rec.id;
    } on Object {
      return null;
    }
    return rec;
  }
}
