/// 首輪の IMU 用の小さな CNN の推理(T24)。純 Dart、依存なし。
///
/// 重みは collar-pipeline の `scripts/export_cnn.py` が書く JSON
/// (BatchNorm はまとめ済み)。計算は C 版(`tools/cnn_c/cnn_imu.c`)と同じ順番。
library;

export 'src/cnn_imu.dart';
