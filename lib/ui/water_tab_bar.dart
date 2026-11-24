/// T35：下のタブのバー（白い水のデザイン）。浮いた丸いガラスの板に 5 つのタブ。
/// 画面イメージ：首輪開発計画/03_設計メモ/T35_画面イメージ/ホーム画面イメージ_v1_白（.tabs）。
library;

import 'package:flutter/material.dart';

/// タブの絵（画面イメージの線画と同じ形）。
enum WaterTabIcon { today, health, measure, safety, mine }

class WaterTab {
  const WaterTab(this.icon, this.label);

  final WaterTabIcon icon;
  final String label;
}

class WaterTabBar extends StatelessWidget {
  const WaterTabBar({super.key, required this.tabs, required this.index, required this.onSelect});

  final List<WaterTab> tabs;

  /// 今のタブ。
  final int index;
  final ValueChanged<int> onSelect;

  static const Color _on = Color(0xFF0AA3CF);
  static const Color _off = Color(0xFF86A3B3);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          // 広い画面（Mac など）でも間のびしないように
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            key: const ValueKey<String>('water-tab-bar'),
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              border: Border.all(color: const Color(0x383CAAD2)),
              borderRadius: BorderRadius.circular(30),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x2628789F), blurRadius: 30, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabButton(
                      key: ValueKey<String>('tab-${tabs[i].icon.name}'),
                      tab: tabs[i],
                      selected: i == index,
                      color: i == index ? _on : _off,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({super.key, required this.tab, required this.selected, required this.color, required this.onTap});

  final WaterTab tab;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CustomPaint(size: const Size(22, 22), painter: _TabIconPainter(tab.icon, color)),
            const SizedBox(height: 3),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// 線画のアイコン。24×24 の座標で描いて、大きさに合わせて伸ばす。
class _TabIconPainter extends CustomPainter {
  const _TabIconPainter(this.icon, this.color);

  final WaterTabIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (icon) {
      case WaterTabIcon.today:
        canvas.drawCircle(const Offset(12, 12), 8, p);
        canvas.drawCircle(const Offset(12, 12), 3, p);
      case WaterTabIcon.health:
        final Path heart = Path()
          ..moveTo(12, 20)
          ..cubicTo(12, 20, 5, 15.5, 5, 10)
          ..arcToPoint(const Offset(12, 7.4), radius: const Radius.circular(4))
          ..arcToPoint(const Offset(19, 10), radius: const Radius.circular(4))
          ..cubicTo(19, 15.5, 12, 20, 12, 20)
          ..close();
        canvas.drawPath(heart, p);
      case WaterTabIcon.measure:
        final Path pulse = Path()
          ..moveTo(3, 12)
          ..lineTo(7, 12)
          ..lineTo(9, 7)
          ..lineTo(13, 17)
          ..lineTo(15, 12)
          ..lineTo(21, 12);
        canvas.drawPath(pulse, p);
      case WaterTabIcon.safety:
        final Path shield = Path()
          ..moveTo(12, 3)
          ..lineTo(19, 6)
          ..lineTo(19, 11)
          ..cubicTo(19, 16, 15.5, 19, 12, 21)
          ..cubicTo(8.5, 19, 5, 16, 5, 11)
          ..lineTo(5, 6)
          ..close();
        canvas.drawPath(shield, p);
      case WaterTabIcon.mine:
        canvas.drawCircle(const Offset(12, 8), 4, p);
        final Path body = Path()
          ..moveTo(4, 21)
          ..cubicTo(5.5, 17, 9, 15, 12, 15)
          ..cubicTo(15, 15, 18.5, 17, 20, 21);
        canvas.drawPath(body, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TabIconPainter old) => old.icon != icon || old.color != color;
}
