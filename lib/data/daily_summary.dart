import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// パイプライン(T15)が出す 1日まとめ JSON(collar.daily_summary/0.1)。
/// 形は collar-pipeline の `schemas/daily_summary.schema.json` と
/// `データ形式.md` 6章。提醒は「通知」だけで、診断はしない。
class DailySummary {
  const DailySummary({
    required this.dogId,
    required this.date,
    required this.categories,
  });

  final String dogId;
  final String date; // YYYY-MM-DD(その日の朝の日付。夜の睡眠はこの日に入る)
  final List<CategorySummary> categories;

  /// 提醒のあるカードを先に。その中と残りは JSON の順(运动・睡眠・皮肤・生理)。
  List<CategorySummary> get ordered => <CategorySummary>[
        ...categories.where((CategorySummary c) => c.alert != null),
        ...categories.where((CategorySummary c) => c.alert == null),
      ];

  int get alertCount =>
      categories.where((CategorySummary c) => c.alert != null).length;

  static DailySummary fromJson(Map<String, dynamic> json) {
    final List<dynamic> cats = json['categories'] as List<dynamic>? ?? <dynamic>[];
    return DailySummary(
      dogId: json['dog_id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      categories: cats
          .whereType<Map<String, dynamic>>()
          .map(CategorySummary.fromJson)
          .toList(),
    );
  }
}

enum SummaryStatus { ok, collecting, noData, unknown }

SummaryStatus _status(String? s) {
  switch (s) {
    case 'ok':
      return SummaryStatus.ok;
    case 'collecting':
      return SummaryStatus.collecting;
    case 'no_data':
      return SummaryStatus.noData;
    default:
      return SummaryStatus.unknown;
  }
}

class CategorySummary {
  const CategorySummary({
    required this.id,
    required this.status,
    this.alert,
    this.daily,
    this.daysUntilCompare,
  });

  final String id; // exercise / sleep / skin / physio
  final SummaryStatus status;
  final TextItem? alert;
  final TextItem? daily;
  final int? daysUntilCompare;

  static CategorySummary fromJson(Map<String, dynamic> json) {
    return CategorySummary(
      id: json['id'] as String? ?? '',
      status: _status(json['status'] as String?),
      alert: TextItem.maybe(json['alert']),
      daily: TextItem.maybe(json['daily']),
      daysUntilCompare: (json['days_until_compare'] as num?)?.toInt(),
    );
  }
}

/// 文言のキーと、文に入れる値。文はアプリ側で作る(summary_text.dart)。
class TextItem {
  const TextItem({required this.textKey, required this.values, this.level});

  final String textKey;
  final Map<String, dynamic> values;
  final String? level;

  static TextItem? maybe(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return TextItem(
      textKey: json['text_key'] as String? ?? '',
      values: (json['values'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      level: json['level'] as String?,
    );
  }

  num? number(String key) {
    final Object? v = values[key];
    return v is num ? v : null;
  }

  String? text(String key) {
    final Object? v = values[key];
    return v is String ? v : null;
  }
}

/// history.json の 1日分(小さな折れ線用)。
class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.validDay,
    this.activeMin,
    this.sleepMin,
    this.itchCount,
    this.restHr,
  });

  final String date;
  final bool validDay;
  final double? activeMin;
  final double? sleepMin;
  final double? itchCount;
  final double? restHr;

  static HistoryDay fromJson(Map<String, dynamic> json) {
    double? d(String k) => (json[k] as num?)?.toDouble();
    return HistoryDay(
      date: json['date'] as String? ?? '',
      validDay: json['valid_day'] as bool? ?? false,
      activeMin: d('active_min'),
      sleepMin: d('sleep_min'),
      itchCount: d('itch_count'),
      restHr: d('rest_hr'),
    );
  }
}

/// 1日分の読み込み結果。JSON が壊れていても落とさず、その日を「読めない」にする。
class DayEntry {
  const DayEntry({required this.date, this.summary, this.error});

  final String date;
  final DailySummary? summary;
  final String? error;
}

class SummaryBundle {
  const SummaryBundle({required this.dogId, required this.days, required this.history});

  final String dogId;
  final List<DayEntry> days;
  final List<HistoryDay> history;
}

/// デモ用(T23):アプリに同梱した `assets/demo/<dog>/` から読む。
/// T16 で本物の受け取り口(ファイル・サーバー)に差し替える。
class DemoSummaryRepository {
  DemoSummaryRepository({AssetBundle? bundle, this.dogId = 'dog_sim01'})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String dogId;

  String get _base => 'assets/demo/$dogId';

  Future<SummaryBundle> load() async {
    final Map<String, dynamic> index =
        jsonDecode(await _bundle.loadString('$_base/index.json')) as Map<String, dynamic>;
    final List<String> dates =
        (index['dates'] as List<dynamic>? ?? <dynamic>[]).whereType<String>().toList()..sort();

    final List<DayEntry> days = <DayEntry>[];
    for (final String d in dates) {
      try {
        final String text = await _bundle.loadString('$_base/summary/$d.json');
        days.add(DayEntry(
          date: d,
          summary: DailySummary.fromJson(jsonDecode(text) as Map<String, dynamic>),
        ));
      } catch (e) {
        days.add(DayEntry(date: d, error: e.toString()));
      }
    }

    List<HistoryDay> history = <HistoryDay>[];
    try {
      final Map<String, dynamic> h =
          jsonDecode(await _bundle.loadString('$_base/history.json')) as Map<String, dynamic>;
      history = (h['days'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(HistoryDay.fromJson)
          .toList();
    } catch (_) {
      // 履歴が無くても画面は出す(折れ線だけ消える)。
    }
    return SummaryBundle(dogId: dogId, days: days, history: history);
  }
}
