// T23「每天」画面のテスト(設計メモ T23 8章)。
import 'dart:convert';

import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/l10n/summary_text.dart';
import 'package:collar_app/ui/daily_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final String? s = files[key];
    if (s == null) {
      throw FlutterError('missing $key');
    }
    return ByteData.view(Uint8List.fromList(utf8.encode(s)).buffer);
  }
}

Map<String, dynamic> _cat(String id, String status, {Map<String, dynamic>? alert, Map<String, dynamic>? daily, int? wait}) =>
    <String, dynamic>{
      'id': id,
      'status': status,
      'alert': alert,
      'daily': daily,
      'days_until_compare': ?wait,
    };

String _day(String date, {String status = 'ok', bool skinAlert = false, int? wait}) => jsonEncode(<String, dynamic>{
      'schema': 'collar.daily_summary/0.1',
      'dog_id': 'dog_sim01',
      'date': date,
      'generated_at': '2026-10-14T22:59:03+08:00',
      'categories': <dynamic>[
        _cat('exercise', status,
            daily: <String, dynamic>{'text_key': 'exercise.daily', 'values': <String, dynamic>{'active_min': 56}},
            wait: wait),
        _cat('sleep', status,
            daily: <String, dynamic>{
              'text_key': 'sleep.daily',
              'values': <String, dynamic>{'sleep_min': 523, 'quality': 'good'}
            },
            wait: wait),
        _cat('skin', status,
            alert: skinAlert
                ? <String, dynamic>{
                    'level': 'notice',
                    'text_key': 'skin.alert.more',
                    'values': <String, dynamic>{'metric': 'itch_count', 'ratio': 2.4, 'count': 24}
                  }
                : null,
            wait: wait),
        _cat('physio', status,
            daily: <String, dynamic>{'text_key': 'physio.daily', 'values': <String, dynamic>{'rest_hr': 90, 'rest_rr': 19}},
            wait: wait),
      ],
    });

const String _base = 'assets/demo/dog_sim01';

_MapBundle _bundle({bool broken = false}) => _MapBundle(<String, String>{
      '$_base/index.json': jsonEncode(<String, dynamic>{
        'dog_id': 'dog_sim01',
        'dates': <String>['2026-10-01', '2026-10-02', '2026-10-03', if (broken) '2026-10-04'],
      }),
      '$_base/summary/2026-10-01.json': _day('2026-10-01', status: 'collecting', wait: 9),
      '$_base/summary/2026-10-02.json': _day('2026-10-02'),
      '$_base/summary/2026-10-03.json': _day('2026-10-03', skinAlert: true),
      if (broken) '$_base/summary/2026-10-04.json': '{ this is not json',
      '$_base/history.json': jsonEncode(<String, dynamic>{
        'days': <dynamic>[
          for (final String d in <String>['2026-10-01', '2026-10-02', '2026-10-03'])
            <String, dynamic>{'date': d, 'valid_day': true, 'active_min': 56, 'sleep_min': 500, 'rest_hr': 90},
        ],
      }),
    });

void main() {
  const SummaryTextZh t = SummaryTextZh();

  test('提醒のあるカードが先に来る', () {
    final DailySummary s =
        DailySummary.fromJson(jsonDecode(_day('2026-10-03', skinAlert: true)) as Map<String, dynamic>);
    expect(s.alertCount, 1);
    expect(s.ordered.first.id, 'skin');
  });

  test('文言：知らないキーはそのまま、提醒に倍率が入る', () {
    expect(t.daily(const TextItem(textKey: 'zzz.unknown', values: <String, dynamic>{})), 'zzz.unknown');
    final String a = t.alert(const TextItem(
        textKey: 'skin.alert.more', values: <String, dynamic>{'ratio': 2.4, 'count': 24}));
    expect(a, contains('2.4'));
    expect(a, contains('24'));
    expect(t.daily(const TextItem(textKey: 'sleep.daily', values: <String, dynamic>{'sleep_min': 523})),
        contains('8 小时 43 分钟'));
  });

  test('壊れた JSON の日は「読めない」で、ほかの日は読める', () async {
    final SummaryBundle b = await DemoSummaryRepository(bundle: _bundle(broken: true)).load();
    expect(b.days.length, 4);
    expect(b.days[3].summary, isNull);
    expect(b.days[3].error, isNotNull);
    expect(b.days[2].summary!.alertCount, 1);
    expect(b.history.length, 3);
  });

  testWidgets('最新の日に提醒、前の日へ動かせる', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DailySummaryPage(repository: DemoSummaryRepository(bundle: _bundle()))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 3 天'), findsOneWidget);
    expect(find.textContaining('挠和舔比平时多很多'), findsOneWidget);
    expect(find.text(t.notDiagnosis), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('prev-day')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 天'), findsOneWidget);
    expect(find.textContaining('挠和舔比平时多很多'), findsNothing);
    expect(find.text(t.skinOk), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('prev-day')));
    await tester.pumpAndSettle();
    expect(find.textContaining('还要 9 天'), findsWidgets);
  });
}
