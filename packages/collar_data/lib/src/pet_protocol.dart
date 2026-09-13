/// PET v1 wire protocol — a faithful Dart port of `tools/pet_codec.py` from the
/// firmware repo (PET-main). Pure Dart, zero dependencies, no Bluetooth I/O:
/// this file only turns bytes into objects and back, so the whole protocol can
/// be unit-tested with a bare `dart` SDK and no hardware.
///
/// The collar is a Seeed XIAO nRF54LM20A Sense. It speaks BLE GATT only — it
/// has no WiFi, TCP or MQTT — so this replaces the JSON-over-WebSocket
/// assumption the data layer was originally built around.
///
/// Two layers, both little-endian:
///   * a *logical frame* (24-byte header + payload) carries one command,
///     response or sample;
///   * a *transport fragment* (8-byte header + bytes) is what fits in a single
///     GATT characteristic value. Even a frame small enough for one Notify
///     still carries a fragment header.
///
/// Keep one [PetReassembler] per characteristic (Data and Status each need
/// their own) and reset both on every connection change.
library;

import 'dart:convert';
import 'dart:typed_data';

const int petVersion = 1;
const int petHeaderSize = 24;
const int petMaxFrameSize = 768;
const int petMaxPayloadSize = petMaxFrameSize - petHeaderSize;
const int petFragmentHeaderSize = 8;
const int petFragmentMagic = 0xA5;

/// Every sensor enabled: `0x1f`. Power-on default rates, by sensor ID 1..5.
const int petDefaultMask = 0x1F;
const List<int> petDefaultRates = <int>[104, 100, 2, 0, 16000];

/// Message kinds (frame header offset 3).
enum PetKind {
  command(1),
  response(2),
  sample(3),
  /// Reserved in v1 — the firmware never sends this.
  event(4);

  const PetKind(this.value);
  final int value;

  static PetKind? fromValue(int value) {
    for (final PetKind kind in PetKind.values) {
      if (kind.value == value) return kind;
    }
    return null;
  }
}

/// Control-characteristic commands (first payload byte).
enum PetOpcode {
  getCapabilities(1),
  getConfig(2),
  setConfig(3),
  start(4),
  stop(5),
  timeSync(6);

  const PetOpcode(this.value);
  final int value;

  static PetOpcode? fromValue(int value) {
    for (final PetOpcode op in PetOpcode.values) {
      if (op.value == value) return op;
    }
    return null;
  }

  /// Required command body length, excluding the opcode byte itself.
  int get bodyLength => switch (this) {
        PetOpcode.setConfig => 14,
        PetOpcode.timeSync => 8,
        _ => 0,
      };
}

/// Result codes in a response payload (offset 1).
enum PetResult {
  ok(0),
  badCommand(1),
  badPayload(2),
  busy(3),
  unavailable(4),
  badRate(5),
  notSubscribed(6),
  ioError(7),
  idReuse(8),
  mtuTooSmall(9);

  const PetResult(this.value);
  final int value;

  static PetResult? fromValue(int value) {
    for (final PetResult r in PetResult.values) {
      if (r.value == value) return r;
    }
    return null;
  }
}

/// Sensor IDs. Mask bit for a sensor is `1 << (id - 1)`.
enum PetSensor {
  /// Onboard LSM6DS3TR-C IMU. 26/52/104 Hz, default 104.
  onboardImu(1),

  /// External BMI088 IMU. 25/50/100 Hz, default 100.
  bmi088(2),

  /// External MLX90615 infrared thermometer. 1/2/5/10 Hz, default 2.
  mlx90615(3),

  /// External Air530/Air530Z GPS. Rate is always 0 — it is event-driven,
  /// emitting whatever NMEA the module natively produces. Rate 0 does NOT
  /// mean disabled; only the mask bit decides that.
  gps(4),

  /// Onboard MSM261DGT006 microphone, nominal 16000 Hz.
  mic(5);

  const PetSensor(this.value);
  final int value;

  int get maskBit => 1 << (value - 1);

  static PetSensor? fromValue(int value) {
    for (final PetSensor s in PetSensor.values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// Device collection state (`state` in a config/status body or Status Read).
enum PetState {
  idle(0),

  /// Collecting and able to send right now.
  streaming(1),

  /// Collecting, but the data channel cannot send — not connected, or Data
  /// not subscribed yet.
  buffering(2);

  const PetState(this.value);
  final int value;

  static PetState? fromValue(int value) {
    for (final PetState s in PetState.values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// Thrown for invalid wire bytes, and for invalid arguments to the encoders.
/// Mirrors `ProtocolError` in pet_codec.py.
class PetProtocolException implements Exception {
  const PetProtocolException(this.message);
  final String message;

  @override
  String toString() => 'PetProtocolException: $message';
}

Never _fail(String message) => throw PetProtocolException(message);

int _checkUint(int value, int bits, String name) {
  // bits == 64 would overflow `1 << bits` on a signed 64-bit int, and Dart has
  // no unsigned type, so a u64 field is only checked for non-negativity.
  if (value < 0 || (bits < 64 && value >= (1 << bits))) {
    _fail('$name must be an unsigned $bits-bit integer');
  }
  return value;
}

/// One complete logical frame: the 24-byte header plus its payload.
class PetFrame {
  const PetFrame({
    required this.kind,
    required this.bootId,
    required this.sequence,
    required this.monotonicUs,
    required this.payload,
  });

  final PetKind kind;

  /// Device boot-session ID. A phone-sent command always carries 0. This is a
  /// session discriminator, not a serial number and not a credential.
  final int bootId;

  /// `request_id` for command/response; the shared sample frame number for
  /// samples. Wraps naturally as u32.
  final int sequence;

  /// MCU monotonic microseconds since boot — not Unix time. A phone-sent
  /// command always carries 0.
  final int monotonicUs;

  final Uint8List payload;

  @override
  String toString() => 'PetFrame(${kind.name}, boot=$bootId, seq=$sequence, '
      'us=$monotonicUs, payload=${payload.length}B)';
}

/// Builds a complete logical frame. Frames are capped at 768 bytes total.
Uint8List encodeFrame({
  required PetKind kind,
  required int bootId,
  required int sequence,
  required int monotonicUs,
  List<int> payload = const <int>[],
}) {
  if (payload.length > petMaxPayloadSize) {
    _fail('frame exceeds $petMaxFrameSize bytes');
  }
  _checkUint(bootId, 32, 'boot_id');
  _checkUint(sequence, 32, 'sequence');
  _checkUint(monotonicUs, 64, 'monotonic_us');

  final Uint8List out = Uint8List(petHeaderSize + payload.length);
  final ByteData view = ByteData.sublistView(out);
  out[0] = 0x50; // 'P'
  out[1] = 0x54; // 'T'
  out[2] = petVersion;
  out[3] = kind.value;
  view.setUint32(4, bootId, Endian.little);
  view.setUint32(8, sequence, Endian.little);
  view.setUint16(12, payload.length, Endian.little);
  view.setUint16(14, 0, Endian.little); // flags: fixed 0 in v1
  view.setUint64(16, monotonicUs, Endian.little);
  out.setRange(petHeaderSize, out.length, payload);
  return out;
}

/// Parses a complete logical frame, validating magic, version, kind, flags and
/// the exact `24 + payload_len` length. An unknown *version* must stop v1
/// decoding rather than guessing the field layout.
PetFrame decodeFrame(List<int> raw) {
  if (raw.length < petHeaderSize || raw.length > petMaxFrameSize) {
    _fail('frame size outside $petHeaderSize..$petMaxFrameSize bytes');
  }
  final Uint8List bytes =
      raw is Uint8List ? raw : Uint8List.fromList(raw);
  final ByteData view = ByteData.sublistView(bytes);

  if (bytes[0] != 0x50 || bytes[1] != 0x54 || bytes[2] != petVersion) {
    _fail('invalid frame magic/version');
  }
  final int flags = view.getUint16(14, Endian.little);
  final int payloadLen = view.getUint16(12, Endian.little);
  if (flags != 0 || payloadLen != bytes.length - petHeaderSize) {
    _fail('nonzero reserved flags or mismatched payload length');
  }
  final PetKind? kind = PetKind.fromValue(bytes[3]);
  if (kind == null) _fail('unknown message kind');

  return PetFrame(
    kind: kind,
    bootId: view.getUint32(4, Endian.little),
    sequence: view.getUint32(8, Endian.little),
    monotonicUs: view.getUint64(16, Endian.little),
    payload: Uint8List.sublistView(bytes, petHeaderSize),
  );
}

/// The 14-byte SET_CONFIG body: mask u32 + five u16 rates, sensor ID 1..5.
/// A sensor whose mask bit is clear MUST have rate 0.
Uint8List encodeConfig({required int mask, required List<int> rates}) {
  _checkUint(mask, 32, 'sensor_mask');
  if ((mask & ~0x1F) != 0 || rates.length != 5) {
    _fail('configuration requires mask bits 0..4 and five rates');
  }
  for (int i = 0; i < 5; i++) {
    _checkUint(rates[i], 16, 'rate[$i]');
    if ((mask & (1 << i)) == 0 && rates[i] != 0) {
      _fail('disabled sensors must have rate zero');
    }
  }
  final Uint8List out = Uint8List(14);
  final ByteData view = ByteData.sublistView(out);
  view.setUint32(0, mask, Endian.little);
  for (int i = 0; i < 5; i++) {
    view.setUint16(4 + i * 2, rates[i], Endian.little);
  }
  return out;
}

/// A requested sensor mask plus its five rates.
class PetConfig {
  const PetConfig({required this.mask, required this.rates});

  final int mask;

  /// Rates by sensor ID 1..5, i.e. `rates[PetSensor.gps.value - 1]`.
  final List<int> rates;

  bool enabled(PetSensor sensor) => (mask & sensor.maskBit) != 0;
  int rateOf(PetSensor sensor) => rates[sensor.value - 1];

  @override
  String toString() => 'PetConfig(mask=0x${mask.toRadixString(16)}, '
      'rates=$rates)';
}

PetConfig decodeConfig(List<int> body) {
  if (body.length != 14) _fail('configuration body must be 14 bytes');
  final ByteData view = ByteData.sublistView(
      body is Uint8List ? body : Uint8List.fromList(body));
  final int mask = view.getUint32(0, Endian.little);
  final List<int> rates = <int>[
    for (int i = 0; i < 5; i++) view.getUint16(4 + i * 2, Endian.little),
  ];
  encodeConfig(mask: mask, rates: rates); // reuse the same validation
  return PetConfig(mask: mask, rates: rates);
}

/// Builds a command frame. `boot_id` and `monotonic_us` are fixed at 0 for
/// phone-sent commands. Commands with no documented body must carry exactly
/// the single opcode byte.
Uint8List encodeCommand({
  required PetOpcode opcode,
  required int requestId,
  List<int> body = const <int>[],
}) {
  if (body.length != opcode.bodyLength) {
    _fail('${opcode.name} body must be ${opcode.bodyLength} bytes');
  }
  if (opcode == PetOpcode.setConfig) {
    decodeConfig(body); // reject a malformed config before it goes on the wire
  }
  return encodeFrame(
    kind: PetKind.command,
    bootId: 0,
    sequence: requestId,
    monotonicUs: 0,
    payload: <int>[opcode.value, ...body],
  );
}

/// Convenience wrapper for the 8-byte TIME_SYNC body.
Uint8List encodeTimeSyncBody(int hostUnixUs) {
  _checkUint(hostUnixUs, 64, 'host_unix_us');
  final Uint8List out = Uint8List(8);
  ByteData.sublistView(out).setUint64(0, hostUnixUs, Endian.little);
  return out;
}

/// Splits one logical frame into GATT characteristic values.
///
/// Each fragment carries `mtu - 3 - 8` bytes of frame content. The firmware
/// also caps a single value at 244 bytes, so a large MTU only reduces the
/// number of fragments; it never changes the format. Write the results to
/// Control one at a time, each with *write with response*, waiting for each
/// write to complete — never Write Without Response and never ATT long write.
List<Uint8List> fragmentFrame(
  List<int> frame, {
  int messageId = 0,
  int mtu = 23,
}) {
  decodeFrame(frame); // never fragment something that is not a valid frame
  _checkUint(messageId, 16, 'message_id');
  if (mtu < 23 || mtu > 517) _fail('ATT MTU must be in 23..517');

  final int chunk = mtu - 3 - petFragmentHeaderSize;
  final List<Uint8List> out = <Uint8List>[];
  for (int offset = 0; offset < frame.length; offset += chunk) {
    final int end =
        (offset + chunk) < frame.length ? offset + chunk : frame.length;
    final Uint8List value = Uint8List(petFragmentHeaderSize + (end - offset));
    final ByteData view = ByteData.sublistView(value);
    value[0] = petFragmentMagic;
    value[1] = petVersion;
    view.setUint16(2, messageId, Endian.little);
    view.setUint16(4, frame.length, Endian.little);
    view.setUint16(6, offset, Endian.little);
    value.setRange(petFragmentHeaderSize, value.length,
        frame.getRange(offset, end));
    out.add(value);
  }
  return out;
}

/// Ordered, bounded reassembly of one characteristic's fragments.
///
/// `offset == 0` always starts a new message and discards any unfinished one.
/// Anything malformed throws [PetProtocolException] *and* resets the state, so
/// the caller should count a receive error and wait for the next offset-0
/// fragment. There is no built-in timer: reset on disconnect, and optionally
/// on your own stall timeout (5 s is a reasonable choice).
class PetReassembler {
  int? _messageId;
  int _total = 0;
  final BytesBuilder _data = BytesBuilder(copy: true);

  /// True while a message is partially received.
  bool get inProgress => _messageId != null;

  void reset() {
    _messageId = null;
    _total = 0;
    _data.clear();
  }

  /// Feeds one GATT characteristic value. Returns the frame once complete,
  /// otherwise null.
  PetFrame? feed(List<int> value) {
    try {
      if (value.length <= petFragmentHeaderSize ||
          value.length > petFragmentHeaderSize + petMaxFrameSize) {
        _fail('fragment has no data or exceeds maximum size');
      }
      final Uint8List bytes =
          value is Uint8List ? value : Uint8List.fromList(value);
      final ByteData view = ByteData.sublistView(bytes);
      final int count = bytes.length - petFragmentHeaderSize;

      if (bytes[0] != petFragmentMagic || bytes[1] != petVersion) {
        _fail('invalid fragment magic/version');
      }
      final int messageId = view.getUint16(2, Endian.little);
      final int total = view.getUint16(4, Endian.little);
      final int offset = view.getUint16(6, Endian.little);

      if (total < petHeaderSize ||
          total > petMaxFrameSize ||
          offset >= total ||
          offset + count > total) {
        _fail('invalid fragment length/offset');
      }
      if (offset == 0) {
        reset();
        _messageId = messageId;
        _total = total;
      }
      if (_messageId != messageId ||
          _total != total ||
          offset != _data.length) {
        _fail('fragment is not contiguous or message identity changed');
      }
      _data.add(Uint8List.sublistView(bytes, petFragmentHeaderSize));

      if (_data.length == total) {
        final PetFrame frame = decodeFrame(_data.toBytes());
        reset();
        return frame;
      }
      return null;
    } on PetProtocolException {
      reset();
      rethrow;
    }
  }
}

/// The 20-byte Status **Read** snapshot.
///
/// This is a different format from a Status **Indicate**: the Read value has no
/// fragment header and no frame header, so it must never be fed to a
/// [PetReassembler].
class PetStatusSnapshot {
  const PetStatusSnapshot({
    required this.state,
    required this.flags,
    required this.bootId,
    required this.configId,
    required this.requestedMask,
    required this.dropped,
  });

  final PetState? state;
  final int flags;
  final int bootId;
  final int configId;

  /// The mask currently *requested*. For the mask actually running, send
  /// GET_CONFIG and read `activeMask`.
  final int requestedMask;
  final int dropped;

  bool get dataSubscribed => (flags & 0x01) != 0;
  bool get statusSubscribed => (flags & 0x02) != 0;
  bool get connected => (flags & 0x04) != 0;
  bool get timeSynced => (flags & 0x08) != 0;

  @override
  String toString() => 'PetStatusSnapshot(state=${state?.name}, '
      'boot=$bootId, config=$configId, '
      'mask=0x${requestedMask.toRadixString(16)}, dropped=$dropped)';
}

PetStatusSnapshot decodeStatusRead(List<int> value) {
  if (value.length != 20) _fail('status Read must be 20 bytes');
  final Uint8List bytes =
      value is Uint8List ? value : Uint8List.fromList(value);
  final ByteData view = ByteData.sublistView(bytes);
  if (bytes[0] != petVersion) _fail('unsupported status version');
  return PetStatusSnapshot(
    state: PetState.fromValue(bytes[1]),
    flags: view.getUint16(2, Endian.little),
    bootId: view.getUint32(4, Endian.little),
    configId: view.getUint32(8, Endian.little),
    requestedMask: view.getUint32(12, Endian.little),
    dropped: view.getUint32(16, Endian.little),
  );
}

/// One sensor's capability record inside a GET_CAPABILITIES body.
class PetSensorCapability {
  const PetSensorCapability({
    required this.sensorId,
    required this.format,
    required this.available,
    required this.flags,
    required this.rates,
  });

  final int sensorId;
  final int format;

  /// flags bit0. For GPS this is only true once a checksum-valid NMEA sentence
  /// was seen during the ~2.2 s probe window — a ready UART is not enough.
  final bool available;
  final int flags;
  final List<int> rates;
}

/// GET_CAPABILITIES response body.
class PetCapabilities {
  const PetCapabilities({
    required this.supportedMask,
    required this.availableMask,
    required this.maxFrameSize,
    required this.queueCapacity,
    required this.sensors,
  });

  final int supportedMask;

  /// Modules successfully probed during *this* boot.
  final int availableMask;
  final int maxFrameSize;

  /// Ring-buffer depth in sample frames (32 today), shared by all sensors.
  /// Not 32 seconds and not 32 BLE fragments.
  final int queueCapacity;
  final List<PetSensorCapability> sensors;
}

/// GET_CONFIG / SET_CONFIG / START / STOP response body (32 bytes).
class PetConfigStatus {
  const PetConfigStatus({
    required this.config,
    required this.state,
    required this.dropped,
    required this.readErrors,
    required this.availableMask,
    required this.activeMask,
  });

  final PetConfig config;
  final PetState? state;

  /// Frames discarded by queue overflow, send failure, and explicit
  /// STOP/config changes — not a wireless packet-loss counter.
  final int dropped;
  final int readErrors;
  final int availableMask;

  /// What is actually collecting right now. 0 after STOP.
  final int activeMask;

  bool active(PetSensor sensor) => (activeMask & sensor.maskBit) != 0;
  bool available(PetSensor sensor) => (availableMask & sensor.maskBit) != 0;

  @override
  String toString() => 'PetConfigStatus(${state?.name}, '
      'active=0x${activeMask.toRadixString(16)}, '
      'available=0x${availableMask.toRadixString(16)}, '
      'dropped=$dropped, readErrors=$readErrors)';
}

/// TIME_SYNC response body (24 bytes).
///
/// This does not turn the MCU's monotonic clock into UTC; it gives you the
/// three timestamps needed to build your own mapping. `deviceTxUs` is when the
/// result was *built*, not when it was transmitted, so keep the samples with
/// the smallest round trip and re-sync periodically. These values do not
/// provide microsecond-accurate cross-device synchronisation.
class PetTimeSync {
  const PetTimeSync({
    required this.hostUnixUs,
    required this.deviceRxUs,
    required this.deviceTxUs,
  });

  final int hostUnixUs;
  final int deviceRxUs;
  final int deviceTxUs;
}

/// A decoded response frame. [body] is set when [result] is OK, and also for
/// START returning IO_ERROR — which still carries the 32-byte config/status
/// body so the app can read the real `activeMask` instead of assuming a full
/// rollback. For any other failure, do not assume a body is present.
class PetResponse {
  const PetResponse({
    required this.requestId,
    required this.opcode,
    required this.rawOpcode,
    required this.result,
    required this.rawResult,
    required this.configId,
    required this.bodyBytes,
    this.body,
  });

  final int requestId;
  final PetOpcode? opcode;
  final int rawOpcode;
  final PetResult? result;
  final int rawResult;
  final int configId;
  final Uint8List bodyBytes;

  /// [PetCapabilities], [PetConfigStatus] or [PetTimeSync] when decodable.
  final Object? body;

  bool get isOk => result == PetResult.ok;

  @override
  String toString() => 'PetResponse(#$requestId ${opcode?.name ?? rawOpcode} '
      '=> ${result?.name ?? rawResult}, config=$configId)';
}

/// Decodes a `kind == response` frame. The frame header's `sequence` is the
/// original `request_id`, echoed back.
PetResponse decodeResponse(PetFrame frame) {
  if (frame.kind != PetKind.response) _fail('frame is not a response');
  final Uint8List payload = frame.payload;
  if (payload.length < 8) _fail('response header truncated');
  final ByteData view = ByteData.sublistView(payload);

  final int rawOpcode = payload[0];
  final int rawResult = payload[1];
  if (view.getUint16(2, Endian.little) != 0) {
    _fail('response reserved field is nonzero');
  }
  final int configId = view.getUint32(4, Endian.little);
  final Uint8List body = Uint8List.sublistView(payload, 8);

  final PetOpcode? opcode = PetOpcode.fromValue(rawOpcode);
  final PetResult? result = PetResult.fromValue(rawResult);

  Object? decoded;
  final bool startPartialFailure = opcode == PetOpcode.start &&
      result == PetResult.ioError &&
      body.length == 32;
  if (result == PetResult.ok || startPartialFailure) {
    decoded = _decodeResponseBody(opcode, body);
  }

  return PetResponse(
    requestId: frame.sequence,
    opcode: opcode,
    rawOpcode: rawOpcode,
    result: result,
    rawResult: rawResult,
    configId: configId,
    bodyBytes: body,
    body: decoded,
  );
}

Object? _decodeResponseBody(PetOpcode? opcode, Uint8List body) {
  switch (opcode) {
    case PetOpcode.getCapabilities:
      if (body.length < 13) _fail('capabilities header truncated');
      final ByteData view = ByteData.sublistView(body);
      final int supported = view.getUint32(0, Endian.little);
      final int available = view.getUint32(4, Endian.little);
      final int maxFrame = view.getUint16(8, Endian.little);
      final int queue = view.getUint16(10, Endian.little);
      final int count = body[12];
      int offset = 13;
      final List<PetSensorCapability> sensors = <PetSensorCapability>[];
      for (int i = 0; i < count; i++) {
        if (body.length - offset < 4) {
          _fail('capability sensor record truncated');
        }
        final int sensorId = body[offset];
        final int format = body[offset + 1];
        final int rateCount = body[offset + 2];
        final int flags = body[offset + 3];
        offset += 4;
        if (body.length - offset < 2 * rateCount) {
          _fail('capability rate list truncated');
        }
        final List<int> rates = <int>[
          for (int r = 0; r < rateCount; r++)
            view.getUint16(offset + r * 2, Endian.little),
        ];
        offset += 2 * rateCount;
        // Records are variable length (4 + 2 * rate_count) — advance by the
        // parsed length, never by a fixed stride.
        sensors.add(PetSensorCapability(
          sensorId: sensorId,
          format: format,
          available: (flags & 1) != 0,
          flags: flags,
          rates: rates,
        ));
      }
      if (offset != body.length) _fail('extra bytes after capabilities');
      return PetCapabilities(
        supportedMask: supported,
        availableMask: available,
        maxFrameSize: maxFrame,
        queueCapacity: queue,
        sensors: sensors,
      );

    case PetOpcode.getConfig:
    case PetOpcode.setConfig:
    case PetOpcode.start:
    case PetOpcode.stop:
      if (body.length != 32) {
        _fail('configuration/status response must be 32 bytes');
      }
      final ByteData view = ByteData.sublistView(body);
      if (body[15] != 0) _fail('configuration reserved byte nonzero');
      return PetConfigStatus(
        config: decodeConfig(Uint8List.sublistView(body, 0, 14)),
        state: PetState.fromValue(body[14]),
        dropped: view.getUint32(16, Endian.little),
        readErrors: view.getUint32(20, Endian.little),
        availableMask: view.getUint32(24, Endian.little),
        activeMask: view.getUint32(28, Endian.little),
      );

    case PetOpcode.timeSync:
      if (body.length != 24) _fail('time-sync response must be 24 bytes');
      final ByteData view = ByteData.sublistView(body);
      return PetTimeSync(
        hostUnixUs: view.getUint64(0, Endian.little),
        deviceRxUs: view.getUint64(8, Endian.little),
        deviceTxUs: view.getUint64(16, Endian.little),
      );

    case null:
      return null;
  }
}

/// Hex helper for logs and tests — the firmware docs quote example frames as
/// hex, so being able to print and parse that form directly is useful.
String petToHex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List petFromHex(String hex) {
  final String clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd) _fail('hex string must have an even length');
  return Uint8List.fromList(<int>[
    for (int i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// Only used by the sample decoder for NMEA, kept here so the protocol layer
/// owns every `dart:convert` use.
String petAsciiDecode(List<int> bytes) {
  try {
    return ascii.decode(bytes);
  } on FormatException {
    _fail('NMEA sentence is not ASCII');
  }
}
