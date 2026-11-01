/// T34-C：正解のラベル（Unity・偽のデータ・D のボタン）と CNN の結果を比べる。
///
/// 正解のラベル → CNN v1 のクラス（still / walk / run / other）は collar-pipeline の
/// MENDELEY_LABEL_MAP → CNN_CLASS_MAP と同じ。知らないラベルは比べない（null）。
library;

import 'imu_input.dart';
import 'pipeline_runner.dart';

const Map<String, String> _toCnn = <String, String>{
  // collar-pipeline の ID
  'rest_lie': 'still', 'sit': 'still', 'stand': 'still', 'still': 'still',
  'walk': 'walk', 'run': 'run',
  'sniff': 'other', 'play': 'other', 'pace': 'other', 'drink': 'other', 'body_shake': 'other',
  'eat': 'other', 'pant': 'other', 'other': 'other',
  // 偽のデータ（shake＝体を振る → v1 では other）
  'shake': 'other',
  // Unity（DogMoveData の元のラベル）
  'walking': 'walk', 'trotting': 'run', 'galloping': 'run', 'sniffing': 'other',
  'lying chest': 'still', 'lying on chest': 'still', 'sitting': 'still', 'standing': 'still',
  'shaking': 'other', 'drinking': 'other', 'panting': 'other', 'playing': 'other', 'tugging': 'other',
  'carrying object': 'other', 'eating': 'other', 'pacing': 'other',
  // D のボタン（伏せ・座る・立つ・歩く・走る・掻く・舐める・飲む・食べる・震える・その他）
  'lie': 'still', 'scratch': 'other', 'lick': 'other', 'tremble': 'other',
};

/// 正解のラベル → CNN v1 のクラス。知らなければ null。
String? truthToCnnClass(String label) => _toCnn[label.trim().toLowerCase()];

/// 時刻 tUs の正解（その時刻より前で一番新しい印）。なければ null。
TruthMark? truthAt(List<TruthMark> marks, int tUs) {
  TruthMark? best;
  for (final TruthMark m in marks) {
    if (m.tDevUs <= tUs && (best == null || m.tDevUs >= best.tDevUs)) best = m;
  }
  return best;
}

class Agreement {
  const Agreement(this.n, this.same);
  final int n; // 比べた窓の数
  final int same; // CNN と正解が同じだった数
  double? get rate => n == 0 ? null : same / n;
}

/// 窓の真ん中（開始 + 1 秒）の正解と CNN のラベルを比べる。
Agreement agreement(List<WindowResult> windows, List<TruthMark> marks, {int halfWindowUs = 1000000}) {
  int n = 0, same = 0;
  for (final WindowResult w in windows) {
    final TruthMark? t = truthAt(marks, w.tDevUs + halfWindowUs);
    final String? c = t == null ? null : truthToCnnClass(t.label);
    if (c == null) continue;
    n++;
    if (c == w.label) same++;
  }
  return Agreement(n, same);
}
