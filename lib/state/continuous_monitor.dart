/// T34-A・F：入力（首輪・Unity・偽のデータ）から IMU を流し続けて、スマホの中の処理
/// （[PipelineRunner]）に入れる。
///
/// 心拍の手動測定（[VitalsSession]）は「測って終わり」で、終わると接続も切る。
/// 毎日のまとめには一日中のデータが要るので、こちらは「記録を始める／止める」だけを持つ。
/// 首輪の生のフレームは今までどおり [CollarLink] の FrameArchive に残る（T21）。
///
/// 今の制限（B で直す）：首輪で記録中に手動測定をすると、測定の終わりで接続が切れて記録も止まる。
library;

import 'dart:async';
import 'dart:convert';

import 'package:collar_data/collar_data.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ble_collar_data_source.dart';
import '../pipeline/imu_input.dart';
import '../pipeline/pipeline_runner.dart';
import '../pipeline/test_subject.dart';
import 'collar_link.dart';
import 'vitals_session.dart';

typedef ImuInputFactory = ImuInput Function(InputKind kind, ContinuousMonitor m);

ImuInput _defaultFactory(InputKind kind, ContinuousMonitor m) => kind == InputKind.unity
    ? UnityImuInput(m.unityUrl)
    : FakeImuInput(speed: m.fakeSpeed);

class ContinuousMonitor extends ChangeNotifier {
  ContinuousMonitor({required this.link, required this.runner, this.vitals, ImuInputFactory? inputFactory})
      : _factory = inputFactory ?? _defaultFactory;

  final CollarLink link;
  final PipelineRunner runner;
  final VitalsSession? vitals;
  final ImuInputFactory _factory;

  static const String _kKind = 'monitor.input';
  static const String _kUrl = 'monitor.unity_url';
  static const String _kSpeed = 'monitor.fake_speed';
  static const String _kSubject = 'monitor.subject';

  /// 入力の選び方（F）。止めているときだけ変えられる。
  InputKind kind = InputKind.collar;
  String unityUrl = 'ws://192.168.1.96:8765/imu'; // 10/26 に正轩とつないだときのアドレス
  double fakeSpeed = 1;

  /// E：試験の犬の情報。記録の頭に入れる。
  TestSubject subject = const TestSubject();

  bool running = false;
  bool starting = false;
  String? errorMessage;
  DateTime? startedAt;
  InputKind? runningKind;
  StreamSubscription<PetImuSample>? _sub;
  ImuInput? _input;
  StreamSubscription<ImuSample>? _inSub;
  StreamSubscription<TruthMark>? _markSub;

  /// 今動いている BLE 以外の入力（テスト画面・バー用）。
  ImuInput? get input => _input;

  Future<void> loadSaved() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? k = p.getString(_kKind);
      kind = InputKind.values.firstWhere((InputKind x) => x.name == k, orElse: () => InputKind.collar);
      unityUrl = p.getString(_kUrl) ?? unityUrl;
      fakeSpeed = p.getDouble(_kSpeed) ?? fakeSpeed;
      final String? sj = p.getString(_kSubject);
      if (sj != null) subject = TestSubject.fromJson(jsonDecode(sj) as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {
      // 読めなくても既定のまま使える
    }
  }

  Future<void> setInput({InputKind? kind, String? unityUrl, double? fakeSpeed}) async {
    if (running || starting) return;
    this.kind = kind ?? this.kind;
    this.unityUrl = unityUrl ?? this.unityUrl;
    this.fakeSpeed = fakeSpeed ?? this.fakeSpeed;
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_kKind, this.kind.name);
      await p.setString(_kUrl, this.unityUrl);
      await p.setDouble(_kSpeed, this.fakeSpeed);
    } catch (_) {
      // 保存できなくても今回は使える
    }
  }

  /// E：犬の情報を変える。記録中なら今の記録にも書き足す。
  Future<void> setSubject(TestSubject s) async {
    subject = s;
    runner.sessionInfo = <String, Object?>{...runner.sessionInfo, 'subject': s.toJson()};
    if (running) runner.updateInfo();
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_kSubject, jsonEncode(s.toJson()));
    } catch (_) {
      // 保存できなくても今回は使える
    }
  }

  Future<void> toggle() => running ? stop() : start();

  Future<void> start() async {
    if (running || starting) return;
    starting = true;
    errorMessage = null;
    runner.sessionInfo = <String, Object?>{
      'input': kind.name,
      'subject': subject.toJson(),
      if (kind == InputKind.unity) 'unity_url': unityUrl,
      if (kind == InputKind.fake) 'fake_speed': fakeSpeed,
    };
    notifyListeners();
    try {
      if (kind == InputKind.collar) {
        await _startCollar();
      } else {
        await _startInput();
      }
      if (errorMessage == null) {
        running = true;
        runningKind = kind;
        startedAt = DateTime.now();
      }
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> _startCollar() async {
    if (vitals?.isBusy ?? false) {
      errorMessage = 'busy';
      return;
    }
    if (!link.isConnected) {
      await link.connect(remoteId: link.selectedRemoteId);
      if (!link.isConnected) {
        errorMessage = link.errorMessage ?? 'connect_failed';
        return;
      }
    }
    final BleCollarDataSource? src = link.source;
    final Stream<PetImuSample>? imu = link.imuSamples;
    if (src == null || imu == null) {
      errorMessage = 'link_lost';
      return;
    }
    try {
      await src.startStreaming();
    } on Exception catch (e) {
      errorMessage = 'start_failed|$e';
      return;
    }
    _sub = imu.listen(runner.addPet);
    link.archive?.event('monitor_start', <String, Object?>{
      'started_at_ms': DateTime.now().millisecondsSinceEpoch,
      'imu_rate_hz': link.activeImuRateHz,
    });
    link.addListener(_onLink);
  }

  Future<void> _startInput() async {
    final ImuInput input = _factory(kind, this);
    _input = input;
    _inSub = input.samples.listen(runner.add);
    _markSub = input.marks.listen(runner.addTruth);
    input.addListener(notifyListeners);
    try {
      await input.start();
    } on Object catch (e) {
      errorMessage = input.error ?? 'start_failed|$e';
      await _closeInput();
    }
  }

  Future<void> _closeInput() async {
    final ImuInput? input = _input;
    _input = null;
    if (input == null) return;
    await input.stop(); // 偽のデータは止めるときに残りを出す → 下の購読を外す前に
    await Future<void>.delayed(Duration.zero); // 出した分が runner に届くまで待つ
    await _inSub?.cancel();
    await _markSub?.cancel();
    _inSub = null;
    _markSub = null;
    input.removeListener(notifyListeners);
    input.dispose();
  }

  void _onLink() {
    // 首輪が離れた：取れた分は計算して残す。
    if (running && runningKind == InputKind.collar && !link.isConnected) unawaited(_end(stopDevice: false));
  }

  Future<void> stop() => _end(stopDevice: true);

  Future<void> _end({required bool stopDevice}) async {
    if (!running) return;
    running = false;
    final InputKind? k = runningKind;
    runningKind = null;
    if (k == InputKind.collar) {
      link.removeListener(_onLink);
      await _sub?.cancel();
      _sub = null;
      link.archive?.event('monitor_stop', <String, Object?>{
        'started_at_ms': startedAt?.millisecondsSinceEpoch,
        'windows': runner.windowsTotal,
      });
    } else {
      await _closeInput();
    }
    notifyListeners();
    await runner.flush();
    if (stopDevice && k == InputKind.collar) {
      try {
        await link.source?.stopCollecting();
      } on Exception {
        // もう切れている
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    link.removeListener(_onLink);
    _sub?.cancel();
    _inSub?.cancel();
    _markSub?.cancel();
    _input?.dispose();
    super.dispose();
  }
}
