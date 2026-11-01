/// T34-A：首輪から IMU を流し続けて、スマホの中の処理（[PipelineRunner]）に入れる。
///
/// 心拍の手動測定（[VitalsSession]）は「測って終わり」で、終わると接続も切る。
/// 毎日のまとめには一日中のデータが要るので、こちらは「記録を始める／止める」だけを持つ。
/// 生のフレームは今までどおり [CollarLink] の FrameArchive に残る（T21）。
///
/// 今の制限（B で直す）：記録中に手動測定をすると、測定の終わりで接続が切れて記録も止まる。
library;

import 'dart:async';

import 'package:collar_data/collar_data.dart';
import 'package:flutter/foundation.dart';

import '../data/ble_collar_data_source.dart';
import '../pipeline/pipeline_runner.dart';
import 'collar_link.dart';
import 'vitals_session.dart';

class ContinuousMonitor extends ChangeNotifier {
  ContinuousMonitor({required this.link, required this.runner, this.vitals});

  final CollarLink link;
  final PipelineRunner runner;
  final VitalsSession? vitals;

  bool running = false;
  bool starting = false;
  String? errorMessage;
  DateTime? startedAt;
  StreamSubscription<PetImuSample>? _sub;

  Future<void> toggle() => running ? stop() : start();

  Future<void> start() async {
    if (running || starting) return;
    if (vitals?.isBusy ?? false) {
      errorMessage = 'busy';
      notifyListeners();
      return;
    }
    starting = true;
    errorMessage = null;
    notifyListeners();
    try {
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
      startedAt = DateTime.now();
      link.archive?.event('monitor_start', <String, Object?>{
        'started_at_ms': startedAt!.millisecondsSinceEpoch,
        'imu_rate_hz': link.activeImuRateHz,
      });
      link.addListener(_onLink);
      running = true;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  void _onLink() {
    // 首輪が離れた：取れた分は計算して残す。
    if (running && !link.isConnected) unawaited(_end(stopDevice: false));
  }

  Future<void> stop() => _end(stopDevice: true);

  Future<void> _end({required bool stopDevice}) async {
    if (!running) return;
    running = false;
    link.removeListener(_onLink);
    await _sub?.cancel();
    _sub = null;
    link.archive?.event('monitor_stop', <String, Object?>{
      'started_at_ms': startedAt?.millisecondsSinceEpoch,
      'windows': runner.windowsTotal,
    });
    notifyListeners();
    await runner.flush();
    if (stopDevice) {
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
    super.dispose();
  }
}
