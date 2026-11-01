import 'dart:typed_data';

import 'package:collar_imu_cnn/collar_imu_cnn.dart';

import 'events.dart';
import 'preprocess.dart';

/// collar/judge/cnn.py の predict_windows と同じ：前処理の窓 → CNN のラベルと確率。
/// モデルは collar-pipeline の scripts/export_cnn.py が出す JSON（assets/models/cnn_imu_v1.json）。
class WindowClassifier {
  WindowClassifier(this.model, this.channels, {this.minProb, this.synthClasses = const <String>['lick', 'scratch', 'shake']});

  /// JSON の 'channels'（例 [0, 1, 2]＝加速度だけ）がなければ全部のチャンネル。
  factory WindowClassifier.fromJson(Map<String, dynamic> j, {double? minProb}) {
    final CnnImuModel m = CnnImuModel.fromJson(j);
    final List<int> ch = (j['channels'] as List<dynamic>?)?.map((dynamic e) => (e as num).toInt()).toList() ??
        List<int>.generate(m.inCh, (int i) => i);
    return WindowClassifier(m, ch, minProb: minProb);
  }

  final CnnImuModel model;
  final List<int> channels;

  /// 段階B（T10 12-8）：模擬で学んだクラスの確率がこれ未満なら、本物のクラスで一番のものにする。null＝使わない。
  final double? minProb;
  final List<String> synthClasses;

  CnnWindow classifyOne(Float32List x6, int windowLen, List<double> gravity, int tStartMs, int tStartDevUs) {
    final Float32List x = Float32List(channels.length * windowLen);
    for (int k = 0; k < channels.length; k++) {
      final int src = channels[k] * windowLen;
      for (int t = 0; t < windowLen; t++) {
        x[k * windowLen + t] = x6[src + t];
      }
    }
    final CnnPrediction p = model.predict(x, gravity: gravity);
    int k = p.label;
    final double? mp = minProb;
    if (mp != null && synthClasses.contains(model.classes[k]) && p.prob[k] < mp) {
      double best = double.negativeInfinity;
      for (int i = 0; i < model.classes.length; i++) {
        if (!synthClasses.contains(model.classes[i]) && p.prob[i] > best) {
          best = p.prob[i];
          k = i;
        }
      }
    }
    return CnnWindow(tStartMs: tStartMs, tStartDevUs: tStartDevUs, label: model.classes[k], prob: p.prob[k]);
  }

  List<CnnWindow> classify(PreprocessResult r) => <CnnWindow>[
        for (int i = 0; i < r.nWindows; i++)
          classifyOne(r.x[i], r.windowLen, r.gravity[i], r.tStartMs[i], r.tStartDevUs[i]),
      ];
}
