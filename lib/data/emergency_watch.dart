/// T34-G：緊急の判定（冲击・倒下・心率异常）。画面なしの計算だけ（D-060）。
///
/// - 冲击：加速度の大きさが [MotionWatcher.impactG] を超えた。記録だけ（通知しない）。
/// - 倒下：急な変化（[MotionWatcher.suddenG] 以上か、1 秒で体の向きが [MotionWatcher.turnDeg] 以上変わる）
///   → 落ち着くまで [MotionWatcher.settleS] 秒待って、そのあと [MotionWatcher.stillS] 秒ほぼ動かない。通知する。
///   ゆっくり横になる（寝る）のは「急な変化」がないので出ない。
/// - 心率异常：安静時の自動測定で、品質 good の値が [HeartWatcher.need] 回続けて安全線の外。通知する（試用）。
/// 数字は全部仮（L6 の 12 番で直す）。向きは「重力の向きの角度」で見るので、首輪の軸の向きには左右されない。
library;

import 'dart:math' as math;

import 'package:collar_pipeline/collar_pipeline.dart' show ImuSample;

import 'safety.dart' show EmergencyKind;

const double gravity = 9.80665;

/// 判定した 1 件。
class EmergencyHit {
  EmergencyHit({required this.kind, required this.tMs, required this.value, required this.detail, this.notify = true});

  final EmergencyKind kind;

  /// 起きた時刻（UTC ミリ秒）。倒下は倒れた時刻（判定は [MotionWatcher.stillS] 秒あと）。
  final int tMs;

  /// 冲击・倒下は g、心率は bpm。
  final double value;
  final String detail;

  /// 通知する種類か（冲击は false）。
  final bool notify;

  /// 実際に通知したか（同じ種類は 10 分に 1 回まで。EmergencyController が入れる）。
  bool notified = false;
}

/// IMU から冲击・倒下を見る。1 つのセンサー（[sensor]）だけ見る。
class MotionWatcher {
  MotionWatcher({
    this.sensor = 'front',
    this.impactG = 4,
    this.suddenG = 2.5,
    this.turnDeg = 60,
    this.turnWindowS = 1,
    this.settleS = 3,
    this.stillS = 120,
    this.stillStd = 0.4,
    this.gravityTauS = 0.2,
    this.maxGapS = 2,
  });

  final String sensor;
  final double impactG, suddenG, turnDeg, turnWindowS, settleS, stillS;

  /// 1 秒ごとの |a| のばらつき（m/s²）。休息のしきい値（PipelineConfig.restThreshold）と同じ。
  final double stillStd;
  final double gravityTauS;
  final double maxGapS;

  int? _lastUs;
  // 重力の向き（ゆっくりした平均）
  double _gx = 0, _gy = 0, _gz = 0;
  bool _hasG = false;
  // 0.1 秒ごとの重力の向き（turnWindowS より少し長く持つ）
  final List<(int, double, double, double)> _hist = <(int, double, double, double)>[];
  int _impactUntilUs = -1;

  // 倒下の候補
  int? _candUs;
  int? _candMs;
  double _candPeakG = 0;
  double _candTurn = 0;
  int _blockStartUs = 0;
  int _blockN = 0;
  double _blockSum = 0, _blockSq = 0;

  bool get pending => _candUs != null;

  void reset() {
    _lastUs = null;
    _hasG = false;
    _hist.clear();
    _impactUntilUs = -1;
    _clearCandidate();
  }

  void _clearCandidate() {
    _candUs = null;
    _candMs = null;
    _candPeakG = 0;
    _candTurn = 0;
    _blockN = 0;
    _blockSum = 0;
    _blockSq = 0;
  }

  /// 1 サンプル入れる。判定したものを返す（ふつうは空）。
  List<EmergencyHit> add(ImuSample s) {
    if (s.sensor != sensor) return const <EmergencyHit>[];
    final int us = s.tDevUs;
    final int? last = _lastUs;
    if (last != null && (us <= last - 1000000 || us - last > maxGapS * 1e6)) {
      reset(); // 時計が戻った・データが途切れた：分からないので数え直す
    }
    if (last != null && us <= last && _lastUs != null) return const <EmergencyHit>[];
    final double dt = _lastUs == null ? 0 : (us - _lastUs!) / 1e6;
    _lastUs = us;
    final int ms = s.tMs ?? us ~/ 1000;

    final double mag = math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    final double magG = mag / gravity;
    final List<EmergencyHit> out = <EmergencyHit>[];

    // 重力の向き
    if (!_hasG) {
      _gx = s.ax;
      _gy = s.ay;
      _gz = s.az;
      _hasG = true;
    } else {
      final double a = dt / (gravityTauS + dt);
      _gx += a * (s.ax - _gx);
      _gy += a * (s.ay - _gy);
      _gz += a * (s.az - _gz);
    }
    if (_hist.isEmpty || us - _hist.last.$1 >= 100000) {
      _hist.add((us, _gx, _gy, _gz));
      while (_hist.length > 2 && us - _hist[1].$1 >= turnWindowS * 1e6) {
        _hist.removeAt(0);
      }
    }
    double turn = 0;
    if (_hist.length >= 2 && us - _hist.first.$1 >= turnWindowS * 1e6 * 0.9) {
      final (int, double, double, double) h = _hist.first;
      turn = _angleDeg(h.$2, h.$3, h.$4, _gx, _gy, _gz);
    }

    // 冲击（同じぶつかりで何件も出さない：1 秒あける）
    if (magG > impactG && us > _impactUntilUs) {
      _impactUntilUs = us + 1000000;
      out.add(EmergencyHit(
        kind: EmergencyKind.impact,
        tMs: ms,
        value: magG,
        detail: '很大的冲击（约 ${magG.toStringAsFixed(1)} g）',
        notify: false,
      ));
    }

    final bool sudden = magG >= suddenG || turn >= turnDeg;
    final int? cand = _candUs;
    if (cand != null && us - cand < settleS * 1e6) {
      // 倒れている途中：一番大きいところを覚える
      _candPeakG = math.max(_candPeakG, magG);
      _candTurn = math.max(_candTurn, turn);
      _blockStartUs = us;
      return out;
    }
    if (sudden) {
      // 新しい候補（前の候補の静止中に動いたのと同じ：やり直し）
      _clearCandidate();
      _candUs = us;
      _candMs = ms;
      _candPeakG = magG;
      _candTurn = turn;
      _blockStartUs = us;
      return out;
    }
    if (cand == null) return out;

    // 落ち着いたあと：1 秒ずつ動きの強さを見る
    _blockN++;
    _blockSum += mag;
    _blockSq += mag * mag;
    if (us - _blockStartUs >= 1000000) {
      final double m = _blockSum / _blockN;
      final double sd = math.sqrt(math.max(0, _blockSq / _blockN - m * m));
      _blockStartUs = us;
      _blockN = 0;
      _blockSum = 0;
      _blockSq = 0;
      if (sd > stillStd) {
        _clearCandidate(); // 動いた：倒れたのではない
        return out;
      }
    }
    if (us - cand >= (settleS + stillS) * 1e6) {
      final double g = _candPeakG;
      final int deg = _candTurn.round();
      final int min = (stillS / 60).round();
      out.add(EmergencyHit(
        kind: EmergencyKind.fall,
        tMs: _candMs!,
        value: g,
        detail: '突然倒下（约 ${g.toStringAsFixed(1)} g，方向变了 $deg°），之后 $min 分钟几乎不动',
      ));
      _clearCandidate();
    }
    return out;
  }
}

double _angleDeg(double ax, double ay, double az, double bx, double by, double bz) {
  final double na = math.sqrt(ax * ax + ay * ay + az * az), nb = math.sqrt(bx * bx + by * by + bz * bz);
  if (na < 1e-6 || nb < 1e-6) return 0;
  final double c = ((ax * bx + ay * by + az * bz) / (na * nb)).clamp(-1.0, 1.0);
  return math.acos(c) * 180 / math.pi;
}

/// 安静時の心率の安全線（D-060 G4、試用）。
class HeartWatcher {
  HeartWatcher({this.low = 50, this.high = 180, this.need = 2});

  final double low, high;
  final int need;
  int _n = 0;

  /// 自動測定の結果 1 つ。[good] は品質が good か（それ以外は数えない・リセットもしない）。
  EmergencyHit? add({required int tMs, required double bpm, required bool good, bool fake = false}) {
    if (!good) return null;
    if (bpm >= low && bpm <= high) {
      _n = 0;
      return null;
    }
    _n++;
    if (_n < need) return null;
    _n = 0;
    return EmergencyHit(
      kind: EmergencyKind.heart,
      tMs: tMs,
      value: bpm,
      detail: '安静时心率 ${bpm.round()} 次/分（连续 $need 次在 ${low.round()}〜${high.round()} 外面）${fake ? '（模拟）' : ''}',
    );
  }
}
