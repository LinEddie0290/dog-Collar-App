// アプリが起動して、下のタブ（T35：今天・健康・测定・安全・我的）が出ることと、
// 「我的 → 开发」から記録・テストの画面が開けることを確かめる簡単なスモークテスト。
//
// package:collar_data 側の詳細な動作確認は packages/collar_data 側のテストに
// 任せ、ここではUIが例外なく組み上がることだけを見る。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:collar_app/main.dart';

void main() {
  testWidgets('CollarApp starts and shows the 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const CollarApp());
    await tester.pump();

    // 言語の初期値は日本語
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('健康'), findsOneWidget);
    expect(find.text('測定'), findsOneWidget);
    expect(find.text('安全'), findsOneWidget);
    expect(find.text('マイ'), findsOneWidget);
    // 古いタブは無い
    expect(find.text('ホーム'), findsNothing);
    expect(find.text('履歴'), findsNothing);
    // 最初は「今天」（仮の画面）
    expect(find.byKey(const ValueKey<String>('today-page')), findsOneWidget);
  });

  // IndexedStack は隠れているタブのアニメーションも動かし続ける（健康の「読み込み中」のくるくるなど。
  // テストでは本物のデータが読み終わらない）ので、
  // pumpAndSettle は終わらない。決まった時間だけ進める。
  testWidgets('我的 → 开发 → 记录・测试 で記録バーが出る', (WidgetTester tester) async {
    await tester.pumpWidget(const CollarApp());
    await tester.pump();

    await tester.tap(find.text('マイ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final Finder open = find.byKey(const ValueKey<String>('open-recording'));
    await tester.scrollUntilVisible(open, 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey<String>('open-cnn-bench')), findsOneWidget);
    await tester.tap(open);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey<String>('monitor-bar')), findsOneWidget);
    expect(find.text('开始记录'), findsOneWidget);
  });
}
