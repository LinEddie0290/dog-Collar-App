import 'package:amap_map/amap_map.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/material.dart';
// LatLng は amap_map 本体ではなく、その土台パッケージ x_amap_base 側にある
// (Marker / Polygon / CameraPosition は amap_map が独自に持っているので、
// show で LatLng だけ取り込んで名前衝突を避ける)。
import 'package:x_amap_base/x_amap_base.dart' show LatLng;

import 'map_provider.dart';

/// 高德地図(Amap)を使った国内版 [MapProvider] 実装。
///
/// `packages/collar_geo` の [wgs84ToGcj02] は「これから高德地図に描画する」
/// ときだけ呼ぶ、というルールがこのファイルの中で完結している。呼び出す
/// 側(MapPage)からは常に WGS84 の座標を渡すだけでよい。
///
/// 円形の地理围栏(囲い)は、`amap_map` の現行バージョンで Circle
/// オーバーレイが確実に使えるか検証できなかったため、[circleToPolygon] で
/// 多角形に近似して Polygon として描画している(詳しい理由は
/// `packages/collar_geo/README.md` 参照)。
class AmapMapProvider implements MapProvider {
  const AmapMapProvider();

  @override
  String get name => 'amap';

  @override
  Widget buildMapView({
    required GeoPoint initialCenter,
    GeoPoint? dogPosition,
    bool dogPositionIsStale = false,
    GeofenceConfig? fence,
  }) {
    final GeoPoint centerGcj02 = wgs84ToGcj02(initialCenter);

    final Set<Marker> markers = <Marker>{};
    if (dogPosition != null) {
      final GeoPoint gcj02 = wgs84ToGcj02(dogPosition);
      markers.add(Marker(
        position: LatLng(gcj02.lat, gcj02.lng),
        alpha: dogPositionIsStale ? 0.55 : 1.0,
      ));
    }

    final Set<Polygon> polygons = <Polygon>{};
    if (fence != null) {
      final List<LatLng> points = circleToPolygon(fence.center, fence.radiusM)
          .map(wgs84ToGcj02)
          .map((GeoPoint p) => LatLng(p.lat, p.lng))
          .toList();
      polygons.add(Polygon(
        points: points,
        strokeWidth: 2,
        strokeColor: const Color(0xFFB85042),
        fillColor: const Color(0x26B85042), // アクセントカラーを薄く
      ));
    }

    return AMapWidget(
      initialCameraPosition: CameraPosition(
        target: LatLng(centerGcj02.lat, centerGcj02.lng),
        zoom: 16,
      ),
      markers: markers,
      polygons: polygons,
    );
  }
}
