// ignore_for_file: avoid_print
// このファイルは `dart run bin/nmea_demo.dart` で NMEA 解析を検証する CLI。
// print が出力そのものなので avoid_print はここでは適用しない。

/// Self-verifying test of the NMEA parser.
///
/// The two sentences below are the ones that matter for this project:
///   * a valid RMC fix, to prove coordinates come out right (degrees *and
///     minutes*, not decimal degrees — the /60 is the classic bug);
///   * a well-formed GGA reporting no fix at all, which is exactly what the
///     collar produced for 1,200 sentences during the 2026-09-11 bench test
///     because it was indoors. If the map ever plots that, it is a bug.
library;

import 'package:collar_geo/collar_geo.dart';

int _checks = 0;
int _failures = 0;

void check(String what, bool ok, [String detail = '']) {
  _checks++;
  if (ok) {
    print('  ok   $what');
  } else {
    _failures++;
    print('  FAIL $what${detail.isEmpty ? '' : ' — $detail'}');
  }
}

void checkEq(String what, Object? actual, Object? expected) =>
    check(what, actual == expected, 'got $actual, want $expected');

void checkClose(String what, double? actual, double expected,
        [double tol = 1e-4]) =>
    check(what, actual != null && (actual - expected).abs() < tol,
        'got $actual, want $expected');

const String fixRmc =
    r'$GNRMC,083559.00,A,3113.8240,N,12128.4220,E,0.004,77.52,091226,,,A*4D';
const String noFixGga = r'$GPGGA,083559.00,,,,,0,00,99.99,,,,,,*64';
const String fixGga =
    r'$GNGGA,083559.00,3113.8240,N,12128.4220,E,1,09,0.94,45.2,M,,M,,*6B';

void main() {
  print('NMEA parser self-test\n');

  print('1. 測位成功した RMC の解析');
  final NmeaFix? rmc = parseNmea(fixRmc);
  check('RMC parses', rmc != null);
  if (rmc != null) {
    checkEq('type', rmc.type, NmeaSentenceType.rmc);
    checkEq('talker is GN, not GP', rmc.talker, 'GN');
    check('has a fix (status A)', rmc.hasFix);
    // 3113.8240 = 31° 13.824' = 31 + 13.824/60 = 31.2304
    checkClose('latitude', rmc.point?.lat, 31.2304);
    // 12128.4220 = 121° 28.422' = 121 + 28.422/60 = 121.4737
    checkClose('longitude', rmc.point?.lng, 121.4737);
    checkClose('speed knots', rmc.speedKnots, 0.004);
    checkClose('course deg', rmc.courseDeg, 77.52);
    checkEq('UTC date came from the sentence', rmc.utc?.year, 2026);
    print('       ${rmc.point}');
  }

  print('\n2. 正しい文だが未測位 — ここが一番大事');
  final NmeaFix? bad = parseNmea(noFixGga);
  check('no-fix GGA still parses', bad != null);
  if (bad != null) {
    checkEq('hasFix is false', bad.hasFix, false);
    checkEq('point is null so nothing can be plotted', bad.point, null);
    checkEq('fix quality 0 is reported', bad.fixQuality, 0);
    checkEq('0 satellites is reported', bad.satellites, 0);
    check('HDOP 99.99 is kept as a warning signal',
        bad.hdop != null && bad.hdop! > 50);
  }

  print('\n3. 測位成功した GGA と品質情報');
  final NmeaFix? gga = parseNmea(fixGga);
  if (gga != null) {
    check('has a fix (quality 1)', gga.hasFix);
    checkEq('fix quality', gga.fixQuality, 1);
    checkEq('satellites', gga.satellites, 9);
    checkClose('hdop', gga.hdop, 0.94, 1e-6);
    checkClose('altitude m', gga.altitudeM, 45.2, 1e-6);
    checkClose('latitude matches the RMC', gga.point?.lat, 31.2304);
  }

  print('\n4. チェックサムと書式の異常系');
  checkEq('valid checksum passes', nmeaChecksumValid(fixRmc), true);
  checkEq('a flipped digit fails',
      nmeaChecksumValid(fixRmc.replaceRange(fixRmc.length - 1, null, 'E')),
      false);
  try {
    parseNmea(r'$GNRMC,083559.00,A,3113.8240,N*00');
    check('bad checksum throws', false, 'no exception');
  } on NmeaFormatException {
    check('bad checksum throws', true);
  }
  try {
    parseNmea('GNRMC,no dollar sign');
    check('missing \$ throws', false, 'no exception');
  } on NmeaFormatException {
    check('missing \$ throws', true);
  }
  checkEq('an uninterpreted sentence type returns null',
      parseNmea(r'$GPGSV,3,1,11,01,05,040,20*49'), null);

  print('\n5. 高徳地図に出すための座標変換（これを忘れると数百m ずれる）');
  final GeoPoint wgs = GeoPoint(31.2304, 121.4737);
  final GeoPoint gcj = wgs84ToGcj02(wgs);
  final double shift = distanceMeters(wgs, gcj);
  check('WGS84 と GCJ-02 の差は 100m 以上ある',
      shift > 100, 'shift = ${shift.toStringAsFixed(1)} m');
  print('       ずれ = ${shift.toStringAsFixed(1)} m '
      '(${wgs.lat.toStringAsFixed(6)},${wgs.lng.toStringAsFixed(6)}'
      ' → ${gcj.lat.toStringAsFixed(6)},${gcj.lng.toStringAsFixed(6)})');
  final double roundTrip = distanceMeters(wgs, gcj02ToWgs84(gcj));
  check('往復変換で元に戻る（誤差 1m 未満）', roundTrip < 1.0,
      'round trip error = ${roundTrip.toStringAsFixed(3)} m');

  print('\n6. 複数文のまとめこみ');
  final NmeaAggregator agg = NmeaAggregator();
  checkEq('未測位の文では位置が入らない', agg.addSentence(noFixGga), false);
  checkEq('まだ位置なし', agg.hasFix, false);
  check('未測位でも衛星数は記録される', agg.satellites == 0);
  checkEq('測位した文で位置が入る', agg.addSentence(fixRmc), true);
  check('位置が入った', agg.hasFix);
  checkEq('解釈しない文は位置を動かさない',
      agg.addSentence(r'$GPGSV,3,1,11,01,05,040,20*49'), false);
  check('位置は保持されている', agg.hasFix);
  agg.addSentence(fixGga);
  checkEq('GGA の品質情報が入る', agg.fixQuality, 1);
  checkEq('衛星数が更新される', agg.satellites, 9);

  print('\n7. 精度の推定 — HDOP は倍率であってメートルではない');
  checkClose('HDOP 0.94 → 約 4.7m 相当の目安',
      estimateAccuracyM(0.94), 4.7, 0.01);
  checkEq('HDOP が無ければ推定もしない', estimateAccuracyM(null), null);
  checkEq('不正な HDOP は推定しない', estimateAccuracyM(0), null);
  print('       ※ 首輪は精度の実測値を送ってこない。UI では「目安」と明示する。');

  print('\n${'=' * 52}');
  if (_failures == 0) {
    print('全 $_checks 件 通過');
  } else {
    print('$_checks 件中 $_failures 件 失敗');
  }
  print('=' * 52);
}
