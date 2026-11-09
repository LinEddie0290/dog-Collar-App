/// T35：アプリの行動の CNN（v1・v2）と、判定の設定（設計メモ T35_CNNv2をアプリへ、D-051 D4・T10B D4〜D6）。
///
/// - v2（標準）：7 クラス（still・walk・run・other＋lick・scratch・shake）。lick・scratch・shake は模擬の波形で学んだ（試用）。
/// - v1：4 クラス（still・walk・run・other）。我的 → 开发 で戻せる（比べるため）。
/// - 下限 0.9：模擬のクラスが一番でも確率 0.9 未満なら、本物の 4 クラスで一番のものにする（T10B D4、誤報 8% → 0.57%）。
/// - 休息中でも、CNN が lick・scratch・shake を 0.9 以上で出したら CNN を使う（T10B D5）。v1 の結果にはこの 3 つが出ないので、v1 でも同じ設定でよい。
/// どちらの重みも collar-pipeline の scripts/export_cnn.py が書いたもの（PyTorch と同じ答え：test/cnn_v2_test.dart）。
library;

import 'dart:convert';

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/services.dart' show rootBundle;

enum CnnVersion { v1, v2 }

extension CnnVersionX on CnnVersion {
  String get asset => 'assets/models/cnn_imu_$name.json';

  /// 我的 → 开发 に出す名前。
  String get label => switch (this) {
        CnnVersion.v1 => 'v1（4 类）',
        CnnVersion.v2 => 'v2（7 类：+舔・挠・颤抖，试用）',
      };
}

/// アプリの標準。
const CnnVersion defaultCnnVersion = CnnVersion.v2;

/// 模擬のクラス（lick・scratch・shake）の確率の下限（T10B D4）。
const double cnnSynthMinProb = 0.9;

/// 出来事の設定（T10B D5：休息中でも 0.9 以上なら lick・scratch・shake を使う）。ほかは collar_pipeline の既定のまま。
const EventConfig appEventConfig =
    EventConfig(overrideRest: <String, double>{'lick': 0.9, 'scratch': 0.9, 'shake': 0.9});

/// アプリに入っている CNN を読む（下限つき）。
Future<WindowClassifier> loadClassifierAsset(CnnVersion v) async {
  final String text = await rootBundle.loadString(v.asset);
  return WindowClassifier.fromJson(jsonDecode(text) as Map<String, dynamic>, minProb: cnnSynthMinProb);
}

CnnVersion cnnVersionFromName(String? name) =>
    CnnVersion.values.firstWhere((CnnVersion v) => v.name == name, orElse: () => defaultCnnVersion);
