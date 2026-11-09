/// T35 健康タブ：項目ごとの日々の値（实际／示例）・平時・平時との差。画面から切り離した計算だけ。
///
/// - 实际：运动量（history の active_min）・活动与休息（raw の rest_lie）・睡眠时长（sleep_min）・
///   安静时心率（rest_hr）・呼吸数（rest_rr）。睡觉时的呼吸は今は履歴に出ていない（提醒があればその値だけ）。
///   T35：挠（raw の scratch_count）・持续舔舐（lick_min）・发抖（shake_count）＝CNN v2（试用）。
/// - 示例：項目ごとの範囲から日付で作る（同じ日なら同じ）。板块の代表の項目（ホームの泡）は
///   7 日に 1 回くらい提醒が出て、その日は値も少ない／多い方に寄せる。
/// - 平時：今日より前の 14 日の中央値（値のある日が 7 日以上のときだけ）。帯は ±15%。
///   見せるための目安で、新しい提醒は作らない（提醒は 1 日まとめのものだけ）。
/// 設計メモ：首輪開発計画/03_設計メモ/T35_健康タブ.md（H2・H3）。
library;

import 'package:collar_pipeline/collar_pipeline.dart' show dateKey;

import '../l10n/summary_text.dart';
import 'daily_summary.dart';
import 'health_items.dart';
import 'item_specs.dart';

/// 値がないときの文。
const String noDataValue = '没有数据';

/// 作る日数（線は最後の 14 日、平時はその前の 14 日を使う）。
const int seriesDays = 28;

/// 平時を出すのに要る、値のある日の数。
const int minUsualDays = 7;

/// 平時の帯（±%）。
const int bandPct = 15;

class ItemDay {
  const ItemDay(this.date, this.value);

  final String date;
  final double? value;
}

class ItemSeries {
  const ItemSeries({required this.item, required this.spec, required this.days, required this.demo, this.alert});

  final HealthItem item;
  final ItemSpec spec;

  /// 古い順。最後が今日。
  final List<ItemDay> days;

  /// 示例（偽のデータ）なら true。
  final bool demo;

  /// 今日の提醒の一文。なければ null。
  final String? alert;

  double? get today => days.isEmpty ? null : days.last.value;

  /// 線に出す最後の 14 日。
  List<ItemDay> get recent14 => days.length <= 14 ? days : days.sublist(days.length - 14);

  /// 平時：今日より前の 14 日の中央値。値のある日が [minUsualDays] 日より少なければ null。
  double? get usual {
    if (days.length < 2) return null;
    final int end = days.length - 1;
    final int start = end - 14 < 0 ? 0 : end - 14;
    final List<double> v = <double>[
      for (final ItemDay d in days.sublist(start, end))
        if (d.value != null) d.value!,
    ]..sort();
    if (v.length < minUsualDays) return null;
    final int n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }

  /// 今日と平時の差（%、四捨五入）。比べられないときは null。
  int? get diffPct {
    final double? t = today;
    final double? u = usual;
    if (t == null || u == null || u == 0) return null;
    return ((t / u - 1) * 100).round();
  }

  /// 今日が平時の帯（±[bandPct]%）の中か。比べられないときは null。
  bool? get inBand {
    final int? p = diffPct;
    return p == null ? null : p.abs() <= bandPct;
  }

  String format(double? v) => formatItemValue(spec, v);
}

String formatItemValue(ItemSpec s, double? v) {
  if (s.link) return '查看波形';
  if (v == null) return noDataValue;
  return '${v.toStringAsFixed(s.decimals)} ${s.unit}';
}

/// [today] で終わる [n] 日（古い順、YYYY-MM-DD）。
List<String> lastDates(String today, int n) {
  final DateTime t = DateTime.utc(
      int.parse(today.substring(0, 4)), int.parse(today.substring(5, 7)), int.parse(today.substring(8, 10)));
  return <String>[for (int i = n - 1; i >= 0; i--) dateKey(t.subtract(Duration(days: i)))];
}

// ───────── 示例 ─────────

/// 示例の提醒の日に、板块の代表の項目の値をどちらに寄せるか。
enum AlertDir { less, more }

const Map<String, AlertDir> demoLeadDir = <String, AlertDir>{
  'activity': AlertDir.less,
  'sleep_time': AlertDir.less,
  'rest_hr': AlertDir.more,
  'scratch': AlertDir.more,
  'bark': AlertDir.more,
  'drink': AlertDir.less,
};

/// 示例の提醒がその日に出るか（板块ごと、7 日に 1 回くらい）。
bool demoAlertOn(String date, Board b) => _hash('$date/${b.name}') % 7 == 0;

String demoAlertText(Board b) => switch (b) {
      Board.exercise => '今天运动比平时少很多',
      Board.sleep => '昨晚睡得比平时少',
      Board.physio => '安静时心率比平时高',
      Board.skin => '今天挠和舔比平时多很多',
      Board.mind => '今天叫得比平时多',
      Board.diet => '喝水比平时少约 20%，留意一下水碗',
    };

/// 示例の値（[ItemSpec.decimals] で丸めたもの）。同じ日・同じ項目なら同じ。
double demoValue(String date, String itemId) {
  final ItemSpec s = itemSpec(itemId);
  final double f = (_hash('$date/$itemId') % 1000) / 999;
  double v = s.min + f * (s.max - s.min);
  final AlertDir? dir = demoLeadDir[itemId];
  if (dir != null && demoAlertOn(date, boardOfItem(itemId))) {
    v = dir == AlertDir.less ? s.min * 0.55 : s.max * 1.5;
  }
  return double.parse(v.toStringAsFixed(s.decimals));
}

/// FNV-1a（32 bit）。Dart の hashCode は実行ごとに変わることがあるので使わない。
int _hash(String s) {
  int h = 0x811c9dc5;
  for (final int c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

// ───────── 作る ─────────

/// 1 つの項目の日々の値。
///
/// 实际の項目は [real]（スマホで計算した 1 日まとめ・履歴）から。[real] がなければ値は全部なし（示例にはしない）。
/// 示例の項目と、[demoAll]（演示）のときは示例。
ItemSeries buildItemSeries(String itemId, {required String today, SummaryBundle? real, bool demoAll = false}) {
  final HealthItem item = healthItem(itemId);
  final ItemSpec spec = itemSpec(itemId);
  final Board board = boardOfItem(itemId);
  final List<String> dates = lastDates(today, seriesDays);

  if (!item.real || demoAll) {
    final bool lead = boardInfo(board).lead == itemId;
    return ItemSeries(
      item: item,
      spec: spec,
      demo: true,
      days: <ItemDay>[for (final String d in dates) ItemDay(d, spec.link ? null : demoValue(d, itemId))],
      alert: lead && demoAlertOn(today, board) ? demoAlertText(board) : null,
    );
  }

  final Map<String, HistoryDay> hist = <String, HistoryDay>{
    for (final HistoryDay h in real?.history ?? const <HistoryDay>[]) h.date: h,
  };
  final Map<String, Map<String, double>> raw = real?.raw ?? const <String, Map<String, double>>{};
  DailySummary? todaySummary;
  for (final DayEntry d in real?.days ?? const <DayEntry>[]) {
    if (d.date == today) todaySummary = d.summary;
  }

  double? valueOn(String d) {
    final HistoryDay? h = hist[d];
    switch (itemId) {
      case 'activity':
        return h?.activeMin;
      case 'active_rest':
        final Map<String, double>? m = raw[d];
        return m == null ? null : (m['rest_lie'] ?? 0) / 60;
      case 'sleep_time':
        final double? m = h?.sleepMin;
        return m == null ? null : m / 60;
      case 'rest_hr':
        return h?.restHr;
      case 'rr':
        return h?.restRr;
      // T35：CNN v2（1 日まとめの値を raw に入れてある）。CNN の shake＝颤抖＝发抖
      case 'scratch':
        return raw[d]?['scratch_count'];
      case 'lick':
        return raw[d]?['lick_min'];
      case 'tremble':
        return raw[d]?['shake_count'];
      default:
        return null;
    }
  }

  final List<ItemDay> days = <ItemDay>[for (final String d in dates) ItemDay(d, valueOn(d))];
  final TextItem? a = _realAlertItem(itemId, todaySummary);
  // 睡觉时的呼吸：履歴にはないが、提醒に値があれば今日の値にする
  if (itemId == 'sleep_rr' && a != null) {
    final num? v = a.number('value');
    if (v != null) days[days.length - 1] = ItemDay(today, v.toDouble());
  }
  return ItemSeries(
    item: item,
    spec: spec,
    demo: false,
    days: days,
    alert: a == null ? null : const SummaryTextZh().alert(a),
  );
}

/// 板块の全部の項目（一覧の順）。
List<ItemSeries> buildBoardSeries(Board b, {required String today, SummaryBundle? real, bool demoAll = false}) =>
    <ItemSeries>[
      for (final HealthItem i in boardInfo(b).items)
        buildItemSeries(i.id, today: today, real: real, demoAll: demoAll),
    ];

/// 1 日まとめの提醒を項目に割り当てる。皮肤（挠と舔の回数）の提醒は「挠」に出す（T35：CNN v2）。
TextItem? _realAlertItem(String itemId, DailySummary? s) {
  if (s == null) return null;
  for (final CategorySummary c in s.categories) {
    final TextItem? a = c.alert;
    if (a == null) continue;
    final String? target = switch (c.id) {
      'exercise' => 'activity',
      'sleep' => 'sleep_time',
      'skin' => 'scratch',
      'physio' => switch (a.text('metric')) {
          'rest_rr_median' => 'rr',
          'sleep_rr_median' => 'sleep_rr',
          _ => 'rest_hr',
        },
      _ => null,
    };
    if (target == itemId) return a;
  }
  return null;
}
