/// T35：ホーム（今天）に出すもの。画面から切り離した計算だけ（テストしやすいように）。
///
/// - 6 つの泡：板块ごとの今日の値・示例かどうか・提醒。
///   运动・睡眠・生理は本物（スマホで計算した 1 日まとめ）。皮肤・心理・饮食は示例（D-051 D2）。
///   皮肤は CNN v2 をアプリに入れたら本物に替える（D-051 D4）。
/// - 真ん中：今の状態（記録中なら 休息中／在动 と続いている時間）。総合点は出さない（確かめていない数字なので）。
/// 文言は中国語だけ（D-051 D6）。
library;

import 'package:collar_pipeline/collar_pipeline.dart';

import '../l10n/summary_text.dart';
import 'daily_summary.dart';
import 'health_items.dart';

class BubbleData {
  const BubbleData({required this.board, required this.value, required this.demo, this.alert});

  final Board board;

  /// 泡の中の短い値（例：42 分钟）。
  final String value;

  /// 示例（偽のデータ）なら true。
  final bool demo;

  /// 今日の提醒の一文。なければ null。
  final String? alert;

  String get name => boardInfo(board).name;
}

class HomeSnapshot {
  const HomeSnapshot({required this.date, required this.bubbles, required this.hasRealData});

  /// その土地の日付（YYYY-MM-DD）。
  final String date;

  /// [Board] の順（上から時計回り）に 6 つ。
  final List<BubbleData> bubbles;

  /// 今日の本物の 1 日まとめがあったか。
  final bool hasRealData;

  BubbleData bubble(Board b) => bubbles.firstWhere((BubbleData x) => x.board == b);

  /// 提醒のある泡（[Board] の順）。
  List<BubbleData> get alerts => bubbles.where((BubbleData b) => b.alert != null).toList();
}

const String noDataValue = '没有数据';

/// 今日の日付（1 日まとめと同じ数え方：UTC＋[DailyConfig.tzOffsetHours]）。
String todayKey(DateTime now, {DailyConfig cfg = const DailyConfig()}) =>
    dateKey(now.toUtc().add(Duration(hours: cfg.tzOffsetHours)));

/// ホームの 6 つの泡を作る。
///
/// [real] は今日の本物の 1 日まとめ（なければ null）。[demoAll] なら全部を示例にする（演示）。
HomeSnapshot buildHomeSnapshot({required String date, DailySummary? real, bool demoAll = false}) {
  const SummaryTextZh t = SummaryTextZh();
  final DailySummary? r = demoAll ? null : real;
  final bool useReal = r != null;
  CategorySummary? cat(String id) {
    if (r == null) return null;
    for (final CategorySummary c in r.categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  BubbleData realOrDemo(Board b, String catId, String Function(TextItem d) valueOf) {
    if (demoAll) return demoBubble(date, b);
    final CategorySummary? c = cat(catId);
    final TextItem? d = c?.daily;
    String value = noDataValue;
    if (d != null) {
      final String v = valueOf(d);
      if (v.isNotEmpty) value = v;
    }
    final TextItem? a = c?.alert;
    return BubbleData(board: b, value: value, demo: false, alert: a == null ? null : t.alert(a));
  }

  return HomeSnapshot(
    date: date,
    hasRealData: useReal,
    bubbles: <BubbleData>[
      realOrDemo(Board.exercise, 'exercise', (TextItem d) {
        final num? m = d.number('active_min');
        return m == null ? '' : '${m.round()} 分钟';
      }),
      realOrDemo(Board.sleep, 'sleep', (TextItem d) {
        final num? m = d.number('sleep_min');
        return m == null ? '' : '${(m / 60).toStringAsFixed(1)} 小时';
      }),
      realOrDemo(Board.physio, 'physio', (TextItem d) {
        final num? hr = d.number('rest_hr');
        return hr == null ? '' : '心率 ${hr.round()}';
      }),
      demoBubble(date, Board.skin),
      demoBubble(date, Board.mind),
      demoBubble(date, Board.diet),
    ],
  );
}

/// 示例の泡。日付と板块から決まる（同じ日なら何度作っても同じ）。7 日に 1 回くらい提醒が出る。
BubbleData demoBubble(String date, Board b) {
  final int h = _hash('$date/${b.name}');
  final bool alert = h % 7 == 0;
  switch (b) {
    case Board.exercise:
      final int m = 25 + (h >> 3) % 50;
      return BubbleData(board: b, value: '$m 分钟', demo: true, alert: alert ? '今天运动比平时少很多' : null);
    case Board.sleep:
      final double hours = 8 + ((h >> 3) % 25) / 10;
      return BubbleData(
          board: b, value: '${hours.toStringAsFixed(1)} 小时', demo: true, alert: alert ? '昨晚睡得比平时少' : null);
    case Board.physio:
      final int hr = 70 + (h >> 3) % 25;
      return BubbleData(board: b, value: '心率 $hr', demo: true, alert: alert ? '安静时心率比平时高' : null);
    case Board.skin:
      final int n = (h >> 3) % 6;
      return BubbleData(board: b, value: '挠 $n 次', demo: true, alert: alert ? '今天挠和舔比平时多很多' : null);
    case Board.mind:
      const List<String> lv = <String>['少', '一般', '多'];
      return BubbleData(
          board: b, value: '吠叫 ${lv[(h >> 3) % 3]}', demo: true, alert: alert ? '今天叫得比平时多' : null);
    case Board.diet:
      final int n = 4 + (h >> 3) % 6;
      return BubbleData(board: b, value: '喝水 $n 次', demo: true, alert: alert ? '喝水比平时少约 20%，留意一下水碗' : null);
  }
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

/// 真ん中のボタンの文。
class NowLine {
  const NowLine(this.title, this.sub);

  final String title;
  final String? sub;
}

/// 今の状態。[states] は今の記録の状態（古い順）。
NowLine nowLine({required bool recording, bool starting = false, List<WindowState> states = const <WindowState>[]}) {
  if (starting) return const NowLine('连接中…', null);
  if (!recording) return const NowLine('没有在记录', '在「我的 → 开发」开始记录');
  if (states.isEmpty) return const NowLine('记录中', '大约 40 秒后出结果');
  final WindowState last = states.last;
  if (last.rest) {
    final double s = last.stillS;
    return NowLine('休息中', s < 60 ? '刚安静下来' : '已安静 ${_dur(s)}');
  }
  int i = states.length - 1;
  while (i > 0 && !states[i - 1].rest) {
    i--;
  }
  final double s = (last.tStartMs - states[i].tStartMs) / 1000 + 1;
  return NowLine('在动', s < 60 ? '刚开始动' : '已经动了 ${_dur(s)}');
}

String _dur(double seconds) {
  final int m = seconds ~/ 60;
  if (m < 60) return '$m 分钟';
  return '${m ~/ 60} 小时 ${m % 60} 分钟';
}
