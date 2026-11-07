/// T35 健康タブ：板块のページ（項目の一覧）。行：名前・今日の値・平時との比・14 日の小さな線・实际数据／示例。
library;

import 'package:flutter/material.dart';

import '../../data/daily_summary.dart';
import '../../data/health_items.dart';
import '../../data/health_series.dart';
import '../home/water_background.dart';
import '../home/water_style.dart';
import 'health_text.dart';
import 'item_page.dart';
import 'series_chart.dart';

class BoardPage extends StatelessWidget {
  const BoardPage({
    super.key,
    required this.board,
    required this.today,
    this.real,
    this.demoAll = false,
    this.onOpenEcg,
  });

  final Board board;
  final String today;
  final SummaryBundle? real;
  final bool demoAll;
  final VoidCallback? onOpenEcg;

  @override
  Widget build(BuildContext context) {
    final BoardInfo info = boardInfo(board);
    final List<ItemSeries> items = buildBoardSeries(board, today: today, real: real, demoAll: demoAll);
    return Scaffold(
      backgroundColor: WaterColors.bgTop,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(boardIcon(board), color: Color.lerp(boardColor(board), Colors.black, 0.15)),
            const SizedBox(width: 8),
            Text(info.name, style: const TextStyle(fontSize: 18, color: WaterColors.text)),
          ],
        ),
        backgroundColor: WaterColors.bgTop,
        surfaceTintColor: Colors.transparent,
        foregroundColor: WaterColors.text,
      ),
      body: WaterBackground(
        child: ListView(
          key: ValueKey<String>('board-page-${board.name}'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            for (final ItemSeries s in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ItemRow(
                  series: s,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (BuildContext _) => ItemPage(series: s, onOpenEcg: onOpenEcg),
                  )),
                ),
              ),
            const SizedBox(height: 4),
            const Text('「示例」是假的数据（还没有做好的项目）。这不是诊断。',
                style: TextStyle(fontSize: 11, color: WaterColors.sub)),
          ],
        ),
      ),
    );
  }
}

class ItemRow extends StatelessWidget {
  const ItemRow({super.key, required this.series, required this.onTap});

  final ItemSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ItemSeries s = series;
    final Color c = boardColor(boardOfItem(s.item.id));
    final String diff = diffText(s);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('item-row-${s.item.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: glassCard(radius: 18),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(s.item.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WaterColors.text)),
                        ),
                        if (s.alert != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            key: ValueKey<String>('row-alert-${s.item.id}'),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: WaterColors.alert, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      diff.isEmpty ? s.format(s.today) : '${s.format(s.today)}　$diff',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: WaterColors.value),
                    ),
                  ],
                ),
              ),
              if (!s.spec.link)
                SizedBox(
                  width: 72,
                  height: 30,
                  child: SeriesChart(values: <double?>[for (final ItemDay d in s.recent14) d.value], color: c, mini: true),
                ),
              const SizedBox(width: 8),
              Text(s.demo ? '示例' : '实际',
                  style: TextStyle(fontSize: 11, color: s.demo ? WaterColors.demo : WaterColors.aqua)),
              const Icon(Icons.chevron_right, size: 18, color: WaterColors.sub),
            ],
          ),
        ),
      ),
    );
  }
}
