import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/widgets.dart';

/// 地図 Provider の統一インターフェース。
///
/// MapPage はこのインターフェースだけを見て、高徳地図(Amap)の具体的な
/// ウィジェットや API を直接 import しない。国内版は [AmapMapProvider] を
/// 使うが、将来海外版を作るときは同じインターフェースを実装した
/// GoogleMapsMapProvider を作って差し替えるだけで済む
/// (`lib/ui/google_maps_provider_stub.dart` 参照)。
///
/// 渡す座標は必ず WGS84。GCJ-02 への変換(高徳に表示する直前の一手間)は
/// Provider の実装側の責任で、呼び出す側は意識しなくてよい。
abstract class MapProvider {
  String get name;

  /// [dogPosition] が null のときは、まだ一度も位置を受信していない状態。
  /// [dogPositionIsStale] が true のときは、直近の受信から時間が経っていて
  /// 「最後に確認された位置」であることを示す(マーカーの見た目を薄くする等)。
  Widget buildMapView({
    required GeoPoint initialCenter,
    GeoPoint? dogPosition,
    bool dogPositionIsStale = false,
    GeofenceConfig? fence,
  });
}
