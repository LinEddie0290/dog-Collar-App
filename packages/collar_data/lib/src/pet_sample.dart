/// Decoding of PET v1 *sample* frames (`kind == 3`) into typed readings.
///
/// One frame carries exactly one sensor. That is the single biggest difference
/// from the JSON model this data layer was first built against: there is no
/// combined "one reading with everything in it" frame on the wire, so the
/// merging into a single app-facing snapshot happens a layer up.
///
/// Units are fixed integers on the wire — never platform floats, never C
/// struct padding — and are converted to SI here so nothing downstream has to
/// remember the scale factors.
library;

import 'dart:typed_data';

import 'pet_protocol.dart';

/// Fields every sample frame carries, whatever the sensor.
sealed class PetSample {
  const PetSample({
    required this.configId,
    required this.sensor,
    required this.sequence,
    required this.monotonicUs,
  });

  /// The configuration this sample was produced under. A sample whose
  /// `configId` differs from the current one belongs to the previous setup and
  /// should not be charted alongside the new data.
  final int configId;

  final PetSensor sensor;

  /// Frame number shared across *all* sensors, so consecutive numbers do not
  /// mean consecutive readings of the same sensor. Wraps as u32.
  final int sequence;

  /// MCU monotonic microseconds since boot. Not Unix time; combine with a
  /// TIME_SYNC mapping if wall-clock time is needed.
  final int monotonicUs;
}

/// Accelerometer + gyroscope, from either IMU (sensor 1 or 2).
///
/// The two IMUs use each chip's own axes with no mounting alignment, no
/// attitude solution and no cross-sensor calibration, so the same axis name on
/// the two devices does not point the same way.
class PetImuSample extends PetSample {
  const PetImuSample({
    required super.configId,
    required super.sensor,
    required super.sequence,
    required super.monotonicUs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  /// Acceleration in m/s². Includes gravity, so at rest the magnitude is about
  /// 9.8 — all-zero axes would be the anomaly, not the normal case.
  final double ax;
  final double ay;
  final double az;

  /// Angular velocity in rad/s.
  final double gx;
  final double gy;
  final double gz;

  /// Magnitude of the acceleration vector, m/s².
  double get accelMagnitude =>
      (ax * ax + ay * ay + az * az) > 0 ? _sqrt(ax * ax + ay * ay + az * az) : 0;

  @override
  String toString() => 'PetImuSample(${sensor.name}, a=[$ax,$ay,$az], '
      'g=[$gx,$gy,$gz])';
}

// Avoids a dart:math import for one call, keeping this file's imports to
// dart:typed_data only.
double _sqrt(double v) {
  if (v <= 0) return 0;
  double x = v;
  for (int i = 0; i < 20; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

/// MLX90615 infrared thermometer (sensor 3).
///
/// This is the only body-signal sensor the collar actually has. `objectC` is
/// the infrared target temperature — the dog, when the sensor faces the skin —
/// and `ambientC` is the sensor's own surroundings.
class PetTemperatureSample extends PetSample {
  const PetTemperatureSample({
    required super.configId,
    required super.sensor,
    required super.sequence,
    required super.monotonicUs,
    required this.objectC,
    required this.ambientC,
  });

  /// Infrared target temperature, °C (wire unit is milli-°C).
  final double objectC;

  /// Sensor ambient temperature, °C.
  final double ambientC;

  @override
  String toString() =>
      'PetTemperatureSample(object=${objectC}C, ambient=${ambientC}C)';
}

/// Air530/Air530Z GPS (sensor 4): one raw NMEA sentence, checksum already
/// verified by the firmware and re-verified here.
///
/// The sentence is *not* pre-parsed into coordinates, by design. Parse it with
/// `parseNmea` from the `collar_geo` package, and remember that a well-formed
/// sentence does not mean a fix — check the GGA fix quality or RMC status.
class PetGpsSample extends PetSample {
  const PetGpsSample({
    required super.configId,
    required super.sensor,
    required super.sequence,
    required super.monotonicUs,
    required this.sentence,
  });

  /// Complete sentence, `$...*HH`, no CR/LF and no NUL terminator.
  final String sentence;

  @override
  String toString() => 'PetGpsSample($sentence)';
}

/// MSM261DGT006 microphone (sensor 5): one 20 ms block of mono PCM16.
///
/// Not used by the app yet. Kept decodable so the frames can be recognised and
/// dropped deliberately rather than treated as a parse failure — the mic alone
/// is roughly 32 kB/s and will starve the other streams over BLE, so it should
/// normally be switched off with SET_CONFIG.
class PetMicSample extends PetSample {
  const PetMicSample({
    required super.configId,
    required super.sensor,
    required super.sequence,
    required super.monotonicUs,
    required this.sampleRate,
    required this.samples,
  });

  /// Nominal configured rate (16000), not a calibrated measurement. The bench
  /// test measured about 16.08 ksample/s, a ~0.5 % offset.
  final int sampleRate;

  /// 320 signed 16-bit mono samples — digital amplitude, not calibrated to
  /// sound pressure or decibels.
  final Int16List samples;

  @override
  String toString() =>
      'PetMicSample(${samples.length} samples @ ${sampleRate}Hz)';
}

/// A sensor read that failed (`status == 1`). The payload is an errno, usually
/// negative, and must not be decoded as a normal reading.
///
/// These are real sample frames with their own sequence and timestamp. Show
/// the error and keep parsing the other streams. Five consecutive read
/// failures stop that sensor's active bit; STOP/START retries it.
class PetReadError extends PetSample {
  const PetReadError({
    required super.configId,
    required super.sensor,
    required super.sequence,
    required super.monotonicUs,
    required this.errno,
  });

  final int errno;

  @override
  String toString() => 'PetReadError(${sensor.name}, errno=$errno)';
}

/// Decodes one sample frame. Throws [PetProtocolException] for anything that
/// does not match the documented layout, so a malformed frame is counted
/// rather than silently producing a plausible-looking reading.
PetSample decodePetSample(PetFrame frame) {
  if (frame.kind != PetKind.sample) {
    throw const PetProtocolException('frame is not a sample');
  }
  final Uint8List payload = frame.payload;
  if (payload.length < 8) {
    throw const PetProtocolException('sample header truncated');
  }
  final ByteData view = ByteData.sublistView(payload);
  final int configId = view.getUint32(0, Endian.little);
  final int sensorId = payload[4];
  final int status = payload[5];
  final int bodyLen = view.getUint16(6, Endian.little);
  final Uint8List body = Uint8List.sublistView(payload, 8);

  if (body.length != bodyLen) {
    throw const PetProtocolException('sample length mismatch');
  }
  final PetSensor? sensor = PetSensor.fromValue(sensorId);
  if (sensor == null) {
    throw const PetProtocolException('unknown sensor ID');
  }
  if (status != 0 && status != 1) {
    throw const PetProtocolException('unknown sample status');
  }

  if (status == 1) {
    if (body.length != 4) {
      throw const PetProtocolException(
          'read-error sample must have i32 errno');
    }
    return PetReadError(
      configId: configId,
      sensor: sensor,
      sequence: frame.sequence,
      monotonicUs: frame.monotonicUs,
      errno: ByteData.sublistView(body).getInt32(0, Endian.little),
    );
  }

  switch (sensor) {
    case PetSensor.onboardImu:
    case PetSensor.bmi088:
      if (body.length != 24) {
        throw const PetProtocolException(
            'IMU sample must contain six i32 values');
      }
      final ByteData b = ByteData.sublistView(body);
      // 10^-6 m/s² and 10^-6 rad/s on the wire.
      double at(int i) => b.getInt32(i * 4, Endian.little) / 1000000.0;
      return PetImuSample(
        configId: configId,
        sensor: sensor,
        sequence: frame.sequence,
        monotonicUs: frame.monotonicUs,
        ax: at(0), ay: at(1), az: at(2),
        gx: at(3), gy: at(4), gz: at(5),
      );

    case PetSensor.mlx90615:
      if (body.length != 8) {
        throw const PetProtocolException(
            'temperature sample must contain two i32 values');
      }
      final ByteData b = ByteData.sublistView(body);
      return PetTemperatureSample(
        configId: configId,
        sensor: sensor,
        sequence: frame.sequence,
        monotonicUs: frame.monotonicUs,
        objectC: b.getInt32(0, Endian.little) / 1000.0,
        ambientC: b.getInt32(4, Endian.little) / 1000.0,
      );

    case PetSensor.gps:
      return PetGpsSample(
        configId: configId,
        sensor: sensor,
        sequence: frame.sequence,
        monotonicUs: frame.monotonicUs,
        sentence: _validateNmea(body),
      );

    case PetSensor.mic:
      if (body.length < 6) {
        throw const PetProtocolException('PCM header truncated');
      }
      final ByteData b = ByteData.sublistView(body);
      final int rate = b.getUint32(0, Endian.little);
      final int count = b.getUint16(4, Endian.little);
      if (rate == 0 || body.length != 6 + count * 2) {
        throw const PetProtocolException('PCM count/rate invalid');
      }
      final Int16List pcm = Int16List(count);
      for (int i = 0; i < count; i++) {
        pcm[i] = b.getInt16(6 + i * 2, Endian.little);
      }
      return PetMicSample(
        configId: configId,
        sensor: sensor,
        sequence: frame.sequence,
        monotonicUs: frame.monotonicUs,
        sampleRate: rate,
        samples: pcm,
      );
  }
}

/// Structural validation of the raw NMEA bytes, mirroring pet_codec.py.
///
/// The firmware only forwards checksum-valid sentences, so a failure here
/// means the transport corrupted the bytes — worth counting as a receive
/// error rather than passing a damaged sentence to the parser.
String _validateNmea(Uint8List body) {
  final String sentence = petAsciiDecode(body);
  if (sentence.length < 10 ||
      sentence.length > 128 ||
      !sentence.startsWith(r'$') ||
      sentence[6] != ',' ||
      sentence[sentence.length - 3] != '*') {
    throw const PetProtocolException(
        r'NMEA must be $TTSSS,...*HH, 10..128 bytes without CRLF');
  }
  for (int i = 1; i < 6; i++) {
    final int c = sentence.codeUnitAt(i);
    final bool upper = c >= 0x41 && c <= 0x5A;
    final bool digit = c >= 0x30 && c <= 0x39;
    if (!upper && !digit) {
      throw const PetProtocolException(
          'NMEA talker/type must be five uppercase letters/digits');
    }
  }
  int checksum = 0;
  for (int i = 1; i < body.length - 3; i++) {
    final int byte = body[i];
    if (byte < 0x20 || byte > 0x7E || byte == 0x24 || byte == 0x2A) {
      throw const PetProtocolException(
          'NMEA contains nonprintable bytes or misplaced delimiter');
    }
    checksum ^= byte;
  }
  final int? expected =
      int.tryParse(sentence.substring(sentence.length - 2), radix: 16);
  if (expected == null) {
    throw const PetProtocolException('invalid NMEA checksum digits');
  }
  if (checksum != expected) {
    throw const PetProtocolException('NMEA checksum mismatch');
  }
  return sentence;
}
