// T35「我的」タブ：狗的信息（编辑）・项圈・自動測定・言語・开发。
import 'package:collar_app/l10n/app_language.dart';
import 'package:collar_app/l10n/app_strings.dart';
import 'package:collar_app/pipeline/auto_vitals.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/continuous_monitor.dart';
import 'package:collar_app/state/locale_controller.dart';
import 'package:collar_app/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// アプリと同じく AppStringsScope で包む（我的は言語の文言を使う）。
Widget _app(Widget body) => MaterialApp(
      builder: (BuildContext context, Widget? child) => AppStringsScope(language: AppLanguage.ja, child: child!),
      home: Scaffold(body: body),
    );

void _tall(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

({ContinuousMonitor m, AutoVitals av, CollarLink link}) _setup() {
  final AutoVitals av = AutoVitals();
  final PipelineRunner r = PipelineRunner(loadClassifier: () async => throw StateError('使わない'), autoVitals: av);
  final CollarLink link = CollarLink();
  return (m: ContinuousMonitor(link: link, runner: r), av: av, link: link);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('狗的信息：まだ名前がない → 修改で入れると、記録の Subject も変わる', (WidgetTester tester) async {
    _tall(tester);
    final ({ContinuousMonitor m, AutoVitals av, CollarLink link}) s = _setup();
    await tester.pumpWidget(_app(SettingsPage(localeController: LocaleController(), monitor: s.m, link: s.link)));
    await tester.pumpAndSettle();
    expect(find.text('还没有填狗的名字'), findsOneWidget);
    expect(find.textContaining('喉咙下面（前）'), findsOneWidget); // 首輪の位置の初期値

    await tester.tap(_key('mine-dog-edit'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('subject-name'), '小白');
    await tester.enterText(_key('subject-breed'), '柴犬');
    await tester.enterText(_key('subject-weight'), '9.2');
    await tester.tap(_key('subject-save'));
    await tester.pumpAndSettle();

    expect(s.m.subject.name, '小白');
    expect(s.m.subject.weightKg, 9.2);
    expect(find.descendant(of: _key('mine-dog'), matching: find.text('小白')), findsOneWidget);
    expect(find.textContaining('柴犬・9.2 kg'), findsOneWidget);
  });

  testWidgets('项圈：接続していない・自動測定のオン／オフ・センサー', (WidgetTester tester) async {
    _tall(tester);
    final ({ContinuousMonitor m, AutoVitals av, CollarLink link}) s = _setup();
    await tester.pumpWidget(_app(SettingsPage(localeController: LocaleController(), monitor: s.m, link: s.link)));
    await tester.pumpAndSettle();
    expect(find.text('没有连接（选择项圈）'), findsOneWidget);

    expect(s.av.enabled, isTrue);
    await tester.tap(_key('mine-vitals-auto'));
    await tester.pumpAndSettle();
    expect(s.av.enabled, isFalse);
    expect(tester.widget<Switch>(_key('mine-vitals-auto')).value, isFalse);

    expect(s.av.sensor, 'front');
    await tester.tap(_key('mine-sensor-side'));
    await tester.pumpAndSettle();
    expect(s.av.sensor, 'side');
    expect(tester.widget<ChoiceChip>(_key('mine-sensor-side')).selected, isTrue);
  });

  testWidgets('言語を変えられる・开发の 3 つ', (WidgetTester tester) async {
    _tall(tester);
    final ({ContinuousMonitor m, AutoVitals av, CollarLink link}) s = _setup();
    final LocaleController lc = LocaleController();
    await tester.pumpWidget(_app(SettingsPage(localeController: lc, monitor: s.m, link: s.link, liveSummary: null)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppLanguage.zh.nativeName));
    await tester.pumpAndSettle();
    expect(lc.language, AppLanguage.zh);
    expect(_key('open-recording'), findsOneWidget);
    expect(_key('open-cnn-bench'), findsOneWidget);
    expect(_key('open-daily-old'), findsNothing); // 本物の 1 日まとめがないときは出さない
  });

  testWidgets('記録・首輪がないとき：狗的信息・项圈の欄を出さない', (WidgetTester tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(SettingsPage(localeController: LocaleController())));
    await tester.pumpAndSettle();
    expect(_key('mine-dog'), findsNothing);
    expect(_key('mine-collar-select'), findsNothing);
    expect(_key('open-recording'), findsNothing);
    expect(_key('open-cnn-bench'), findsOneWidget);
  });

  testWidgets('幅 320 でもはみ出さない', (WidgetTester tester) async {
    _tall(tester, width: 320);
    final ({ContinuousMonitor m, AutoVitals av, CollarLink link}) s = _setup();
    await tester.pumpWidget(_app(SettingsPage(localeController: LocaleController(), monitor: s.m, link: s.link)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
