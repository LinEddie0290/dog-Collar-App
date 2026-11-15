// T35：ホーム（今天）の泡・真ん中の文の計算。
import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/data/health_items.dart';
import 'package:collar_app/data/home_snapshot.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

DailySummary _summary({
  Map<String, dynamic>? exerciseDaily,
  Map<String, dynamic>? exerciseAlert,
  Map<String, dynamic>? sleepDaily,
  Map<String, dynamic>? physioDaily,
  String physioStatus = 'ok',
}) =>
    DailySummary.fromJson(<String, dynamic>{
      'dog_id': 'my_dog',
      'date': '2026-11-05',
      'categories': <dynamic>[
        <String, dynamic>{'id': 'exercise', 'status': 'ok', 'daily': exerciseDaily, 'alert': exerciseAlert},
        <String, dynamic>{'id': 'sleep', 'status': 'ok', 'daily': sleepDaily},
        // 皮肤の提醒（挠と舔の回数、T35：CNN v2 で本物）
        <String, dynamic>{
          'id': 'skin',
          'status': 'ok',
          'alert': <String, dynamic>{'text_key': 'skin.alert.more', 'values': <String, dynamic>{'count': 30}},
        },
        <String, dynamic>{'id': 'physio', 'status': physioStatus, 'daily': physioDaily},
      ],
    });

Map<String, dynamic> _item(String key, Map<String, dynamic> values) =>
    <String, dynamic>{'text_key': key, 'values': values};

WindowState _st(int i, {required bool rest, double stillS = 0}) => WindowState(
      tStartMs: 1762300000000 + i * 1000,
      tStartDevUs: i * 1000000,
      activity: rest ? 0.05 : 0.8,
      rest: rest,
      stillS: stillS,
      quietS: stillS,
      measureOk: false,
    );

void main() {
  group('六大板块の一覧', () {
    test('Board の順と同じ・項目の id は重ならない・本物は运动・睡眠・生理・皮肤（试用は挠・舔・发抖）', () {
      expect(boardInfos.map((BoardInfo b) => b.board).toList(), Board.values);
      expect(boardInfos.map((BoardInfo b) => b.name).toList(), <String>['运动', '睡眠', '生理', '皮肤', '心理', '饮食']);
      final List<String> ids = <String>[for (final BoardInfo b in boardInfos) ...b.items.map((HealthItem i) => i.id)];
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 25); // 完成度表の 23 項目＋吠叫・低吼
      for (final BoardInfo b in boardInfos) {
        expect(b.items, isNotEmpty);
        final bool anyReal = b.items.any((HealthItem i) => i.real);
        expect(anyReal, <Board>[Board.exercise, Board.sleep, Board.physio, Board.skin].contains(b.board), reason: b.name);
      }
      final Set<String> trial = <String>{
        for (final BoardInfo b in boardInfos) ...b.items.where((HealthItem i) => i.trial).map((HealthItem i) => i.id),
      };
      expect(trial, <String>{'scratch', 'lick', 'tremble'});
      for (final BoardInfo b in boardInfos) {
        for (final HealthItem i in b.items.where((HealthItem i) => i.trial)) {
          expect(i.real, isTrue, reason: i.id); // 试用は本物の中だけ
        }
      }
    });
  });

  group('泡', () {
    test('本物のまとめ：运动・睡眠・生理・皮肤（试用）は本物の値、心理・饮食は示例', () {
      final HomeSnapshot s = buildHomeSnapshot(
        date: '2026-11-05',
        rawToday: <String, double>{'wear_min': 300, 'scratch_count': 7, 'lick_min': 2.5},
        real: _summary(
          exerciseDaily: _item('exercise.daily', <String, dynamic>{'active_min': 42.4}),
          exerciseAlert: _item('exercise.alert.less', <String, dynamic>{'ratio': 0.4}),
          sleepDaily: _item('sleep.daily', <String, dynamic>{'sleep_min': 570}),
          physioDaily: _item('physio.daily', <String, dynamic>{'rest_hr': 81.6, 'rest_rr': 20}),
        ),
      );
      expect(s.hasRealData, isTrue);
      expect(s.bubbles.map((BubbleData b) => b.board).toList(), Board.values);
      expect(s.bubble(Board.exercise).value, '42 分钟');
      expect(s.bubble(Board.sleep).value, '9.5 小时');
      expect(s.bubble(Board.physio).value, '心率 82');
      for (final Board b in <Board>[Board.exercise, Board.sleep, Board.physio, Board.skin]) {
        expect(s.bubble(b).demo, isFalse, reason: b.name);
      }
      for (final Board b in <Board>[Board.mind, Board.diet]) {
        expect(s.bubble(b).demo, isTrue, reason: b.name);
      }
      expect(s.bubble(Board.skin).value, '挠 7 次');
      expect(s.bubble(Board.skin).trial, isTrue);
      expect(s.bubble(Board.exercise).trial, isFalse);
      expect(s.bubble(Board.skin).alert, '今天挠和舔比平时多很多，挠和舔了 30 次');
      expect(s.bubble(Board.exercise).alert, '今天运动比平时少很多（大约是平时的 40%）');
      expect(s.bubble(Board.sleep).alert, isNull);
      expect(s.alerts.first.board, Board.exercise);
    });

    test('今日の本物がない・まだ集めている日：本物の泡は「没有数据」（示例にはしない）', () {
      final HomeSnapshot none = buildHomeSnapshot(date: '2026-11-05');
      expect(none.hasRealData, isFalse);
      for (final Board b in <Board>[Board.exercise, Board.sleep, Board.physio, Board.skin]) {
        expect(none.bubble(b).value, noDataValue, reason: b.name);
        expect(none.bubble(b).demo, isFalse);
        expect(none.bubble(b).alert, isNull);
      }
      final HomeSnapshot collecting = buildHomeSnapshot(
        date: '2026-11-05',
        real: _summary(physioStatus: 'collecting', physioDaily: _item('physio.daily', <String, dynamic>{})),
      );
      expect(collecting.bubble(Board.exercise).value, noDataValue);
      expect(collecting.bubble(Board.physio).value, noDataValue);
    });

    test('演示：全部が示例（本物があっても使わない）', () {
      final HomeSnapshot s = buildHomeSnapshot(
        date: '2026-11-05',
        real: _summary(exerciseDaily: _item('exercise.daily', <String, dynamic>{'active_min': 42})),
        demoAll: true,
      );
      expect(s.hasRealData, isFalse);
      expect(s.bubbles.every((BubbleData b) => b.demo), isTrue);
      expect(s.bubble(Board.exercise).value, demoBubble('2026-11-05', Board.exercise).value);
    });

    test('示例は同じ日なら同じ・日によって変わる・提醒はときどき', () {
      for (final Board b in Board.values) {
        final BubbleData a1 = demoBubble('2026-11-05', b);
        final BubbleData a2 = demoBubble('2026-11-05', b);
        expect(a1.value, a2.value);
        expect(a1.alert, a2.alert);
        final List<String> dates = <String>[
          for (int d = 1; d <= 60; d++) dateKey(DateTime.utc(2026, 9, 1).add(Duration(days: d))),
        ];
        final Set<String> values = dates.map((String d) => demoBubble(d, b).value).toSet();
        expect(values.length, greaterThan(1), reason: b.name);
        final int alerts = dates.where((String d) => demoBubble(d, b).alert != null).length;
        expect(alerts, inInclusiveRange(1, 30), reason: '${b.name}: $alerts');
      }
    });

    test('今日の日付は 1 日まとめと同じ（UTC＋8）', () {
      expect(todayKey(DateTime.utc(2026, 11, 5, 15, 59)), '2026-11-05');
      expect(todayKey(DateTime.utc(2026, 11, 5, 16, 0)), '2026-11-06');
    });
  });

  group('真ん中', () {
    test('記録していない・つないでいる・結果待ち', () {
      expect(nowLine(recording: false).title, '没有在记录');
      expect(nowLine(recording: false, starting: true).title, '连接中…');
      final NowLine w = nowLine(recording: true);
      expect(w.title, '记录中');
      expect(w.sub, contains('40 秒'));
    });

    test('休息中：安静の長さ', () {
      expect(nowLine(recording: true, states: <WindowState>[_st(0, rest: true, stillS: 30)]).sub, '刚安静下来');
      final NowLine n = nowLine(recording: true, states: <WindowState>[_st(0, rest: false), _st(1, rest: true, stillS: 1500)]);
      expect(n.title, '休息中');
      expect(n.sub, '已安静 25 分钟');
      expect(nowLine(recording: true, states: <WindowState>[_st(0, rest: true, stillS: 3900)]).sub, '已安静 1 小时 5 分钟');
    });

    test('在动：休息のあとから数える', () {
      final List<WindowState> s = <WindowState>[
        for (int i = 0; i < 10; i++) _st(i, rest: true, stillS: 100),
        for (int i = 10; i < 100; i++) _st(i, rest: false),
      ];
      final NowLine n = nowLine(recording: true, states: s);
      expect(n.title, '在动');
      expect(n.sub, '已经动了 1 分钟'); // 90 秒
      expect(nowLine(recording: true, states: s.sublist(0, 30)).sub, '刚开始动'); // 20 秒
    });
  });
}
