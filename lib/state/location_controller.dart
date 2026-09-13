import 'dart:async';

import 'package:collar_data/collar_data.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/foundation.dart';

import 'collar_controller.dart';

/// GPS 機能の状態。CollarController(接続・心拍・呼吸)とは別に持っている
/// のは、心拍/呼吸まわりのロジックと位置/囲い判定のロジックが関心事として
/// 独立しているため——`packages/collar_geo` が `collar_data` と別パッケージ
/// なのと同じ理由。
///
/// [CollarController] が受信した [SensorSample] を監視し、位置情報
/// (`lat`/`lng`)が乗っているものだけを取り出して、地理囲い判定に回す。
/// ソケットや JSON、フィルタの中身はここでも一切扱わない。
class LocationController extends ChangeNotifier {
  LocationController({
    required this.collar,
    GeofenceConfig? homeFence,
  }) : homeFence = homeFence ?? defaultHomeFence {
    _tracker = GeofenceTracker(<GeofenceConfig>[this.homeFence]);
    collar.addListener(_onCollarChanged);
    _offlineTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkOffline());
  }

  /// プレースホルダーの初期値。実際の「家」の座標が決まったら、設定画面
  /// などから [setHomeFence] で上書きする想定。
  static const GeofenceConfig defaultHomeFence = GeofenceConfig(
    id: 'home',
    name: 'home',
    center: GeoPoint(31.2304, 121.4737),
    radiusM: 150,
  );

  /// このぶん新しい位置が来なければ「オフライン(最後に確認された位置)」
  /// 扱いにする。前回 React Native 版で作った MapScreen と同じ閾値。
  static const Duration offlineThreshold = Duration(minutes: 2);

  final CollarController collar;
  late final GeofenceTracker _tracker;
  Timer? _offlineTimer;

  GeofenceConfig homeFence;

  /// 直近の位置(WGS84)。まだ一度も GPS フィックスを受信していなければ null。
  GeoPoint? latestPosition;

  /// 直近フィックスの精度の「目安」(メートル)。分からなければ null。
  ///
  /// ⚠️ これは実測値ではない。首輪は精度を一切送ってこないので、NMEA の
  /// GGA から取れる HDOP(無次元の倍率)に受信機ごとの定数 5m を掛けた
  /// 概算にすぎない。UI では必ず「目安」と分かる形で見せる。
  int? latestAccuracyM;

  /// 直近の測位品質(GGA の fix quality)。0 は未測位。
  int? latestFixQuality;

  /// 直近の測位に使われた衛星数。0 なら空が見えていない。
  int? latestSatellites;

  DateTime? _lastFixAt;

  /// true の間は [latestPosition] が「最後に確認された位置」であり、
  /// リアルタイムの位置ではないことを示す。UI 側はマーカーを薄く表示したり
  /// 「n分前」を出したりする。
  bool isOffline = false;

  /// 直近で発生した地理囲いイベント(enter/exit)。UI 側がこれを見て
  /// バナー文言を(AppStrings 経由で)組み立てる。ここでは翻訳済み文字列を
  /// 持たない — ConnStatus と同じ扱い方。
  GeofenceEvent? lastEvent;

  /// 最後に GPS フィックスを受信してからの経過時間。まだ一度も受信して
  /// いなければ null。
  Duration? get sinceLastFix =>
      _lastFixAt == null ? null : DateTime.now().difference(_lastFixAt!);

  void setHomeFence(GeofenceConfig fence) {
    homeFence = fence;
    _tracker.setFences(<GeofenceConfig>[fence]);
    notifyListeners();
  }

  void _onCollarChanged() {
    final SensorSample? sample = collar.latest;
    if (sample == null) return;

    // 測位品質は位置が無くても記録しておく。「衛星0個」と「モジュール無応答」
    // を UI で区別できるのは、この2つの値だけ。
    latestFixQuality = sample.fixQuality ?? latestFixQuality;
    latestSatellites = sample.satellites ?? latestSatellites;

    // hasLocation は座標の有無だけでなく測位品質も見る。正しい書式の NMEA が
    // 品質0で延々と届くのが屋内での通常状態なので、ここを緩めると「測位して
    // いないのに地図に犬が出る」ことになる。
    if (!sample.hasLocation) {
      notifyListeners();
      return;
    }

    final GeoPoint point = GeoPoint(sample.lat!, sample.lng!);
    latestPosition = point;
    latestAccuracyM = sample.estimatedAccuracyM?.round();
    latestFixQuality = sample.fixQuality;
    latestSatellites = sample.satellites;
    _lastFixAt = DateTime.now();
    isOffline = false;

    final List<GeofenceEvent> events = _tracker.update(point);
    if (events.isNotEmpty) {
      lastEvent = events.last;
    }

    notifyListeners();
  }

  void _checkOffline() {
    if (_lastFixAt == null) return;
    final bool stale = DateTime.now().difference(_lastFixAt!) > offlineThreshold;
    if (stale != isOffline) {
      isOffline = stale;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    collar.removeListener(_onCollarChanged);
    _offlineTimer?.cancel();
    super.dispose();
  }
}
