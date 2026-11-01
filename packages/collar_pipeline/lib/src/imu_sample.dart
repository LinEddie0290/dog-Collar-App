/// IMU の 1 サンプル（collar-pipeline の共通形式 imu.parquet の 1 行と同じ）。
/// 単位：加速度 m/s²、角速度 rad/s。sensor は 'front' か 'side'。
class ImuSample {
  const ImuSample({
    required this.sensor,
    required this.tDevUs,
    this.tMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  final String sensor;
  final int tDevUs; // 首輪の時計（マイクロ秒）
  final int? tMs; // UTC（ミリ秒）。分からなければ null
  final double ax, ay, az, gx, gy, gz;

  List<double> get values => <double>[ax, ay, az, gx, gy, gz];
}
