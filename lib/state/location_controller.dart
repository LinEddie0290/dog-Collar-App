/// T36：犬の位置と安全区（家）。
///
/// 位置は記録の入力（首輪 BLE／模拟）から [attach] で受け取る（前は古い CollarController を見ていて、
/// そちらは一度もつながれていなかったので、位置はずっと空だった）。
/// 出入りの判定は [ZoneJudge]（余裕 20 m・外が 2 回続く、D-059 M5）。
/// 「可能走失」（外＋BLE が切れた、M3）と「回到了安全区」のときだけ通知する（M4）。
/// 家は地図の長押しで決め（M2）、shared_preferences に残す。
library;

import 'dart:async';
import 'dart:convert';

import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/gps_track.dart';
import '../data/safe_zone.dart';
import '../data/temp_judge.dart' show localDateOf;
import 'app_notifier.dart';

class LocationController extends ChangeNotifier {
  LocationController({
    this.notifier,
    int Function()? nowMs,
    Duration? tick = const Duration(seconds: 15),
    this.offlineAfter = const Duration(minutes: 2),
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (tick != null) _timer = Timer.periodic(tick, (_) => _checkOffline());
  }

  final AppNotifier? notifier;
  final int Function() _nowMs;
  final Duration offlineAfter;
  Timer? _timer;

  static const String _kZone = 'location.home_zone';
  static const int maxEvents = 50;

  /// 家（安全区）。まだ決めていなければ null（判定しない）。
  SafeZone? zone;
  ZoneJudge? _judge;

  /// 判定を始める前（家を決める前）の最後の位置も覚えておく。
  LocationFix? lastFix;

  /// 出た・戻った・可能走失（新しいものが先）。
  final List<ZoneEvent> events = <ZoneEvent>[];

  bool _linked = true;
  StreamSubscription<LocationFix>? _sub;
  bool _wasOffline = false;

  // ---- 地図の画面（MapPage）が使うもの

  GeoPoint? get latestPosition => lastFix?.point;
  int? get latestAccuracyM => lastFix?.accuracyM;

  /// 最後の位置が古い（[offlineAfter] より前）。
  bool get isOffline => lastFix != null && _nowMs() - lastFix!.tMs > offlineAfter.inMilliseconds;

  Duration? get sinceLastFix => lastFix == null ? null : Duration(milliseconds: _nowMs() - lastFix!.tMs);

  /// 地図に描く円（高德の部品が使う形）。
  GeofenceConfig? get homeFence {
    final SafeZone? z = zone;
    return z == null ? null : GeofenceConfig(id: 'home', name: z.name, center: z.center, radiusM: z.radiusM);
  }

  ZoneEvent? get lastEvent => events.isEmpty ? null : events.first;

  // ---- 状態

  ZoneState get state => _judge?.state ?? ZoneState.unknown;
  double? get distanceM {
    final SafeZone? z = zone;
    final LocationFix? f = lastFix;
    return z == null || f == null ? null : z.distanceTo(f.point);
  }

  bool get linked => _linked;
  bool get attached => _sub != null;

  // ---- 家

  Future<void> loadSaved() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? j = p.getString(_kZone);
      if (j == null) return;
      final SafeZone? z = SafeZone.fromJson(jsonDecode(j) as Map<String, dynamic>);
      if (z != null) _setZone(z);
      notifyListeners();
    } catch (_) {
      // 読めなければ「家はまだない」のまま
    }
  }

  /// 家を決める（地図の長押し、WGS84 で渡す）。前の家での出入りの状態は持ち越さない。
  Future<void> setHome(GeoPoint center, double radiusM) async {
    _setZone(SafeZone(center: center, radiusM: radiusM));
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_kZone, jsonEncode(zone!.toJson()));
    } catch (_) {
      // 保存できなくても今回は使える
    }
  }

  void _setZone(SafeZone z) {
    zone = z;
    final ZoneJudge j = ZoneJudge(zone: z, linked: _linked);
    _judge = j;
    final LocationFix? f = lastFix;
    if (f != null) j.update(f); // 今の位置から判定を始める（出来事は出さない）
  }

  // ---- 位置の入力

  /// 記録を始めたとき（ContinuousMonitor から）。つながっている状態で始める。
  void attach(Stream<LocationFix> fixes) {
    unawaited(_sub?.cancel());
    _sub = fixes.listen(addFix);
    setLinked(true);
  }

  /// 記録を止めたとき。最後の位置と状態は残す（地図・安全タブに出し続ける）。
  void detach() {
    unawaited(_sub?.cancel());
    _sub = null;
    notifyListeners();
  }

  // ---- T12：今日の屋外の距離・時間（安全タブ）。1 日まとめと同じ計算（GpsTracker）
  final GpsTracker _tracker = GpsTracker();
  String? _todayDate;
  double todayOutdoorM = 0;
  double todayOutdoorMin = 0;

  /// 今日（UTC＋8）の屋外の距離・時間の一行。今日の位置がまだなければ null。
  String? get todayOutdoorLine {
    final LocationFix? f = lastFix;
    if (f == null || _todayDate != localDateOf(_nowMs())) return null;
    return '今天户外：${outdoorText(todayOutdoorM, todayOutdoorMin)}';
  }

  void _track(LocationFix f) {
    final String d = localDateOf(f.tMs);
    if (d != _todayDate) {
      _todayDate = d;
      todayOutdoorM = 0;
      todayOutdoorMin = 0;
      _tracker.reset();
    }
    final int? acc = f.accuracyM;
    final TrackPoint? p = _tracker.add(
        GpsPoint(tMs: f.tMs, lat: f.point.lat, lng: f.point.lng, hdop: acc == null ? null : acc / 5));
    if (p != null) {
      todayOutdoorM += p.stepM;
      todayOutdoorMin += p.dtS / 60;
    }
  }

  void addFix(LocationFix f) {
    lastFix = f;
    _wasOffline = false;
    _track(f);
    final ZoneJudge? j = _judge;
    if (j != null) _handle(j.update(f));
    notifyListeners();
  }

  /// 首輪とスマホの BLE がつながった／切れた（模拟では「模拟断开」）。
  void setLinked(bool linked) {
    if (linked == _linked) return;
    _linked = linked;
    final ZoneJudge? j = _judge;
    if (j != null) _handle(j.setLinked(linked, _nowMs()));
    notifyListeners();
  }

  void _handle(List<ZoneEvent> evs) {
    for (final ZoneEvent e in evs) {
      events.insert(0, e);
      if (events.length > maxEvents) events.removeLast();
      final String d = distanceText(e.distanceM);
      switch (e.kind) {
        case ZoneEventKind.lost:
          unawaited(notifier?.show(
              key: 'zone', title: '可能走失', body: '狗在安全区外面（离家 $d），项圈和手机断开了。最后的位置在「安全」页。'));
        case ZoneEventKind.enter:
          unawaited(notifier?.show(key: 'zone', title: '回到了安全区', body: '狗回到了家附近（离中心 $d）。'));
        case ZoneEventKind.exit:
          break; // 外に出ただけ（散歩など）は通知しない。安全タブに出す
      }
    }
  }

  void _checkOffline() {
    final bool off = isOffline;
    if (off != _wasOffline) {
      _wasOffline = off;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
