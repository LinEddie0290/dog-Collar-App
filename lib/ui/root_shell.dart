import 'package:flutter/material.dart';

import '../data/daily_summary.dart';
import '../l10n/app_strings.dart';
import '../state/collar_controller.dart';
import '../state/collar_link.dart';
import '../state/continuous_monitor.dart';
import '../state/locale_controller.dart';
import '../state/location_controller.dart';
import '../state/vitals_session.dart';
import 'health/health_page.dart';
import 'map_page.dart';
import 'measure_page.dart';
import 'safety/safety_page.dart';
import 'settings_page.dart';
import 'today_page.dart';
import 'vitals_history_page.dart';

/// 下のタブ（T35・D-051）：今天・健康・测定・安全・我的。
class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.controller,
    required this.localeController,
    required this.locationController,
    required this.vitalsSession,
    required this.collarLink,
    this.monitor,
    this.liveSummary,
  });

  /// 古いつなぎ方。今は地図（安全）の位置のためだけに残している（T12 で本物の GPS に替えるときに消す）。
  final CollarController controller;
  final LocaleController localeController;
  final LocationController locationController;
  final VitalsSession vitalsSession;
  final CollarLink collarLink;

  /// T34-A：記録の開始・停止と、本物のデータの毎日のまとめ。null ならデモだけ。
  final ContinuousMonitor? monitor;
  final SummarySource? liveSummary;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  /// 「测定」の記録（像心电图的波形）。測定画面の「过去的测量」と同じ画面。
  void _openRecords() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext ctx) => Scaffold(
        appBar: AppBar(title: Text(AppStringsScope.of(ctx).recordsTitle)),
        body: VitalsHistoryPage(store: widget.vitalsSession.store),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStringsScope.of(context);

    final List<Widget> pages = <Widget>[
      // 今天：白い水のホーム（T35）
      TodayPage(
        live: widget.liveSummary,
        monitor: widget.monitor,
        link: widget.collarLink,
        onOpenEcg: _openRecords,
      ),
      // 健康：六大板块 → 板块 → 項目（T35）
      HealthPage(live: widget.liveSummary, onOpenEcg: _openRecords),
      // 测定：手動の心拍測定。「首輪」と「記録」はこの画面から開く
      MeasurePage(
        session: widget.vitalsSession,
        link: widget.collarLink,
      ),
      // 安全：今の状態・地図・緊急（T35。位置は T12、緊急の判定は T34-G で本物に替える）
      SafetyPage(
        monitor: widget.monitor,
        link: widget.collarLink,
        map: MapPage(controller: widget.controller, locationController: widget.locationController),
      ),
      // 我的：狗的信息・项圈・言語・データ・开发（記録・テスト画面、每天（旧）、CNN の速さ）
      SettingsPage(
        localeController: widget.localeController,
        monitor: widget.monitor,
        link: widget.collarLink,
        liveSummary: widget.liveSummary,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), label: strings.navToday),
          NavigationDestination(icon: const Icon(Icons.favorite_outline), label: strings.navHealth),
          NavigationDestination(icon: const Icon(Icons.monitor_heart_outlined), label: strings.navMeasure),
          NavigationDestination(icon: const Icon(Icons.shield_outlined), label: strings.navSafety),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: strings.navMine),
        ],
      ),
    );
  }
}
