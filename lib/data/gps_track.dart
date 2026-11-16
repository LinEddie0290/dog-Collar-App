/// T12 GPS（M7、D-063）：位置 → 跳んだ点・不正確な点を除く → 屋外の距離・時間。画面なしの計算だけ。
///
/// collar-pipeline の `collar/judge/gps.py` と同じ計算（test/temp_gps_golden_test.dart で同じ答えを確認）。
/// 1 点ずつ入れる [GpsTracker]（安全タブの今日の散歩）と、まとめて計算する [trackGps]（1 日まとめ）は同じもの。
/// 数字は全部仮。
library;

import 'package:collar_geo/collar_geo.dart';

import 'temp_judge.dart' show localDateOf;

const double gpsMaxHdop = 5; // HDOP がこれより大きいのは捨てる（アプリの acc_m＝HDOP×5）
const int gpsMinSats = 4; // 衛星がこれより少ないのは捨てる（分からなければ見ない）
const double gpsMaxSpeedMps = 15; // これより速い移動は跳んだ点
const double gpsMinStepM = 2; // 前の点から 2 m 未満は距離に足さない
const double gpsOutdoorGapS = 60; // 前の有効な点から 60 秒以内なら屋外

class GpsPoint {
  const GpsPoint({required this.tMs, required this.lat, required this.lng, this.hdop, this.sats, this.fix});

  final int tMs;
  final double lat;
  final double lng;
  final double? hdop;
  final int? sats;
  final int? fix;

  bool get usable =>
      lat.isFinite &&
      lng.isFinite &&
      (fix == null || fix! > 0) &&
      (hdop == null || !hdop!.isFinite || hdop! <= gpsMaxHdop) &&
      (sats == null || sats! >= gpsMinSats);
}

class TrackPoint {
  const TrackPoint(
      {required this.tMs, required this.outdoor, required this.stepM, required this.speedMps, required this.dtS});

  final int tMs;
  final bool outdoor;
  final double stepM;
  final double speedMps;

  /// 屋外のときの前の点からの秒（屋外の時間に足す）。屋外でなければ 0。
  final double dtS;
}

/// 1 点ずつ入れる。時刻の順に入れること。
class GpsTracker {
  int? _prevT;
  GpsPoint? _anchor;

  void reset() {
    _prevT = null;
    _anchor = null;
  }

  /// 残した点を返す（捨てた点は null）。
  TrackPoint? add(GpsPoint p) {
    if (!p.usable) return null;
    final int? prevT = _prevT;
    final GpsPoint? a = _anchor;
    if (prevT == null || a == null) {
      _prevT = p.tMs;
      _anchor = p;
      return TrackPoint(tMs: p.tMs, outdoor: false, stepM: 0, speedMps: 0, dtS: 0);
    }
    final double dt = (p.tMs - prevT) / 1000;
    if (dt <= 0) return null;
    final double d = distanceMeters(GeoPoint(a.lat, a.lng), GeoPoint(p.lat, p.lng));
    if (d / dt > gpsMaxSpeedMps) return null; // 跳んだ点
    final bool outdoor = dt <= gpsOutdoorGapS;
    double step = 0, speed = 0;
    if (!outdoor) {
      _anchor = p; // 途切れた：ここから測り直す（距離は足さない）
    } else if (d >= gpsMinStepM) {
      step = d;
      speed = d / ((p.tMs - a.tMs) / 1000);
      _anchor = p;
    }
    _prevT = p.tMs;
    return TrackPoint(tMs: p.tMs, outdoor: outdoor, stepM: step, speedMps: speed, dtS: outdoor ? dt : 0);
  }
}

/// まとめて（時刻の順に並べ直してから）。
List<TrackPoint> trackGps(List<GpsPoint> points) {
  final List<GpsPoint> ok = <GpsPoint>[for (final GpsPoint p in points) if (p.usable) p];
  final List<int> order = List<int>.generate(ok.length, (int i) => i)
    ..sort((int a, int b) {
      final int c = ok[a].tMs.compareTo(ok[b].tMs);
      return c != 0 ? c : a.compareTo(b);
    });
  final GpsTracker t = GpsTracker();
  return <TrackPoint>[
    for (final int i in order)
      if (t.add(ok[i]) case final TrackPoint tp) tp,
  ];
}

/// 1 日（UTC＋8）の屋外の距離（m）・時間（分）。
Map<String, ({double outdoorM, double outdoorMin})> dailyOutdoor(List<TrackPoint> track) {
  final Map<String, List<double>> m = <String, List<double>>{};
  for (final TrackPoint p in track) {
    final List<double> v = m.putIfAbsent(localDateOf(p.tMs), () => <double>[0, 0]);
    v[0] += p.stepM;
    v[1] += p.dtS;
  }
  final List<String> dates = m.keys.toList()..sort();
  return <String, ({double outdoorM, double outdoorMin})>{
    for (final String d in dates) d: (outdoorM: m[d]![0], outdoorMin: m[d]![1] / 60),
  };
}

/// 「0.42 km・7 分钟」。
String outdoorText(double m, double min) =>
    '${m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(2)} km'}・${min.round()} 分钟';
