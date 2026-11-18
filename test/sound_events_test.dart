// T43（D-065）：犬の声のイベント化（爱迪の aggregate.py の Dart 版）・フレームの切り方・WAV の読み方。
// test/fixtures/sound_golden.json は爱迪の aggregate.py（aidi_sound/）で作った答え。
// 1 つ目はテスト wav を公式 TFLite（0.48 秒ずらし）に通した点数（期待：bark 1440–4320 ms）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collar_app/sound/sound_detector.dart';
import 'package:collar_app/sound/sound_events.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _g() =>
    jsonDecode(File('test/fixtures/sound_golden.json').readAsStringSync()) as Map<String, dynamic>;

/// golden の点数（使う列だけ）→ [フレーム][521]。
List<List<double>> _scores(Map<String, dynamic> sc) {
  final int n = (sc.values.first as List<dynamic>).length;
  return <List<double>>[
    for (int f = 0; f < n; f++)
      () {
        final List<double> row = List<double>.filled(521, 0);
        for (final MapEntry<String, dynamic> e in sc.entries) {
          row[int.parse(e.key)] = ((e.value as List<dynamic>)[f] as num).toDouble();
        }
        return row;
      }(),
  ];
}

class _FakeScorer implements SoundScorer {
  _FakeScorer(this.scores);
  final List<List<double>> scores;
  int frames = 0;

  @override
  Future<List<List<double>>> score(List<Float32List> f) async {
    frames = f.length;
    return scores;
  }

  @override
  void close() {}
}

void main() {
  final Map<String, dynamic> g = _g();

  test('イベント化：爱迪の aggregate.py と同じ区間・種類・確信度（7 例）', () {
    for (final dynamic c in g['cases'] as List<dynamic>) {
      final Map<String, dynamic> cs = c as Map<String, dynamic>;
      final List<SoundEvent> got = framesToEvents(_scores(cs['scores'] as Map<String, dynamic>));
      final List<dynamic> exp = cs['events'] as List<dynamic>;
      expect(got.length, exp.length, reason: cs['name'] as String);
      for (int i = 0; i < exp.length; i++) {
        final Map<String, dynamic> e = exp[i] as Map<String, dynamic>;
        expect(got[i].startMs, e['start_ms'], reason: cs['name'] as String);
        expect(got[i].endMs, e['end_ms']);
        expect(got[i].cls, e['class']);
        expect(got[i].prob, closeTo((e['prob'] as num).toDouble(), 6e-4)); // Python は 3 桁に丸めている
      }
    }
  });

  test('設定の値が aidi_sound/config.yaml と同じ', () {
    final String y = File('aidi_sound/config.yaml').readAsStringSync();
    double num1(String key) => double.parse(RegExp('$key:\\s*([0-9.]+)').firstMatch(y)!.group(1)!);
    expect(num1('hop_s'), soundHopS);
    expect(num1('dog_score_threshold'), dogScoreThreshold);
    expect(num1('smoothing_window_frames').toInt(), smoothingWindowFrames);
    expect(num1('min_event_duration_s'), minEventDurationS);
    expect(num1('merge_gap_s'), mergeGapS);
    expect(num1('    dog').toInt(), dogIndex);
    expect(y, contains('gate_combine: "dog_only"'));
    expect(y, contains('smoothing_method: "median"'));
    expect(y, contains('type_vote: "mean_score"'));
    expect(y, contains('bark:     [70, 73]'));
    expect(y, contains('growling: [74]'));
    expect(y, contains('whimper:  [75]'));
  });

  test('テスト wav：16 kHz・モノラル・5 秒 → TFLite のフレーム 10 個（TF Hub 版と同じ数）', () {
    final ({Int16List pcm, int sampleRate}) w = readWavInt16(File('aidi_sound/test/test_input.wav').readAsBytesSync());
    expect(w.sampleRate, 16000);
    expect(w.pcm.length, 80000);
    final List<Float32List> f = yamnetFrames(pcmToFloat(w.pcm));
    expect(f.length, 10);
    expect(f.every((Float32List x) => x.length == yamnetWindow), isTrue);
    expect(f[1][0], closeTo(w.pcm[7680] / 32768, 1e-7)); // 0.48 秒ずつ
    expect(f.last[15599], 0); // 最後は 0 で埋める
    expect(yamnetFrames(Float32List(1000)).length, 1); // 短くても 1 個
  });

  test('detectEventsInt16：wav → フレーム → 点数（偽物）→ bark 1440–4320 ms（爱迪の期待と同じ）', () async {
    final ({Int16List pcm, int sampleRate}) w = readWavInt16(File('aidi_sound/test/test_input.wav').readAsBytesSync());
    final Map<String, dynamic> first = (g['cases'] as List<dynamic>).first as Map<String, dynamic>;
    final _FakeScorer s = _FakeScorer(_scores(first['scores'] as Map<String, dynamic>));
    final List<SoundEvent> ev = await detectEventsInt16(w.pcm, s, sampleRate: w.sampleRate);
    expect(s.frames, 10);
    expect(ev.single.toString(), startsWith('1440\t4320\tbark\t0.47'));
    final List<dynamic> expected =
        jsonDecode(File('aidi_sound/test/expected_output.json').readAsStringSync()) as List<dynamic>;
    final Map<String, dynamic> e = expected.single as Map<String, dynamic>;
    expect(<Object>[ev.single.startMs, ev.single.endMs, ev.single.cls], <Object>[e['start_ms'], e['end_ms'], e['class']]);
    expect(ev.single.prob, closeTo((e['prob'] as num).toDouble(), 0.05)); // TFLite は量子化（0.472 と 0.502）
    expect(() => detectEventsInt16(w.pcm, s, sampleRate: 44100), throwsArgumentError);
  });

  test('中央値（端は窓を縮める）・WAV でないもの', () {
    expect(smoothMedian(<double>[0, 1, 0, 1, 1], 3), <double>[0.5, 0, 1, 1, 1]);
    expect(() => readWavInt16(Uint8List.fromList(List<int>.filled(20, 0))), throwsFormatException);
  });
}
