/// A collar this phone has seen before, so it can be reconnected without a
/// scan.
///
/// Modelled on how a phone's own Bluetooth settings behave: once a device is
/// known, you tap it and it connects. The gain is not cosmetic — attaching to a
/// known identifier takes about a second, while searching for it takes up to
/// the full scan timeout.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class KnownDevice {
  const KnownDevice({
    required this.remoteId,
    required this.name,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.lastConnectedAt,
    this.connectCount = 0,
    this.nickname,
  });

  /// The platform's identifier.
  ///
  /// ⚠️ On Android this is the hardware MAC address, but on iOS it is a
  /// CoreBluetooth UUID that is **generated per phone**. The same collar
  /// therefore has a different id on a different phone, so this must never be
  /// treated as the collar's serial number or synced between devices.
  final String remoteId;

  /// Advertised name, normally `PET-Sense`.
  final String name;

  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? lastConnectedAt;
  final int connectCount;

  /// A name the owner gave it, for when there is more than one collar.
  final String? nickname;

  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : name;

  /// Short form of the id, enough to tell two collars apart on screen without
  /// showing a full MAC address.
  String get shortId => remoteId.length <= 8
      ? remoteId
      : '…${remoteId.substring(remoteId.length - 8)}';

  KnownDevice copyWith({
    String? name,
    DateTime? lastSeenAt,
    DateTime? lastConnectedAt,
    int? connectCount,
    String? nickname,
  }) =>
      KnownDevice(
        remoteId: remoteId,
        name: name ?? this.name,
        firstSeenAt: firstSeenAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        connectCount: connectCount ?? this.connectCount,
        nickname: nickname ?? this.nickname,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': 1,
        'remote_id': remoteId,
        'name': name,
        'first_seen_at': firstSeenAt.toIso8601String(),
        'last_seen_at': lastSeenAt.toIso8601String(),
        'last_connected_at': lastConnectedAt?.toIso8601String(),
        'connect_count': connectCount,
        'nickname': nickname,
      };

  factory KnownDevice.fromJson(Map<String, dynamic> j) {
    DateTime t(Object? v, DateTime fallback) =>
        DateTime.tryParse((v ?? '').toString()) ?? fallback;
    final DateTime seen = t(j['last_seen_at'], DateTime(1970));
    return KnownDevice(
      remoteId: (j['remote_id'] ?? '').toString(),
      name: (j['name'] ?? 'PET-Sense').toString(),
      firstSeenAt: t(j['first_seen_at'], seen),
      lastSeenAt: seen,
      lastConnectedAt: j['last_connected_at'] == null
          ? null
          : DateTime.tryParse(j['last_connected_at'].toString()),
      connectCount: j['connect_count'] is num
          ? (j['connect_count'] as num).toInt()
          : 0,
      nickname: j['nickname']?.toString(),
    );
  }
}

/// Stores known collars as a single JSON file.
///
/// Rewritten whole on every change rather than appended to: unlike
/// measurements, this is current state rather than a log, and there will only
/// ever be a handful of entries.
class KnownDeviceStore {
  KnownDeviceStore({this.fileName = 'known_devices.json'});

  final String fileName;
  File? _file;

  Future<File> _open() async {
    if (_file != null) return _file!;
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$fileName');
    if (!await f.exists()) {
      await f.create(recursive: true);
      await f.writeAsString('[]');
    }
    _file = f;
    return f;
  }

  /// Most recently seen first.
  Future<List<KnownDevice>> loadAll() async {
    final File f = await _open();
    final String raw = await f.readAsString();
    if (raw.trim().isEmpty) return <KnownDevice>[];
    try {
      final Object? j = jsonDecode(raw);
      if (j is! List) return <KnownDevice>[];
      final List<KnownDevice> out = j
          .whereType<Map<String, dynamic>>()
          .map(KnownDevice.fromJson)
          .where((KnownDevice d) => d.remoteId.isNotEmpty)
          .toList();
      out.sort((KnownDevice a, KnownDevice b) =>
          b.lastSeenAt.compareTo(a.lastSeenAt));
      return out;
    } on FormatException {
      // A corrupt file must not lock the user out of connecting.
      return <KnownDevice>[];
    }
  }

  Future<void> _writeAll(List<KnownDevice> devices) async {
    final File f = await _open();
    await f.writeAsString(
      jsonEncode(devices.map((KnownDevice d) => d.toJson()).toList()),
      flush: true,
    );
  }

  /// Records that a collar was seen, creating or refreshing its entry.
  Future<KnownDevice> remember(String remoteId, String name) async {
    final List<KnownDevice> all = await loadAll();
    final DateTime now = DateTime.now();
    final int i = all.indexWhere((KnownDevice d) => d.remoteId == remoteId);
    KnownDevice updated;
    if (i >= 0) {
      updated = all[i].copyWith(name: name, lastSeenAt: now);
      all[i] = updated;
    } else {
      updated = KnownDevice(
        remoteId: remoteId,
        name: name,
        firstSeenAt: now,
        lastSeenAt: now,
      );
      all.add(updated);
    }
    await _writeAll(all);
    return updated;
  }

  /// Records a successful connection.
  Future<void> markConnected(String remoteId) async {
    final List<KnownDevice> all = await loadAll();
    final int i = all.indexWhere((KnownDevice d) => d.remoteId == remoteId);
    if (i < 0) return;
    final DateTime now = DateTime.now();
    all[i] = all[i].copyWith(
      lastSeenAt: now,
      lastConnectedAt: now,
      connectCount: all[i].connectCount + 1,
    );
    await _writeAll(all);
  }

  Future<void> rename(String remoteId, String? nickname) async {
    final List<KnownDevice> all = await loadAll();
    final int i = all.indexWhere((KnownDevice d) => d.remoteId == remoteId);
    if (i < 0) return;
    all[i] = all[i].copyWith(nickname: nickname ?? '');
    await _writeAll(all);
  }

  Future<void> forget(String remoteId) async {
    final List<KnownDevice> all = await loadAll();
    all.removeWhere((KnownDevice d) => d.remoteId == remoteId);
    await _writeAll(all);
  }
}
