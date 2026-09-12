import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'state/collar_controller.dart';
import 'state/locale_controller.dart';
import 'state/location_controller.dart';
import 'ui/amap_init.dart';
import 'ui/root_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const CollarApp());
}

class CollarApp extends StatefulWidget {
  const CollarApp({super.key});

  @override
  State<CollarApp> createState() => _CollarAppState();
}

class _CollarAppState extends State<CollarApp> {
  final CollarController _controller = CollarController();
  final LocaleController _localeController = LocaleController();
  late final LocationController _locationController;
  bool _amapInitialized = false;

  @override
  void initState() {
    super.initState();
    _locationController = LocationController(collar: _controller);
    unawaited(_localeController.loadSaved());
  }

  @override
  void dispose() {
    _controller.dispose();
    _localeController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 高徳地図 SDK の初期化は BuildContext が要るので、ここで一度だけ呼ぶ。
    // API キーが未設定 (isAmapConfigured == false) の間は呼ばない —
    // amap_init.dart の説明どおり、プレースホルダーキーで SDK を呼ぶと
    // エラーになる可能性があるため。
    if (!_amapInitialized && isAmapConfigured) {
      _amapInitialized = true;
      initAmap(context);
    }

    return AnimatedBuilder(
      animation: _localeController,
      builder: (BuildContext context, Widget? _) {
        final AppStrings strings = AppStrings.forLanguage(_localeController.language);
        return MaterialApp(
          title: strings.appTitle,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: Locale(_localeController.language.code),
          supportedLocales: const <Locale>[
            Locale('ja'),
            Locale('en'),
            Locale('zh'),
          ],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (BuildContext context, Widget? child) {
            return AppStringsScope(
              language: _localeController.language,
              child: child!,
            );
          },
          home: RootShell(
            controller: _controller,
            localeController: _localeController,
            locationController: _locationController,
          ),
        );
      },
    );
  }
}
