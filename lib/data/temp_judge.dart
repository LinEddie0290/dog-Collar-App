/// T11 体温（M6、D-063）：皮膚の温度 → 安定した 60 秒の段 → 1 日の値 → 平時との差。画面なしの計算だけ。
///
/// collar-pipeline の `collar/judge/temp.py` と同じ計算（test/temp_gps_golden_test.dart で同じ答えを確認）。
/// 皮膚の温度は体の中の温度と違うので、「体温が何度」とは言わず「平時との差」だけを使う（K2）。
/// 数字は全部仮。
library;

import 'package:collar_pipeline/collar_pipeline.dart' show dateKey;

const double tempMinC = 20; // これより低いのは捨てる
const double tempMaxC = 45; // これより高いのは捨てる
const double tempContactMinDiffC = 2.0; // 物体−環境がこれより小さい＝皮膚に向いていない
const int tempAvgMs = 10000; // 移動平均（10 秒）
const int tempBlockMs = 60000; // 安定を見る段（UTC の 1 分ごと）
const int tempBlockMinN = 10; // 段の点の数の下限
const double tempStableRangeC = 0.2; // 段の中の移動平均の最大−最小
const int tempDayMinBlocks = 3; // 1 日に安定した段がこれ以上で、その日の値を出す
const int tempUsualDays = 14; // 平時：今日より前の 14 日
const int tempUsualMinDays = 3; // 平時に要る日の数（K3）
const double tempDiffC = 1.0; // 平時との差 ±1.0℃ で偏高・偏低

/// 首輪の温度 1 つ（MLX90615：物体＝皮膚、環境）。
class TempReading {
  const TempReading({required this.tMs, required this.objC, required this.ambC, this.source = ''});

  final int tMs;
  final double objC;
  final double ambC;
  final String source;
}

/// 安定した 60 秒の段（真ん中の時刻・段の値・点の数）。
class TempBlock {
  const TempBlock(this.tMs, this.value, this.n);

  final int tMs;
  final double value;
  final int n;
}

List<TempBlock> stableTempBlocks(List<TempReading> xs) {
  final List<TempReading> ok = <TempReading>[
    for (final TempReading r in xs)
      if (r.objC.isFinite &&
          r.ambC.isFinite &&
          r.objC >= tempMinC &&
          r.objC <= tempMaxC &&
          r.objC - r.ambC >= tempContactMinDiffC)
        r,
  ];
  final List<int> order = List<int>.generate(ok.length, (int i) => i)
    ..sort((int a, int b) {
      final int c = ok[a].tMs.compareTo(ok[b].tMs);
      return c != 0 ? c : a.compareTo(b);
    });
  final Map<int, List<TempReading>> blocks = <int, List<TempReading>>{};
  for (final int i in order) {
    blocks.putIfAbsent(_floorDiv(ok[i].tMs, tempBlockMs), () => <TempReading>[]).add(ok[i]);
  }
  final List<int> keys = blocks.keys.toList()..sort();
  final List<TempBlock> out = <TempBlock>[];
  for (final int k in keys) {
    final List<TempReading> b = blocks[k]!;
    if (b.length < tempBlockMinN) continue;
    double mn = double.infinity, mx = double.negativeInfinity;
    for (final TempReading ri in b) {
      double s = 0;
      int n = 0;
      for (final TempReading rj in b) {
        if (rj.tMs > ri.tMs - tempAvgMs && rj.tMs <= ri.tMs) {
          s += rj.objC;
          n++;
        }
      }
      final double m = s / n;
      if (m < mn) mn = m;
      if (m > mx) mx = m;
    }
    if (mx - mn <= tempStableRangeC + 1e-9) {
      double s = 0;
      for (final TempReading r in b) {
        s += r.objC;
      }
      out.add(TempBlock(k * tempBlockMs + tempBlockMs ~/ 2, s / b.length, b.length));
    }
  }
  return out;
}

int _floorDiv(int a, int b) => (a / b).floor();

/// その土地（UTC＋8）の日付。
String localDateOf(int ms, {int tzOffsetHours = 8}) =>
    dateKey(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(Duration(hours: tzOffsetHours)));

double median(List<double> v) {
  final List<double> s = List<double>.of(v)..sort();
  final int n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// 1 日の値（安定した段の中央値）。安定した段が [tempDayMinBlocks] より少ない日は出さない。
Map<String, ({double value, int nBlocks})> dailyTemp(List<TempBlock> blocks) {
  final Map<String, List<double>> by = <String, List<double>>{};
  for (final TempBlock b in blocks) {
    by.putIfAbsent(localDateOf(b.tMs), () => <double>[]).add(b.value);
  }
  final List<String> dates = by.keys.toList()..sort();
  return <String, ({double value, int nBlocks})>{
    for (final String d in dates)
      if (by[d]!.length >= tempDayMinBlocks) d: (value: median(by[d]!), nBlocks: by[d]!.length),
  };
}

enum TempState { collecting, provisional, ok }

class TempStatus {
  const TempStatus({required this.value, required this.usual, required this.usualDays, required this.state});

  final double? value;
  final double? usual;
  final int usualDays;
  final TempState state;

  double? get delta => value == null || usual == null ? null : value! - usual!;

  /// 偏高（+1）・偏低（−1）・ふつう（0）。比べられないときは null。
  int? get flag {
    final double? d = delta;
    if (d == null) return null;
    return d >= tempDiffC ? 1 : (d <= -tempDiffC ? -1 : 0);
  }

  /// 平時まであと何日（収集中のとき）。
  int get daysToGo => state == TempState.collecting ? tempUsualMinDays - usualDays : 0;
}

/// 今日と平時（今日より前の 14 日の中央値。3 日から、14 日までは暂定）。[days]：日付 → 値。
TempStatus tempStatus(Map<String, double> days, String today) {
  final List<String> prev = (days.keys.where((String d) => d.compareTo(today) < 0).toList()..sort());
  final List<String> use = prev.length > tempUsualDays ? prev.sublist(prev.length - tempUsualDays) : prev;
  final int n = use.length;
  final double? usual = n >= tempUsualMinDays ? median(<double>[for (final String d in use) days[d]!]) : null;
  return TempStatus(
    value: days[today],
    usual: usual,
    usualDays: n,
    state: usual == null ? TempState.collecting : (n < tempUsualDays ? TempState.provisional : TempState.ok),
  );
}
