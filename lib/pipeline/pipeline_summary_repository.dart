/// T34-A：保存した窓から「每天」のページのデータを作る（本物のデータ）。
///
/// collar-pipeline の daily と同じ：セッションごとに状態判断と出来事を作り直し →
/// 日ごとの窓の数・出来事・心拍 → buildDaily（平時比）→ buildSummary・buildHistory。
/// 計算は別の isolate で（何日分もあると重いので）。
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/foundation.dart';

import '../data/daily_summary.dart';
import 'cnn_models.dart';
import 'pipeline_runner.dart';
import 'pipeline_store.dart';

class PipelineSummaryRepository implements SummarySource {
  PipelineSummaryRepository({required this.store, this.dogId = 'my_dog', this.changes, this.inIsolate = true});

  final PipelineStore store;
  final String dogId;
  @override
  final Listenable? changes;

  /// テストでは false（同じ isolate で計算）。
  final bool inIsolate;

  @override
  Future<SummaryBundle> load() async {
    await store.idle();
    final String path = (await store.dir()).path;
    final String id = dogId;
    final String gen = DateTime.now().toUtc().toIso8601String();
    final String text =
        inIsolate ? await Isolate.run(() => buildSummaryData(path, id, gen)) : buildSummaryData(path, id, gen);
    return bundleFromSummaryData(jsonDecode(text) as Map<String, dynamic>);
  }
}

/// 出来事の種類ごとの分（生の数字。テスト中に「本当に動いているか」を見るため）。
const List<String> rawEventTypes = <String>['rest_lie', 'walk_run', 'other', 'lick', 'scratch', 'shake', 'long_still'];

/// 1 日まとめ（DailyRow）から raw に入れる値（T35：CNN v2）。
const List<String> dailyRawMetrics = <String>['scratch_count', 'lick_min', 'shake_count'];

/// フォルダの中のセッション → JSON の文字列（isolate から返すため）。
String buildSummaryData(String dirPath, String dogId, String generatedAt,
    {PipelineConfig cfg = const PipelineConfig(),
    EventConfig ecfg = appEventConfig,
    DailyConfig dcfg = const DailyConfig()}) {
  final List<StoredSession> sessions = loadSessionsFrom(dirPath);
  final List<BehaviorEvent> events = <BehaviorEvent>[];
  final Map<String, int> wins = <String, int>{};
  final List<VitalReading> vitals = <VitalReading>[];
  for (final StoredSession s in sessions) {
    final EventsSnapshot snap = computeEvents(s.windows, s.vitals, cfg: cfg, ecfg: ecfg);
    events.addAll(snap.events);
    countWindowsByDate(<int>[for (final WindowResult w in s.windows) w.tMs], cfg: dcfg)
        .forEach((String d, int n) => wins[d] = (wins[d] ?? 0) + n);
    vitals.addAll(s.vitals);
  }
  if (wins.isEmpty) {
    return jsonEncode(<String, Object?>{'dates': <String>[], 'summaries': <String, Object?>{}, 'raw': <String, Object?>{}});
  }
  events.sort((BehaviorEvent a, BehaviorEvent b) => a.tStartMs.compareTo(b.tStartMs));
  vitals.sort((VitalReading a, VitalReading b) => a.tMs.compareTo(b.tMs));

  final List<DailyRow> rows = buildDaily(events, wins, vitals, cfg: dcfg);
  final List<String> dates = wins.keys.toList()..sort();

  final Map<String, Map<String, double>> raw = <String, Map<String, double>>{
    for (final String d in dates) d: <String, double>{'wear_min': wins[d]! / 60.0},
  };
  // T35：CNN v2 の 挠の回数・舔の分・颤抖の回数（1 日まとめが出す値。皮肤・生理の項目に使う）
  for (final DailyRow r in rows) {
    if (!dailyRawMetrics.contains(r.metric) || r.value.isNaN) continue;
    raw[r.date]?[r.metric] = r.value;
  }
  for (final BehaviorEvent e in events) {
    if (e.tStartMs < 0) continue;
    final String d = dateKey(DateTime.fromMillisecondsSinceEpoch(e.tStartMs, isUtc: true)
        .add(Duration(hours: dcfg.tzOffsetHours)));
    final Map<String, double>? m = raw[d];
    if (m == null) continue;
    m[e.type] = (m[e.type] ?? 0) + e.durationS / 60.0;
  }

  return jsonEncode(<String, Object?>{
    'dates': dates,
    'summaries': <String, Object?>{for (final String d in dates) d: buildSummary(rows, d, dogId, generatedAt: generatedAt)},
    'history': buildHistory(rows, dates.last),
    'raw': raw,
  });
}

SummaryBundle bundleFromSummaryData(Map<String, dynamic> j) {
  final List<String> dates = (j['dates'] as List<dynamic>).cast<String>();
  final Map<String, dynamic> sums = j['summaries'] as Map<String, dynamic>;
  final List<DayEntry> days = <DayEntry>[
    for (final String d in dates)
      () {
        try {
          return DayEntry(date: d, summary: DailySummary.fromJson(sums[d] as Map<String, dynamic>));
        } catch (e) {
          return DayEntry(date: d, error: e.toString());
        }
      }(),
  ];
  final Map<String, dynamic>? h = j['history'] as Map<String, dynamic>?;
  final List<HistoryDay> history = (h?['days'] as List<dynamic>? ?? <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(HistoryDay.fromJson)
      .toList();
  final Map<String, Map<String, double>> raw = <String, Map<String, double>>{
    for (final MapEntry<String, dynamic> e in (j['raw'] as Map<String, dynamic>? ?? <String, dynamic>{}).entries)
      e.key: <String, double>{
        for (final MapEntry<String, dynamic> v in (e.value as Map<String, dynamic>).entries)
          v.key: (v.value as num).toDouble(),
      },
  };
  return SummaryBundle(
    dogId: (sums.isNotEmpty ? (sums.values.first as Map<String, dynamic>)['dog_id'] as String? : null) ?? '',
    days: days,
    history: history,
    raw: raw,
  );
}
