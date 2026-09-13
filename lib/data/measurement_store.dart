/// Persistence for measurements: append-only JSONL in the app's documents
/// directory.
///
/// Why not SQLite: this needs no new dependency (`path_provider` is already
/// here), the volume is tiny — one line per measurement, a few hundred bytes —
/// and a plain text file can be copied off the phone and read by anyone,
/// including a vet's spreadsheet. The schema carries a version number so a move
/// to SQLite later is a migration rather than a rewrite.
///
/// Append-only matters: a measurement is a record of something that happened,
/// so editing history is not a feature. Notes are the exception and are applied
/// by rewriting the file.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'measurement_record.dart';

class MeasurementStore {
  MeasurementStore({this.fileName = 'measurements.jsonl'});

  final String fileName;
  File? _file;

  Future<File> _open() async {
    if (_file != null) return _file!;
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$fileName');
    if (!await f.exists()) {
      await f.create(recursive: true);
    }
    _file = f;
    return f;
  }

  /// Where the file lives, for a "share this with your vet" action.
  Future<String> get path async => (await _open()).path;

  Future<void> save(MeasurementRecord r) async {
    final File f = await _open();
    await f.writeAsString('${jsonEncode(r.toJson())}\n',
        mode: FileMode.append, flush: true);
  }

  /// Newest first. A corrupt line is skipped rather than failing the whole
  /// read — one bad write should not cost the user their history.
  Future<List<MeasurementRecord>> loadAll() async {
    final File f = await _open();
    final List<String> lines = await f.readAsLines();
    final List<MeasurementRecord> out = <MeasurementRecord>[];
    for (final String line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final Object? j = jsonDecode(line);
        if (j is Map<String, dynamic>) {
          out.add(MeasurementRecord.fromJson(j));
        }
      } on FormatException {
        continue;
      }
    }
    out.sort((MeasurementRecord a, MeasurementRecord b) =>
        b.startedAt.compareTo(a.startedAt));
    return out;
  }

  /// Adds or replaces the note and posture on an existing record.
  Future<void> annotate(String id, {String? note, String? posture}) async {
    final List<MeasurementRecord> all = await loadAll();
    final File f = await _open();
    final StringBuffer sb = StringBuffer();
    for (final MeasurementRecord r in all.reversed) {
      final MeasurementRecord out = r.id == id
          ? MeasurementRecord(
              id: r.id,
              startedAt: r.startedAt,
              durationSeconds: r.durationSeconds,
              quality: r.quality,
              heartRateBpm: r.heartRateBpm,
              heartRateConfidence: r.heartRateConfidence,
              respirationPerMin: r.respirationPerMin,
              bodyTempC: r.bodyTempC,
              sdnnMs: r.sdnnMs,
              rmssdMs: r.rmssdMs,
              beatIntervalCvPercent: r.beatIntervalCvPercent,
              beatCount: r.beatCount,
              sampleCount: r.sampleCount,
              gapCount: r.gapCount,
              receiveErrors: r.receiveErrors,
              imuRateHz: r.imuRateHz,
              note: note ?? r.note,
              posture: posture ?? r.posture,
              beatIntervalsMs: r.beatIntervalsMs,
            )
          : r;
      sb.writeln(jsonEncode(out.toJson()));
    }
    await f.writeAsString(sb.toString(), flush: true);
  }

  Future<void> delete(String id) async {
    final List<MeasurementRecord> all = await loadAll();
    final File f = await _open();
    final StringBuffer sb = StringBuffer();
    for (final MeasurementRecord r in all.reversed) {
      if (r.id == id) continue;
      sb.writeln(jsonEncode(r.toJson()));
    }
    await f.writeAsString(sb.toString(), flush: true);
  }

  /// CSV for a vet or a spreadsheet.
  ///
  /// The quality columns are not optional extras — they are what lets a reader
  /// tell a solid 120 bpm from a guess, so they sit right next to the value.
  Future<String> exportCsv({String? petName}) async {
    final List<MeasurementRecord> all = await loadAll();
    final StringBuffer sb = StringBuffer();
    if (petName != null && petName.isNotEmpty) {
      sb.writeln('# pet,$petName');
    }
    sb.writeln('# 測定方法: 首輪の加速度センサーによる心弾動（心臓の機械的な'
        '振動）。心電図ではありません。不整脈の診断には使えません。');
    sb.writeln('# 品質: good=信頼できる / fair=参考値 / unusable=算出不可');
    sb.writeln('# SDNN・RMSSD は機械振動由来のため、心電図の基準値とは'
        '比較できません。同一個体の履歴比較にのみ使用してください。');
    sb.writeln([
      '日時',
      '測定秒数',
      '心拍(bpm)',
      '呼吸(回/分)',
      '体温(C)',
      '品質',
      '信頼度',
      '検出拍数',
      '拍間隔ばらつき(%)',
      'SDNN(ms)',
      'RMSSD(ms)',
      '取りこぼし',
      '受信エラー',
      'サンプリング(Hz)',
      '姿勢',
      'メモ',
    ].join(','));
    String q(Object? v) {
      if (v == null) return '';
      final String s = v.toString();
      return s.contains(',') || s.contains('"')
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }
    String n(double? v, [int digits = 1]) =>
        v == null ? '' : v.toStringAsFixed(digits);

    for (final MeasurementRecord r in all) {
      sb.writeln([
        q(r.startedAt.toIso8601String()),
        n(r.durationSeconds, 0),
        n(r.heartRateBpm),
        n(r.respirationPerMin),
        n(r.bodyTempC),
        r.quality,
        n(r.heartRateConfidence, 2),
        r.beatCount,
        n(r.beatIntervalCvPercent),
        n(r.sdnnMs),
        n(r.rmssdMs),
        r.gapCount,
        r.receiveErrors,
        r.imuRateHz ?? '',
        q(r.posture),
        q(r.note),
      ].join(','));
    }
    return sb.toString();
  }

  /// Simple aggregate for a trend line: daily mean heart rate, oldest first.
  /// Unusable measurements are excluded — averaging in a non-measurement would
  /// be worse than having a gap in the chart.
  Future<List<({DateTime day, double meanBpm, int count})>> dailyMeans() async {
    final List<MeasurementRecord> all = await loadAll();
    final Map<String, List<double>> byDay = <String, List<double>>{};
    for (final MeasurementRecord r in all) {
      if (!r.isUsable) continue;
      final DateTime d = r.startedAt;
      final String key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => <double>[]).add(r.heartRateBpm!);
    }
    final List<({DateTime day, double meanBpm, int count})> out = <({DateTime day, double meanBpm, int count})>[];
    final List<String> keys = byDay.keys.toList()..sort();
    for (final String k in keys) {
      final List<double> vs = byDay[k]!;
      out.add((
        day: DateTime.parse(k),
        meanBpm: vs.reduce((a, b) => a + b) / vs.length,
        count: vs.length,
      ));
    }
    return out;
  }
}
