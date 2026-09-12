// ignore_for_file: avoid_print
// このファイルは `dart run bin/demo.dart` で動作確認するための CLI。
// print が出力そのものなので avoid_print はここでは適用しない。
import 'dart:io';

import 'package:collar_geo/collar_geo.dart';

/// Self-verifying demo, same style as ../collar_data/bin/demo.dart:
///
///   dart run bin/demo.dart
///
/// No Flutter, no phone, no network. Checks coordinate conversion, geofence
/// enter/exit detection, and the circle-to-polygon helper.
void main() {
  _checkGcj02();
  _checkGeofence();
  _checkCirclePolygon();
  print('\nALL CHECKS PASSED ✅');
}

void _checkGcj02() {
  print('--- wgs84ToGcj02 / gcj02ToWgs84 ---');

  // 1) Points outside China must not shift (e.g. Tokyo).
  const tokyo = GeoPoint(35.6812, 139.7671);
  final tokyoConverted = wgs84ToGcj02(tokyo);
  _check(tokyoConverted.lat == tokyo.lat && tokyoConverted.lng == tokyo.lng,
      'points outside China are not shifted');
  _check(isOutsideChina(tokyo), 'Tokyo is detected as outside China');

  // 2) A Beijing point must shift by a plausible amount (tens to hundreds of
  //    metres) — this is the number that guards against someone accidentally
  //    disabling the offset, or applying it twice.
  const beijing = GeoPoint(39.9075, 116.3972);
  _check(!isOutsideChina(beijing), 'Beijing is detected as inside China');
  final beijingConverted = wgs84ToGcj02(beijing);
  _check(beijingConverted.lat != beijing.lat && beijingConverted.lng != beijing.lng,
      'Beijing point actually moves after conversion');
  final offsetM = distanceMeters(beijing, beijingConverted);
  print('  Beijing offset: ${offsetM.toStringAsFixed(1)} m');
  _check(offsetM > 50 && offsetM < 1000,
      'Beijing offset is within the known plausible range (50-1000m)');

  // 3) Round-trip WGS84 -> GCJ-02 -> WGS84 should land within ~1m.
  const shanghai = GeoPoint(31.2304, 121.4737);
  final roundTrip = gcj02ToWgs84(wgs84ToGcj02(shanghai));
  final roundTripErrorM = distanceMeters(shanghai, roundTrip);
  print('  Shanghai round-trip error: ${roundTripErrorM.toStringAsFixed(3)} m');
  _check(roundTripErrorM < 1, 'round-trip conversion error stays under 1m');
}

void _checkGeofence() {
  print('\n--- GeofenceTracker ---');

  const home = GeofenceConfig(
    id: 'home',
    name: 'Home',
    center: GeoPoint(31.2304, 121.4737),
    radiusM: 100,
  );

  // distanceMeters sanity check against a known reference: 1 degree of
  // latitude is ~111km, regardless of longitude.
  final oneDegreeLat = distanceMeters(const GeoPoint(0, 0), const GeoPoint(1, 0));
  print('  1 deg latitude ~= ${oneDegreeLat.toStringAsFixed(0)} m');
  _check(oneDegreeLat > 110000 && oneDegreeLat < 112000,
      'distanceMeters matches the known ~111km/degree reference');

  final tracker = GeofenceTracker(<GeofenceConfig>[home]);

  // First update establishes baseline — must NOT emit (avoids a false "left
  // the yard" alert the instant the app starts).
  final baseline = tracker.update(home.center);
  _check(baseline.isEmpty, 'no event on the very first update');

  // Moving far away must emit exactly one "exit" event.
  final farAway = GeoPoint(home.center.lat + 0.01, home.center.lng); // ~1.1km
  final exitEvents = tracker.update(farAway);
  _check(exitEvents.length == 1 && exitEvents.first.type == GeofenceEventType.exit,
      'leaving the fence emits exactly one exit event');

  // Coming back must emit exactly one "enter" event.
  final enterEvents = tracker.update(home.center);
  _check(enterEvents.length == 1 && enterEvents.first.type == GeofenceEventType.enter,
      'returning to the fence emits exactly one enter event');

  // Staying inside must not spam more events (notification-spam guard).
  final stillInside1 = tracker.update(GeoPoint(home.center.lat + 0.0001, home.center.lng));
  final stillInside2 = tracker.update(GeoPoint(home.center.lat + 0.0002, home.center.lng));
  _check(stillInside1.isEmpty && stillInside2.isEmpty,
      'no repeated events while staying in the same state');

  // Replacing the fence list resets state (first update after is baseline again).
  tracker.setFences(<GeofenceConfig>[
    GeofenceConfig(id: 'work', name: 'Work', center: home.center, radiusM: 50),
  ]);
  final afterReset = tracker.update(home.center);
  _check(afterReset.isEmpty, 'setFences resets tracker state (no false event)');
}

void _checkCirclePolygon() {
  print('\n--- circleToPolygon ---');

  const center = GeoPoint(31.2304, 121.4737);
  const radiusM = 150.0;
  final polygon = circleToPolygon(center, radiusM, segments: 32);

  _check(polygon.length == 32, 'returns the requested number of segments');

  // Every vertex should sit ~radiusM from the center (haversine distance is
  // an approximation of the destination-point formula's inverse, so allow a
  // small tolerance).
  final maxError = polygon
      .map((p) => (distanceMeters(center, p) - radiusM).abs())
      .reduce((a, b) => a > b ? a : b);
  print('  max vertex distance error: ${maxError.toStringAsFixed(2)} m');
  _check(maxError < 1, 'every polygon vertex is within 1m of the target radius');
}

void _check(bool ok, String what) {
  if (!ok) {
    stderr.writeln('CHECK FAILED: $what');
    exit(1);
  }
  print('ok: $what');
}
