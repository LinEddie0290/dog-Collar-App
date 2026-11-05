/// T35：泡を押したときに下から出る、板块の簡単な詳細。
/// 今日の値・提醒・その板块の項目（実际数据／示例）。くわしいページは「健康」タブで作る。
library;

import 'package:flutter/material.dart';

import '../../data/health_items.dart';
import '../../data/home_snapshot.dart';
import 'water_style.dart';

Future<void> showBoardSheet(BuildContext context, BubbleData data) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (BuildContext _) => BoardSheet(data: data),
  );
}

class BoardSheet extends StatelessWidget {
  const BoardSheet({super.key, required this.data});

  final BubbleData data;

  @override
  Widget build(BuildContext context) {
    final BoardInfo info = boardInfo(data.board);
    final Color c = boardColor(data.board);
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
                if (data.demo) const _Tag('示例', WaterColors.demo),
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
                    : (data.value == noDataValue ? '今天还没有数据（开始记录以后会有）' : '今天的数据（这个手机算出来的）'),
                style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
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
                    if (item.real)
                      const _Tag('实际数据', WaterColors.aqua)
                    else
                      const _Tag('示例', WaterColors.demo),
                  ],
                ),
              ),
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
