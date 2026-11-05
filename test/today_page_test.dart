// T35：ホーム（今天）の画面。
import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/ui/home/water_ripples.dart';
import 'package:collar_app/ui/today_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-05（木）の昼（UTC＋8 で 12 時）。
DateTime _clock() => DateTime.utc(2026, 11, 5, 4);

class _FakeSource implements SummarySource {
  _FakeSource(this.days);

  List<DayEntry> days;
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  @override
  Listenable? get changes => version;

  @override
  Future<SummaryBundle> load() async =>
      SummaryBundle(dogId: 'my_dog', days: days, history: const <HistoryDay>[]);
}

DayEntry _day(String date, {num activeMin = 42, bool exerciseAlert = false}) => DayEntry(
      date: date,
      summary: DailySummary.fromJson(<String, dynamic>{
        'dog_id': 'my_dog',
        'date': date,
        'categories': <dynamic>[
          <String, dynamic>{
            'id': 'exercise',
            'status': 'ok',
            'daily': <String, dynamic>{
              'text_key': 'exercise.daily',
              'values': <String, dynamic>{'active_min': activeMin},
            },
            'alert': exerciseAlert
                ? <String, dynamic>{
                    'text_key': 'exercise.alert.less',
                    'values': <String, dynamic>{'ratio': 0.4},
                  }
                : null,
          },
          <String, dynamic>{
            'id': 'sleep',
            'status': 'ok',
            'daily': <String, dynamic>{
              'text_key': 'sleep.daily',
              'values': <String, dynamic>{'sleep_min': 570},
            },
          },
          <String, dynamic>{
            'id': 'physio',
            'status': 'ok',
            'daily': <String, dynamic>{
              'text_key': 'physio.daily',
              'values': <String, dynamic>{'rest_hr': 81.6},
            },
          },
        ],
      }),
    );

Widget _app(Widget page) => MaterialApp(home: Scaffold(body: page));

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('本物なし：本物の泡は「没有数据」、示例は印つき、真ん中は「没有在记录」', (WidgetTester tester) async {
    await tester.pumpWidget(_app(const TodayPage(clock: _clock)));
    await tester.pumpAndSettle();

    expect(find.text('没有数据'), findsNWidgets(3));
    for (final String b in <String>['exercise', 'sleep', 'physio']) {
      expect(_key('bubble-$b'), findsOneWidget);
      expect(_key('demo-$b'), findsNothing);
    }
    for (final String b in <String>['skin', 'mind', 'diet']) {
      expect(_key('demo-$b'), findsOneWidget);
    }
    expect(find.text('没有在记录'), findsOneWidget);
    expect(find.text('11月5日 星期四'), findsOneWidget);
    expect(find.text('我的狗'), findsOneWidget);
    // 首輪がわからないときは出さない
    expect(_key('home-collar-chip'), findsNothing);
  });

  testWidgets('本物あり：今日の値と提醒（点・下のカード・真ん中の数）', (WidgetTester tester) async {
    final _FakeSource src = _FakeSource(<DayEntry>[
      _day('2026-11-04', activeMin: 10),
      _day('2026-11-05', exerciseAlert: true),
    ]);
    await tester.pumpWidget(_app(TodayPage(live: src, clock: _clock)));
    await tester.pumpAndSettle();

    expect(find.text('42 分钟'), findsOneWidget); // 昨日の 10 ではなく今日
    expect(find.text('9.5 小时'), findsOneWidget);
    expect(find.text('心率 82'), findsOneWidget);
    expect(_key('alert-dot-exercise'), findsOneWidget);
    expect(find.textContaining('运动：今天运动比平时少很多'), findsOneWidget);
    // 示例の提醒があればそれも出る（日付で決まる）。少なくとも 1 つ
    expect(find.textContaining('今天有'), findsOneWidget);
  });

  testWidgets('まとめが変わったら読み直す', (WidgetTester tester) async {
    final _FakeSource src = _FakeSource(<DayEntry>[]);
    await tester.pumpWidget(_app(TodayPage(live: src, clock: _clock)));
    await tester.pumpAndSettle();
    expect(find.text('没有数据'), findsNWidgets(3));

    src.days = <DayEntry>[_day('2026-11-05', activeMin: 55)];
    src.version.value++;
    await tester.pumpAndSettle();
    expect(find.text('55 分钟'), findsOneWidget);
  });

  testWidgets('演示：押すと全部が示例、もう一度押すと戻る', (WidgetTester tester) async {
    await tester.pumpWidget(_app(TodayPage(live: _FakeSource(<DayEntry>[_day('2026-11-05')]), clock: _clock)));
    await tester.pumpAndSettle();
    expect(find.text('42 分钟'), findsOneWidget);

    await tester.tap(_key('home-demo-toggle'));
    await tester.pumpAndSettle();
    expect(find.text('演示中（全部示例）'), findsOneWidget);
    for (final String b in <String>['exercise', 'sleep', 'physio', 'skin', 'mind', 'diet']) {
      expect(_key('demo-$b'), findsOneWidget);
    }
    expect(find.text('42 分钟'), findsNothing);

    await tester.tap(_key('home-demo-toggle'));
    await tester.pumpAndSettle();
    expect(find.text('42 分钟'), findsOneWidget);
  });

  testWidgets('泡を押す：波紋が出て消え、下から詳細（項目と实际／示例）', (WidgetTester tester) async {
    await tester.pumpWidget(_app(const TodayPage(clock: _clock)));
    await tester.pumpAndSettle();

    await tester.tap(_key('bubble-sleep'));
    await tester.pump();
    final WaterRipplesState rip = tester.state<WaterRipplesState>(find.byType(WaterRipples));
    expect(rip.activeCount, 1);

    await tester.pumpAndSettle();
    expect(rip.activeCount, 0);
    expect(_key('board-sheet-sleep'), findsOneWidget);
    expect(_key('item-sleep_time'), findsOneWidget);
    expect(_key('item-sleep_rr'), findsOneWidget);
    expect(_key('item-sleep_restless'), findsOneWidget);
    expect(find.text('实际数据'), findsNWidgets(2));

    // 閉じる
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_key('board-sheet-sleep'), findsNothing);
  });

  testWidgets('首輪の表示：つながっていない', (WidgetTester tester) async {
    final CollarLink link = CollarLink();
    await tester.pumpWidget(_app(TodayPage(link: link, clock: _clock)));
    await tester.pumpAndSettle();
    expect(find.text('项圈未连接'), findsOneWidget);
  });

  for (final double w in <double>[320, 390, 430]) {
    testWidgets('幅 $w でもはみ出さない', (WidgetTester tester) async {
      tester.view.physicalSize = Size(w * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const TodayPage(clock: _clock)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 泡が画面の中に収まる
      for (final String b in <String>['exercise', 'sleep', 'physio', 'skin', 'mind', 'diet']) {
        final Rect r = tester.getRect(_key('bubble-$b'));
        expect(r.left, greaterThanOrEqualTo(0), reason: b);
        expect(r.right, lessThanOrEqualTo(w), reason: b);
      }
    });
  }
}
