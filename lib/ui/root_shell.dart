import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/collar_controller.dart';
import '../state/locale_controller.dart';
import '../state/location_controller.dart';
import '../state/collar_link.dart';
import '../state/vitals_session.dart';
import 'history_page.dart';
import 'measure_page.dart';
import 'daily_summary_page.dart';
import 'home_page.dart';
import 'map_page.dart';
import 'settings_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.controller,
    required this.localeController,
    required this.locationController,
    required this.vitalsSession,
    required this.collarLink,
  });

  final CollarController controller;
  final LocaleController localeController;
  final LocationController locationController;
  final VitalsSession vitalsSession;
  final CollarLink collarLink;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStringsScope.of(context);

    final List<Widget> pages = <Widget>[
      HomePage(controller: widget.controller),
      // T23 デモ：パイプラインの 1日まとめ(每天看・提醒)。T16 で完成させる。
      DailySummaryPage(),
      MapPage(controller: widget.controller, locationController: widget.locationController),
      // 「首輪」と「記録」は測定画面から開く。タブを増やしすぎると
      // 下部ナビのラベルが潰れるため。
      MeasurePage(
        session: widget.vitalsSession,
        link: widget.collarLink,
      ),
      HistoryPage(controller: widget.controller),
      SettingsPage(
        controller: widget.controller,
        localeController: widget.localeController,
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
          NavigationDestination(icon: const Icon(Icons.home), label: strings.navHome),
          // 文言は暫定で中国語直書き(T23 D2)。3言語は T16。
          const NavigationDestination(icon: Icon(Icons.today_outlined), label: '每天'),
          NavigationDestination(icon: const Icon(Icons.map_outlined), label: strings.navMap),
          // 文言は暫定で日本語直書き。3言語対応は app_strings への追加が必要。
          const NavigationDestination(
              icon: Icon(Icons.favorite_outline), label: '測定'),
          NavigationDestination(icon: const Icon(Icons.history), label: strings.navHistory),
          NavigationDestination(icon: const Icon(Icons.settings), label: strings.navSettings),
        ],
      ),
    );
  }
}
