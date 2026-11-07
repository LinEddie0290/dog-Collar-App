/// T35 健康タブ：項目のページ（25 項目すべて同じ型）。
/// 今日の値／平時との比／提醒／14 日の線（平時の帯）／看什么・为什么重要・数据从哪里来。
library;

import 'package:flutter/material.dart';

import '../../data/health_items.dart';
import '../../data/health_series.dart';
import '../home/water_background.dart';
import '../home/water_style.dart';
import 'health_text.dart';
import 'series_chart.dart';

class ItemPage extends StatelessWidget {
  const ItemPage({super.key, required this.series, this.onOpenEcg});

  final ItemSeries series;

  /// 像心电图的波形：「测定」の記録を開く。null ならボタンを出さない。
  final VoidCallback? onOpenEcg;

  @override
  Widget build(BuildContext context) {
    final ItemSeries s = series;
    final Color c = boardColor(boardOfItem(s.item.id));
    final double? u = s.usual;
    final List<ItemDay> d14 = s.recent14;
    final String diff = diffText(s);

    return Scaffold(
      backgroundColor: WaterColors.bgTop,
      appBar: AppBar(
        title: Text(s.item.name, style: const TextStyle(fontSize: 17, color: WaterColors.text)),
        backgroundColor: WaterColors.bgTop,
        surfaceTintColor: Colors.transparent,
        foregroundColor: WaterColors.text,
      ),
      body: WaterBackground(
        child: ListView(
          key: ValueKey<String>('item-page-${s.item.id}'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(s.demo ? '示例' : '实际数据',
                    style: TextStyle(fontSize: 12, color: s.demo ? WaterColors.demo : WaterColors.aqua)),
                const Spacer(),
                Text('今天 ${shortDate(s.days.last.date)}', style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
              ],
            ),
            const SizedBox(height: 6),
            if (s.spec.link)
              Align(
                alignment: Alignment.centerLeft,
                child: onOpenEcg == null
                    ? const Text('在「测定」的记录里看', style: TextStyle(fontSize: 16, color: WaterColors.text))
                    : FilledButton.icon(
                        key: const ValueKey<String>('open-ecg'),
                        onPressed: onOpenEcg,
                        style: FilledButton.styleFrom(backgroundColor: c),
                        icon: const Icon(Icons.monitor_heart_outlined, size: 18),
                        label: const Text('打开「测定」的记录'),
                      ),
              )
            else ...<Widget>[
              Text(s.format(s.today),
                  key: const ValueKey<String>('item-today'),
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Color.lerp(c, Colors.black, 0.2))),
              if (diff.isNotEmpty)
                Text(diff,
                    key: const ValueKey<String>('item-diff'),
                    style: const TextStyle(fontSize: 14, color: WaterColors.value)),
            ],
            if (s.alert != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey<String>('item-alert'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WaterColors.alert.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.circle, size: 9, color: WaterColors.alert),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.alert!, style: const TextStyle(fontSize: 14, color: WaterColors.text))),
                  ],
                ),
              ),
            ],
            if (!s.spec.link) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: glassCard(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('最近 14 天', style: TextStyle(fontSize: 12, color: WaterColors.sub)),
                    const SizedBox(height: 6),
                    SizedBox(
                      key: const ValueKey<String>('item-chart'),
                      height: 150,
                      child: SeriesChart(
                        values: <double?>[for (final ItemDay x in d14) x.value],
                        color: c,
                        usual: u,
                        bandPct: bandPct,
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        Text(shortDate(d14.first.date), style: const TextStyle(fontSize: 10, color: WaterColors.sub)),
                        const Spacer(),
                        Text(shortDate(d14.last.date), style: const TextStyle(fontSize: 10, color: WaterColors.sub)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      u == null ? '平时：数据收集中（需要 $minUsualDays 天以上）' : '平时 ${s.format(u)}（带子是 ±$bandPct%）',
                      key: const ValueKey<String>('item-usual'),
                      style: const TextStyle(fontSize: 11, color: WaterColors.sub),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: glassCard(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Info('看什么', s.spec.what),
                  _Info('为什么重要', s.spec.why),
                  _Info('数据从哪里来', s.spec.source),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('这不是诊断。如果担心，请问兽医。', style: TextStyle(fontSize: 11, color: WaterColors.sub)),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WaterColors.sub)),
          const SizedBox(height: 2),
          Text(text, style: const TextStyle(fontSize: 14, color: WaterColors.text)),
        ],
      ),
    );
  }
}
