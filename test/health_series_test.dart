// T35 健康タブ：項目ごとの日々の値（实际／示例）・平時・平時との差。
import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/data/health_items.dart';
import 'package:collar_app/data/health_series.dart';
import 'package:collar_app/data/home_snapshot.dart' show demoBubble;
import 'package:collar_app/data/item_specs.dart';
import 'package:flutter_test/flutter_test.dart';

const String _today = '2026-11-05';

/// 今日で終わる [values.length] 日の history（古い順）。
List<HistoryDay> _hist(List<double?> values, {String field = 'active'}) {
  final List<String> dates = lastDates(_today, values.length);
  return <HistoryDay>[
    for (int i = 0; i < values.length; i++)
      HistoryDay(
        date: dates[i],
        validDay: true,
        activeMin: field == 'active' ? values[i] : null,
        sleepMin: field == 'sleep' ? values[i] : null,
        restHr: field == 'hr' ? values[i] : null,
        restRr: field == 'rr' ? values[i] : null,
      ),
  ];
}

SummaryBundle _bundle({List<HistoryDay> history = const <HistoryDay>[], Map<String, Map<String, double>> raw = const <String, Map<String, double>>{}, List<Map<String, dynamic>> alerts = const <Map<String, dynamic>>[]}) =>
    SummaryBundle(
      dogId: 'my_dog',
      history: history,
      raw: raw,
      days: <DayEntry>[
        DayEntry(
          date: _today,
          summary: DailySummary.fromJson(<String, dynamic>{
            'dog_id': 'my_dog',
            'date': _today,
            'categories': alerts,
          }),
        ),
      ],
    );

Map<String, dynamic> _alertCat(String id, String key, Map<String, dynamic> values) => <String, dynamic>{
      'id': id,
      'status': 'ok',
      'alert': <String, dynamic>{'text_key': key, 'values': values},
    };

void main() {
  group('項目の決まり', () {
    test('全部の項目に決まりがある・範囲が正しい・代表の項目がそろっている', () {
      final List<String> ids = <String>[for (final BoardInfo b in boardInfos) ...b.items.map((HealthItem i) => i.id)];
      expect(itemSpecs.map((ItemSpec s) => s.id).toSet(), ids.toSet());
      expect(itemSpecs.length, ids.length);
      for (final ItemSpec s in itemSpecs) {
        expect(s.min, lessThanOrEqualTo(s.max), reason: s.id);
        expect(s.what, isNotEmpty, reason: s.id);
        expect(s.why, isNotEmpty, reason: s.id);
        expect(s.source, isNotEmpty, reason: s.id);
        if (!s.link) expect(s.unit, isNotEmpty, reason: s.id);
      }
      expect(demoLeadDir.keys.toSet(), boardInfos.map((BoardInfo b) => b.lead).toSet());
      for (final BoardInfo b in boardInfos) {
        expect(b.items.map((HealthItem i) => i.id), contains(b.lead), reason: b.name);
        for (final HealthItem i in b.items) {
          expect(boardOfItem(i.id), b.board);
          expect(healthItem(i.id).name, i.name);
        }
      }
    });

    test('日付の並び（月をまたぐ）', () {
      expect(lastDates(_today, 3), <String>['2026-11-03', '2026-11-04', '2026-11-05']);
      expect(lastDates('2026-03-01', 2), <String>['2026-02-28', '2026-03-01']);
      expect(lastDates(_today, seriesDays).length, 28);
    });
  });

  group('示例', () {
    test('28 日・同じ日なら同じ・ふつうの範囲（代表の項目は提醒の日だけ外れる）', () {
      for (final ItemSpec s in itemSpecs) {
        final ItemSeries a = buildItemSeries(s.id, today: _today);
        final HealthItem item = healthItem(s.id);
        if (item.real) continue; // 实际の項目は別に見る
        expect(a.demo, isTrue, reason: s.id);
        expect(a.days.length, seriesDays);
        expect(a.days.last.date, _today);
        expect(buildItemSeries(s.id, today: _today).days.map((ItemDay d) => d.value).toList(),
            a.days.map((ItemDay d) => d.value).toList());
        for (final ItemDay d in a.days) {
          if (s.link) {
            expect(d.value, isNull);
            continue;
          }
          final bool alertDay = demoLeadDir.containsKey(s.id) && demoAlertOn(d.date, boardOfItem(s.id));
          if (!alertDay) {
            expect(d.value, inInclusiveRange(s.min, s.max), reason: '${s.id} ${d.date}');
          }
        }
      }
      expect(buildItemSeries('ecg_like', today: _today).format(null), '查看波形');
    });

    test('ホームの泡と同じ値・同じ提醒', () {
      for (int k = 0; k < 40; k++) {
        final String date = lastDates(_today, 40)[k];
        for (final BoardInfo b in boardInfos) {
          final ItemSeries s = buildItemSeries(b.lead, today: date, demoAll: true);
          final String n = s.today!.toStringAsFixed(s.spec.decimals);
          expect(demoBubble(date, b.board).value, contains(n), reason: '${b.name} $date');
          expect(demoBubble(date, b.board).alert, s.alert, reason: '${b.name} $date');
        }
      }
    });

    test('提醒の日は値が少ない／多い方に寄る', () {
      final List<String> dates = lastDates(_today, 120);
      final String lessDay = dates.firstWhere((String d) => demoAlertOn(d, Board.exercise));
      expect(demoValue(lessDay, 'activity'), lessThan(itemSpec('activity').min));
      final String moreDay = dates.firstWhere((String d) => demoAlertOn(d, Board.physio));
      expect(demoValue(moreDay, 'rest_hr'), greaterThan(itemSpec('rest_hr').max));
    });
  });

  group('实际', () {
    test('history・raw から：単位を変える（分→時間）', () {
      final SummaryBundle b = _bundle(
        history: _hist(<double?>[480, 570], field: 'sleep'),
        raw: <String, Map<String, double>>{
          '2026-11-04': <String, double>{'wear_min': 600},
          _today: <String, double>{'wear_min': 900, 'rest_lie': 600},
        },
      );
      final ItemSeries sleep = buildItemSeries('sleep_time', today: _today, real: b);
      expect(sleep.demo, isFalse);
      expect(sleep.today, 9.5);
      expect(sleep.days[seriesDays - 2].value, 8.0);
      expect(sleep.days.first.value, isNull); // 履歴のない日
      expect(sleep.format(sleep.today), '9.5 小时');

      final ItemSeries rest = buildItemSeries('active_rest', today: _today, real: b);
      expect(rest.today, 10.0);
      expect(rest.days[seriesDays - 2].value, 0); // 記録はあるが休息なし
      expect(rest.days[seriesDays - 3].value, isNull); // 記録のない日

      final ItemSeries hr = buildItemSeries('rest_hr', today: _today, real: _bundle(history: _hist(<double?>[82], field: 'hr')));
      expect(hr.format(hr.today), '82 次/分');
      final ItemSeries rr = buildItemSeries('rr', today: _today, real: _bundle(history: _hist(<double?>[21], field: 'rr')));
      expect(rr.today, 21);
    });

    test('平時：前の 14 日の中央値、7 日未満なら比べない、帯は ±15%', () {
      final ItemSeries s = buildItemSeries('activity',
          today: _today, real: _bundle(history: _hist(<double?>[...List<double?>.filled(14, 40), 20])));
      expect(s.usual, 40);
      expect(s.diffPct, -50);
      expect(s.inBand, isFalse);

      final ItemSeries ok = buildItemSeries('activity',
          today: _today, real: _bundle(history: _hist(<double?>[...List<double?>.filled(14, 40), 44])));
      expect(ok.diffPct, 10);
      expect(ok.inBand, isTrue);

      // 偶数個の中央値・15 日より前は使わない
      final ItemSeries even = buildItemSeries('activity',
          today: _today,
          real: _bundle(history: _hist(<double?>[999, 999, 1, 2, 3, 4, 5, 6, 7, 8, null, null, null, null, null, null, 10])));
      expect(even.usual, 4.5);

      final ItemSeries few = buildItemSeries('activity',
          today: _today, real: _bundle(history: _hist(<double?>[40, 40, 40, 40, 40, 40, 30])));
      expect(few.usual, isNull);
      expect(few.diffPct, isNull);
      expect(few.inBand, isNull);
    });

    test('本物がない：値は全部なし（示例にはしない）・演示なら示例', () {
      final ItemSeries none = buildItemSeries('activity', today: _today);
      expect(none.demo, isFalse);
      expect(none.days.every((ItemDay d) => d.value == null), isTrue);
      expect(none.format(none.today), noDataValue);
      expect(none.alert, isNull);

      final ItemSeries demo = buildItemSeries('activity', today: _today, real: _bundle(history: _hist(<double?>[42])), demoAll: true);
      expect(demo.demo, isTrue);
      expect(demo.today, demoValue(_today, 'activity'));
    });

    test('1 日まとめの提醒を項目に割り当てる（皮肤は使わない）', () {
      final SummaryBundle b = _bundle(alerts: <Map<String, dynamic>>[
        _alertCat('exercise', 'exercise.alert.less', <String, dynamic>{'ratio': 0.4}),
        _alertCat('physio', 'physio.alert.up', <String, dynamic>{'metric': 'sleep_rr_median', 'value': 32}),
        _alertCat('skin', 'skin.alert.more', <String, dynamic>{'count': 30}),
      ]);
      expect(buildItemSeries('activity', today: _today, real: b).alert, '今天运动比平时少很多（大约是平时的 40%）');
      final ItemSeries srr = buildItemSeries('sleep_rr', today: _today, real: b);
      expect(srr.alert, '睡觉时呼吸比较快（32 次/分）');
      expect(srr.today, 32);
      expect(buildItemSeries('rest_hr', today: _today, real: b).alert, isNull);
      expect(buildItemSeries('scratch', today: _today, real: b).alert, demoBubble(_today, Board.skin).alert);

      final SummaryBundle rr = _bundle(alerts: <Map<String, dynamic>>[
        _alertCat('physio', 'physio.alert.up', <String, dynamic>{'metric': 'rest_rr_median', 'ratio': 1.3}),
      ]);
      expect(buildItemSeries('rr', today: _today, real: rr).alert, '安静时呼吸比平时高（平时的 1.3 倍）');
      expect(buildItemSeries('rest_hr', today: _today, real: rr).alert, isNull);
    });

    test('板块ごと：一覧の順', () {
      final List<ItemSeries> s = buildBoardSeries(Board.sleep, today: _today);
      expect(s.map((ItemSeries x) => x.item.id).toList(), <String>['sleep_time', 'sleep_rr', 'sleep_restless']);
    });
  });
}
