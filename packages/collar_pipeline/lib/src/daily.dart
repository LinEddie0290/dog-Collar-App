import 'events.dart';

/// collar/context/daily.py（情境層 M9 / T14）と collar/user/summary.py（用户層 M10 / T15）と同じ。
/// 出来事 → 1 日の値と平時比 → アプリの 1 日まとめ JSON（collar.daily_summary/0.1）。
class DailyConfig {
  const DailyConfig({
    this.tzOffsetHours = 8, // TIMEZONE = Asia/Shanghai（夏時間なし）
    this.nightStartH = 20,
    this.nightEndH = 8,
    this.wearMinMin = 1200,
    this.sleepJoinS = 120,
    this.sleepBlockMinS = 1800,
    this.baselineDays = 14,
    this.warmupDays = 2,
    this.minBaselineDays = 7,
    this.windowStepS = 1.0,
    this.skinRatio = 2.0,
    this.skinMinCount = 10,
    this.exerciseRatio = 0.6,
    this.sleepRatio = 0.8,
    this.sleepQualityGood = 0.85,
    this.sleepQualityOk = 0.70,
    this.physioRatio = 1.2,
    this.sleepRrMax = 30.0,
    this.historyDays = 30,
  });

  final int tzOffsetHours;
  final int nightStartH;
  final int nightEndH;
  final double wearMinMin;
  final double sleepJoinS;
  final double sleepBlockMinS;
  final int baselineDays;
  final int warmupDays;
  final int minBaselineDays;
  final double windowStepS;
  final double skinRatio;
  final double skinMinCount;
  final double exerciseRatio;
  final double sleepRatio;
  final double sleepQualityGood;
  final double sleepQualityOk;
  final double physioRatio;
  final double sleepRrMax;
  final int historyDays;
}

const List<List<String>> dailyMetrics = <List<String>>[
  <String>['exercise', 'active_min'],
  <String>['exercise', 'run_min'],
  <String>['exercise', 'outdoor_dist_m'],
  <String>['sleep', 'sleep_min'],
  <String>['sleep', 'sleep_quality'],
  <String>['sleep', 'wake_count'],
  <String>['sleep', 'sleep_rr_median'],
  <String>['skin', 'scratch_count'],
  <String>['skin', 'scratch_min'],
  <String>['skin', 'lick_count'],
  <String>['skin', 'lick_min'],
  <String>['skin', 'itch_count'],
  <String>['skin', 'night_share'],
  <String>['physio', 'rest_hr_median'],
  <String>['physio', 'rest_rr_median'],
  <String>['physio', 'shake_count'],
  <String>['physio', 'temp_delta_median'],
];

class DailyRow {
  DailyRow(this.date, this.category, this.metric, this.value, this.wearMin);
  final String date;
  final String category;
  final String metric;
  final double value; // NaN＝なし
  final double wearMin;
  bool validDay = false;
  double baseline = double.nan;
  double ratio = double.nan;
  int nDays = 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'date': date,
        'category': category,
        'metric': metric,
        'value': value.isNaN ? null : value,
        'baseline': baseline.isNaN ? null : baseline,
        'ratio': ratio.isNaN ? null : ratio,
        'n_days': nDays,
        'wear_min': wearMin,
        'valid_day': validDay,
      };
}

/// UTC ミリ秒 → その土地の時刻（DateTime の UTC 欄に入れて使う）。
DateTime _local(int ms, DailyConfig c) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(Duration(hours: c.tzOffsetHours));

String dateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

DateTime _dateOf(String key) => DateTime.utc(int.parse(key.substring(0, 4)), int.parse(key.substring(5, 7)),
    int.parse(key.substring(8, 10)));

/// 窓の開始時刻（UTC ms）→ その土地の日付ごとの窓の数。t < 0（UTC なし）は数えない。
Map<String, int> countWindowsByDate(Iterable<int> tStartMs, {DailyConfig cfg = const DailyConfig()}) {
  final Map<String, int> out = <String, int>{};
  for (final int t in tStartMs) {
    if (t < 0) continue;
    final String d = dateKey(_local(t, cfg));
    out[d] = (out[d] ?? 0) + 1;
  }
  return out;
}

double _medianOrNan(List<double> v) {
  if (v.isEmpty) return double.nan;
  final List<double> s = List<double>.of(v)..sort();
  final int n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

class _Span {
  _Span(this.s, this.e);
  DateTime s;
  DateTime e;
}

Map<String, double> _sleepMetrics(List<_Span> rest, List<VitalReading> vit, String date, DailyConfig c) {
  final DateTime d = _dateOf(date);
  final DateTime a = d.subtract(Duration(hours: 24 - c.nightStartH));
  final DateTime b = d.add(Duration(hours: c.nightEndH));
  final Map<String, double> out = <String, double>{
    'sleep_min': 0.0,
    'sleep_quality': double.nan,
    'wake_count': 0.0,
    'sleep_rr_median': double.nan,
  };
  final List<_Span> r = <_Span>[
    for (final _Span x in rest)
      if (x.e.isAfter(a) && x.s.isBefore(b)) _Span(x.s.isBefore(a) ? a : x.s, x.e.isAfter(b) ? b : x.e),
  ];
  if (r.isEmpty) return out;
  r.sort((_Span p, _Span q) => p.s.compareTo(q.s)); // pandas の sort_values（同じ時刻の順は気にしない）
  final List<List<Object>> blocks = <List<Object>>[]; // [start, end, rest 秒]
  List<Object>? cur;
  for (final _Span x in r) {
    if (cur != null && x.s.difference(cur[1] as DateTime).inMicroseconds / 1e6 < c.sleepJoinS) {
      final DateTime ce = cur[1] as DateTime;
      cur[1] = x.e.isAfter(ce) ? x.e : ce;
      cur[2] = (cur[2] as double) + x.e.difference(x.s).inMicroseconds / 1e6;
    } else {
      if (cur != null) blocks.add(cur);
      cur = <Object>[x.s, x.e, x.e.difference(x.s).inMicroseconds / 1e6];
    }
  }
  blocks.add(cur!);
  final List<List<Object>> kept = <List<Object>>[
    for (final List<Object> bk in blocks)
      if ((bk[1] as DateTime).difference(bk[0] as DateTime).inMicroseconds / 1e6 >= c.sleepBlockMinS) bk,
  ];
  if (kept.isEmpty) return out;
  final double span = (kept.last[1] as DateTime).difference(kept.first[0] as DateTime).inMicroseconds / 1e6;
  double restS = 0;
  for (final List<Object> bk in kept) {
    restS += bk[2] as double;
  }
  out['sleep_min'] = restS / 60;
  out['sleep_quality'] = span > 0 ? restS / span : double.nan;
  out['wake_count'] = (kept.length - 1).toDouble();
  final List<double> rr = <double>[];
  for (final VitalReading v in vit) {
    if (v.kind != 'rr' || v.value == null) continue;
    final DateTime t = _local(v.tMs, c);
    for (final List<Object> bk in kept) {
      if (!t.isBefore(bk[0] as DateTime) && t.isBefore(bk[1] as DateTime)) {
        rr.add(v.value!);
        break;
      }
    }
  }
  if (rr.isNotEmpty) out['sleep_rr_median'] = _medianOrNan(rr);
  return out;
}

/// day_values：日付 × 指標の値（平時比はまだ）。
/// events：その犬の全部の出来事。windowsByDate：countWindowsByDate の結果。vitals：心拍・呼吸。
List<DailyRow> dayValues(List<BehaviorEvent> events, Map<String, int> windowsByDate, List<VitalReading> vitals,
    {DailyConfig cfg = const DailyConfig()}) {
  if (windowsByDate.isEmpty) return <DailyRow>[];
  final List<String> dates = windowsByDate.keys.toList()..sort();
  final List<BehaviorEvent> ev = <BehaviorEvent>[for (final BehaviorEvent e in events) if (e.tStartMs >= 0) e];
  final List<VitalReading> vit = <VitalReading>[for (final VitalReading v in vitals) if (v.tMs >= 0 && v.valid) v];
  final List<_Span> rest = <_Span>[
    for (final BehaviorEvent e in ev)
      if (e.type == 'rest_lie') _Span(_local(e.tStartMs, cfg), _local(e.tEndMs, cfg)),
  ];
  final List<DailyRow> rows = <DailyRow>[];
  for (final String d in dates) {
    final List<BehaviorEvent> e = <BehaviorEvent>[for (final BehaviorEvent x in ev) if (dateKey(_local(x.tStartMs, cfg)) == d) x];
    double dur(bool Function(BehaviorEvent) f) {
      double s = 0;
      for (final BehaviorEvent x in e) {
        if (f(x)) s += x.durationS;
      }
      return s / 60;
    }

    double cnt(String typ) => e.where((BehaviorEvent x) => x.type == typ).length.toDouble();
    final List<BehaviorEvent> itch = <BehaviorEvent>[for (final BehaviorEvent x in e) if (x.type == 'scratch' || x.type == 'lick') x];
    double nightShare = double.nan;
    if (itch.isNotEmpty) {
      int nn = 0;
      for (final BehaviorEvent x in itch) {
        final int h = _local(x.tStartMs, cfg).hour;
        if (h >= cfg.nightStartH || h < cfg.nightEndH) nn++;
      }
      nightShare = nn / itch.length;
    }
    final Map<String, double> vals = <String, double>{
      'active_min': dur((BehaviorEvent x) => x.type == 'walk_run'),
      'run_min': dur((BehaviorEvent x) => x.type == 'walk_run' && x.sub == 'run'),
      'outdoor_dist_m': double.nan,
      'scratch_count': cnt('scratch'),
      'scratch_min': dur((BehaviorEvent x) => x.type == 'scratch'),
      'lick_count': cnt('lick'),
      'lick_min': dur((BehaviorEvent x) => x.type == 'lick'),
      'itch_count': itch.length.toDouble(),
      'night_share': nightShare,
      'shake_count': cnt('shake'),
      'temp_delta_median': double.nan,
    };
    for (final List<String> kn in <List<String>>[
      <String>['hr', 'rest_hr_median'],
      <String>['rr', 'rest_rr_median'],
    ]) {
      vals[kn[1]] = _medianOrNan(<double>[
        for (final VitalReading v in vit)
          if (v.kind == kn[0] && v.value != null && dateKey(_local(v.tMs, cfg)) == d) v.value!,
      ]);
    }
    vals.addAll(_sleepMetrics(rest, vit, d, cfg));
    final double wear = windowsByDate[d]! * cfg.windowStepS / 60;
    for (final List<String> cm in dailyMetrics) {
      rows.add(DailyRow(d, cm[0], cm[1], vals[cm[1]]!, wear));
    }
  }
  return rows;
}

/// add_baseline（D-020）：平時＝最近 14 日の中央値（最初の 2 日は使わない、7 日分そろってから）。
List<DailyRow> addBaseline(List<DailyRow> dv, {DailyConfig cfg = const DailyConfig()}) {
  for (final DailyRow r in dv) {
    r.validDay = r.wearMin >= cfg.wearMinMin;
  }
  final List<String> dates = <String>{for (final DailyRow r in dv) r.date}.toList()..sort();
  if (dates.isEmpty) return dv;
  final DateTime first = _dateOf(dates.first);
  final Set<String> warm = <String>{
    for (int i = 0; i < cfg.warmupDays; i++) dateKey(first.add(Duration(days: i))),
  };
  final Map<String, Map<String, double>> piv = <String, Map<String, double>>{};
  final Map<String, bool> valid = <String, bool>{};
  for (final DailyRow r in dv) {
    piv.putIfAbsent(r.date, () => <String, double>{})[r.metric] = r.value;
    valid.putIfAbsent(r.date, () => r.validDay);
  }
  for (final DailyRow r in dv) {
    final DateTime d = _dateOf(r.date);
    final DateTime lo = d.subtract(Duration(days: cfg.baselineDays));
    final List<double> vals = <double>[];
    for (final String x in dates) {
      final DateTime xd = _dateOf(x);
      if (!xd.isBefore(lo) && xd.isBefore(d) && !warm.contains(x) && valid[x]!) {
        final double? v = piv[x]![r.metric];
        if (v != null && !v.isNaN) vals.add(v);
      }
    }
    r.nDays = vals.length;
    r.baseline = vals.length >= cfg.minBaselineDays ? _medianOrNan(vals) : double.nan;
    r.ratio = (r.baseline > 0 && !r.value.isNaN) ? r.value / r.baseline : double.nan;
  }
  return dv;
}

List<DailyRow> buildDaily(List<BehaviorEvent> events, Map<String, int> windowsByDate, List<VitalReading> vitals,
        {DailyConfig cfg = const DailyConfig()}) =>
    addBaseline(dayValues(events, windowsByDate, vitals, cfg: cfg), cfg: cfg);

// ------------------------------------------------------------------ 用户層（T15）

/// Python の round()（偶数への丸め）。
int _roundEven(double x) {
  final double f = x.floorToDouble();
  final double diff = x - f;
  if (diff > 0.5) return f.toInt() + 1;
  if (diff < 0.5) return f.toInt();
  final int fi = f.toInt();
  return fi.isEven ? fi : fi + 1;
}

Object? _num(double? x, [int nd = 0]) {
  if (x == null || x.isNaN) return null;
  if (nd == 0) return _roundEven(x);
  return double.parse(x.toStringAsFixed(nd));
}

String? qualityLevel(double q, DailyConfig c) {
  if (q.isNaN) return null;
  if (q >= c.sleepQualityGood) return 'good';
  if (q >= c.sleepQualityOk) return 'ok';
  return 'poor';
}

int daysUntilCompare(List<DailyRow> dv, String date, DailyConfig c) {
  final List<String> dates = <String>{for (final DailyRow r in dv) r.date}.toList()..sort();
  final int since = dates.indexOf(date);
  int n = 0;
  for (final DailyRow r in dv) {
    if (r.date == date && r.nDays > n) n = r.nDays;
  }
  final int warmLeft = c.warmupDays - since > 0 ? c.warmupDays - since : 0;
  final int v = warmLeft + c.minBaselineDays - n;
  return v > 0 ? v : 0;
}

Map<String, Object?> buildSummary(List<DailyRow> dv, String date, String dogId,
    {required String generatedAt, DailyConfig cfg = const DailyConfig()}) {
  final Map<String, DailyRow> day = <String, DailyRow>{for (final DailyRow r in dv) if (r.date == date) r.metric: r};
  double get(String m, [String col = 'value']) {
    final DailyRow? r = day[m];
    if (r == null) return double.nan;
    switch (col) {
      case 'baseline':
        return r.baseline;
      case 'ratio':
        return r.ratio;
      default:
        return r.value;
    }
  }

  final bool valid = day.isNotEmpty && day.values.first.validDay;
  final int? wait = day.isNotEmpty ? daysUntilCompare(dv, date, cfg) : null;

  String status(List<String> ms) {
    if (!valid || ms.every((String m) => get(m).isNaN)) return 'no_data';
    return ms.every((String m) => get(m, 'baseline').isNaN) ? 'collecting' : 'ok';
  }

  Map<String, Object?> alert(String key, String metric, [Map<String, Object?>? extra]) {
    final Map<String, Object?> a = <String, Object?>{
      'level': 'notice',
      'text_key': key,
      'values': <String, Object?>{'metric': metric, 'ratio': _num(get(metric, 'ratio'), 1)},
    };
    if (extra != null) (a['values']! as Map<String, Object?>).addAll(extra);
    return a;
  }

  final List<Map<String, Object?>> cats = <Map<String, Object?>>[];
  // 运动
  String st = status(<String>['active_min']);
  Map<String, Object?>? al;
  if (st == 'ok' && get('active_min', 'ratio') <= cfg.exerciseRatio) al = alert('exercise.alert.less', 'active_min');
  cats.add(<String, Object?>{
    'id': 'exercise',
    'status': st,
    'alert': al,
    'daily': st == 'no_data'
        ? null
        : <String, Object?>{
            'text_key': 'exercise.daily',
            'values': <String, Object?>{'active_min': _num(get('active_min'))},
          },
  });
  // 睡眠
  st = status(<String>['sleep_min']);
  final String? q = qualityLevel(get('sleep_quality'), cfg);
  al = null;
  if (st == 'ok' && (get('sleep_min', 'ratio') <= cfg.sleepRatio || q == 'poor')) {
    al = alert('sleep.alert.less', 'sleep_min', <String, Object?>{'quality': q});
  }
  cats.add(<String, Object?>{
    'id': 'sleep',
    'status': st,
    'alert': al,
    'daily': st == 'no_data'
        ? null
        : <String, Object?>{
            'text_key': 'sleep.daily',
            'values': <String, Object?>{'sleep_min': _num(get('sleep_min')), 'quality': q},
          },
  });
  // 皮肤（毎日の表示はなし、提醒だけ）
  st = status(<String>['itch_count']);
  al = null;
  if (st == 'ok' && get('itch_count', 'ratio') >= cfg.skinRatio && get('itch_count') >= cfg.skinMinCount) {
    al = alert('skin.alert.more', 'itch_count', <String, Object?>{'count': _num(get('itch_count'))});
  }
  cats.add(<String, Object?>{'id': 'skin', 'status': st, 'alert': al, 'daily': null});
  // 生理
  st = status(<String>['rest_hr_median', 'rest_rr_median']);
  al = null;
  final double rrSleep = get('sleep_rr_median');
  if (valid && !rrSleep.isNaN && rrSleep > cfg.sleepRrMax) {
    al = <String, Object?>{
      'level': 'notice',
      'text_key': 'physio.alert.up',
      'values': <String, Object?>{'metric': 'sleep_rr_median', 'value': _num(rrSleep)},
    };
  } else if (st == 'ok') {
    for (final String m in <String>['rest_hr_median', 'rest_rr_median']) {
      final double r = get(m, 'ratio');
      if (!r.isNaN && r >= cfg.physioRatio) {
        al = alert('physio.alert.up', m);
        break;
      }
    }
  }
  cats.add(<String, Object?>{
    'id': 'physio',
    'status': st,
    'alert': al,
    'daily': st == 'no_data'
        ? null
        : <String, Object?>{
            'text_key': 'physio.daily',
            'values': <String, Object?>{'rest_hr': _num(get('rest_hr_median')), 'rest_rr': _num(get('rest_rr_median'))},
          },
  });
  for (final Map<String, Object?> c in cats) {
    if (c['status'] == 'collecting') c['days_until_compare'] = wait;
  }
  return <String, Object?>{
    'schema': 'collar.daily_summary/0.1',
    'dog_id': dogId,
    'date': date,
    'generated_at': generatedAt,
    'categories': cats,
  };
}

Map<String, Object?> buildHistory(List<DailyRow> dv, String upto, {DailyConfig cfg = const DailyConfig()}) {
  final List<String> all = <String>{for (final DailyRow r in dv) r.date}.toList()..sort();
  final List<String> dates = <String>[for (final String d in all) if (d.compareTo(upto) <= 0) d];
  final List<String> last = dates.length > cfg.historyDays ? dates.sublist(dates.length - cfg.historyDays) : dates;
  double v(String d, String m) {
    for (final DailyRow r in dv) {
      if (r.date == d && r.metric == m) return r.value;
    }
    return double.nan;
  }

  bool valid(String d) => dv.firstWhere((DailyRow r) => r.date == d).validDay;
  return <String, Object?>{
    'schema': 'collar.history/0.1',
    'days': <Map<String, Object?>>[
      for (final String d in last)
        <String, Object?>{
          'date': d,
          'valid_day': valid(d),
          'active_min': _num(v(d, 'active_min')),
          'sleep_min': _num(v(d, 'sleep_min')),
          'sleep_quality': _num(v(d, 'sleep_quality'), 2),
          'itch_count': _num(v(d, 'itch_count')),
          'rest_hr': _num(v(d, 'rest_hr_median')),
          'rest_rr': _num(v(d, 'rest_rr_median')),
        },
    ],
  };
}
