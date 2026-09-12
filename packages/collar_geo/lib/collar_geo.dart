/// Pet-collar location math — pure Dart, zero UI / zero Flutter imports.
///
/// The Flutter app imports only this file:
///   * [GeoPoint] / [wgs84ToGcj02] / [gcj02ToWgs84] for coordinate conversion
///   * [distanceMeters] / [GeofenceConfig] / [GeofenceTracker] / [GeofenceEvent]
///     for the "did the dog leave the yard" logic
///   * [circleToPolygon] to draw a geofence circle on the map
library;

export 'src/circle_polygon.dart';
export 'src/gcj02.dart';
export 'src/geofence.dart';
export 'src/lat_lng.dart';
