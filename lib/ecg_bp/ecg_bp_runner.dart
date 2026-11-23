import 'dart:isolate';
import 'dart:typed_data';

import 'package:collar_ecg_bp/collar_ecg_bp.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// T44（D-066）：汪磊先生のグループのモデル（心電図・血圧）を TFLite で動かす。
/// モデル：assets/models/（collar-pipeline の scripts/export_tflite.py で作った。心電図 fp32、血圧 5 分割 × 2 は int8）。
/// 前処理（VMD など、数秒かかる）は別の isolate で計算し、画面を止めない。
abstract class EcgBpBackend {
  /// [W][1024] → [W][1024]
  Future<List<List<double>>> ecg(List<Float32List> windows);

  /// target：sbp/dbp、fold：1〜5。[W][3·900] → [W]（mmHg）
  Future<List<double>> bp(String target, int fold, List<Float32List> windows);

  void close() {}
}

const String ecgModelAsset = 'assets/models/ecg_bilstm.tflite';
String bpModelAsset(String target, int fold) => 'assets/models/bp_${target}_f$fold.tflite';
const int bpFolds = 5;

class TfliteEcgBp implements EcgBpBackend {
  Interpreter? _ecg;
  final Map<String, Interpreter> _bp = <String, Interpreter>{};

  @override
  Future<List<List<double>>> ecg(List<Float32List> windows) async {
    final Interpreter it = _ecg ??= await Interpreter.fromAsset(ecgModelAsset);
    final List<List<double>> out = <List<double>>[];
    for (final Float32List w in windows) {
      final List<List<List<double>>> o = <List<List<double>>>[
        <List<double>>[List<double>.filled(w.length, 0.0)],
      ];
      it.run(<List<List<double>>>[
        <List<double>>[w.toList()],
      ], o);
      out.add(o[0][0]);
      await Future<void>.delayed(Duration.zero); // 画面を止めない
    }
    return out;
  }

  @override
  Future<List<double>> bp(String target, int fold, List<Float32List> windows) async {
    final String key = '${target}_$fold';
    final Interpreter it = _bp[key] ??= await Interpreter.fromAsset(bpModelAsset(target, fold));
    final List<double> out = <double>[];
    for (final Float32List w in windows) {
      final int win = w.length ~/ 3;
      final List<List<List<double>>> x = <List<List<double>>>[
        <List<double>>[
          for (int c = 0; c < 3; c++) w.sublist(c * win, (c + 1) * win).toList(),
        ],
      ];
      final List<List<double>> o = <List<double>>[
        <double>[0.0],
      ];
      it.run(x, o);
      out.add(o[0][0]);
      await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  @override
  void close() {
    _ecg?.close();
    _ecg = null;
    for (final Interpreter it in _bp.values) {
      it.close();
    }
    _bp.clear();
  }
}

/// 1 回の測定の心電図・血圧（试用）。
class EcgBpOutcome {
  EcgBpOutcome({required this.ecg, required this.bp, required this.bpError, required this.prepMs, required this.modelMs});

  final EcgResult ecg;
  final BpResult? bp; // 45 秒の静かな所がないなどで出せないときは null
  final String? bpError;
  final int prepMs; // 前処理の時間
  final int modelMs; // モデルの時間
}

/// 3 軸（m/s²、fs Hz、60 秒くらい）→ 心電図の形・R 波・心拍数、SBP・DBP。
Future<EcgBpOutcome> runEcgBp(Float64List ax, Float64List ay, Float64List az, double fs, EcgBpBackend backend,
    {EcgSettings settings = const EcgSettings()}) async {
  final Stopwatch prep = Stopwatch(), model = Stopwatch();

  prep.start();
  final EcgInput ein = await Isolate.run(() => ecgModelInput(ax, ay, az, fs, settings));
  prep.stop();
  model.start();
  final List<List<double>> eout = ein.windows.isEmpty ? <List<double>>[] : await backend.ecg(ein.windows);
  model.stop();
  final Float64List all = stitchWindows(eout, ein.starts, ein.signal.length);
  final Float64List ecg = Float64List.fromList(<double>[for (final double v in all) if (v.isFinite) v]);
  final List<int> pk = rPeaksNeurokit(ecg, 150);
  final EcgResult er =
      EcgResult(settings: settings, input: ein, ecg: ecg, rPeaks: pk, heartRateBpm: heartRateFromPeaks(pk, 150));

  BpResult? br;
  String? bpError;
  try {
    prep.start();
    final BpInput bin = await Isolate.run(() => bpModelInput(ax, ay, az, fs));
    prep.stop();
    model.start();
    final List<List<double>> s = <List<double>>[
      for (int k = 1; k <= bpFolds; k++) await backend.bp('sbp', k, bin.windows),
    ];
    final List<List<double>> d = <List<double>>[
      for (int k = 1; k <= bpFolds; k++) await backend.bp('dbp', k, bin.windows),
    ];
    model.stop();
    double mean(List<double> v) => v.isEmpty ? double.nan : v.reduce((double a, double b) => a + b) / v.length;
    br = BpResult(
      input: bin,
      sbp: mean(<double>[for (final List<double> r in s) ...r]),
      dbp: mean(<double>[for (final List<double> r in d) ...r]),
      sbpPerModel: <double>[for (final List<double> r in s) mean(r)],
      dbpPerModel: <double>[for (final List<double> r in d) mean(r)],
    );
  } catch (e) {
    // 45 秒の静かな所がないなど（isolate から戻るとき RemoteError になることもある）
    prep.stop();
    model.stop();
    bpError = e is ArgumentError ? '${e.message}' : '$e';
  }
  return EcgBpOutcome(ecg: er, bp: br, bpError: bpError, prepMs: prep.elapsedMilliseconds, modelMs: model.elapsedMilliseconds);
}
