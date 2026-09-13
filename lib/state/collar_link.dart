/// Owns the BLE connection to the collar, independently of any measurement.
///
/// Split out from [VitalsSession] because connecting and measuring are
/// different things to the user: they expect to pair once and then measure
/// whenever, the way a phone's Bluetooth settings work. It also removes a
/// 15-second scan from the front of every measurement.
///
/// The firmware accepts **one client at a time**, so holding this connection
/// means the Mac's `pet_ble_client.py` cannot attach — which is exactly why
/// disconnecting has to be as easy as connecting.
library;

import 'dart:async';

import 'package:collar_data/collar_data.dart';
import 'package:flutter/foundation.dart';

import '../data/ble_collar_data_source.dart';
import '../data/known_device.dart';

enum LinkState {
  disconnected,

  /// Looking for a collar because no known id was given.
  scanning,

  /// Attaching to a specific collar.
  connecting,
  connected,

  /// Tearing down. Shown so the button does not look stuck.
  disconnecting,
  failed,
}

class CollarLink extends ChangeNotifier {
  CollarLink({KnownDeviceStore? deviceStore})
      : deviceStore = deviceStore ?? KnownDeviceStore();

  final KnownDeviceStore deviceStore;

  LinkState state = LinkState.disconnected;
  String? errorMessage;

  /// Collars this phone has seen before.
  List<KnownDevice> known = const <KnownDevice>[];

  /// Collars visible right now, refreshed while [isScanning].
  List<CollarScanHit> discovered = const <CollarScanHit>[];

  BleCollarDataSource? _source;
  StreamSubscription<ConnStatus>? _statusSub;
  StreamSubscription<List<CollarScanHit>>? _scanSub;

  /// The collar we are attached to, or attempting to attach to.
  String? targetRemoteId;
  String? targetName;

  /// 次の測定で使う首輪。**選んだだけでは接続しない。**
  ///
  /// 接続の開始・停止は測定ボタンだけが行う。首輪画面にも接続ボタンを置くと、
  /// 片方でキャンセルしてももう片方の状態が残る不具合になるため、こちらは
  /// 「どれを使うか」の記録に留めている。null なら最初に見つかったものを使う。
  String? selectedRemoteId;
  String? selectedName;

  /// 前回つないだ首輪を既定の選択にする。
  void _restoreSelection() {
    if (selectedRemoteId != null) return;
    final Iterable<KnownDevice> used =
        known.where((KnownDevice d) => d.lastConnectedAt != null);
    if (used.isEmpty) return;
    final KnownDevice latest = used.reduce((KnownDevice a, KnownDevice b) =>
        a.lastConnectedAt!.isAfter(b.lastConnectedAt!) ? a : b);
    selectedRemoteId = latest.remoteId;
    selectedName = latest.displayName;
  }

  /// 使う首輪を選ぶ。接続はしない。
  void select(String remoteId, String name) {
    selectedRemoteId = remoteId;
    selectedName = name;
    notifyListeners();
  }

  void clearSelection() {
    selectedRemoteId = null;
    selectedName = null;
    notifyListeners();
  }

  BleCollarDataSource? get source => _source;
  bool get isConnected => state == LinkState.connected;
  bool get isBusy =>
      state == LinkState.scanning ||
      state == LinkState.connecting ||
      state == LinkState.disconnecting;
  bool get isScanning => _scanSub != null;

  /// Full-rate IMU samples, once connected. Null when there is no link.
  Stream<PetImuSample>? get imuSamples => _source?.imuSamples;

  int? get negotiatedMtu => _source?.negotiatedMtu;
  int? get activeImuRateHz => _source?.activeImuRateHz;
  PetCapabilities? get capabilities => _source?.capabilities;

  Future<void> loadKnown() async {
    known = await deviceStore.loadAll();
    _restoreSelection();
    notifyListeners();
  }

  /// The single entry point the UI needs: one tap connects, the next
  /// disconnects.
  ///
  /// Also cancels a connection *attempt*, which matters because the slow paths
  /// here are a 15-second scan and a 20-second connect timeout — without this,
  /// a mistaken tap would leave the user waiting with no way out.
  Future<void> toggle({String? remoteId}) async {
    if (isBusy || isConnected) {
      await disconnect();
      return;
    }
    await connect(remoteId: remoteId);
  }

  Future<void> connect({String? remoteId}) async {
    if (isBusy || isConnected) return;
    errorMessage = null;
    targetRemoteId = remoteId;
    // 登録済みならその表示名。初回接続でまだ登録されていない首輪は、
    // 選択時に覚えた名前を使う(なければ接続後に firmware 側の名前で埋まる)。
    targetName = remoteId == null
        ? null
        : known
                .where((KnownDevice d) => d.remoteId == remoteId)
                .map((KnownDevice d) => d.displayName)
                .firstOrNull ??
            (selectedRemoteId == remoteId ? selectedName : null);
    state = remoteId == null ? LinkState.scanning : LinkState.connecting;
    notifyListeners();

    await stopScan();
    final BleCollarDataSource src = BleCollarDataSource();
    _source = src;
    _statusSub = src.status.listen((ConnStatus s) {
      // A drop reported by the transport must move the UI out of "connected",
      // otherwise the button lies about the state.
      if (s == ConnStatus.disconnected && state == LinkState.connected) {
        state = LinkState.disconnected;
        targetRemoteId = null;
        notifyListeners();
      }
    });

    try {
      await src.connectTo(remoteId: remoteId);
      final String? id = src.deviceRemoteId;
      if (id != null) {
        await deviceStore.remember(id, src.deviceName ?? 'PET-Sense');
        await deviceStore.markConnected(id);
        targetRemoteId = id;
        targetName = src.deviceName;
        selectedRemoteId = id;
        selectedName = src.deviceName;
        await loadKnown();
      }
      state = LinkState.connected;
      notifyListeners();
    } on Exception catch (e) {
      errorMessage = friendlyError(e);
      await _teardown();
      // failed のまま留まらせない。ボタンはすぐ押し直せる状態に戻す。
      state = LinkState.disconnected;
      targetRemoteId = null;
      targetName = null;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_source == null && !isScanning) {
      state = LinkState.disconnected;
      targetRemoteId = null;
      notifyListeners();
      return;
    }
    state = LinkState.disconnecting;
    notifyListeners();
    await stopScan();
    await _teardown();
    state = LinkState.disconnected;
    targetRemoteId = null;
    targetName = null;
    notifyListeners();
  }

  Future<void> _teardown() async {
    final BleCollarDataSource? src = _source;
    _source = null;
    await _statusSub?.cancel();
    _statusSub = null;
    if (src != null) {
      try {
        // Stop the collar collecting before letting go, so it is not left
        // streaming into nothing.
        if (src.isReady) await src.stopCollecting();
      } on Exception {
        // never started, or already gone
      }
      try {
        await src.disconnect();
      } on Exception {
        // already gone
      }
    }
  }

  /// Starts a discovery scan for the device list. Independent of connecting.
  Future<void> startScan() async {
    if (isScanning || isConnected) return;
    discovered = const <CollarScanHit>[];
    notifyListeners();
    _scanSub = scanForCollars().listen(
      (List<CollarScanHit> hits) async {
        discovered = hits;
        // Remember every collar we see, not only the ones we connect to, so the
        // list is useful before the first successful connection.
        for (final CollarScanHit h in hits) {
          await deviceStore.remember(h.remoteId, h.name);
        }
        known = await deviceStore.loadAll();
        notifyListeners();
      },
      onError: (Object e) {
        errorMessage = friendlyError(e);
        notifyListeners();
      },
      onDone: () {
        _scanSub = null;
        notifyListeners();
      },
      cancelOnError: true,
    );
    notifyListeners();
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    notifyListeners();
  }

  Future<void> rename(String remoteId, String? nickname) async {
    await deviceStore.rename(remoteId, nickname);
    await loadKnown();
  }

  Future<void> forget(String remoteId) async {
    if (targetRemoteId == remoteId && (isConnected || isBusy)) {
      await disconnect();
    }
    if (selectedRemoteId == remoteId) {
      selectedRemoteId = null;
      selectedName = null;
    }
    await deviceStore.forget(remoteId);
    await loadKnown();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _statusSub?.cancel();
    _source?.disconnect();
    super.dispose();
  }
}

/// プラットフォームの生の例外を、言語に依存しない「原因コード」に変える。
///
/// 生の `PlatformException(startScan, bluetooth must be turned on.
/// (CBManagerStateUnknown), null, null)` を画面に出してしまっていたので、
/// 実際に出た文言に合わせて判定を足した。
///
/// 文言そのものはここでは決めない。日本語・英語・中国語の3言語があるので、
/// 表示する言葉は UI 側 (`errorText` + `AppStrings`) で選ぶ。
String friendlyError(Object e) {
  if (e is BluetoothUnavailable) {
    return switch (e.reason) {
      BluetoothUnavailableReason.off => 'bt_off',
      BluetoothUnavailableReason.unauthorized => 'bt_denied',
    };
  }
  final String s = e.toString();
  final String lower = s.toLowerCase();

  // iOS/Android が返す「オフ」系の言い回しを一括で拾う。
  if (lower.contains('must be turned on') ||
      lower.contains('bluetooth must be') ||
      lower.contains('cbmanagerstateunknown') ||
      lower.contains('cbmanagerstatepoweredoff') ||
      lower.contains('adapter is off') ||
      (lower.contains('bluetooth') && lower.contains('off'))) {
    return 'bt_off';
  }
  if (lower.contains('unauthorized') ||
      lower.contains('cbmanagerstateunauthorized') ||
      lower.contains('permission')) {
    return 'bt_denied';
  }
  if (e is TimeoutException || s.contains('no PET-Sense')) {
    return 'not_found';
  }
  if (s.contains('PET service not found')) {
    return 'wrong_device';
  }
  if (s.contains('characteristic')) {
    return 'old_firmware';
  }
  if (lower.contains('already connected') || lower.contains('busy')) {
    return 'busy';
  }
  return 'connect_failed';
}
