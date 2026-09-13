/// A WGS84 coordinate (the international standard — what the collar's GPS
/// chip outputs directly).
///
/// Convention for this whole package: every public API takes/returns WGS84
/// unless the name explicitly says otherwise (only [wgs84ToGcj02] /
/// [gcj02ToWgs84] in gcj02.dart cross that line). Geofence math, distance
/// calculations, and anything stored to disk should stay in WGS84 — only the
/// final "about to draw this on Amap" step should convert.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  String toString() => 'GeoPoint($lat, $lng)';

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}
