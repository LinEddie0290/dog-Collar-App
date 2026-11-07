// T35 健康タブ：六大板块の一覧 → 板块のページ → 項目のページ。
import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/data/health_items.dart';
import 'package:collar_app/data/health_series.dart';
import 'package:collar_app/data/item_specs.dart';
import 'package:collar_app/ui/health/board_page.dart';
import 'package:collar_app/ui/health/health_page.dart';
import 'package:collar_app/ui/health/health_text.dart';
import 'package:collar_app/ui/health/item_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-05（木）の昼（UTC＋8 で 12 時）。
DateTime _clock() => DateTime.utc(2026, 11, 5, 4);
const String _today = '2026-11-05';

class _Source implements SummarySource {
  _Source(this.bundle);

  final SummaryBundle bundle;

  @override
  Listenable? get changes => null;

  @override
  Future<SummaryBundle> load() async => bundle;
}

/// 运动量：前の 14 日は 40 分、今日は 42 分。今日の 1 日まとめに运动の提醒（[alert] のとき）。
SummaryBundle _bundle({bool alert = false}) {
  final List<String> dates = lastDates(_today, 15);
  return SummaryBundle(
    dogId: 'my_dog',
    history: <HistoryDay>[
      for (int i = 0; i < 15; i++) HistoryDay(date: dates[i], validDay: true, activeMin: i == 14 ? 42 : 40),
    ],
    days: <DayEntry>[
      DayEntry(
        date: _today,
        summary: DailySummary.fromJson(<String, dynamic>{
          'dog_id': 'my_dog',
          'date': _today,
          'categories': <dynamic>[
            if (alert)
              <String, dynamic>{
                'id': 'exercise',
                'status': 'ok',
                'alert': <String, dynamic>{
                  'text_key': 'exercise.alert.less',
                  'values': <String, dynamic>{'ratio': 0.4},
                },
              },
          ],
        }),
      ),
    ],
  );
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// key の付いた Text の文字。
String? _text(WidgetTester tester, String k) => tester.widget<Text>(_key(k)).data;

void _tall(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  test('平時との比べ方の文', () {
    ItemSeries s(String id, double today, double usual) => ItemSeries(
          item: healthItem(id),
          spec: itemSpec(id),
          demo: false,
          days: <ItemDay>[
            for (final String d in lastDates(_today, 15)) ItemDay(d, d == _today ? today : usual),
          ],
        );
    expect(diffText(s('activity', 42, 40)), '和平时差不多');
    expect(diffText(s('activity', 20, 40)), '比平时少 50%');
    expect(diffText(s('activity', 60, 40)), '比平时多 50%');
    expect(diffText(s('rest_hr', 100, 80)), '比平时高 25%');
    expect(diffText(s('rest_hr', 60, 80)), '比平时低 25%');
    final ItemSeries few = ItemSeries(
      item: healthItem('activity'),
      spec: itemSpec('activity'),
      demo: false,
      days: <ItemDay>[ItemDay(_today, 30)],
    );
    expect(diffText(few), '数据收集中，还不能和平时比');
    expect(shortDate('2026-11-05'), '11/05');
  });

  testWidgets('25 項目すべて：板块のカード → 板块のページ → 項目のページが開ける', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HealthPage(clock: _clock))));
    await tester.pumpAndSettle();

    int opened = 0;
    for (final BoardInfo b in boardInfos) {
      await tester.tap(_key('board-card-${b.board.name}'));
      await tester.pumpAndSettle();
      expect(_key('board-page-${b.board.name}'), findsOneWidget);
      for (final HealthItem i in b.items) {
        expect(_key('item-row-${i.id}'), findsOneWidget, reason: i.id);
        await tester.tap(_key('item-row-${i.id}'));
        await tester.pumpAndSettle();
        expect(_key('item-page-${i.id}'), findsOneWidget, reason: i.id);
        expect(find.text('看什么'), findsOneWidget);
        opened++;
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(opened, 25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('实际：カード・行・項目のページに今日の値と平時との比', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HealthPage(live: _Source(_bundle()), clock: _clock))));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _key('board-card-exercise'), matching: find.text('42 分钟')), findsOneWidget);
    expect(_key('card-alert-exercise'), findsNothing);

    await tester.tap(_key('board-card-exercise'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _key('item-row-activity'), matching: find.text('实际')), findsOneWidget);
    expect(find.descendant(of: _key('item-row-jump'), matching: find.text('示例')), findsOneWidget);

    await tester.tap(_key('item-row-activity'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'item-today'), '42 分钟');
    expect(_text(tester, 'item-diff'), '和平时差不多');
    expect(_text(tester, 'item-usual'), '平时 40 分钟（带子是 ±15%）');
    expect(_key('item-alert'), findsNothing);
  });

  testWidgets('提醒：カードの点・行の点・項目のページ', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HealthPage(live: _Source(_bundle(alert: true)), clock: _clock))));
    await tester.pumpAndSettle();
    expect(_key('card-alert-exercise'), findsOneWidget);
    await tester.tap(_key('board-card-exercise'));
    await tester.pumpAndSettle();
    expect(_key('row-alert-activity'), findsOneWidget);
    await tester.tap(_key('item-row-activity'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _key('item-alert'), matching: find.textContaining('今天运动比平时少很多')), findsOneWidget);
  });

  testWidgets('演示：本物の項目も示例になる', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HealthPage(live: _Source(_bundle()), clock: _clock))));
    await tester.pumpAndSettle();
    await tester.tap(_key('health-demo-toggle'));
    await tester.pumpAndSettle();
    expect(find.text('演示中（全部示例）'), findsOneWidget);
    await tester.tap(_key('board-card-exercise'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _key('item-row-activity'), matching: find.text('示例')), findsOneWidget);
  });

  testWidgets('本物がない实际の項目：没有数据（線も「没有数据」、比べる文なし）', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(MaterialApp(home: ItemPage(series: buildItemSeries('sleep_time', today: _today))));
    await tester.pumpAndSettle();
    expect(_text(tester, 'item-today'), noDataValue);
    expect(find.descendant(of: _key('item-chart'), matching: find.text('没有数据')), findsOneWidget);
    expect(_key('item-diff'), findsNothing);
    expect(find.textContaining('数据收集中'), findsOneWidget); // 平時の行
  });

  testWidgets('像心电图的波形：「测定」の記録を開くボタン', (WidgetTester tester) async {
    _tall(tester);
    int opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: BoardPage(board: Board.physio, today: _today, onOpenEcg: () => opened++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(_key('item-row-ecg_like'));
    await tester.pumpAndSettle();
    await tester.tap(_key('open-ecg'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(_key('item-chart'), findsNothing);
  });

  testWidgets('幅 320 でもはみ出さない（一覧・7 項目の板块・項目のページ）', (WidgetTester tester) async {
    _tall(tester, width: 320);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HealthPage(live: _Source(_bundle()), clock: _clock))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_key('board-card-physio'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_key('item-row-excretion'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
