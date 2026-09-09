// アプリが起動してホーム画面(ボトムナビゲーション含む)が描画されることだけを
// 確認する簡単なスモークテスト。
//
// package:collar_data 側の詳細な動作確認は packages/collar_data 側のテストに
// 任せ、ここではUIが例外なく組み上がることだけを見る。

import 'package:flutter_test/flutter_test.dart';

import 'package:collar_app/main.dart';

void main() {
  testWidgets('CollarApp starts and shows the bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const CollarApp());
    await tester.pump();

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('履歴'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
  });
}
