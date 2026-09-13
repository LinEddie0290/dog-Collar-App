/// WGS84 <-> GCJ-02 coordinate conversion.
///
/// 为什么需要这个文件：
/// 项圈硬件的 GPS 芯片输出的是国际标准 WGS84 坐标。但中国大陆的地图服务
/// （高德、腾讯、百度）出于测绘法规要求，不允许直接显示未加偏的 WGS84 坐标——
/// 必须先加上一层非线性偏移，转换成 GCJ-02（俗称"火星坐标系"）。
///
/// 如果漏掉这一步，地图上的狗狗定位点会偏移大约 200~700 米，在城市场景里
/// 经常直接偏到马路对面或隔壁小区，是这类项目里最容易被忽略、但一旦出错
/// 很难第一时间发现的 bug（因为地图看起来"有点位置"，不会报错，只是不准）。
///
/// 使用范围：
/// - 只在 UI 层「即将渲染到高德地图」这一步调用 [wgs84ToGcj02]。
/// - 围栏判断、距离计算、SensorSample 里存的坐标、业务逻辑全部使用原始
///   WGS84，不要在业务层提前转换。
///
/// 算法来源：国家测绘局公开的加偏算法（克拉索夫斯基椭球参数），是国内地图
/// 开发中的通用公开算法，非任何商业 SDK 的私有实现。这是
/// `pet-collar-app`（React Native 版原型）里 coords.ts 的 Dart 移植版，
/// 逻辑与其单元测试验证过的结果一致。
library;

import 'dart:math' as math;

import 'lat_lng.dart';

const double _earthSemiMajorAxis = 6378245.0;
const double _earthEccentricitySquared = 0.00669342162296594323;

double _transformLat(double x, double y) {
  double ret = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (160.0 * math.sin(y / 12.0 * math.pi) + 320 * math.sin(y * math.pi / 30.0)) *
      2.0 /
      3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret =
      300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) *
      2.0 /
      3.0;
  return ret;
}

/// 粗略判断一个 WGS84 坐标是否落在中国大陆范围之外。
/// 范围外的点不需要加偏（也不应该加偏，公式在境外会给出错误结果）。
bool isOutsideChina(GeoPoint p) {
  return p.lng < 72.004 || p.lng > 137.8347 || p.lat < 0.8293 || p.lat > 55.8271;
}

/// WGS84 -> GCJ-02。仅用于"把坐标画到高德地图上"这一件事。
GeoPoint wgs84ToGcj02(GeoPoint point) {
  if (isOutsideChina(point)) return point;

  final double lat = point.lat;
  final double lng = point.lng;
  double dLat = _transformLat(lng - 105.0, lat - 35.0);
  double dLng = _transformLng(lng - 105.0, lat - 35.0);

  final double radLat = lat / 180.0 * math.pi;
  double magic = math.sin(radLat);
  magic = 1 - _earthEccentricitySquared * magic * magic;
  final double sqrtMagic = math.sqrt(magic);

  dLat = (dLat * 180.0) /
      ((_earthSemiMajorAxis * (1 - _earthEccentricitySquared)) / (magic * sqrtMagic) * math.pi);
  dLng = (dLng * 180.0) / (_earthSemiMajorAxis / sqrtMagic * math.cos(radLat) * math.pi);

  return GeoPoint(lat + dLat, lng + dLng);
}

/// GCJ-02 -> WGS84（近似逆运算，二分逼近）。
///
/// 用途：如果未来接入某个只给 GCJ-02 坐标的第三方数据源，需要先转回 WGS84
/// 才能存入业务层。当前项圈硬件直接给 WGS84，这个函数暂时用不到，但保留
/// 以便后续接入其它数据源，且用于往返转换的单元测试。
GeoPoint gcj02ToWgs84(GeoPoint point) {
  if (isOutsideChina(point)) return point;

  double minLat = point.lat - 0.5;
  double maxLat = point.lat + 0.5;
  double minLng = point.lng - 0.5;
  double maxLng = point.lng + 0.5;

  GeoPoint candidate = point;
  for (int i = 0; i < 30; i++) {
    candidate = GeoPoint((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final GeoPoint guess = wgs84ToGcj02(candidate);
    final double dLat = guess.lat - point.lat;
    final double dLng = guess.lng - point.lng;

    if (dLat.abs() < 1e-9 && dLng.abs() < 1e-9) break;

    if (dLat > 0) {
      maxLat = candidate.lat;
    } else {
      minLat = candidate.lat;
    }
    if (dLng > 0) {
      maxLng = candidate.lng;
    } else {
      minLng = candidate.lng;
    }
  }

  return candidate;
}
