// T43（D-065）：声の結果 → 記録ファイル → 1 日まとめ → 健康タブ。声のテストのカード。
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/data/daily_summary.dart';
import 'package:collar_app/data/health_series.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/pipeline/pipeline_summary_repository.dart';
import 'package:collar_app/sound/sound_events.dart';
import 'package:collar_app/ui/sound_test_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _t0 = 1762650000000; // 2025-11-09 01:00 UTC（当地 09:00）

const List<SoundEvent> _ev = <SoundEvent>[
  SoundEvent(startMs: 1440, endMs: 4320, cls: 'bark', prob: 0.472),
  SoundEvent(startMs: 6000, endMs: 7440, cls: 'whine', prob: 0.31),
];

void main() {
  test('記録ファイル（sound の行）→ 1 日まとめに種類ごとの回数 → 健康タブの吠叫・呜咽', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('t43');
    addTearDown(() => tmp.delete(recursive: true));
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    await store.startSession('s1', <String, Object?>{'started_ms': _t0});
    await store.appendWindows('s1', <WindowResult>[
      for (int i = 0; i < 60; i++)
        WindowResult(tDevUs: i * 1000000, tMs: _t0 + i * 1000, activity: 0.01, label: 'still', prob: 0.9),
    ]);
    for (final SoundEvent e in _ev) {
      await store.appendSound('s1', e, _t0, source: 'test_wav');
    }
    await store.appendSound('s1', _ev.first, _t0 + 10000);
    await store.idle();
    final String dir = (await store.dir()).path;
    final List<String> lines = File('$dir/s1.jsonl').readAsLinesSync();
    final Map<String, dynamic> row =
        jsonDecode(lines.firstWhere((String l) => l.contains('"sound"'))) as Map<String, dynamic>;
    expect(row, <String, dynamic>{
      'rec': 'sound',
      't_ms': _t0 + 1440,
      'end_ms': _t0 + 4320,
      'class': 'bark',
      'prob': 0.472,
      'src': 'test_wav',
    });
    expect(loadSessionsFrom(dir).single.sounds.length, 3);

    final Map<String, dynamic> j = jsonDecode(buildSummaryData(dir, 'my_dog', 'gen')) as Map<String, dynamic>;
    final Map<String, dynamic> raw = (j['raw'] as Map<String, dynamic>)['2025-11-09'] as Map<String, dynamic>;
    expect(raw['sound_bark'], 2);
    expect(raw['sound_whine'], 1);
    expect(raw.containsKey('sound_growl'), isFalse);

    final SummaryBundle b = SummaryBundle(
      dogId: 'my_dog',
      days: const <DayEntry>[],
      history: const <HistoryDay>[],
      raw: <String, Map<String, double>>{
        '2025-11-09': <String, double>{for (final MapEntry<String, dynamic> e in raw.entries) e.key: (e.value as num).toDouble()},
      },
    );
    final ItemSeries bark = buildItemSeries('bark', today: '2025-11-09', real: b);
    expect(bark.demo, isFalse);
    expect(bark.item.trial, isTrue);
    expect(bark.today, 2);
    expect(buildItemSeries('whine', today: '2025-11-09', real: b).today, 1);
    expect(buildItemSeries('howl', today: '2025-11-09', real: b).today, isNull); // 記録がない種類は「没有数据」
  });

  testWidgets('声のテストのカード：押すと結果が出る。記録していなければ保存しない', (WidgetTester tester) async {
    final PipelineRunner r = PipelineRunner();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SoundTestCard(runner: r, run: () async => _ev, nowMs: () => _t0)),
    ));
    await tester.tap(find.byKey(const ValueKey<String>('sound-test-run')));
    await tester.pumpAndSettle();
    expect(find.text('吠叫　1.44–4.32 秒　0.47'), findsOneWidget);
    expect(find.text('呜咽　6.00–7.44 秒　0.31'), findsOneWidget);
    expect(find.text('没有在记录（只显示，不保存）'), findsOneWidget);
  });

  testWidgets('声のテストのカード：うまくいかないときはエラーの文', (WidgetTester tester) async {
    final PipelineRunner r = PipelineRunner();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SoundTestCard(runner: r, run: () async => throw StateError('no model'))),
    ));
    await tester.tap(find.byKey(const ValueKey<String>('sound-test-run')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('sound-test-error')), findsOneWidget);
  });
}
