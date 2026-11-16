// T35「安全」タブの画面。
import 'package:collar_app/data/safe_zone.dart';
import 'package:collar_app/data/safety.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/emergency_controller.dart';
import 'package:collar_app/state/location_controller.dart';
import 'package:collar_app/ui/safety/safety_page.dart';
import 'package:flutter/material.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-11-05（木）の昼（UTC＋8 で 12 時）。この日までの 7 日の示例：11/01 冲击・10/30 走失。
DateTime _clock() => DateTime.utc(2026, 11, 5, 4);

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void _tall(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('今の状態・地図の案内・緊急の 4 項目・最近 7 日の記録', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SafetyPage(clock: _clock))));
    await tester.pumpAndSettle();

    expect(find.descendant(of: _key('safety-status'), matching: find.text('没有在记录')), findsOneWidget);
    expect(find.text('位置：还没有（GPS 还没定位）'), findsOneWidget);
    expect(find.text('安全区：还没设（在地图上长按）'), findsOneWidget);
    expect(_key('safety-stale'), findsNothing);
    expect(find.textContaining('需要设置高德地图'), findsOneWidget);
    for (final EmergencyKind k in EmergencyKind.values) {
      expect(_key('emergency-${k.name}'), findsOneWidget, reason: k.name);
    }
    expect(_key('event-2026-11-01-impact'), findsOneWidget);
    expect(_key('event-2026-10-30-lost'), findsOneWidget);
    expect(find.text('最近 7 天没有紧急情况'), findsNothing);
  });

  testWidgets('首輪の表示（つながっていない）と、渡した地図', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SafetyPage(link: CollarLink(), clock: _clock, map: const SizedBox(key: ValueKey<String>('my-map'))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('项圈未连接・没有在记录'), findsOneWidget);
    expect(_key('my-map'), findsOneWidget);
    expect(find.textContaining('需要设置高德地图'), findsNothing);
  });

  testWidgets('緊急の項目を押す → 怎么判断・看什么… と、その項目の記録', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SafetyPage(clock: _clock))));
    await tester.pumpAndSettle();

    await tester.tap(_key('emergency-impact'));
    await tester.pumpAndSettle();
    expect(_key('emergency-page-impact'), findsOneWidget);
    expect(find.text('怎么判断'), findsOneWidget);
    expect(find.text(emergencySpec(EmergencyKind.impact).how), findsOneWidget);
    expect(_key('event-2026-11-01-impact'), findsOneWidget);
    expect(_key('event-2026-10-30-lost'), findsNothing); // ほかの項目の記録は出さない
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(_key('emergency-fall'));
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天没有'), findsOneWidget);
  });

  testWidgets('記録がない週は「没有紧急情况」', (WidgetTester tester) async {
    _tall(tester);
    // 示例の記録がない週を探す（9 月〜10 月のどこか。Python で同じ計算をすると 2026-09-30 まで）
    String? quiet;
    for (int d = 0; d < 60 && quiet == null; d++) {
      final DateTime t = DateTime.utc(2026, 9, 1).add(Duration(days: d));
      final String key = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      if (demoEmergencyEvents(key).isEmpty) quiet = key;
    }
    expect(quiet, isNotNull);
    final DateTime q = DateTime.parse('${quiet!}T04:00:00Z');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafetyPage(clock: () => q))));
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天没有紧急情况'), findsOneWidget);
  });

  testWidgets('T36：外に出て BLE が切れた → 位置は「可能走失」、走失の記録は本物（示例の走失は出さない）', (WidgetTester tester) async {
    _tall(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final int nowMs = _clock().millisecondsSinceEpoch;
    const GeoPoint home = GeoPoint(31.2304, 121.4737);
    final LocationController lc = LocationController(nowMs: () => nowMs, tick: null);
    addTearDown(lc.dispose);
    await lc.setHome(home, 100);
    final int t = nowMs - 60000;
    for (final double m in <double>[10, 200, 210]) {
      lc.addFix(LocationFix(point: offsetPoint(home, m, 0), tMs: t));
    }
    lc.setLinked(false);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafetyPage(clock: _clock, location: lc))));
    await tester.pumpAndSettle();
    expect(find.text('位置：可能走失！最后在离家 210 m 的地方（1 分钟前）'), findsOneWidget);
    expect(find.text('安全区：家（半径 100 m）'), findsOneWidget);
    expect(_key('event-zone-$nowMs-lost'), findsOneWidget);
    expect(_key('event-zone-$t-exit'), findsOneWidget);
    expect(_key('event-2026-10-30-lost'), findsNothing); // 示例の走失は消える
    expect(_key('event-2026-11-01-impact'), findsOneWidget); // ほかは示例のまま
    expect(find.descendant(of: _key('emergency-lost'), matching: find.text('实际')), findsOneWidget);
    expect(find.descendant(of: _key('emergency-impact'), matching: find.text('示例')), findsOneWidget);

    // つながって家に戻った
    lc.setLinked(true);
    lc.addFix(LocationFix(point: home, tMs: nowMs));
    await tester.pumpAndSettle();
    expect(find.textContaining('位置：在家（安全区里）'), findsOneWidget);
  });

  testWidgets('T34-G：緊急の見張りがあると冲击・倒下・心率は实际（記録は本物だけ）、走失は示例のまま', (WidgetTester tester) async {
    _tall(tester);
    final int nowMs = _clock().millisecondsSinceEpoch;
    final EmergencyController em = EmergencyController();
    addTearDown(em.dispose);
    em.addHeart(tMs: nowMs - 120000, bpm: 190, good: true);
    em.addHeart(tMs: nowMs - 60000, bpm: 195, good: true);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafetyPage(clock: _clock, emergency: em))));
    await tester.pumpAndSettle();
    for (final EmergencyKind k in <EmergencyKind>[EmergencyKind.fall, EmergencyKind.heart, EmergencyKind.impact]) {
      expect(find.descendant(of: _key('emergency-${k.name}'), matching: find.text('实际')), findsOneWidget, reason: k.name);
    }
    expect(find.descendant(of: _key('emergency-lost'), matching: find.text('示例')), findsOneWidget);
    expect(find.text('走失是示例，其他是实际的'), findsOneWidget);
    expect(_key('event-hit-${nowMs - 60000}-heart'), findsOneWidget);
    expect(find.textContaining('安静时心率 195 次/分'), findsOneWidget);
    expect(_key('event-2026-11-01-impact'), findsNothing); // 冲击の示例は消える
    expect(_key('event-2026-10-30-lost'), findsOneWidget); // 走失は示例のまま

    await tester.tap(_key('emergency-heart'));
    await tester.pumpAndSettle();
    expect(find.text('实际（试用：自动测的心率还在验证）'), findsOneWidget);
    expect(_key('event-hit-${nowMs - 60000}-heart'), findsOneWidget);
  });

  testWidgets('幅 320 でもはみ出さない', (WidgetTester tester) async {
    _tall(tester, width: 320);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SafetyPage(clock: _clock))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_key('emergency-heart'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
