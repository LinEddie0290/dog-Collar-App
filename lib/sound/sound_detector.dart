/// T43（D-065）：犬の声の検出。YAMNet（公式 TFLite）を 0.48 秒ずつずらして点数 → [framesToEvents]。
///
/// 爱迪の `detect_events_int16(pcm, 16000)` と同じ入出力。TFLite の部分は [SoundScorer] に分けてあり、
/// テストでは偽物（決まった点数）を渡す（flutter test では TFLite のネイティブが動かないため）。
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'sound_events.dart';

/// フレーム（15600 点）ごとの 521 クラスの点数。
abstract class SoundScorer {
  Future<List<List<double>>> score(List<Float32List> frames);
  void close() {}
}

/// 本物：`aidi_sound/model/yamnet.tflite`（Google 公式、Apache-2.0）。
class TfliteYamnet implements SoundScorer {
  TfliteYamnet._(this._it);

  static const String asset = 'aidi_sound/model/yamnet.tflite';
  final Interpreter _it;

  static Future<TfliteYamnet> load() async => TfliteYamnet._(await Interpreter.fromAsset(asset));

  @override
  Future<List<List<double>>> score(List<Float32List> frames) async {
    final List<List<double>> out = <List<double>>[];
    for (final Float32List f in frames) {
      final List<List<double>> o = <List<double>>[List<double>.filled(521, 0)];
      _it.run(f, o);
      out.add(List<double>.of(o[0]));
    }
    return out;
  }

  @override
  void close() => _it.close();
}

/// 16 kHz・モノラル・int16 → 声のイベント（爱迪の detect_events_int16 と同じ）。
Future<List<SoundEvent>> detectEventsInt16(Int16List pcm, SoundScorer scorer, {int sampleRate = soundSampleRate}) async {
  if (sampleRate != soundSampleRate) {
    throw ArgumentError('只支持 16 kHz（这个是 $sampleRate Hz）');
  }
  final List<List<double>> scores = await scorer.score(yamnetFrames(pcmToFloat(pcm)));
  return framesToEvents(scores);
}

/// 声のテスト（記録・测试の画面）：同梱の wav（爱迪の test_input.wav、ESC-50 の犬）。
const String soundTestWavAsset = 'aidi_sound/test/test_input.wav';

Future<({Int16List pcm, int sampleRate})> loadSoundTestWav() async {
  final ByteData d = await rootBundle.load(soundTestWavAsset);
  return readWavInt16(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
}
