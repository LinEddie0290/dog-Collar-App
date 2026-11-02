import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'state/collar_controller.dart';
import 'state/locale_controller.dart';
import 'data/measurement_store.dart';
import 'state/location_controller.dart';
import 'state/collar_link.dart';
import 'state/vitals_session.dart';
import 'state/continuous_monitor.dart';
import 'pipeline/auto_vitals.dart';
import 'pipeline/pipeline_runner.dart';
import 'data/measurement_record.dart';
import 'pipeline/pipeline_store.dart';
import 'pipeline/pipeline_summary_repository.dart';
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
  final MeasurementStore _measurementStore = MeasurementStore();
  final CollarLink _collarLink = CollarLink();
  late final VitalsSession _vitalsSession;
  // T34-A：スマホの中の処理の流れ（受けた IMU → 毎日のまとめ）
  final PipelineStore _pipelineStore = PipelineStore();
  // T34-B：記録の中のデータから心拍を測る（自動・記録中の手動）
  final AutoVitals _autoVitals = AutoVitals();
  late final PipelineRunner _pipelineRunner = PipelineRunner(store: _pipelineStore, autoVitals: _autoVitals);
  late final ContinuousMonitor _monitor;
  late final PipelineSummaryRepository _liveSummary;
  bool _amapInitialized = false;

  @override
  void initState() {
    super.initState();
    _locationController = LocationController(collar: _controller);
    _vitalsSession =
        VitalsSession(
      store: _measurementStore,
      link: _collarLink,
      blockedReason: () => _monitor.running ? '正在记录：请在测试画面（📊）按「现在测」，不会断开' : null,
    );
    // 測れた（品質が悪いのも含む）ら、今の測定の履歴にも入れる（D-050 B3）
    _autoVitals.finishedListeners.add((VitalAttempt a) {
      final r = a.result;
      if (a.status != AttemptStatus.done || r == null) return;
      unawaited(_measurementStore
          .save(MeasurementRecord.fromResult(
            startedAt: DateTime.fromMillisecondsSinceEpoch(a.tStartMs),
            result: r,
            sampleCount: a.samples,
            imuRateHz: a.fs?.round(),
            note: a.trigger == 'auto' ? '自动测量（记录中，安静 30 秒后）・${a.sensor}' : '记录中手动测量・${a.sensor}',
          ))
          .catchError((Object _) {}));
    });
    _monitor = ContinuousMonitor(link: _collarLink, runner: _pipelineRunner, vitals: _vitalsSession);
    _liveSummary = PipelineSummaryRepository(store: _pipelineStore, changes: _pipelineRunner.dataVersion);
    unawaited(_collarLink.loadKnown());
    unawaited(_localeController.loadSaved());
    unawaited(_monitor.loadSaved());
  }

  @override
  void dispose() {
    _controller.dispose();
    _localeController.dispose();
    _locationController.dispose();
    _monitor.dispose();
    _pipelineRunner.dispose();
    _autoVitals.dispose();
    _vitalsSession.dispose();
    _collarLink.dispose();
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
            vitalsSession: _vitalsSession,
            collarLink: _collarLink,
            monitor: _monitor,
            liveSummary: _liveSummary,
          ),
        );
      },
    );
  }
}
