// T19：地図の緯度・経度の表示（設計メモ T19 8章）。
import 'package:collar_app/l10n/app_language.dart';
import 'package:collar_app/l10n/app_strings.dart';
import 'package:collar_app/ui/app_colors.dart';
import 'package:collar_app/ui/map_page.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  final AppStrings s = AppStrings.forLanguage(AppLanguage.ja);
  const GeoPoint p = GeoPoint(31.2304, 121.4737);

  test('表示の形：小数 5 桁', () {
    expect(formatLatLng(p), '31.23040, 121.47370');
    expect(formatLatLng(const GeoPoint(-33.8688197, 151.2092955)), '-33.86882, 151.20930');
  });

  testWidgets('精度なし：緯度・経度だけ出る', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(PositionChip(position: p, accuracyM: null, stale: false, strings: s)));
    expect(find.text('31.23040, 121.47370'), findsOneWidget);
    expect(find.textContaining('±'), findsNothing);
  });

  testWidgets('精度あり：精度と緯度・経度の 2 行', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(PositionChip(position: p, accuracyM: 8, stale: false, strings: s)));
    expect(find.text(s.gpsAccuracyLabel(8)), findsOneWidget);
    expect(find.text('31.23040, 121.47370'), findsOneWidget);
  });

  testWidgets('オフライン：数字が薄い色になる', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(PositionChip(position: p, accuracyM: 8, stale: true, strings: s)));
    final Text t = tester.widget<Text>(find.byKey(PositionChip.coordsKey));
    expect(t.style?.color, AppColors.textFaint);
  });

  testWidgets('3 言語とも崩れない（コピーの文言がある）', (WidgetTester tester) async {
    for (final AppLanguage lang in AppLanguage.values) {
      final AppStrings ls = AppStrings.forLanguage(lang);
      expect(ls.coordsCopied, contains('WGS84'));
      await tester.pumpWidget(_wrap(PositionChip(position: p, accuracyM: 12, stale: false, strings: ls)));
      expect(tester.takeException(), isNull);
    }
  });
}
