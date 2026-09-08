import 'raw_frame.dart';

/// A parsed collar reading, ready for the UI. This is the *contract* between
/// the data layer (you) and the UI layer (your teammate): the UI consumes
/// `SensorSample`s and never touches sockets, JSON, or filters.
///
/// Why are hr / resp (and the rest) NULLABLE?
/// ------------------------------------------
/// A frame is NOT guaranteed to carry every field:
///   * The collar may interleave frame types — e.g. high-rate IMU frames with
///     no heart-rate field, and slower HR frames.
///   * The optical HR sensor often fails to get a lock (loose collar, motion),
///     so it legitimately reports "no reading this frame".
///   * battery is usually sent only occasionally, not every frame.
///
/// If we defaulted a missing HR to 0.0 (or -1), the chart would draw a fake
/// value and the filter would treat it as real data — a phantom dip. `null`
/// makes "no reading" explicit and honest: the filter skips it, and the UI can
/// draw a gap instead of inventing a point. Missing stays missing.
class SensorSample {
  /// Phone receive time (epoch ms) — always present, our trustworthy clock.
  final int rxTs;

  /// Collar's own timestamp (may be absent, may drift vs [rxTs]).
  final int? deviceTs;

  /// Sequence number from the collar, if present.
  final int? seq;

  final double? hr;
  final double? resp;
  final double? ax;
  final double? ay;
  final double? az;
  final int? battery;

  const SensorSample({
    required this.rxTs,
    this.deviceTs,
    this.seq,
    this.hr,
    this.resp,
    this.ax,
    this.ay,
    this.az,
    this.battery,
  });

  /// Parse a [RawFrame] into a sample. Anything missing or wrong-typed becomes
  /// null rather than throwing — one weird frame must not break the stream.
  factory SensorSample.fromRaw(RawFrame f) {
    final r = f.raw;
    double? d(dynamic v) => v is num ? v.toDouble() : null;
    int? i(dynamic v) => v is num ? v.toInt() : null;
    final imu = r['imu'];
    final isMap = imu is Map;
    return SensorSample(
      rxTs: f.rxTs,
      deviceTs: i(r['ts']),
      seq: i(r['seq']),
      hr: d(r['hr']),
      resp: d(r['resp']),
      ax: isMap ? d(imu['ax']) : null,
      ay: isMap ? d(imu['ay']) : null,
      az: isMap ? d(imu['az']) : null,
      battery: i(r['battery']),
    );
  }

  SensorSample copyWith({
    double? hr,
    double? resp,
    double? ax,
    double? ay,
    double? az,
  }) {
    // Note: these params are the *filtered* values; nulls are meaningful
    // (no reading), so we pass them straight through rather than ??-coalescing.
    return SensorSample(
      rxTs: rxTs,
      deviceTs: deviceTs,
      seq: seq,
      hr: hr,
      resp: resp,
      ax: ax,
      ay: ay,
      az: az,
      battery: battery,
    );
  }

  @override
  String toString() =>
      'SensorSample(rxTs:$rxTs seq:$seq hr:$hr resp:$resp '
      'imu:[$ax,$ay,$az] batt:$battery)';
}
