/// 把一个圆形围栏近似成一圈多边形顶点，用来在地图上画出来。
///
/// 为什么不直接用地图 SDK 自带的 Circle 覆盖物：`amap_map` 插件不同版本对
/// Circle 的支持不完全一致（截至写这份代码时，无法在没有真机/模拟器的环境
/// 下确认当前锁定版本是否导出了 Circle 类）。用多边形近似是更保守、跨版本
/// 都能用的方案——本质上就是"半径足够大时，正 N 边形看起来就是圆"。
///
/// 如果确认了当前 `amap_map` 版本支持 Circle 覆盖物，直接用原生 Circle
/// 会更精确也更省性能，可以把这个当作 fallback 保留。
library;

import 'dart:math' as math;

import 'lat_lng.dart';

const double _earthRadiusM = 6371000;

/// 生成围栏圆的近似多边形顶点（WGS84 坐标，首尾不重复）。
///
/// [segments] 越大越接近正圆，也越多顶点；64 段对手机屏幕上的围栏圈来说
/// 已经完全看不出棱角，默认给 64。
List<GeoPoint> circleToPolygon(
  GeoPoint center,
  double radiusM, {
  int segments = 64,
}) {
  final List<GeoPoint> points = <GeoPoint>[];
  final double latRad = center.lat * math.pi / 180;
  final double angularDistance = radiusM / _earthRadiusM;

  for (int i = 0; i < segments; i++) {
    final double bearing = 2 * math.pi * i / segments;
    final double destLatRad = math.asin(
      math.sin(latRad) * math.cos(angularDistance) +
          math.cos(latRad) * math.sin(angularDistance) * math.cos(bearing),
    );
    final double destLngRad = center.lng * math.pi / 180 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(latRad),
          math.cos(angularDistance) - math.sin(latRad) * math.sin(destLatRad),
        );

    points.add(GeoPoint(
      destLatRad * 180 / math.pi,
      destLngRad * 180 / math.pi,
    ));
  }

  return points;
}
