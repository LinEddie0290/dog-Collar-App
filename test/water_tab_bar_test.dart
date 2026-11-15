// T35：下のタブのバー（白い水のデザイン）。
import 'package:collar_app/ui/water_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<WaterTab> _tabs = <WaterTab>[
  WaterTab(WaterTabIcon.today, '今天'),
  WaterTab(WaterTabIcon.health, '健康'),
  WaterTab(WaterTabIcon.measure, '测定'),
  WaterTab(WaterTabIcon.safety, '安全'),
  WaterTab(WaterTabIcon.mine, '我的'),
];

/// 画面の一番下にバーを置く（アプリの外枠と同じ置き方）。
Widget _app({required int Function() index, required ValueChanged<int> onSelect}) => MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Spacer(),
            WaterTabBar(tabs: _tabs, index: index(), onSelect: onSelect),
          ],
        ),
      ),
    );

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('5 つの名前が出て、押すと番号が返る。今のタブだけ色が違う', (WidgetTester tester) async {
    int index = 0;
    Future<void> show() => tester.pumpWidget(_app(index: () => index, onSelect: (int i) => index = i));
    Color colorOf(String label) => tester.widget<Text>(find.text(label)).style!.color!;

    await show();
    for (final WaterTab t in _tabs) {
      expect(find.text(t.label), findsOneWidget);
    }
    expect(colorOf('今天'), isNot(colorOf('健康')));
    expect(colorOf('健康'), colorOf('我的'));

    await tester.tap(_key('tab-safety'));
    expect(index, 3);
    await show();
    expect(colorOf('安全'), isNot(colorOf('今天')));
    expect(colorOf('今天'), colorOf('健康'));

    // 絵のところを押しても同じ
    await tester.tapAt(tester.getCenter(_key('tab-measure')) - const Offset(0, 8));
    expect(index, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('広い画面では幅 520 まで、狭い画面では左右に 14 の余白', (WidgetTester tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(_app(index: () => 0, onSelect: (int _) {}));
    expect(tester.getSize(_key('water-tab-bar')), const Size(520, 64));
    expect(tester.getCenter(_key('water-tab-bar')).dx, 600);

    tester.view.physicalSize = const Size(360, 700);
    await tester.pumpWidget(_app(index: () => 0, onSelect: (int _) {}));
    await tester.pump();
    expect(tester.getSize(_key('water-tab-bar')), const Size(332, 64));
    // 下の余白 14
    expect(tester.getRect(_key('water-tab-bar')).bottom, 700 - 14);
    expect(tester.takeException(), isNull);
  });
}
