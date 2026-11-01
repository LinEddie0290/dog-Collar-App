import 'dart:typed_data';

import 'config.dart';
import 'state.dart';

/// collar/behavior/events.py と同じ：窓の結果 → 出来事（M8 / T13）。
///
/// 1. t_start_dev_us でつなぐ
/// 2. 窓のラベル：休息は状態判断のとおり、ほかは CNN
/// 3. 前後 5 窓の多数決（一瞬だけのものを消す）
/// 4. 同じラベルを 1 つの出来事に。2 秒以内の切れ目はつなぐ
/// 5. 短すぎるものは隣の長い方へ（休息は除く）。両隣がなければ other
/// 6. 確からしさ：確率の平均 ≥ 0.8 →「高」
/// 7. 休息 5 分以上で心拍が測れていれば long_still の行を足す
class EventConfig {
  const EventConfig({
    this.smoothWindows = 5,
    this.mergeGapS = 2.0,
    this.minS = const <String, double>{'lick': 2.0, 'scratch': 2.0, 'shake': 2.0, 'walk_run': 3.0},
    this.overrideRest = const <String, double>{},
    this.highProb = 0.8,
    this.longStillS = 300.0,
  });

  final int smoothWindows; // EVENT_SMOOTH_WINDOWS
  final double mergeGapS; // EVENT_MERGE_GAP_S
  final Map<String, double> minS; // EVENT_MIN_S
  final Map<String, double> overrideRest; // EVENT_OVERRIDE_REST
  final double highProb; // EVENT_HIGH_PROB
  final double longStillS; // LONG_STILL_S
}

const String confHigh = '高';
const String confMid = '中';

/// CNN の 1 窓の結果（cnn.parquet の 1 行）。
class CnnWindow {
  const CnnWindow({required this.tStartMs, required this.tStartDevUs, required this.label, required this.prob});
  final int tStartMs;
  final int tStartDevUs;
  final String label;
  final double prob; // float32 の値
}

/// 心拍・呼吸の 1 回の結果（vitals.parquet の 1 行）。
class VitalReading {
  const VitalReading({required this.tMs, required this.tDevUs, required this.kind, this.value, required this.valid});
  final int tMs;
  final int tDevUs;
  final String kind; // 'hr' か 'rr'
  final double? value;
  final bool valid;
}

class BehaviorEvent {
  BehaviorEvent({
    required this.type,
    required this.sub,
    required this.tStartMs,
    required this.tEndMs,
    required this.durationS,
    required this.tStartDevUs,
    required this.confidence,
    required this.source,
    this.hrMedian,
    this.rrMedian,
  });

  int eventId = 0;
  final String type; // rest_lie / walk_run / other / lick / scratch / shake / long_still
  final String sub; // walk_run のとき walk か run
  final int tStartMs;
  final int tEndMs;
  final double durationS;
  final int tStartDevUs;
  final String confidence; // 高 / 中
  final String source; // state / cnn_imu / state+vitals
  final double? hrMedian;
  final double? rrMedian;

  BehaviorEvent copyAs(String newType, String newSource) => BehaviorEvent(
        type: newType,
        sub: sub,
        tStartMs: tStartMs,
        tEndMs: tEndMs,
        durationS: durationS,
        tStartDevUs: tStartDevUs,
        confidence: confidence,
        source: newSource,
        hrMedian: hrMedian,
        rrMedian: rrMedian,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'event_id': eventId,
        'type': type,
        'sub': sub,
        't_start_ms': tStartMs,
        't_end_ms': tEndMs,
        'duration_s': durationS,
        't_start_dev_us': tStartDevUs,
        'confidence': confidence,
        'source': source,
        'hr_median': hrMedian,
        'rr_median': rrMedian,
      };
}

/// 窓ごとの表（window_table の 1 行）。
class WindowLabel {
  WindowLabel(this.tStartMs, this.tUs, this.label, this.sub, this.prob, this.forcedMid, this.src);
  final int tStartMs;
  final int tUs;
  final String label;
  final String sub;
  final double prob;
  final bool forcedMid;
  final String src;
  String finalKey = '';
}

double _f32(double v) => (Float32List(1)..[0] = v)[0];

List<WindowLabel> windowTable(List<WindowState> state, List<CnnWindow> cnn,
    {List<String>? warnings, EventConfig ecfg = const EventConfig()}) {
  final Map<int, CnnWindow> byUs = <int, CnnWindow>{for (final CnnWindow c in cnn) c.tStartDevUs: c};
  final List<WindowState> st = <WindowState>[for (final WindowState s in state) if (byUs.containsKey(s.tStartDevUs)) s]
    ..sort((WindowState a, WindowState b) => a.tStartDevUs.compareTo(b.tStartDevUs));
  final int lost = state.length + cnn.length - 2 * st.length;
  if (lost != 0) warnings?.add('state 和 cnn 对不上的窗口有 $lost 个，没有用');
  final List<WindowLabel> out = <WindowLabel>[];
  for (final WindowState s in st) {
    final CnnWindow c = byUs[s.tStartDevUs]!;
    final double thr = ecfg.overrideRest[c.label] ?? double.infinity;
    final bool rest = s.rest && !(c.prob >= thr);
    String label = rest ? 'rest_lie' : c.label;
    String sub = '';
    if (label == 'walk' || label == 'run') {
      sub = label;
      label = 'walk_run';
    }
    final bool forcedMid = !rest && !s.rest && label == 'still'; // 動いているのに still
    if (forcedMid) label = 'other';
    out.add(WindowLabel(s.tStartMs, s.tStartDevUs, label, sub, rest ? 1.0 : c.prob, forcedMid, rest ? 'state' : 'cnn_imu'));
  }
  return out;
}

List<List<int>> _segments(List<int> tUs, int stepUs) {
  final List<List<int>> out = <List<int>>[];
  int a = 0;
  for (int i = 0; i + 1 < tUs.length; i++) {
    if (tUs[i + 1] - tUs[i] != stepUs) {
      out.add(<int>[a, i + 1]);
      a = i + 1;
    }
  }
  out.add(<int>[a, tUs.length]);
  return out;
}

String _mostCommon(List<String> xs, int lo, int hi) {
  final Map<String, int> cnt = <String, int>{};
  for (int k = lo; k < hi; k++) {
    cnt[xs[k]] = (cnt[xs[k]] ?? 0) + 1;
  }
  String best = xs[lo];
  int bestN = -1;
  cnt.forEach((String k, int v) {
    if (v > bestN) {
      bestN = v;
      best = k;
    }
  });
  return best;
}

List<List<String>> smoothLabels(List<String> labels, List<String> subs, List<int> tUs, int k, int stepUs) {
  final int h = k ~/ 2;
  final List<String> outL = List<String>.of(labels), outS = List<String>.of(subs);
  for (final List<int> seg in _segments(tUs, stepUs)) {
    final int a = seg[0], b = seg[1];
    for (int i = a; i < b; i++) {
      final int lo = i - h > a ? i - h : a;
      final int hi = i + h + 1 < b ? i + h + 1 : b;
      final Map<String, int> cnt = <String, int>{};
      for (int q = lo; q < hi; q++) {
        cnt[labels[q]] = (cnt[labels[q]] ?? 0) + 1;
      }
      int best = 0;
      for (final int v in cnt.values) {
        if (v > best) best = v;
      }
      if ((cnt[labels[i]] ?? 0) < best) {
        // 一番多いもの（同じ数なら先に出てきたもの）
        for (final MapEntry<String, int> e in cnt.entries) {
          if (e.value == best) {
            outL[i] = e.key;
            break;
          }
        }
      }
      if (labels[i] == 'rest_lie' || outL[i] == 'rest_lie') outL[i] = labels[i]; // 休息は状態判断のとおり
      if (outL[i] == 'walk_run') {
        final List<String> nonEmpty = <String>[for (int q = lo; q < hi; q++) if (subs[q].isNotEmpty) subs[q]];
        if (nonEmpty.isNotEmpty) {
          final Map<String, int> sc = <String, int>{};
          for (final String s in nonEmpty) {
            sc[s] = (sc[s] ?? 0) + 1;
          }
          int top = 0;
          for (final int v in sc.values) {
            if (v > top) top = v;
          }
          outS[i] = subs[i].isNotEmpty && sc[subs[i]] == top ? subs[i] : _mostCommon(nonEmpty, 0, nonEmpty.length);
        }
      } else {
        outS[i] = '';
      }
    }
  }
  return <List<String>>[outL, outS];
}

List<List<int>> _runs(List<String> keys, List<int> tUs, int stepUs) {
  final List<List<int>> out = <List<int>>[];
  for (final List<int> seg in _segments(tUs, stepUs)) {
    final int a = seg[0], b = seg[1];
    if (a >= b) continue;
    int s = a;
    for (int i = a + 1; i <= b; i++) {
      if (i == b || keys[i] != keys[s]) {
        out.add(<int>[s, i]);
        s = i;
      }
    }
  }
  return out;
}

List<String> _mergeGaps(List<String> keysIn, List<int> tUs, double gapS, double stepS) {
  final List<String> keys = List<String>.of(keysIn);
  final int stepUs = roundHalfEven(stepS * 1e6);
  final int gapN = roundHalfEven(gapS / stepS);
  final List<List<int>> runs = _runs(keys, tUs, stepUs);
  for (int j = 1; j + 1 < runs.length; j++) {
    final int a0 = runs[j - 1][0], b0 = runs[j - 1][1];
    final int a1 = runs[j][0], b1 = runs[j][1];
    final int a2 = runs[j + 1][0];
    if (keys[a0] == keys[a2] &&
        keys[a2] != keys[a1] &&
        (b1 - a1) <= gapN &&
        b0 == a1 &&
        b1 == a2 &&
        keys[a0] != 'other:' &&
        keys[a0] != 'rest_lie:' &&
        keys[a1] != 'rest_lie:' &&
        tUs[a2] - tUs[b0 - 1] == (b1 - a1 + 1) * (stepS * 1e6).truncate()) {
      for (int i = a1; i < b1; i++) {
        keys[i] = keys[a0];
      }
    }
  }
  return keys;
}

List<String> _dropShort(List<String> keysIn, List<int> tUs, Map<String, double> minS, double stepS) {
  final List<String> keys = List<String>.of(keysIn);
  final int stepUs = roundHalfEven(stepS * 1e6);
  for (int it = 0; it < 3; it++) {
    final List<List<int>> runs = _runs(keys, tUs, stepUs);
    bool changed = false;
    for (int j = 0; j < runs.length; j++) {
      final int a = runs[j][0], b = runs[j][1];
      final String typ = keys[a].split(':')[0];
      if ((b - a) * stepS >= (minS[typ] ?? 0.0)) continue;
      List<int>? best;
      for (final int x in <int>[j - 1, j + 1]) {
        if (x < 0 || x >= runs.length) continue;
        final List<int> r = runs[x];
        if (!(r[1] == a || r[0] == b) || keys[r[0]] == 'rest_lie:') continue;
        if (best == null || (r[1] - r[0]) > (best[1] - best[0])) best = r;
      }
      final String nw = best != null ? keys[best[0]] : 'other:';
      if (nw != keys[a]) {
        for (int i = a; i < b; i++) {
          keys[i] = nw;
        }
        changed = true;
      }
    }
    if (!changed) break;
  }
  return keys;
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final List<double> s = List<double>.of(v)..sort();
  final int n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

List<double?> _vitalMedians(List<VitalReading>? vitals, int startUs, int endUs) {
  if (vitals == null || vitals.isEmpty) return <double?>[null, null];
  final List<double?> out = <double?>[];
  for (final String kind in <String>['hr', 'rr']) {
    final List<double> x = <double>[
      for (final VitalReading v in vitals)
        if (v.tDevUs >= startUs && v.tDevUs < endUs && v.valid && v.kind == kind && v.value != null && !v.value!.isNaN)
          v.value!,
    ];
    out.add(_median(x));
  }
  return out;
}

class EventsResult {
  EventsResult(this.events, this.windows);
  final List<BehaviorEvent> events;
  final List<WindowLabel> windows;
}

EventsResult buildEvents(List<WindowState> state, List<CnnWindow> cnn,
    {List<VitalReading>? vitals,
    List<String>? warnings,
    PipelineConfig cfg = const PipelineConfig(),
    EventConfig ecfg = const EventConfig()}) {
  final List<WindowLabel> w = windowTable(state, cnn, warnings: warnings, ecfg: ecfg);
  if (w.isEmpty) return EventsResult(<BehaviorEvent>[], w);
  final int stepUs = roundHalfEven(cfg.windowStepS * 1e6);
  final List<int> tUs = <int>[for (final WindowLabel x in w) x.tUs];
  final List<List<String>> sm = smoothLabels(<String>[for (final WindowLabel x in w) x.label],
      <String>[for (final WindowLabel x in w) x.sub], tUs, ecfg.smoothWindows, stepUs);
  List<String> keys = <String>[for (int i = 0; i < w.length; i++) '${sm[0][i]}:${sm[1][i]}'];
  keys = _mergeGaps(keys, tUs, ecfg.mergeGapS, cfg.windowStepS);
  keys = _dropShort(keys, tUs, ecfg.minS, cfg.windowStepS);
  for (int i = 0; i < w.length; i++) {
    w[i].finalKey = keys[i];
  }

  final List<BehaviorEvent> rows = <BehaviorEvent>[];
  for (final List<int> r in _runs(keys, tUs, stepUs)) {
    final int a = r[0], b = r[1];
    final List<String> parts = keys[a].split(':');
    final String typ = parts[0], sb = parts.length > 1 ? parts[1] : '';
    final int t0Ms = w[a].tStartMs;
    final int t1Ms = t0Ms >= 0 ? w[b - 1].tStartMs + stepUs ~/ 1000 : -1;
    String conf, src;
    if (typ == 'rest_lie') {
      conf = confHigh;
      src = 'state';
    } else {
      final List<WindowLabel> seg = w.sublist(a, b);
      final List<WindowLabel> same = <WindowLabel>[for (final WindowLabel x in seg) if (x.label == typ) x];
      final List<WindowLabel> use = same.isNotEmpty ? same : seg;
      double m = 0;
      for (final WindowLabel x in use) {
        m += x.prob;
      }
      m /= use.length;
      final bool midFlag = same.isNotEmpty ? same.any((WindowLabel x) => x.forcedMid) : true;
      conf = (m >= ecfg.highProb && !midFlag) ? confHigh : confMid;
      src = 'cnn_imu';
    }
    final int startUs = tUs[a], endUs = tUs[b - 1] + stepUs;
    final List<double?> v = _vitalMedians(vitals, startUs, endUs);
    final BehaviorEvent ev = BehaviorEvent(
      type: typ,
      sub: sb,
      tStartMs: t0Ms,
      tEndMs: t1Ms,
      durationS: _f32((endUs - startUs) / 1e6),
      tStartDevUs: startUs,
      confidence: conf,
      source: src,
      hrMedian: v[0] == null ? null : _f32(v[0]!),
      rrMedian: v[1] == null ? null : _f32(v[1]!),
    );
    rows.add(ev);
    if (typ == 'rest_lie' && (endUs - startUs) / 1e6 >= ecfg.longStillS && v[0] != null) {
      rows.add(ev.copyAs('long_still', 'state+vitals'));
    }
  }
  for (int i = 0; i < rows.length; i++) {
    rows[i].eventId = i;
  }
  return EventsResult(rows, w);
}
