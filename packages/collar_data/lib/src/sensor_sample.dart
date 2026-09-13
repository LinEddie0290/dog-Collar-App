import 'raw_frame.dart';

/// A parsed collar reading, ready for the UI. This is the *contract* between
/// the data layer and the UI layer: the UI consumes `SensorSample`s and never
/// touches sockets, binary frames, NMEA, or filters.
///
/// Why is everything NULLABLE?
/// ---------------------------
/// A reading is NOT guaranteed to carry every field. On the real collar this is
/// structural, not occasional: **one PET v1 frame carries exactly one sensor.**
/// An IMU frame has no temperature in it, a GPS frame has no IMU in it. This
/// class is therefore a *merged snapshot* of the most recent value from each
/// sensor (see [PetSampleAssembler]), and any sensor that has not reported yet
/// — or is switched off, or absent from the hardware — stays null.
///
/// If we defaulted a missing reading to 0.0 (or -1), the chart would draw a
/// fake value and the filter would treat it as real data. `null` makes "no
/// reading" explicit and honest: the filter skips it, and the UI draws a gap
/// instead of inventing a point.
///
/// 2026-09-12: reshaped to match the actual firmware
/// -------------------------------------------------
/// This class originally described a JSON-over-WiFi link with heart rate and
/// respiration in it. The real device (Seeed XIAO nRF54LM20A Sense) has
/// neither of those sensors and speaks binary over BLE only. See
/// ../../../PROTOCOL_CHANGE.md for what changed and why. In short, the collar
/// has: two IMUs, one infrared thermometer, one GPS, one microphone.
class SensorSample {
  /// Phone receive time (epoch ms) — always present, our trustworthy clock.
  final int rxTs;

  /// The collar's own timestamp. On the real link this is MCU **monotonic
  /// microseconds since boot**, not epoch time and not comparable across
  /// reboots; pair it with a TIME_SYNC mapping if wall-clock time is needed.
  final int? deviceTs;

  /// Frame sequence number from the collar. Shared across all sensors, so
  /// consecutive values do not mean consecutive readings of one sensor.
  final int? seq;

  /// Infrared target temperature in °C — the dog, when the sensor faces skin.
  /// This is the collar's only real body-signal sensor (MLX90615).
  final double? bodyTempC;

  /// The thermometer's own ambient temperature in °C. Useful as context: a
  /// body reading close to ambient usually means the sensor is not aimed at
  /// the animal.
  final double? ambientTempC;

  /// Breaths per minute.
  ///
  /// **Reserved — the current hardware does not measure this.** There is no
  /// respiration sensor; the plan is to derive it from the periodic component
  /// of the IMU signal (chest/neck movement), which is a signal-processing job
  /// that has not been written yet. Kept in the contract so adding it later is
  /// purely additive and does not change this interface again. Always null on
  /// the real link today; the mock source still provides a value.
  final double? resp;

  /// Acceleration in m/s², including gravity (magnitude ≈ 9.8 at rest).
  final double? ax;
  final double? ay;
  final double? az;

  /// Angular velocity in rad/s, from the same IMU frame as [ax]..[az].
  final double? gx;
  final double? gy;
  final double? gz;

  /// Battery percentage.
  ///
  /// **Reserved — the current firmware does not report it.** Neither the
  /// sensor set nor the status snapshot carries a battery field, so this is
  /// always null on the real link and the UI shows `--`. The mock source still
  /// provides a value. Exposing it would need a firmware change (the MCU can
  /// read its own supply voltage, but that is not in the PET v1 protocol).
  final int? battery;

  /// WGS84 latitude of the last GPS fix.
  ///
  /// **Convert with `wgs84ToGcj02` before drawing on Amap** — plotting WGS84
  /// directly on a Chinese map service puts the dog a few hundred metres away.
  final double? lat;

  /// WGS84 longitude of the last GPS fix.
  final double? lng;

  /// GGA fix quality: 0 = no fix, 1 = GPS, 2 = DGPS, 4/5 = RTK.
  ///
  /// A position is only meaningful when this is >= 1. The collar happily emits
  /// well-formed NMEA with quality 0 indefinitely when it cannot see sky — on
  /// 2026-09-11 it produced 1,200 valid sentences and zero fixes indoors — so
  /// [hasLocation] checks this rather than merely checking for non-null
  /// coordinates.
  final int? fixQuality;

  /// Satellites used in the solution (GGA field 7).
  final int? satellites;

  /// Horizontal dilution of precision (GGA field 8).
  ///
  /// **A dimensionless multiplier, not metres.** The collar reports no accuracy
  /// figure at all; [estimatedAccuracyM] turns this into a rough distance for
  /// drawing a circle, and it must be labelled as an estimate in the UI.
  final double? hdop;

  const SensorSample({
    required this.rxTs,
    this.deviceTs,
    this.seq,
    this.bodyTempC,
    this.ambientTempC,
    this.resp,
    this.ax,
    this.ay,
    this.az,
    this.gx,
    this.gy,
    this.gz,
    this.battery,
    this.lat,
    this.lng,
    this.fixQuality,
    this.satellites,
    this.hdop,
  });

  /// Parses a JSON [RawFrame] into a sample. This is the **mock/development
  /// path** only: the mock server in `tools/mock_collar.dart` and
  /// [FakeCollarDataSource] speak JSON, the real collar does not. Anything
  /// missing or wrong-typed becomes null rather than throwing — one weird
  /// frame must not break the stream.
  factory SensorSample.fromRaw(RawFrame f) {
    final Map<String, dynamic> r = f.raw;
    double? d(dynamic v) => v is num ? v.toDouble() : null;
    int? i(dynamic v) => v is num ? v.toInt() : null;
    final dynamic imu = r['imu'];
    final bool isMap = imu is Map;
    return SensorSample(
      rxTs: f.rxTs,
      deviceTs: i(r['ts']),
      seq: i(r['seq']),
      bodyTempC: d(r['body_temp_c']),
      ambientTempC: d(r['ambient_temp_c']),
      resp: d(r['resp']),
      ax: isMap ? d(imu['ax']) : null,
      ay: isMap ? d(imu['ay']) : null,
      az: isMap ? d(imu['az']) : null,
      gx: isMap ? d(imu['gx']) : null,
      gy: isMap ? d(imu['gy']) : null,
      gz: isMap ? d(imu['gz']) : null,
      battery: i(r['battery']),
      lat: d(r['lat']),
      lng: d(r['lng']),
      fixQuality: i(r['fix_quality']),
      satellites: i(r['satellites']),
      hdop: d(r['hdop']),
    );
  }

  /// Does this sample carry a *usable* GPS position?
  ///
  /// Requires coordinates AND a real fix. `fixQuality == null` is treated as
  /// usable so the mock path (which has no GGA quality field) keeps working;
  /// the real BLE path always sets it.
  bool get hasLocation =>
      lat != null && lng != null && (fixQuality == null || fixQuality! >= 1);

  /// Does this sample carry a temperature reading?
  bool get hasTemperature => bodyTempC != null;

  /// Rough horizontal accuracy in metres, for drawing a circle on the map.
  ///
  /// `accuracy ≈ HDOP × UERE`, with UERE about 5 m for consumer GNSS. This is
  /// an order-of-magnitude hint, **not a measured value** — the hardware does
  /// not report accuracy. Label it as an estimate wherever it is shown.
  double? get estimatedAccuracyM =>
      hdop == null || hdop! <= 0 ? null : hdop! * 5.0;

  /// Magnitude of the acceleration vector in m/s², or null if no IMU reading.
  /// Around 9.8 at rest; the deviation from that is the activity signal.
  double? get accelMagnitude {
    if (ax == null || ay == null || az == null) return null;
    final double sum = ax! * ax! + ay! * ay! + az! * az!;
    if (sum <= 0) return 0;
    double x = sum;
    for (int i = 0; i < 20; i++) {
      x = 0.5 * (x + sum / x);
    }
    return x;
  }

  SensorSample copyWith({
    double? bodyTempC,
    double? ambientTempC,
    double? resp,
    double? ax,
    double? ay,
    double? az,
  }) {
    // These params are the *filtered* values; nulls are meaningful (no
    // reading), so they pass straight through rather than being ??-coalesced.
    // Position and gyro are NOT filtered: GPS points pass through untouched
    // (smoothing is the map/geofence layer's job, not this pipeline's), and
    // the gyro is carried over unchanged from `this`.
    return SensorSample(
      rxTs: rxTs,
      deviceTs: deviceTs,
      seq: seq,
      bodyTempC: bodyTempC,
      ambientTempC: ambientTempC,
      resp: resp,
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
      battery: battery,
      lat: lat,
      lng: lng,
      fixQuality: fixQuality,
      satellites: satellites,
      hdop: hdop,
    );
  }

  @override
  String toString() => 'SensorSample(rxTs:$rxTs seq:$seq '
      'temp:${bodyTempC?.toStringAsFixed(2)}C resp:$resp '
      'imu:[$ax,$ay,$az] batt:$battery '
      'loc:${hasLocation ? '($lat,$lng) q=$fixQuality sats=$satellites' : 'none'})';
}
