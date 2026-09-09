import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/collar_controller.dart';
import '../state/locale_controller.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'settings_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.controller,
    required this.localeController,
  });

  final CollarController controller;
  final LocaleController localeController;

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
          NavigationDestination(icon: const Icon(Icons.history), label: strings.navHistory),
          NavigationDestination(icon: const Icon(Icons.settings), label: strings.navSettings),
        ],
      ),
    );
  }
}
