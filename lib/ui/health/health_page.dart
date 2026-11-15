/// T35「健康」タブ：六大板块の一覧 → 板块のページ → 項目のページ（設計メモ T35_健康タブ）。
/// 見た目はホームと同じ白い水（H1）。上の「演示」で全部を示例にできる（ホームとは別に切り替え）。
library;

import 'package:flutter/material.dart';

import '../../data/daily_summary.dart';
import '../../data/health_items.dart';
import '../../data/health_series.dart';
import '../../data/home_snapshot.dart' show todayKey;
import '../home/water_background.dart';
import '../home/water_style.dart';
import 'board_page.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key, this.live, this.clock = DateTime.now, this.onOpenEcg});

  /// 本物の 1 日まとめ（スマホで計算した結果）。null なら本物はない。
  final SummarySource? live;
  final DateTime Function() clock;

  /// 像心电图的波形：「测定」の記録を開く。
  final VoidCallback? onOpenEcg;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  SummaryBundle? _bundle;
  bool _demo = false;
  int _loadNo = 0;

  @override
  void initState() {
    super.initState();
    widget.live?.changes?.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(HealthPage old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) {
      old.live?.changes?.removeListener(_load);
      widget.live?.changes?.addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    widget.live?.changes?.removeListener(_load);
    super.dispose();
  }

  /// 読めなければ「本物なし」（落とさない）。古い読み込みの結果は捨てる。
  Future<void> _load() async {
    final int no = ++_loadNo;
    final SummarySource? live = widget.live;
    SummaryBundle? b;
    if (live != null) {
      try {
        b = await live.load();
      } catch (_) {
        b = null;
      }
    }
    if (!mounted || no != _loadNo) return;
    setState(() => _bundle = b);
  }

  void _open(Board board, String today) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          BoardPage(board: board, today: today, real: _bundle, demoAll: _demo, onOpenEcg: widget.onOpenEcg),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final String today = todayKey(widget.clock());
    return WaterBackground(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double cardW = (c.maxWidth - 40 - 12) / 2;
          return ListView(
            key: const ValueKey<String>('health-page'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text('健康', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: WaterColors.text)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('六大板块・25 个项目', style: TextStyle(fontSize: 12, color: WaterColors.sub)),
                  ),
                  GestureDetector(
                    key: const ValueKey<String>('health-demo-toggle'),
                    onTap: () => setState(() => _demo = !_demo),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _demo ? const Color(0x99FFF0D7) : Colors.white.withValues(alpha: 0.5),
                        border: Border.all(color: _demo ? const Color(0x73C88228) : WaterColors.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_demo ? '演示中（全部示例）' : '演示',
                          style: TextStyle(fontSize: 11, color: _demo ? const Color(0xFFB8741C) : WaterColors.sub)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final BoardInfo b in boardInfos)
                    SizedBox(
                      width: cardW,
                      child: _BoardCard(
                        info: b,
                        items: buildBoardSeries(b.board, today: today, real: _bundle, demoAll: _demo),
                        onTap: () => _open(b.board, today),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('「示例」是假的数据（还没有做好的项目）。这不是诊断。如果担心，请问兽医。',
                  style: TextStyle(fontSize: 11, color: WaterColors.sub)),
            ],
          );
        },
      ),
    );
  }
}

/// 板块のカード：名前・代表の項目の今日の値・提醒（あれば最初の 1 つ）・示例の印。
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.info, required this.items, required this.onTap});

  final BoardInfo info;
  final List<ItemSeries> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color c = boardColor(info.board);
    final ItemSeries lead = items.firstWhere((ItemSeries s) => s.item.id == info.lead);
    final List<ItemSeries> alerts = items.where((ItemSeries s) => s.alert != null).toList();
    final int real = items.where((ItemSeries s) => !s.demo).length;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('board-card-${info.board.name}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: glassCard().copyWith(border: Border.all(color: c.withValues(alpha: 0.45))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(boardIcon(info.board), size: 20, color: Color.lerp(c, Colors.black, 0.15)),
                  const SizedBox(width: 6),
                  Text(info.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WaterColors.text)),
                  const Spacer(),
                  if (alerts.isNotEmpty)
                    Container(
                      key: ValueKey<String>('card-alert-${info.board.name}'),
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(color: WaterColors.alert, shape: BoxShape.circle),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(lead.format(lead.today),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color.lerp(c, Colors.black, 0.2))),
              Text(lead.item.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: WaterColors.sub)),
              const SizedBox(height: 6),
              Text(
                alerts.isEmpty ? '没有提醒' : alerts.first.alert!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: alerts.isEmpty ? WaterColors.sub : const Color(0xFFB8741C)),
              ),
              const SizedBox(height: 4),
              Text(
                '${items.length} 个项目・实际 $real',
                style: const TextStyle(fontSize: 10.5, color: WaterColors.demo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
