/// NMEA 0183 parsing for the collar's Air530/Air530Z GPS module.
///
/// The firmware deliberately does *not* convert NMEA into a lat/lng struct: it
/// forwards raw, checksum-valid sentences and the app parses them. So this file
/// is the missing half — it turns a raw `$GNRMC,…` sentence into a [GeoPoint]
/// plus the fix metadata needed to decide whether that point means anything.
///
/// Two rules this file exists to enforce:
///
///   1. **A valid sentence is not a fix.** GGA can arrive with
///      `fixQuality == 0` and 0 satellites, and RMC with status `V`, forever.
///      That is exactly what the collar produced during the 2026-09-11 bench
///      test: 1,200 well-formed sentences, zero fixes, because it was indoors.
///      [NmeaFix.hasFix] is the only thing that should drive the map.
///   2. **The talker prefix is not fixed.** `$GP` (GPS), `$GN` (multi-GNSS),
///      `$GL` (GLONASS), `$BD`/`$GB` (BeiDou) all appear depending on which
///      constellations the module is using, so dispatch on the 3-letter
///      sentence type and ignore the 2-letter talker.
///
/// Coordinates are WGS84, as NMEA always is. Displaying them on Amap requires
/// [wgs84ToGcj02] from this same package — skipping that conversion puts the
/// dog a few hundred metres from where it is.
library;

import 'lat_lng.dart';

/// Which sentence a line is, once the talker prefix is stripped.
enum NmeaSentenceType {
  /// Global positioning system fix data: position, fix quality, satellites,
  /// HDOP, altitude.
  gga,

  /// Recommended minimum data: position, validity, speed, course, date.
  rmc,

  /// Anything this parser does not interpret (GSA, GSV, VTG, GLL, TXT, ...).
  other,
}

/// One parsed position sentence.
///
/// [point] is null whenever the sentence carried no usable coordinates, which
/// includes the very common case of a well-formed sentence reporting no fix.
class NmeaFix {
  const NmeaFix({
    required this.type,
    required this.talker,
    required this.hasFix,
    this.point,
    this.fixQuality,
    this.satellites,
    this.hdop,
    this.altitudeM,
    this.speedKnots,
    this.courseDeg,
    this.utc,
  });

  final NmeaSentenceType type;

  /// The 2-character talker, e.g. `GP`, `GN`, `GL`, `BD`. Informational only.
  final String talker;

  /// True only when this sentence reports an actual position fix:
  /// GGA `fixQuality >= 1`, or RMC status `A`. When false, [point] is null and
  /// nothing should be plotted.
  final bool hasFix;

  /// WGS84 position. Convert with [wgs84ToGcj02] before drawing on Amap.
  final GeoPoint? point;

  /// GGA field 6. 0 = no fix, 1 = GPS fix, 2 = DGPS, 4/5 = RTK, 6 = estimated.
  final int? fixQuality;

  /// GGA field 7, satellites used in the solution.
  final int? satellites;

  /// GGA field 8, horizontal dilution of precision. **This is a dimensionless
  /// multiplier, not metres** — see [estimateAccuracyM].
  final double? hdop;

  final double? altitudeM;
  final double? speedKnots;
  final double? courseDeg;

  /// UTC timestamp. Only RMC carries a date, so a GGA-derived value has
  /// today's date attached to the sentence's time-of-day and should not be
  /// trusted across midnight.
  final DateTime? utc;

  /// Speed in metres per second, if this sentence carried speed.
  double? get speedMps =>
      speedKnots == null ? null : speedKnots! * 0.514444;

  @override
  String toString() => hasFix
      ? 'NmeaFix(${type.name} $talker, $point, q=$fixQuality, '
          'sats=$satellites, hdop=$hdop)'
      : 'NmeaFix(${type.name} $talker, NO FIX, q=$fixQuality, '
          'sats=$satellites)';
}

/// Thrown when a line is not a well-formed NMEA sentence.
class NmeaFormatException implements Exception {
  const NmeaFormatException(this.message);
  final String message;

  @override
  String toString() => 'NmeaFormatException: $message';
}

/// Verifies the `*HH` XOR checksum over everything between `$` and `*`.
///
/// The firmware already drops sentences that fail this, so a failure here
/// means the transport corrupted the bytes — worth counting rather than
/// silently ignoring.
bool nmeaChecksumValid(String sentence) {
  if (sentence.length < 4 || !sentence.startsWith(r'$')) return false;
  final int star = sentence.lastIndexOf('*');
  if (star < 1 || star + 3 != sentence.length) return false;
  int sum = 0;
  for (int i = 1; i < star; i++) {
    sum ^= sentence.codeUnitAt(i);
  }
  final int? given = int.tryParse(sentence.substring(star + 1), radix: 16);
  return given != null && given == sum;
}

/// Parses one sentence. Returns null for sentence types this parser does not
/// interpret, so a caller can feed it every line the collar emits.
///
/// Throws [NmeaFormatException] for a malformed line or a bad checksum; that
/// is a real error worth surfacing, not a missing fix.
NmeaFix? parseNmea(String raw) {
  // The collar sends sentences without CR/LF, but be tolerant of both.
  final String sentence = raw.trim();
  if (!sentence.startsWith(r'$')) {
    throw const NmeaFormatException('sentence must start with \$');
  }
  if (!nmeaChecksumValid(sentence)) {
    throw const NmeaFormatException('checksum mismatch or malformed suffix');
  }

  final int star = sentence.lastIndexOf('*');
  final List<String> f = sentence.substring(1, star).split(',');
  if (f.isEmpty || f[0].length != 5) {
    throw const NmeaFormatException('address field must be 5 characters');
  }

  final String talker = f[0].substring(0, 2);
  final String kind = f[0].substring(2);

  return switch (kind) {
    'GGA' => _parseGga(talker, f),
    'RMC' => _parseRmc(talker, f),
    _ => null,
  };
}

/// `$--GGA,hhmmss.ss,llll.ll,a,yyyyy.yy,a,q,nn,h.h,aaa.a,M,ggg.g,M,t.t,iii*CS`
NmeaFix _parseGga(String talker, List<String> f) {
  if (f.length < 10) {
    throw const NmeaFormatException('GGA needs at least 10 fields');
  }
  final int quality = int.tryParse(f[6]) ?? 0;
  final GeoPoint? point = _coordinate(f[2], f[3], f[4], f[5]);
  // Field 6 is the authority on whether there is a fix. Some modules emit
  // plausible-looking coordinates alongside quality 0; those must be rejected.
  final bool hasFix = quality >= 1 && point != null;

  return NmeaFix(
    type: NmeaSentenceType.gga,
    talker: talker,
    hasFix: hasFix,
    point: hasFix ? point : null,
    fixQuality: quality,
    satellites: int.tryParse(f[7]),
    hdop: double.tryParse(f[8]),
    altitudeM: f.length > 9 ? double.tryParse(f[9]) : null,
    utc: _timeOnly(f[1]),
  );
}

/// `$--RMC,hhmmss.ss,A,llll.ll,a,yyyyy.yy,a,x.x,x.x,ddmmyy,x.x,a,m*CS`
NmeaFix _parseRmc(String talker, List<String> f) {
  if (f.length < 10) {
    throw const NmeaFormatException('RMC needs at least 10 fields');
  }
  final bool statusActive = f[2] == 'A';
  final GeoPoint? point = _coordinate(f[3], f[4], f[5], f[6]);
  final bool hasFix = statusActive && point != null;

  return NmeaFix(
    type: NmeaSentenceType.rmc,
    talker: talker,
    hasFix: hasFix,
    point: hasFix ? point : null,
    speedKnots: double.tryParse(f[7]),
    courseDeg: double.tryParse(f[8]),
    utc: _dateTime(f[9], f[1]),
  );
}

/// NMEA packs latitude as `ddmm.mmmm` and longitude as `dddmm.mmmm` — degrees
/// and *minutes*, not decimal degrees. Forgetting the /60 is the classic bug
/// and puts you tens of kilometres away.
GeoPoint? _coordinate(String lat, String ns, String lon, String ew) {
  final double? latDeg = _degrees(lat, 2);
  final double? lonDeg = _degrees(lon, 3);
  if (latDeg == null || lonDeg == null) return null;

  final double signedLat = ns == 'S' ? -latDeg : latDeg;
  final double signedLon = ew == 'W' ? -lonDeg : lonDeg;
  if (signedLat.abs() > 90 || signedLon.abs() > 180) return null;
  return GeoPoint(signedLat, signedLon);
}

double? _degrees(String value, int degreeDigits) {
  if (value.length < degreeDigits + 1) return null;
  final double? deg = double.tryParse(value.substring(0, degreeDigits));
  final double? min = double.tryParse(value.substring(degreeDigits));
  if (deg == null || min == null || min >= 60) return null;
  return deg + min / 60.0;
}

DateTime? _timeOnly(String hhmmss) {
  if (hhmmss.length < 6) return null;
  final DateTime now = DateTime.now().toUtc();
  final int? h = int.tryParse(hhmmss.substring(0, 2));
  final int? m = int.tryParse(hhmmss.substring(2, 4));
  final double? s = double.tryParse(hhmmss.substring(4));
  if (h == null || m == null || s == null) return null;
  return DateTime.utc(now.year, now.month, now.day, h, m, s.floor(),
      ((s - s.floor()) * 1000).round());
}

DateTime? _dateTime(String ddmmyy, String hhmmss) {
  if (ddmmyy.length != 6 || hhmmss.length < 6) return null;
  final int? day = int.tryParse(ddmmyy.substring(0, 2));
  final int? month = int.tryParse(ddmmyy.substring(2, 4));
  final int? yy = int.tryParse(ddmmyy.substring(4));
  final int? h = int.tryParse(hhmmss.substring(0, 2));
  final int? m = int.tryParse(hhmmss.substring(2, 4));
  final double? s = double.tryParse(hhmmss.substring(4));
  if (day == null || month == null || yy == null ||
      h == null || m == null || s == null) {
    return null;
  }
  return DateTime.utc(2000 + yy, month, day, h, m, s.floor(),
      ((s - s.floor()) * 1000).round());
}

/// Very rough horizontal accuracy in metres, for drawing a circle on the map.
///
/// **HDOP is a multiplier, not a distance.** The usual field approximation is
/// `accuracy ≈ HDOP × UERE`, where UERE (user equivalent range error) is a
/// per-receiver constant of roughly 4–6 m for consumer GNSS. So this returns an
/// order-of-magnitude hint, not a measured value, and the collar does not
/// report a real accuracy figure at all. Label it as an estimate in the UI and
/// never store it as if the hardware had measured it.
double? estimateAccuracyM(double? hdop, {double uereM = 5.0}) =>
    hdop == null || hdop <= 0 ? null : hdop * uereM;

/// Folds a stream of sentences into a single best-known fix.
///
/// The module emits about 10 sentences per second in one group (which is not a
/// 10 Hz fix rate — see the firmware validation notes). RMC and GGA each carry
/// part of the picture, so this keeps the latest position from either while
/// retaining GGA's quality metadata.
class NmeaAggregator {
  GeoPoint? _point;
  int? _fixQuality;
  int? _satellites;
  double? _hdop;
  double? _speedKnots;
  double? _courseDeg;
  DateTime? _utc;
  DateTime? _updatedAt;

  GeoPoint? get point => _point;
  int? get fixQuality => _fixQuality;
  int? get satellites => _satellites;
  double? get hdop => _hdop;
  double? get speedKnots => _speedKnots;
  double? get courseDeg => _courseDeg;
  DateTime? get utc => _utc;

  /// When [point] was last refreshed by a sentence that actually had a fix.
  DateTime? get updatedAt => _updatedAt;

  bool get hasFix => _point != null;

  /// Feeds one sentence. Returns true when this sentence moved the position.
  bool add(NmeaFix fix) {
    // Quality metadata is worth keeping even with no fix — "0 satellites" is
    // the difference between "no sky view" and "module not responding".
    if (fix.type == NmeaSentenceType.gga) {
      _fixQuality = fix.fixQuality ?? _fixQuality;
      _satellites = fix.satellites ?? _satellites;
      _hdop = fix.hdop ?? _hdop;
    }
    if (fix.speedKnots != null) _speedKnots = fix.speedKnots;
    if (fix.courseDeg != null) _courseDeg = fix.courseDeg;

    if (!fix.hasFix || fix.point == null) return false;
    _point = fix.point;
    _utc = fix.utc ?? _utc;
    _updatedAt = DateTime.now();
    return true;
  }

  /// Convenience: parse and fold in one step. Unknown sentence types are
  /// ignored; malformed ones still throw [NmeaFormatException].
  bool addSentence(String sentence) {
    final NmeaFix? fix = parseNmea(sentence);
    return fix == null ? false : add(fix);
  }

  void reset() {
    _point = null;
    _fixQuality = null;
    _satellites = null;
    _hdop = null;
    _speedKnots = null;
    _courseDeg = null;
    _utc = null;
    _updatedAt = null;
  }
}
