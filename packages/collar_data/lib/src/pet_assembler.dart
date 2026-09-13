/// Merges per-sensor PET v1 frames into the app-facing [SensorSample].
///
/// This layer exists because of one structural mismatch: **the wire sends one
/// sensor per frame, the UI wants one object with everything in it.** At 104 Hz
/// the onboard IMU alone produces a frame every ~10 ms, while the thermometer
/// sends 2 per second and GPS sends a burst once per second. Emitting a
/// `SensorSample` per frame would give the UI a stream that is 98 % IMU with
/// every other field null.
///
/// So this holds the latest value from each sensor and hands out a merged
/// snapshot on demand. It keeps no history — [CollarRepository] already owns
/// that — and does no filtering.
///
/// GPS deliberately does not go through [add]: the collar sends raw NMEA, and
/// parsing it needs the `collar_geo` package, which this package does not
/// depend on (both stay dependency-free and runnable with a bare `dart`).
/// Whoever owns the transport parses the sentence and calls [setPosition].
library;

import 'pet_protocol.dart';
import 'pet_sample.dart';
import 'sensor_sample.dart';

/// How long a sensor's last value stays in the snapshot before it is treated
/// as stale and dropped back to null.
///
/// Without this, a sensor that stops reporting (module yanked, five read
/// errors in a row disabling its active bit) would leave its last value on
/// screen forever, looking live. Each sensor gets its own budget because their
/// natural rates differ by orders of magnitude.
class PetStaleness {
  const PetStaleness({
    this.imu = const Duration(seconds: 3),
    this.temperature = const Duration(seconds: 15),
    this.position = const Duration(minutes: 2),
  });

  final Duration imu;
  final Duration temperature;

  /// Matches `LocationController.offlineThreshold`, which shows the marker as
  /// "last known position" rather than hiding it.
  final Duration position;
}

class PetSampleAssembler {
  PetSampleAssembler({
    this.staleness = const PetStaleness(),
    this.preferredImu,
  });

  final PetStaleness staleness;

  /// Which IMU feeds [SensorSample.ax]..[gz]. Null means "whichever reported
  /// last", which is usually wrong to chart: the two chips use their own axes
  /// with no mounting alignment or cross-calibration, so mixing them makes the
  /// series jump. Pin one for anything the user sees.
  final PetSensor? preferredImu;

  int? _seq;
  int? _monotonicUs;

  double? _ax, _ay, _az, _gx, _gy, _gz;
  DateTime? _imuAt;
  PetSensor? _imuFrom;

  double? _bodyTempC, _ambientTempC;
  DateTime? _tempAt;

  double? _lat, _lng, _hdop;
  int? _fixQuality, _satellites;
  DateTime? _positionAt;

  /// Read errors seen per sensor since the last [reset], for a diagnostics
  /// screen. A sensor accumulating these is failing even while others look
  /// healthy.
  final Map<PetSensor, int> readErrors = <PetSensor, int>{};

  /// The most recent read error, so the UI can name what broke.
  PetReadError? lastError;

  /// config_id of the most recently accepted sample. A change means the
  /// device's configuration was switched and older values describe a
  /// different setup.
  int? configId;

  /// Feeds one decoded sample. Returns true when it changed the snapshot.
  ///
  /// [PetGpsSample] is accepted but ignored — call [setPosition] with the
  /// parsed result instead. [PetMicSample] is ignored by design.
  bool add(PetSample sample) {
    final DateTime now = DateTime.now();
    configId = sample.configId;
    _seq = sample.sequence;
    _monotonicUs = sample.monotonicUs;

    switch (sample) {
      case PetReadError():
        readErrors[sample.sensor] = (readErrors[sample.sensor] ?? 0) + 1;
        lastError = sample;
        return true;

      case PetImuSample():
        // Ignore the IMU we are not charting, otherwise the series alternates
        // between two differently-oriented chips.
        if (preferredImu != null && sample.sensor != preferredImu) return false;
        _ax = sample.ax;
        _ay = sample.ay;
        _az = sample.az;
        _gx = sample.gx;
        _gy = sample.gy;
        _gz = sample.gz;
        _imuAt = now;
        _imuFrom = sample.sensor;
        return true;

      case PetTemperatureSample():
        _bodyTempC = sample.objectC;
        _ambientTempC = sample.ambientC;
        _tempAt = now;
        return true;

      case PetGpsSample():
      case PetMicSample():
        return false;
    }
  }

  /// Records a parsed GPS fix. Call this only for a sentence that actually had
  /// a fix — feeding it coordinates from a `fixQuality == 0` sentence is the
  /// exact bug this whole layer is shaped to prevent.
  void setPosition({
    required double lat,
    required double lng,
    int? fixQuality,
    int? satellites,
    double? hdop,
  }) {
    _lat = lat;
    _lng = lng;
    _fixQuality = fixQuality;
    _satellites = satellites;
    _hdop = hdop;
    _positionAt = DateTime.now();
  }

  /// Updates the fix metadata without moving the position.
  ///
  /// Worth calling even with no fix: "0 satellites" and "HDOP 99.99" are what
  /// distinguishes "indoors, no sky view" from "module not responding", and
  /// that is the difference between waiting and debugging.
  void setFixQuality({int? fixQuality, int? satellites, double? hdop}) {
    if (fixQuality != null) _fixQuality = fixQuality;
    if (satellites != null) _satellites = satellites;
    if (hdop != null) _hdop = hdop;
  }

  /// Which IMU the current values came from, for display.
  PetSensor? get imuSource => _imuFrom;

  /// Have we ever had a position fix?
  bool get hasEverFixed => _lat != null;

  /// Builds the merged snapshot, dropping values that have gone stale.
  SensorSample build() {
    final DateTime now = DateTime.now();
    bool fresh(DateTime? at, Duration budget) =>
        at != null && now.difference(at) <= budget;

    final bool imuOk = fresh(_imuAt, staleness.imu);
    final bool tempOk = fresh(_tempAt, staleness.temperature);
    final bool posOk = fresh(_positionAt, staleness.position);

    return SensorSample(
      rxTs: now.millisecondsSinceEpoch,
      deviceTs: _monotonicUs,
      seq: _seq,
      bodyTempC: tempOk ? _bodyTempC : null,
      ambientTempC: tempOk ? _ambientTempC : null,
      // resp: the hardware cannot measure it — see SensorSample.resp.
      resp: null,
      ax: imuOk ? _ax : null,
      ay: imuOk ? _ay : null,
      az: imuOk ? _az : null,
      gx: imuOk ? _gx : null,
      gy: imuOk ? _gy : null,
      gz: imuOk ? _gz : null,
      // battery: not in the PET v1 protocol — see SensorSample.battery.
      battery: null,
      lat: posOk ? _lat : null,
      lng: posOk ? _lng : null,
      // Fix metadata is reported even when the position itself went stale, so
      // the UI can say *why* there is no dot on the map.
      fixQuality: _fixQuality,
      satellites: _satellites,
      hdop: _hdop,
    );
  }

  /// The same snapshot as [build], in the JSON key shape [RawFrame] uses.
  ///
  /// The pipeline is `frames -> archive -> parse -> filter`, and the archive
  /// step wants something serialisable, so the BLE transport hands the
  /// repository this map (alongside the original bytes) rather than a
  /// [SensorSample]. Keeping both transports on one key shape means the
  /// archive files, `SensorSample.fromRaw`, and the mock server all stay
  /// interchangeable — a capture from the real collar can be replayed through
  /// the mock path unchanged.
  Map<String, dynamic> buildRawMap() {
    final SensorSample s = build();
    return <String, dynamic>{
      'v': 1,
      'type': 'sensor',
      'transport': 'ble',
      if (configId != null) 'config_id': configId,
      if (s.deviceTs != null) 'ts': s.deviceTs,
      if (s.seq != null) 'seq': s.seq,
      if (s.bodyTempC != null) 'body_temp_c': s.bodyTempC,
      if (s.ambientTempC != null) 'ambient_temp_c': s.ambientTempC,
      if (s.ax != null)
        'imu': <String, double?>{
          'ax': s.ax,
          'ay': s.ay,
          'az': s.az,
          'gx': s.gx,
          'gy': s.gy,
          'gz': s.gz,
        },
      if (_imuFrom != null) 'imu_source': _imuFrom!.name,
      if (s.lat != null) 'lat': s.lat,
      if (s.lng != null) 'lng': s.lng,
      if (s.fixQuality != null) 'fix_quality': s.fixQuality,
      if (s.satellites != null) 'satellites': s.satellites,
      if (s.hdop != null) 'hdop': s.hdop,
      if (readErrors.isNotEmpty)
        'read_errors': <String, int>{
          for (final MapEntry<PetSensor, int> e in readErrors.entries)
            e.key.name: e.value,
        },
    };
  }

  void reset() {
    _seq = null;
    _monotonicUs = null;
    _ax = _ay = _az = _gx = _gy = _gz = null;
    _imuAt = null;
    _imuFrom = null;
    _bodyTempC = _ambientTempC = null;
    _tempAt = null;
    _lat = _lng = _hdop = null;
    _fixQuality = _satellites = null;
    _positionAt = null;
    readErrors.clear();
    lastError = null;
    configId = null;
  }
}
