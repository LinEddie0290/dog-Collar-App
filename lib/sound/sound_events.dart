/// T43（D-065）：犬の声のイベント化。爱迪の `aidi_sound/aggregate.py` を Dart に移したもの（TF なし、画面なし）。
///
/// YAMNet の 521 クラスの点数（0.48 秒ごとのフレーム）→「犬か」（Dog の点数）を中央値でならす →
/// しきい値より上の続き → 0.48 秒以内のすき間はつなぐ → 0.96 秒より短いのは捨てる →
/// 種類はフレームの平均点がいちばん高いもの（bark・yip・howl・growling・whimper）。
/// 数字は `aidi_sound/config.yaml` と同じ（test/sound_events_test.dart で突き合わせる）。
/// 答えが同じことは、爱迪の aggregate.py で作った test/fixtures/sound_golden.json で確かめる。
library;

import 'dart:typed_data';

const int soundSampleRate = 16000;

/// 公式 TFLite（yamnet.tflite）の 1 回の入力（0.975 秒）。
const int yamnetWindow = 15600;

/// TF Hub 版と同じ刻み（0.48 秒）。TFLite でもこの刻みでずらす（爱迪の README 6 章）。
const int yamnetHop = 7680;
const double soundHopS = 0.48;

// ---- aidi_sound/config.yaml（classes・detection）と同じ値
const int dogIndex = 69; // Dog（gate_combine: dog_only）
const Map<String, List<int>> soundTypeIndex = <String, List<int>>{
  'bark': <int>[70, 73], // Bark・Bow-wow
  'yip': <int>[71],
  'howl': <int>[72],
  'growling': <int>[74],
  'whimper': <int>[75],
};
const double dogScoreThreshold = 0.50;
const int smoothingWindowFrames = 3; // 中央値
const double minEventDurationS = 0.96;
const double mergeGapS = 0.48;

/// 爱迪の内部の名前 → アプリの名前（infer.py の _CLASS_RENAME と同じ）。
const Map<String, String> soundClassName = <String, String>{
  'bark': 'bark',
  'growling': 'growl',
  'howl': 'howl',
  'whimper': 'whine',
  'yip': 'yip',
};

/// 1 回の声。時刻は音の始まりからのミリ秒。
class SoundEvent {
  const SoundEvent({required this.startMs, required this.endMs, required this.cls, required this.prob, this.typeScores = const <String, double>{}});

  final int startMs;
  final int endMs;

  /// bark・growl・howl・whine・yip。
  final String cls;

  /// その種類のフレームの平均点（0〜1）。
  final double prob;
  final Map<String, double> typeScores;

  @override
  String toString() => '$startMs\t$endMs\t$cls\t${prob.toStringAsFixed(3)}';
}

/// int16 → float（−1〜1）。
Float32List pcmToFloat(Int16List pcm) {
  final Float32List out = Float32List(pcm.length);
  for (int i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] / 32768.0;
  }
  return out;
}

/// TFLite に入れるフレーム（15600 点を 7680 点ずつ。最後は 0 で埋める＝TF Hub 版と同じ数）。
List<Float32List> yamnetFrames(Float32List wav) {
  final int extra = wav.length > yamnetWindow ? wav.length - yamnetWindow : 0;
  final int k = (extra + yamnetHop - 1) ~/ yamnetHop;
  final List<Float32List> out = <Float32List>[];
  for (int i = 0; i <= k; i++) {
    final Float32List f = Float32List(yamnetWindow);
    final int s = i * yamnetHop;
    for (int j = 0; j < yamnetWindow && s + j < wav.length; j++) {
      f[j] = wav[s + j];
    }
    out.add(f);
  }
  return out;
}

double _median(List<double> v) {
  final List<double> s = List<double>.of(v)..sort();
  final int n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// 端では窓を縮める中央値（aggregate.smooth と同じ）。
List<double> smoothMedian(List<double> x, int window) {
  if (window <= 1) return List<double>.of(x);
  final int half = window ~/ 2;
  return <double>[
    for (int i = 0; i < x.length; i++)
      _median(x.sublist(i - half < 0 ? 0 : i - half, i + half + 1 > x.length ? x.length : i + half + 1)),
  ];
}

/// フレームの点数（[フレーム][521]）→ 声のイベント。
List<SoundEvent> framesToEvents(List<List<double>> scores) {
  final int n = scores.length;
  final List<double> gate = <double>[for (final List<double> f in scores) f[dogIndex]];
  final Map<String, List<double>> types = <String, List<double>>{
    for (final MapEntry<String, List<int>> e in soundTypeIndex.entries)
      e.key: <double>[
        for (final List<double> f in scores) e.value.map((int i) => f[i]).reduce((double a, double b) => a > b ? a : b),
      ],
  };
  final List<double> sm = smoothMedian(gate, smoothingWindowFrames);
  // 続いている区間 [s, e)
  final List<List<int>> runs = <List<int>>[];
  int? start;
  for (int i = 0; i < n; i++) {
    final bool on = sm[i] > dogScoreThreshold;
    if (on && start == null) start = i;
    if (!on && start != null) {
      runs.add(<int>[start, i]);
      start = null;
    }
  }
  if (start != null) runs.add(<int>[start, n]);
  // すき間をつなぐ
  final int mergeGap = (mergeGapS / soundHopS).round();
  final List<List<int>> merged = <List<int>>[];
  for (final List<int> r in runs) {
    if (merged.isNotEmpty && r[0] - merged.last[1] <= mergeGap) {
      merged.last[1] = r[1];
    } else {
      merged.add(<int>[r[0], r[1]]);
    }
  }
  final double minFrames = minEventDurationS / soundHopS;
  final List<SoundEvent> out = <SoundEvent>[];
  for (final List<int> r in merged) {
    final int s = r[0], e = r[1];
    if (e - s < minFrames - 1e-9) continue;
    final Map<String, double> means = <String, double>{
      for (final MapEntry<String, List<double>> t in types.entries)
        t.key: t.value.sublist(s, e).reduce((double a, double b) => a + b) / (e - s),
    };
    String winner = means.keys.first;
    for (final MapEntry<String, double> m in means.entries) {
      if (m.value > means[winner]!) winner = m.key; // 同点は前のもの（Python の max と同じ）
    }
    out.add(SoundEvent(
      startMs: (s * soundHopS * 1000).round(),
      endMs: (e * soundHopS * 1000).round(),
      cls: soundClassName[winner] ?? winner,
      prob: means[winner]!,
      typeScores: <String, double>{for (final MapEntry<String, double> m in means.entries) soundClassName[m.key] ?? m.key: m.value},
    ));
  }
  return out;
}

/// 16 kHz・モノラル・16 bit の WAV を読む（テスト wav 用。それ以外の形は例外）。
({Int16List pcm, int sampleRate}) readWavInt16(Uint8List bytes) {
  final ByteData b = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') throw const FormatException('不是 WAV');
  int o = 12, rate = 0, ch = 0, bits = 0;
  while (o + 8 <= bytes.length) {
    final String id = tag(o);
    final int size = b.getUint32(o + 4, Endian.little);
    if (id == 'fmt ') {
      ch = b.getUint16(o + 10, Endian.little);
      rate = b.getUint32(o + 12, Endian.little);
      bits = b.getUint16(o + 22, Endian.little);
    } else if (id == 'data') {
      if (ch != 1 || bits != 16) throw FormatException('只读单声道 16 bit（这个是 $ch 声道 $bits bit）');
      final int n = size ~/ 2;
      final Int16List pcm = Int16List(n);
      for (int i = 0; i < n; i++) {
        pcm[i] = b.getInt16(o + 8 + i * 2, Endian.little);
      }
      return (pcm: pcm, sampleRate: rate);
    }
    o += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('WAV 里没有 data');
}
