/// T34-G：緊急（冲击・倒下・心率异常）の見張り（D-060）。
///
/// 記録の IMU（[addSample]）と自動の心拍（[addAttempt]）から判定し、
/// 記録（安全タブ）・通知（同じ種類は [cooldown] に 1 回まで）・記録ファイル（[hitListeners]）へ渡す。
/// 走失は LocationController（T36）。
library;

import 'dart:async';

import 'package:collar_pipeline/collar_pipeline.dart' show ImuSample;
import 'package:collar_vitals/collar_vitals.dart' show VitalsQuality;
import 'package:flutter/foundation.dart';

import '../data/emergency_watch.dart';
import '../data/safety.dart' show EmergencyKind;
import '../pipeline/auto_vitals.dart';
import '../pipeline/pipeline_runner.dart';
import 'app_notifier.dart';

class EmergencyController extends ChangeNotifier {
  EmergencyController({this.notifier, MotionWatcher? motion, HeartWatcher? heart, this.cooldown = const Duration(minutes: 10)})
      : motion = motion ?? MotionWatcher(),
        heart = heart ?? HeartWatcher();

  final AppNotifier? notifier;
  final MotionWatcher motion;
  final HeartWatcher heart;
  final Duration cooldown;

  static const int maxHits = 100;

  /// 判定したもの（新しいものが先）。
  final List<EmergencyHit> hits = <EmergencyHit>[];

  /// 1 件ごとに呼ぶ（記録ファイルへ）。
  final List<void Function(EmergencyHit h)> hitListeners = <void Function(EmergencyHit h)>[];

  final Map<EmergencyKind, int> _lastNotifiedMs = <EmergencyKind, int>{};
  PipelineRunner? _runner;

  /// 記録の流れにつなぐ（ContinuousMonitor が 1 回だけ呼ぶ）。
  void attachTo(PipelineRunner r) {
    if (_runner != null) return;
    _runner = r;
    r.sampleTaps.add(addSample);
    r.autoVitals?.finishedListeners.add(addAttempt);
    hitListeners.add(r.addEmergency);
  }

  void addSample(ImuSample s) {
    final List<EmergencyHit> hs = motion.add(s);
    if (hs.isEmpty) return;
    hs.forEach(_hit);
    notifyListeners();
  }

  /// 自動の心拍測定が終わった（安静時の自動測定だけ見る）。
  void addAttempt(VitalAttempt a) {
    final double? bpm = a.heartRateBpm;
    if (a.trigger != 'auto' || a.status != AttemptStatus.done || bpm == null) return;
    addHeart(tMs: a.tStartMs, bpm: bpm, good: a.result?.quality == VitalsQuality.good);
  }

  void addHeart({required int tMs, required double bpm, required bool good, bool fake = false}) {
    final EmergencyHit? h = heart.add(tMs: tMs, bpm: bpm, good: good, fake: fake);
    if (h == null) return;
    _hit(h);
    notifyListeners();
  }

  void _hit(EmergencyHit h) {
    hits.insert(0, h);
    if (hits.length > maxHits) hits.removeLast();
    if (h.notify) {
      final int? last = _lastNotifiedMs[h.kind];
      if (last == null || h.tMs - last >= cooldown.inMilliseconds || h.tMs < last) {
        _lastNotifiedMs[h.kind] = h.tMs;
        h.notified = true;
        final (String title, String body) = switch (h.kind) {
          EmergencyKind.fall => ('可能倒下了', '${h.detail}。请马上看一下狗。'),
          EmergencyKind.heart => ('心率异常（试用）', '${h.detail}。请看一下狗的样子，需要的话联系兽医。'),
          EmergencyKind.impact || EmergencyKind.lost => (h.detail, ''),
        };
        unawaited(notifier?.show(key: 'emergency-${h.kind.name}', title: title, body: body));
      }
    }
    for (final void Function(EmergencyHit h) f in List<void Function(EmergencyHit h)>.of(hitListeners)) {
      f(h);
    }
  }

  /// 記録が止まった・始まった：倒下の候補は持ち越さない（判定したものは残す）。
  void resetWatch() => motion.reset();
}
