// T35：ホームの部品（泡・真ん中の球・波紋）。
import 'package:collar_app/data/health_items.dart';
import 'package:collar_app/data/home_snapshot.dart';
import 'package:collar_app/ui/home/water_background.dart';
import 'package:collar_app/ui/home/water_bubble.dart';
import 'package:collar_app/ui/home/water_ripples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: WaterBackground(child: Center(child: child))));

double _scaleOf(WidgetTester tester, Finder f) =>
    tester.widget<AnimatedScale>(find.ancestor(of: f, matching: find.byType(AnimatedScale)).first).scale;

void main() {
  testWidgets('泡：名前・値・示例の印・提醒の点', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WaterBubble(data: BubbleData(board: Board.exercise, value: '42 分钟', demo: false)),
        WaterBubble(data: BubbleData(board: Board.diet, value: '喝水 6 次', demo: true, alert: '喝水比平时少')),
      ],
    )));
    expect(find.text('运动'), findsOneWidget);
    expect(find.text('42 分钟'), findsOneWidget);
    expect(find.text('饮食'), findsOneWidget);
    expect(find.text('喝水 6 次'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('demo-exercise')), findsNothing);
    expect(find.byKey(const ValueKey<String>('demo-diet')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('alert-dot-exercise')), findsNothing);
    expect(find.byKey(const ValueKey<String>('alert-dot-diet')), findsOneWidget);
    // 泡の大きさは決めたとおり
    expect(tester.getSize(find.byKey(const ValueKey<String>('bubble-exercise'))), const Size(96, 96));
  });

  testWidgets('泡を押す：押している間は沈む・押し始めに波紋の合図・離したらタップ', (WidgetTester tester) async {
    int taps = 0;
    int presses = 0;
    await tester.pumpWidget(_wrap(WaterBubble(
      data: const BubbleData(board: Board.sleep, value: '9.5 小时', demo: false),
      onTap: () => taps++,
      onPressStart: () => presses++,
    )));
    final Finder bubble = find.byKey(const ValueKey<String>('bubble-sleep'));
    expect(_scaleOf(tester, bubble), 1.0);

    final TestGesture g = await tester.startGesture(tester.getCenter(bubble));
    await tester.pump(const Duration(milliseconds: 150));
    expect(presses, 1);
    expect(_scaleOf(tester, bubble), 0.9);
    expect(taps, 0);

    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 1);
    expect(_scaleOf(tester, bubble), 1.0);
  });

  testWidgets('真ん中の球：今の状態と提醒の数、押せる', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(_wrap(CoreBubble(
      now: const NowLine('休息中', '已安静 25 分钟'),
      footer: '今天没有提醒',
      onTap: () => taps++,
    )));
    expect(find.text('现在'), findsOneWidget);
    expect(find.text('休息中'), findsOneWidget);
    expect(find.text('已安静 25 分钟'), findsOneWidget);
    expect(find.text('今天没有提醒'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey<String>('core-bubble'))), const Size(164, 164));
    await tester.tap(find.byKey(const ValueKey<String>('core-bubble')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 1);

    // 下の文がないときも出せる
    await tester.pumpWidget(_wrap(const CoreBubble(now: NowLine('没有在记录', null))));
    expect(find.text('没有在记录'), findsOneWidget);
  });

  testWidgets('波紋：出して、終わったら消える（動くものを残さない）', (WidgetTester tester) async {
    final GlobalKey<WaterRipplesState> key = GlobalKey<WaterRipplesState>();
    await tester.pumpWidget(_wrap(WaterRipples(key: key, child: const SizedBox(width: 300, height: 300))));
    expect(key.currentState!.activeCount, 0);

    key.currentState!.add(const Offset(150, 150), Colors.blue);
    key.currentState!.add(const Offset(100, 100), Colors.pink);
    await tester.pump();
    expect(key.currentState!.activeCount, 2);
    await tester.pump(const Duration(milliseconds: 450));
    expect(key.currentState!.activeCount, 2);

    // アニメーションは最初の 1 コマ（上の 450 ms のところ）から数えるので、そこから 900 ms 以上進める
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(key.currentState!.activeCount, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
