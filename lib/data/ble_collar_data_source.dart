/// The real link to the collar: BLE GATT speaking the PET v1 protocol.
///
/// This replaces [WebSocketCollarDataSource] for actual hardware. The collar is
/// a Seeed XIAO nRF54LM20A Sense, which has **no WiFi at all**, so the old
/// `ws://<collar-ip>:81` path can never reach it — it only ever talked to the
/// mock server. See ../../PROTOCOL_CHANGE.md.
///
/// This class lives in the app layer rather than in `collar_data` because it
/// needs flutter_blue_plus (a Flutter plugin) and `collar_geo` (for NMEA). Both
/// of those packages stay pure Dart and runnable with a bare `dart` SDK, which
/// is what lets the whole protocol be tested without hardware.
///
/// What it does on connect, in the order the firmware manual requires:
///   1. scan by service UUID (the advertised name is for display only)
///   2. connect, and ask for a larger MTU (fewer fragments, same format)
///   3. subscribe **Status Indicate first**, then Data Notify — separate CCCDs
///   4. Read Status, check `version == 1`, remember `boot_id`
///   5. GET_CAPABILITIES + GET_CONFIG, so we know what actually exists
///   6. STOP → SET_CONFIG → START, to drop the microphone and calm the IMU
///
/// Why step 6 matters: the device powers on collecting everything, and the
/// microphone alone is about 32 kB/s of PCM. Over BLE that starves the sensors
/// we actually want, and the firmware's queue is 32 frames shared across all
/// sensors, so overflow shows up as `dropped` climbing and GPS fixes going
/// missing. Turning the mic off and running the IMU at 26 Hz instead of 104 Hz
/// keeps the link inside its budget.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:collar_data/collar_data.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GATT identifiers from the firmware manual, section 1.
class PetGatt {
  static final Guid service =
      Guid('7e570001-7b4b-4b6b-8b9b-5d8f1a6c0001');

  /// Notify — sample frame fragments.
  static final Guid data = Guid('7e570002-7b4b-4b6b-8b9b-5d8f1a6c0001');

  /// Write with response — command frame fragments.
  static final Guid control = Guid('7e570003-7b4b-4b6b-8b9b-5d8f1a6c0001');

  /// Read (20-byte snapshot) and Indicate (result frame fragments). **The two
  /// formats are different** — a Read value must never be fed to a
  /// reassembler.
  static final Guid status = Guid('7e570004-7b4b-4b6b-8b9b-5d8f1a6c0001');

  /// Advertised name. Use the service UUID to filter; this is for display.
  static const String advertisedName = 'PET-Sense';
}

/// Thrown when the device answers a command with a non-OK result.
class PetCommandException implements Exception {
  const PetCommandException(this.opcode, this.result);
  final PetOpcode opcode;
  final PetResult? result;

  @override
  String toString() =>
      'PetCommandException: ${opcode.name} returned ${result?.name ?? 'an unknown result'}';
}


/// Bluetooth が使える状態になるまで待つ。
///
/// iOS で `CBManagerStateUnknown` が返るのは、電源が切れている場合だけでなく
/// **CBCentralManager の初期化が終わる前にスキャンした場合**もある。アプリ起動
/// 直後に測定ボタンを押すとこれに当たるので、状態が確定するまで待ってから
/// 判断する。待っても unknown/off のままなら、本当にオフだと分かる。
Future<void> waitForBluetoothReady({
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return;
  try {
    await FlutterBluePlus.adapterState
        .firstWhere((BluetoothAdapterState s) =>
            s == BluetoothAdapterState.on ||
            s == BluetoothAdapterState.off ||
            s == BluetoothAdapterState.unauthorized)
        .timeout(timeout);
  } on TimeoutException {
    // 状態が来ない端末もある。その場合は下の判定に任せる。
  }
  final BluetoothAdapterState now = FlutterBluePlus.adapterStateNow;
  if (now == BluetoothAdapterState.unauthorized) {
    throw const BluetoothUnavailable(BluetoothUnavailableReason.unauthorized);
  }
  if (now != BluetoothAdapterState.on) {
    throw const BluetoothUnavailable(BluetoothUnavailableReason.off);
  }
}

enum BluetoothUnavailableReason { off, unauthorized }

/// Bluetooth そのものが使えない状態。プラットフォームの生の例外を
/// そのまま画面に出さないために型で区別する。
class BluetoothUnavailable implements Exception {
  const BluetoothUnavailable(this.reason);
  final BluetoothUnavailableReason reason;

  @override
  String toString() => 'BluetoothUnavailable(${reason.name})';
}

/// One collar seen while scanning.
class CollarScanHit {
  const CollarScanHit({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });

  /// The platform's device identifier. On Android this is the MAC address; on
  /// iOS it is a CoreBluetooth UUID that is **stable per phone but different on
  /// another phone**, so it can be remembered locally but never shared between
  /// devices as if it identified the hardware.
  final String remoteId;
  final String name;

  /// Signal strength in dBm; closer to zero is stronger. Useful for telling
  /// two collars apart by walking towards one.
  final int rssi;
}

/// Scans for collars without connecting, for a device-picker screen.
///
/// Filters on the service UUID rather than the advertised name: the manual is
/// explicit that the name is for display only and is not an authentication
/// check — this development firmware has no pairing or link encryption.
Stream<List<CollarScanHit>> scanForCollars({
  Duration timeout = const Duration(seconds: 10),
}) {
  final Map<String, CollarScanHit> seen = <String, CollarScanHit>{};
  late final StreamController<List<CollarScanHit>> out;
  StreamSubscription<List<ScanResult>>? sub;

  Future<void> stop() async {
    await sub?.cancel();
    sub = null;
    try {
      await FlutterBluePlus.stopScan();
    } on Exception {
      // already stopped
    }
    if (!out.isClosed) await out.close();
  }

  out = StreamController<List<CollarScanHit>>(
    onListen: () async {
      try {
        await waitForBluetoothReady();
        sub = FlutterBluePlus.scanResults.listen((List<ScanResult> results) {
          bool changed = false;
          for (final ScanResult r in results) {
            if (!r.advertisementData.serviceUuids.contains(PetGatt.service)) {
              continue;
            }
            final String id = r.device.remoteId.str;
            final CollarScanHit hit = CollarScanHit(
              remoteId: id,
              name: r.device.platformName.isEmpty
                  ? PetGatt.advertisedName
                  : r.device.platformName,
              rssi: r.rssi,
            );
            final CollarScanHit? prev = seen[id];
            if (prev == null || prev.rssi != hit.rssi) {
              seen[id] = hit;
              changed = true;
            }
          }
          if (changed && !out.isClosed) {
            out.add(seen.values.toList(growable: false));
          }
        });
        await FlutterBluePlus.startScan(
          withServices: <Guid>[PetGatt.service],
          timeout: timeout,
        );
        // startScan completes when the timeout elapses.
        await stop();
      } on Exception catch (e) {
        if (!out.isClosed) out.addError(e);
        await stop();
      }
    },
    onCancel: stop,
  );
  return out.stream;
}

class BleCollarDataSource implements CollarDataSource {
  BleCollarDataSource({
    this.scanTimeout = const Duration(seconds: 15),
    this.commandTimeout = const Duration(seconds: 5),
    this.commandRetries = 2,
    this.snapshotInterval = const Duration(milliseconds: 250),
    // 104 Hz。26 Hz だと心弾動の 8–40 Hz 帯がナイキスト(13 Hz)の外に出て
    // しまい、心拍が一切取れない。実機で 221.4 bpm という嘘の値が出た原因。
    this.imuRateHz = 104,
    this.temperatureRateHz = 2,
    this.enableMicrophone = false,
    this.preferredImu = PetSensor.onboardImu,
  });

  final Duration scanTimeout;

  /// Per-command wait before a retry. This is a client-side policy, not a
  /// firmware timing guarantee.
  final Duration commandTimeout;
  final int commandRetries;

  /// How often a merged snapshot is emitted. The IMU alone would otherwise
  /// push 26–104 samples a second into the chart buffer, which holds 600 —
  /// about six seconds of history at full rate. Every frame is still archived;
  /// only the UI-facing cadence is throttled.
  final Duration snapshotInterval;

  final int imuRateHz;
  final int temperatureRateHz;

  /// Off by default — see the note about 32 kB/s in the class docs.
  final bool enableMicrophone;

  /// Which IMU feeds the displayed values. The two chips have unaligned axes,
  /// so mixing them makes the series jump.
  final PetSensor preferredImu;

  final StreamController<RawFrame> _frames =
      StreamController<RawFrame>.broadcast();
  final StreamController<ConnStatus> _status =
      StreamController<ConnStatus>.broadcast();

  /// Every IMU sample, un-throttled.
  ///
  /// [frames] is deliberately slowed to [snapshotInterval] because a chart does
  /// not need 104 updates a second. Heart rate does: the beat signal lives at
  /// 8–40 Hz, so the analyser needs the full stream or there is nothing to
  /// filter. Anything measuring vital signs listens here, not to [frames].
  final StreamController<PetImuSample> _imu =
      StreamController<PetImuSample>.broadcast();

  // One reassembler per characteristic, as the manual requires: Data and
  // Status carry independent fragment streams and must never be merged.
  final PetReassembler _dataRx = PetReassembler();
  final PetReassembler _statusRx = PetReassembler();

  final NmeaAggregator _nmea = NmeaAggregator();
  late final PetSampleAssembler _assembler =
      PetSampleAssembler(preferredImu: preferredImu);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _data;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _statusChar;

  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  Timer? _snapshotTimer;
  Completer<PetResponse>? _pending;
  int _pendingRequestId = 0;
  int _nextRequestId = 1;
  int _nextMessageId = 1;
  int _mtu = 23;
  int? _bootId;
  bool _closed = false;
  bool _startedOnce = false;

  /// Frames whose fragments failed to reassemble. A climbing count means the
  /// transport is corrupting data — worth showing on a diagnostics screen
  /// rather than silently swallowing.
  int receiveErrors = 0;

  /// Last capability report, so the UI can say which modules this boot found.
  PetCapabilities? capabilities;

  /// Last config/status the device reported.
  PetConfigStatus? configStatus;

  /// Latest 20-byte Status snapshot.
  PetStatusSnapshot? statusSnapshot;

  @override
  Stream<RawFrame> get frames => _frames.stream;

  @override
  Stream<ConnStatus> get status => _status.stream;

  /// Full-rate IMU samples from [preferredImu]. See [_imu].
  Stream<PetImuSample> get imuSamples => _imu.stream;

  /// The IMU rate the device actually accepted, or null before START.
  int? get activeImuRateHz => _activeImuRateHz;
  int? _activeImuRateHz;

  /// The MTU that was negotiated. Below ~100 bytes a 104 Hz stream cannot fit,
  /// which is why [_applyConfig] lowers the rate in that case.
  int get negotiatedMtu => _mtu;

  /// Identifier of the collar we are attached to, once connected.
  String? get deviceRemoteId => _device?.remoteId.str;

  /// Advertised name, for display.
  String? get deviceName {
    final String? n = _device?.platformName;
    return (n == null || n.isEmpty) ? PetGatt.advertisedName : n;
  }

  /// True once the handshake finished and commands can be sent.
  bool get isReady => _control != null && _bootId != null;

  /// True while there is a usable GPS fix.
  bool get hasFix => _nmea.hasFix;

  void _emit(ConnStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  @override
  Future<void> connect() => connectTo();

  /// Connects, optionally to a specific known collar.
  ///
  /// [remoteId] skips scanning entirely, which is the difference between a
  /// ~1 second reconnect and a 15 second search. That is what makes a
  /// remembered-device list worth having: the slow part of connecting is
  /// finding the thing, not attaching to it.
  ///
  /// [startStreaming] is false by default so that being connected costs the
  /// collar almost nothing. The device powers on already collecting, so the
  /// handshake stops it; a measurement then starts it deliberately via
  /// [startStreaming]. Leaving it streaming to nobody would just drain its
  /// battery.
  Future<void> connectTo({
    String? remoteId,
    bool startStreaming = false,
  }) async {
    if (_closed) throw StateError('source is closed');
    _emit(ConnStatus.connecting);

    try {
      await waitForBluetoothReady();
      final BluetoothDevice device = remoteId != null
          ? BluetoothDevice.fromId(remoteId)
          : await _findDevice();
      _device = device;

      // Watch for drops before connecting, so a failure during setup is seen.
      _connSub = device.connectionState.listen(_onConnectionState);
      // ⚠️ flutter_blue_plus 2.x はこの引数を必須にしている。コードの都合では
      // なくライセンスの都合で、無償枠と有償枠を区別するために置かれている
      // (2.3.12 の bluetooth_device.dart 757行: "This is a paid license")。
      // 旧称 License.free が License.nonprofit に改名されており、無償で
      // 使える条件が「非営利」であることが名前で明示された。
      // **このアプリを商用リリースするならライセンス購入が必要。**
      // 代替は flutter_reactive_ble か flutter_blue_plus 1.x(制限導入前)。
      // 判断が必要な項目なので PROTOCOL_CHANGE.md にも記載した。
      await device.connect(
        timeout: const Duration(seconds: 20),
        license: License.nonprofit,
      );

      // A bigger MTU only means fewer fragments; the format is unchanged, and
      // the negotiated value is what matters, never the requested one.
      await _discover(device);
      // MTU はサービス探索の後に読む。iPhone で 52 Hz に落とされていたのは、
      // 接続直後の mtuNow がまだ 23 のままだったため(CoreBluetooth が実際の
      // 値を入れるのは探索のあと)。探索を先に済ませてから読む。
      _mtu = await _negotiateMtu(device);
      await _subscribe();
      await _handshake();
      if (startStreaming) {
        await this.startStreaming();
      }

      _snapshotTimer =
          Timer.periodic(snapshotInterval, (Timer _) => _emitSnapshot());
      _emit(ConnStatus.connected);
    } on Exception {
      _emit(ConnStatus.disconnected);
      rethrow;
    }
  }

  /// 実際に使える MTU を得る。
  ///
  /// Android は明示的に要求できる。iOS/macOS は CoreBluetooth が自分で決める
  /// ので `requestMtu` は例外になり、そこで 23 と決めつけていたのが
  /// 「104 Hz にしたのに 52 Hz で動く」不具合の原因だった(2026-09-13、実機)。
  /// 例外のあとは実際の値を読み、まだ入っていなければ通知を一度待つ。
  Future<int> _negotiateMtu(BluetoothDevice device) async {
    try {
      final int requested = await device.requestMtu(247);
      if (requested > 23) return requested;
    } on Exception {
      // iOS では必ずここに来る。異常ではない。
    }
    final int now = device.mtuNow;
    if (now > 23) return now;
    try {
      return await device.mtu.first.timeout(const Duration(seconds: 2));
    } on Exception {
      return now > 0 ? now : 23;
    }
  }

  Future<BluetoothDevice> _findDevice() async {
    // Filter by service UUID. Matching on the advertised name would also pick
    // up anything that decided to call itself PET-Sense, and the manual is
    // explicit that neither the name nor the UUID is an authentication check:
    // this development firmware has no pairing, bonding or link encryption.
    await FlutterBluePlus.startScan(
      withServices: <Guid>[PetGatt.service],
      timeout: scanTimeout,
    );

    try {
      await for (final List<ScanResult> results in FlutterBluePlus.scanResults) {
        for (final ScanResult r in results) {
          if (r.advertisementData.serviceUuids.contains(PetGatt.service)) {
            return r.device;
          }
        }
      }
    } finally {
      await FlutterBluePlus.stopScan();
    }
    throw TimeoutException('no PET-Sense collar found', scanTimeout);
  }

  Future<void> _discover(BluetoothDevice device) async {
    // If the OS cached an older service table, the manual's advice is to
    // disconnect and rediscover rather than working with stale handles.
    final List<BluetoothService> services = await device.discoverServices();
    final BluetoothService svc = services.firstWhere(
      (BluetoothService s) => s.uuid == PetGatt.service,
      orElse: () => throw StateError('PET service not found on this device'),
    );

    BluetoothCharacteristic find(Guid id) => svc.characteristics.firstWhere(
          (BluetoothCharacteristic c) => c.uuid == id,
          orElse: () => throw StateError('characteristic $id not found'),
        );

    _data = find(PetGatt.data);
    _control = find(PetGatt.control);
    _statusChar = find(PetGatt.status);
  }

  Future<void> _subscribe() async {
    // Order matters: Status Indicate first, then Data Notify. Each has its own
    // CCCD, and a command result can arrive as soon as Status is live.
    _statusSub = _statusChar!.onValueReceived.listen(_onStatusValue);
    await _statusChar!.setNotifyValue(true);

    _dataSub = _data!.onValueReceived.listen(_onDataValue);
    await _data!.setNotifyValue(true);
  }

  Future<void> _handshake() async {
    // 1) Read the snapshot and validate the protocol version before trusting
    //    any field layout.
    final PetStatusSnapshot snap =
        decodeStatusRead(await _statusChar!.read());
    statusSnapshot = snap;

    // A different boot_id means the device restarted: old sequence numbers and
    // any time mapping are meaningless, so start the merge state over.
    if (_bootId != null && _bootId != snap.bootId) {
      _assembler.reset();
      _nmea.reset();
    }
    _bootId = snap.bootId;

    // 2) Find out what this boot actually probed. GPS only counts as available
    //    once a checksum-valid NMEA sentence arrived inside the ~2.2 s window,
    //    so "UART ready" is not enough and a cold module can be missed.
    final PetResponse caps =
        await _command(PetOpcode.getCapabilities);
    if (caps.body case final PetCapabilities c) capabilities = c;

    final PetResponse cfg = await _command(PetOpcode.getConfig);
    if (cfg.body case final PetConfigStatus c) configStatus = c;

    // The device powers on collecting everything, including the microphone at
    // ~32 kB/s. Stop it here: being connected should be cheap, and a
    // measurement will configure and start it explicitly.
    final PetResponse stopped = await _command(PetOpcode.stop);
    if (stopped.body case final PetConfigStatus c) configStatus = c;
  }

  /// Configures the sensors for a vitals measurement and starts collection.
  ///
  /// Safe to call repeatedly: each call re-runs STOP → SET_CONFIG → START, so
  /// a second measurement over the same connection starts from a known state.
  Future<void> startStreaming() async {
    await _applyConfig();
  }

  /// STOP → SET_CONFIG → START, confirming each step.
  ///
  /// SET_CONFIG returns BUSY while collecting rather than quietly changing a
  /// running configuration, which is why STOP has to come first and be
  /// confirmed. STOP also discards the queue, so a brief gap in data is
  /// expected here.
  Future<void> _applyConfig() async {
    int mask = PetSensor.onboardImu.maskBit |
        PetSensor.bmi088.maskBit |
        PetSensor.mlx90615.maskBit |
        PetSensor.gps.maskBit;
    if (enableMicrophone) mask |= PetSensor.mic.maskBit;

    // The IMU rate has to fit the link. One 104 Hz IMU frame is 56 bytes, which
    // rides in a single notification once the MTU is large; at the 23-byte
    // minimum the same frame needs five fragments, i.e. ~520 notifications a
    // second, which no phone will sustain. Halving the rate is the honest
    // fallback — measured on 2026-09-12, 52 Hz still recovered the same heart
    // rate (77.0 vs 78.0 bpm), only with a weaker margin.
    // 1フレーム 56 バイト + 断片ヘッダ 8 バイト = 64 バイトが 1 通知
    // (MTU - 3) に収まるのは MTU 67 以上。そこを境にする。以前は 100 で
    // 切っていたが、根拠のない値だった。
    int rate = imuRateHz;
    if (_mtu < 67 && rate > 52) {
      rate = 52;
    }
    _activeImuRateHz = rate;

    // A disabled sensor must carry rate 0. GPS is the exception that looks like
    // a bug: its rate is 0 *while enabled*, because it is event-driven — the
    // mask bit alone decides whether it runs.
    final List<int> rates = <int>[
      rate,
      rate >= 100 ? 100 : 50,
      temperatureRateHz,
      0,
      enableMicrophone ? 16000 : 0,
    ];

    // STOP first and confirm it: SET_CONFIG returns BUSY while collecting
    // rather than quietly changing a running configuration.
    await _command(PetOpcode.stop);
    final PetResponse set = await _command(
      PetOpcode.setConfig,
      body: encodeConfig(mask: mask, rates: rates),
    );
    if (set.body case final PetConfigStatus c) configStatus = c;

    final PetResponse started = await _command(PetOpcode.start);
    if (started.body case final PetConfigStatus c) configStatus = c;
    _startedOnce = true;

    // START skips absent modules rather than failing outright, and on IO_ERROR
    // it still returns the real active mask, so partial success is documented
    // behaviour and deliberately not thrown. The answer to "is GPS running" is
    // configStatus.active(PetSensor.gps) — never the absence of an error.
  }

  /// Sends one command and waits for the matching result.
  ///
  /// Commands are strictly serial — one outstanding at a time — because the
  /// firmware keys results by `request_id`. A retry must resend the **exact
  /// same bytes and request_id**: the firmware caches the last 4 requests and
  /// replays the original result for an identical repeat, but answers
  /// ID_REUSE if the same ID arrives with different content.
  Future<PetResponse> _command(
    PetOpcode opcode, {
    List<int> body = const <int>[],
  }) async {
    if (_pending != null) {
      throw StateError('a command is already in flight');
    }
    final int requestId = _nextRequestId++;
    final Uint8List frame =
        encodeCommand(opcode: opcode, requestId: requestId, body: body);
    final int messageId = _nextMessageId++ & 0xFFFF;

    for (int attempt = 0; attempt <= commandRetries; attempt++) {
      final Completer<PetResponse> completer = Completer<PetResponse>();
      _pending = completer;
      _pendingRequestId = requestId;
      try {
        await _writeFragments(frame, messageId);
        final PetResponse resp = await completer.future.timeout(commandTimeout);
        if (resp.result == PetResult.ok ||
            (opcode == PetOpcode.start &&
                resp.result == PetResult.ioError)) {
          return resp;
        }
        // BUSY means "not in a state that allows this" — a bare retry will
        // keep failing, so surface it rather than burning the attempts.
        throw PetCommandException(opcode, resp.result);
      } on TimeoutException {
        if (attempt == commandRetries) {
          throw TimeoutException(
              '${opcode.name} got no result after ${commandRetries + 1} attempts',
              commandTimeout);
        }
        // Fall through and resend the identical frame and request_id.
      } finally {
        _pending = null;
      }
    }
    throw StateError('unreachable');
  }

  /// Writes a frame to Control, one fragment at a time, each awaiting its
  /// response. Never Write Without Response, never ATT long write: the
  /// firmware accepts neither.
  Future<void> _writeFragments(Uint8List frame, int messageId) async {
    // The firmware gives up on an unfinished command if fragments are more
    // than 5 s apart, so these writes must not be interleaved with anything.
    for (final Uint8List value
        in fragmentFrame(frame, messageId: messageId, mtu: _mtu)) {
      await _control!.write(value, withoutResponse: false);
    }
  }

  void _onStatusValue(List<int> value) {
    // A 20-byte value here is ambiguous in principle, but the Read snapshot is
    // fetched explicitly via read(); anything arriving through Indicate is a
    // fragmented result frame.
    try {
      final PetFrame? frame = _statusRx.feed(value);
      if (frame == null) return;
      final PetResponse resp = decodeResponse(frame);
      final Completer<PetResponse>? pending = _pending;
      if (pending != null &&
          !pending.isCompleted &&
          resp.requestId == _pendingRequestId) {
        pending.complete(resp);
      }
    } on PetProtocolException {
      receiveErrors++;
    }
  }

  void _onDataValue(List<int> value) {
    try {
      final PetFrame? frame = _dataRx.feed(value);
      if (frame == null) return;
      final PetSample sample = decodePetSample(frame);

      if (sample is PetGpsSample) {
        _handleNmea(sample);
      } else {
        _assembler.add(sample);
        // Pass the chosen IMU straight through at full rate for the vitals
        // pipeline. Mixing the two IMUs here would corrupt it: the chips have
        // unaligned axes, so alternating between them adds a step change to
        // every other sample.
        if (sample is PetImuSample &&
            sample.sensor == preferredImu &&
            !_imu.isClosed) {
          _imu.add(sample);
        }
      }

      // Archive every frame, throttle only what the UI sees. The bytes go with
      // it, so a decoder bug can be diagnosed from the capture later.
      _lastBytes = frame.payload;
    } on PetProtocolException {
      receiveErrors++;
    }
  }

  Uint8List? _lastBytes;

  void _handleNmea(PetGpsSample sample) {
    try {
      final NmeaFix? fix = parseNmea(sample.sentence);
      if (fix == null) return; // a sentence type we do not interpret

      _nmea.add(fix);
      // Quality metadata is recorded even with no fix: "0 satellites" is how
      // the UI can say "no sky view" instead of just showing nothing.
      _assembler.setFixQuality(
        fixQuality: _nmea.fixQuality,
        satellites: _nmea.satellites,
        hdop: _nmea.hdop,
      );

      // Only a sentence that actually had a fix may move the dog's position.
      // The collar emitted 1,200 well-formed sentences with zero fixes during
      // the 2026-09-11 bench test; plotting those would invent a location.
      if (fix.hasFix && fix.point != null) {
        final GeoPoint p = fix.point!;
        _assembler.setPosition(
          lat: p.lat,
          lng: p.lng,
          fixQuality: _nmea.fixQuality,
          satellites: _nmea.satellites,
          hdop: _nmea.hdop,
        );
      }
    } on NmeaFormatException {
      // The firmware only forwards checksum-valid sentences, so this means the
      // transport damaged the bytes.
      receiveErrors++;
    }
  }

  void _emitSnapshot() {
    if (_frames.isClosed) return;
    _frames.add(RawFrame(
      DateTime.now().millisecondsSinceEpoch,
      _assembler.buildRawMap(),
      bytes: _lastBytes,
    ));
  }

  void _onConnectionState(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.disconnected && !_closed) {
      // Reassemblers MUST be cleared on every disconnect: a half-received
      // frame from before the drop would otherwise corrupt the next one.
      _dataRx.reset();
      _statusRx.reset();
      _snapshotTimer?.cancel();
      _snapshotTimer = null;
      _emit(_startedOnce ? ConnStatus.reconnecting : ConnStatus.disconnected);
    }
  }

  /// Re-runs the post-connection handshake after a reconnect.
  ///
  /// The device keeps collecting into a bounded RAM queue while disconnected
  /// and resumes sending on resubscribe, so state must be re-read rather than
  /// assumed: subscriptions confirmed, reassemblers reset, Status re-read,
  /// config re-queried. Note that after a STOP the device will NOT restart on
  /// its own just because we resubscribed — that needs an explicit START.
  Future<void> resume() async {
    if (_device == null) return;
    _dataRx.reset();
    _statusRx.reset();
    await _subscribe();
    await _handshake();
    _snapshotTimer ??=
        Timer.periodic(snapshotInterval, (Timer _) => _emitSnapshot());
    _emit(ConnStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    _closed = true;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;

    // Leave the collar collecting unless we explicitly stop it; a normal
    // client exit should not silently change the device's state.
    try {
      await _dataSub?.cancel();
      await _statusSub?.cancel();
      await _connSub?.cancel();
      await _device?.disconnect();
    } on Exception {
      // already gone
    }
    _emit(ConnStatus.disconnected);
    if (!_frames.isClosed) await _frames.close();
    if (!_imu.isClosed) await _imu.close();
    if (!_status.isClosed) await _status.close();
  }

  /// Explicitly stops collection on the device. Call this instead of plain
  /// [disconnect] when the user turns monitoring off, so the collar is not
  /// left draining its battery.
  Future<void> stopCollecting() async {
    await _command(PetOpcode.stop);
  }
}
