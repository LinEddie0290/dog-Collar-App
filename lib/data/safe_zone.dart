/// T36：安全区（家）と、位置ごとの出入りの判定。画面なしの計算だけ（テストしやすいように）。
///
/// - 位置は WGS84。地図（高德）に描くときだけ GCJ-02 に直す（collar_geo の約束と同じ）。
/// - GPS は数 m〜数十 m ぶれるので、境目に余裕（[ZoneJudge.marginM]）を持たせ、
///   外に出たと言うのは「半径＋余裕の外」が [ZoneJudge.needOut] 回続いたときだけ。
/// - 「可能走失」は、安全区の外にいて、しかも首輪とスマホの BLE が切れたとき（D-059 M3）。
///   BLE がつながっている＝飼い主がそばにいる（散歩中）とみなす。
/// 文言は中国語だけ（D-051 D6）。
library;

import 'package:collar_geo/collar_geo.dart';

/// 位置 1 つ（WGS84）。
class LocationFix {
  const LocationFix({required this.point, required this.tMs, this.accuracyM, this.source = ''});

  final GeoPoint point;

  /// UTC のミリ秒。
  final int tMs;

  /// 精度の目安（m）。分からなければ null（首輪は HDOP から作った概算しか出せない）。
  final int? accuracyM;

  /// どこから来たか：collar / fake。
  final String source;
}

/// 家（安全区）。今は 1 つだけ。
class SafeZone {
  const SafeZone({required this.center, required this.radiusM, this.name = '家'});

  final GeoPoint center;
  final double radiusM;
  final String name;

  /// 半径の選べる値（m）。
  static const List<double> radiusChoices = <double>[50, 100, 150, 300];

  double distanceTo(GeoPoint p) => distanceMeters(p, center);

  Map<String, Object?> toJson() =>
      <String, Object?>{'lat': center.lat, 'lng': center.lng, 'radius_m': radiusM, 'name': name};

  /// 読めなければ null。
  static SafeZone? fromJson(Map<String, dynamic> j) {
    final Object? lat = j['lat'], lng = j['lng'], r = j['radius_m'];
    if (lat is! num || lng is! num || r is! num || r <= 0) return null;
    return SafeZone(
      center: GeoPoint(lat.toDouble(), lng.toDouble()),
      radiusM: r.toDouble(),
      name: (j['name'] as String?) ?? '家',
    );
  }
}

enum ZoneState {
  /// まだ判定していない（家がない・位置がまだ・境目のあたり）。
  unknown,
  inside,

  /// 外にいる（BLE はつながっている＝飼い主がそば）。
  outside,

  /// 外にいて、BLE が切れた。
  lost,
}

enum ZoneEventKind { exit, enter, lost }

class ZoneEvent {
  const ZoneEvent({required this.kind, required this.tMs, required this.point, required this.distanceM});

  final ZoneEventKind kind;
  final int tMs;

  /// そのときの位置（lost では最後に分かった位置）。
  final GeoPoint point;
  final double distanceM;

  String get title => switch (kind) {
        ZoneEventKind.exit => '离开了安全区',
        ZoneEventKind.enter => '回到了安全区',
        ZoneEventKind.lost => '可能走失',
      };
}

/// 出入りの判定。位置が来るたびに [update]、BLE がつながった・切れたら [setLinked]。
class ZoneJudge {
  // 外からは linked、中では _linked（setLinked でだけ変える）
  ZoneJudge({required this.zone, this.marginM = 20, this.needOut = 2, this.needIn = 1, bool linked = true})
      : _linked = linked; // ignore: prefer_initializing_formals

  SafeZone zone;

  /// 境目の余裕（m）。外は「半径＋余裕」より遠く、中は「半径−余裕」より近く（仮、D-059 M5）。
  final double marginM;

  /// 外に出たと言うのに要る、続けての位置の数（仮）。
  final int needOut;
  final int needIn;

  ZoneState state = ZoneState.unknown;
  bool _linked;
  int _out = 0;
  int _in = 0;

  /// 最後の位置（lost のときの位置に使う）。
  LocationFix? last;

  /// 最後の位置の家からの距離（m）。
  double? lastDistanceM;

  bool get linked => _linked;

  /// 家を変えた：数え直す（前の家での状態は持ち越さない）。
  void setZone(SafeZone z) {
    zone = z;
    state = ZoneState.unknown;
    _out = 0;
    _in = 0;
    lastDistanceM = last == null ? null : z.distanceTo(last!.point);
  }

  List<ZoneEvent> update(LocationFix f) {
    last = f;
    final double d = zone.distanceTo(f.point);
    lastDistanceM = d;
    final List<ZoneEvent> out = <ZoneEvent>[];
    if (d > zone.radiusM + marginM) {
      _out++;
      _in = 0;
      if (_out >= needOut && (state == ZoneState.unknown || state == ZoneState.inside)) {
        // 家の中から出たときだけ「出た」。最初から外（unknown）は黙って外にする
        if (state == ZoneState.inside) {
          out.add(ZoneEvent(kind: ZoneEventKind.exit, tMs: f.tMs, point: f.point, distanceM: d));
        }
        state = ZoneState.outside;
        if (!_linked) {
          state = ZoneState.lost;
          out.add(ZoneEvent(kind: ZoneEventKind.lost, tMs: f.tMs, point: f.point, distanceM: d));
        }
      }
    } else if (d < zone.radiusM - marginM) {
      _in++;
      _out = 0;
      if (_in >= needIn && state != ZoneState.inside) {
        if (state == ZoneState.outside || state == ZoneState.lost) {
          out.add(ZoneEvent(kind: ZoneEventKind.enter, tMs: f.tMs, point: f.point, distanceM: d));
        }
        state = ZoneState.inside;
      }
    } else {
      // 境目のあたり：今の状態のまま。続けての数は数え直す
      _out = 0;
      _in = 0;
    }
    return out;
  }

  /// BLE がつながった／切れた。外にいるときに切れたら「可能走失」。
  List<ZoneEvent> setLinked(bool linked, int tMs) {
    if (linked == _linked) return const <ZoneEvent>[];
    _linked = linked;
    if (!linked && state == ZoneState.outside) {
      state = ZoneState.lost;
      final LocationFix? f = last;
      return <ZoneEvent>[
        ZoneEvent(
          kind: ZoneEventKind.lost,
          tMs: tMs,
          point: f?.point ?? zone.center,
          distanceM: lastDistanceM ?? 0,
        ),
      ];
    }
    if (linked && state == ZoneState.lost) state = ZoneState.outside;
    return const <ZoneEvent>[];
  }
}

/// 距離の文（120 m／1.2 km）。
String distanceText(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

/// 「何分前」（安全タブ）。
String agoText(int fromMs, int nowMs) {
  final int s = ((nowMs - fromMs) / 1000).floor();
  if (s < 60) return '刚才';
  final int m = s ~/ 60;
  if (m < 60) return '$m 分钟前';
  return '${m ~/ 60} 小时前';
}

/// 安全タブの「位置」の 1 行。
String positionLine({required ZoneState state, required double? distanceM, required int? fixMs, required int nowMs,
    required bool hasZone, bool stale = false}) {
  if (fixMs == null) return '位置：还没有（GPS 还没定位）';
  final String ago = agoText(fixMs, nowMs);
  if (!hasZone || distanceM == null) return '位置：有了（$ago）　还没设家';
  final String d = distanceText(distanceM);
  final String where = switch (state) {
    ZoneState.inside => '在家（安全区里），离中心 $d',
    ZoneState.outside => '在外面，离家 $d',
    ZoneState.lost => '可能走失！最后在离家 $d 的地方',
    ZoneState.unknown => '离家 $d',
  };
  return '位置：$where（$ago${stale ? '，之后没有新的位置' : ''}）';
}

// ---------------------------------------------------------------------------
// 模拟的道（D-059 M6）：家から東へ 200 m 歩き、少し回って戻る。10 分で 1 周。

/// 1 周の長さ（秒）。
const double fakeRouteCycleS = 600;

/// [tS] 秒目の、家からのずれ（東へ m・北へ m）。ぶれ ±5 m つき（同じ tS なら同じ値）。
({double east, double north}) fakeRouteOffset(double tS) {
  final double t = tS % fakeRouteCycleS;
  double e, n;
  if (t < 60) {
    e = 0;
    n = 0; // 家
  } else if (t < 260) {
    e = (t - 60); // 1 m/s で東へ
    n = 0;
  } else if (t < 340) {
    // 200 m のところで北へ 40 m 行って戻る（回る）
    final double u = (t - 260) / 80;
    e = 200;
    n = 40 * (u < 0.5 ? u * 2 : (1 - u) * 2);
  } else if (t < 540) {
    e = 200 - (t - 340); // 戻る
    n = 0;
  } else {
    e = 0;
    n = 0;
  }
  // ぶれ（決まった形）
  final int k = tS.floor();
  final double je = ((k * 7919) % 101) / 10 - 5;
  final double jn = ((k * 104729) % 101) / 10 - 5;
  return (east: e + je, north: n + jn);
}

/// 家 [home] から東へ [east] m・北へ [north] m の点（近い距離の近似）。
GeoPoint offsetPoint(GeoPoint home, double east, double north) {
  const double mPerDegLat = 111320;
  final double mPerDegLng = 111320 * _cosDeg(home.lat);
  return GeoPoint(home.lat + north / mPerDegLat, home.lng + east / mPerDegLng);
}

double _cosDeg(double deg) {
  // dart:math を使わずに済むよう、ここだけで足りる精度の cos（緯度 0〜60° で誤差 1e-6 未満）
  final double x = deg * 3.141592653589793 / 180;
  final double x2 = x * x;
  return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720 + x2 * x2 * x2 * x2 / 40320;
}
