/// 地理围栏的纯逻辑部分（不依赖 Flutter，方便单测，且能在 collar_data 那种
/// 纯 Dart 环境下独立验证）。
///
/// 设计要点（对应需求分析里的结论）：
/// - "狗狗离开设定范围要立刻提醒" -> 每次收到新定位就判断一次 in/out，
///   状态变化时才产生 enter/exit 事件，不会同一个状态重复报警。
/// - "不要事无巨细地推送" -> 状态判断和事件产生是分开的，上层可以在
///   事件基础上再加免打扰时段等策略，不需要改这里的核心逻辑。
library;

import 'dart:math' as math;

import 'lat_lng.dart';

const double _earthRadiusM = 6371000;

/// 两个 WGS84 坐标之间的大圆距离（米）。Haversine 公式，米级精度足够本项目
/// 使用。
double distanceMeters(GeoPoint a, GeoPoint b) {
  double toRad(double deg) => deg * math.pi / 180;
  final double dLat = toRad(b.lat - a.lat);
  final double dLng = toRad(b.lng - a.lng);
  final double lat1 = toRad(a.lat);
  final double lat2 = toRad(b.lat);

  final double h = math.pow(math.sin(dLat / 2), 2).toDouble() +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2).toDouble();
  final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return _earthRadiusM * c;
}

/// 一个圆形地理围栏（MVP 阶段够用，多边形围栏后续再加）。
class GeofenceConfig {
  const GeofenceConfig({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusM,
  });

  final String id;
  final String name;
  final GeoPoint center;
  final double radiusM;
}

enum GeofenceEventType { enter, exit }

class GeofenceEvent {
  const GeofenceEvent({
    required this.fenceId,
    required this.type,
    required this.position,
    required this.timestamp,
  });

  final String fenceId;
  final GeofenceEventType type;
  final GeoPoint position;
  final DateTime timestamp;

  @override
  String toString() =>
      'GeofenceEvent(fenceId: $fenceId, type: $type, position: $position)';
}

bool isInsideFence(GeoPoint position, GeofenceConfig fence) {
  return distanceMeters(position, fence.center) <= fence.radiusM;
}

/// 围栏状态机：记录每个围栏上一次的 in/out 状态，收到新定位后返回本次
/// 触发的事件列表（通常是 0 或 1 个，理论上可以同时跨越多个围栏所以用列表）。
class GeofenceTracker {
  GeofenceTracker(List<GeofenceConfig> fences) : _fences = fences;

  List<GeofenceConfig> _fences;
  final Map<String, bool> _fenceState = <String, bool>{};

  void setFences(List<GeofenceConfig> fences) {
    _fences = fences;
    // 围栏配置变化时清空状态，避免用旧围栏的 in/out 状态误判新围栏。
    _fenceState.clear();
  }

  /// 输入一次新的定位，返回本次触发的围栏事件（可能为空列表）。
  List<GeofenceEvent> update(GeoPoint position, {DateTime? at}) {
    final DateTime timestamp = at ?? DateTime.now();
    final List<GeofenceEvent> events = <GeofenceEvent>[];

    for (final GeofenceConfig fence in _fences) {
      final bool inside = isInsideFence(position, fence);
      final bool? wasInside = _fenceState[fence.id];

      // 第一次收到这个围栏的定位时，只记录状态，不产生事件——
      // 否则每次 App 启动都会误报一次"进入/离开"。
      if (wasInside == null) {
        _fenceState[fence.id] = inside;
        continue;
      }

      if (inside != wasInside) {
        events.add(GeofenceEvent(
          fenceId: fence.id,
          type: inside ? GeofenceEventType.enter : GeofenceEventType.exit,
          position: position,
          timestamp: timestamp,
        ));
        _fenceState[fence.id] = inside;
      }
    }

    return events;
  }
}
