/// T35：泡を押したときに下から出る、板块の簡単な詳細。
/// 今日の値・代表の項目の 14 日の線・提醒・その板块の項目（実际数据／示例）。くわしいページは「健康」タブ。
library;

import 'package:flutter/material.dart';

import '../../data/health_items.dart';
import '../../data/health_series.dart';
import '../../data/home_snapshot.dart';
import '../health/health_text.dart';
import '../health/series_chart.dart';
import 'water_style.dart';

/// [series] があれば、その項目（板块の代表）の 14 日の線を出す。
/// [onMore] があれば「查看更多」ボタン（シートを閉じてから呼ぶ）。
Future<void> showBoardSheet(BuildContext context, BubbleData data, {ItemSeries? series, VoidCallback? onMore}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (BuildContext _) => BoardSheet(data: data, series: series, onMore: onMore),
  );
}

class BoardSheet extends StatelessWidget {
  const BoardSheet({super.key, required this.data, this.series, this.onMore});

  final BubbleData data;

  /// 板块の代表の項目の日々の値（14 日の線に使う）。null か、値が 1 つもなければ線は出さない。
  final ItemSeries? series;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final BoardInfo info = boardInfo(data.board);
    final Color c = boardColor(data.board);
    final ItemSeries? ser = series;
    final List<double?> last14 = <double?>[for (final ItemDay d in ser?.recent14 ?? const <ItemDay>[]) d.value];
    final bool hasChart = last14.any((double? v) => v != null);
    final String diff = ser == null ? '' : diffText(ser);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: ValueKey<String>('board-sheet-${data.board.name}'),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(boardIcon(data.board), color: Color.lerp(c, Colors.black, 0.15)),
                const SizedBox(width: 8),
                Text(info.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WaterColors.text)),
                const Spacer(),
                if (data.demo) const _Tag('示例', WaterColors.demo) else if (data.trial) const _Tag('试用', WaterColors.trial),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              data.value,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color.lerp(c, Colors.black, 0.2)),
            ),
            Text(
                data.demo
                    ? '这个板块现在是示例数据（不是这只狗的）'
                    : (data.value == noDataValue
                        ? '今天还没有数据（开始记录以后会有）'
                        : (data.trial ? '今天的数据（试用：用模拟数据学的，还没有用真的狗确认）' : '今天的数据（这个手机算出来的）')),
                style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
            if (ser != null && hasChart) ...<Widget>[
              const SizedBox(height: 14),
              Text('过去 14 天：${ser.item.name}', style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
              const SizedBox(height: 4),
              SizedBox(
                key: ValueKey<String>('board-sheet-chart-${data.board.name}'),
                height: 96,
                width: double.infinity,
                child: SeriesChart(values: last14, color: c, usual: ser.usual),
              ),
              if (diff.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(diff, style: const TextStyle(fontSize: 12, color: WaterColors.value)),
                ),
            ],
            if (data.alert != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WaterColors.alert.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.circle, size: 9, color: WaterColors.alert),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(data.alert!, style: const TextStyle(fontSize: 14, color: WaterColors.text))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text('项目', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WaterColors.sub)),
            const SizedBox(height: 6),
            for (final HealthItem item in info.items)
              Padding(
                key: ValueKey<String>('item-${item.id}'),
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: <Widget>[
                    Expanded(
                        child: Text(item.name, style: const TextStyle(fontSize: 14, color: WaterColors.text))),
                    if (item.trial)
                      const _Tag('试用', WaterColors.trial)
                    else if (item.real)
                      const _Tag('实际数据', WaterColors.aqua)
                    else
                      const _Tag('示例', WaterColors.demo),
                  ],
                ),
              ),
            if (onMore != null) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('board-sheet-more'),
                  style: FilledButton.styleFrom(backgroundColor: c),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onMore!();
                  },
                  child: const Text('查看更多'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text('这不是诊断。如果担心，请问兽医。', style: TextStyle(fontSize: 11, color: WaterColors.sub)),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
