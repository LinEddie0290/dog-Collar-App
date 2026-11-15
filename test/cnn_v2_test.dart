// T35：CNN v2 をアプリへ。Dart と PyTorch の答えが同じ・下限 0.9・版の切り替え。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collar_app/pipeline/cnn_models.dart';
import 'package:collar_app/pipeline/pipeline_runner.dart';
import 'package:collar_imu_cnn/collar_imu_cnn.dart';
import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // test/fixtures/cnn_v2_check.json：collar-pipeline の export_cnn.py（評価用の犬 d46_t1 の窓 200）の
  // PyTorch の確率と、cnn.synth_floor(prob, classes, 0.9) のクラス（label_floor09）。
  final Map<String, dynamic> check = _json('test/fixtures/cnn_v2_check.json');
  final Map<String, dynamic> v2 = _json('assets/models/cnn_imu_v2.json');

  test('v2：200 窓すべてで Dart と PyTorch の答えが同じ（確率の差 1e-4 未満）', () {
    final CnnImuModel m = CnnImuModel.fromJson(v2);
    expect(m.classes, <String>['still', 'walk', 'run', 'other', 'lick', 'scratch', 'shake']);
    final CnnCheckResult r = runCnnCheck(m, check, reps: 1);
    expect(r.windows, 200);
    expect(r.sameLabel, 200);
    expect(r.maxProbDiff, lessThan(1e-4));
  });

  test('下限 0.9：Python の synth_floor と同じクラスになる（本物の犬の窓で、模擬のクラスが 42 → 2 に減る）', () {
    final WindowClassifier c = WindowClassifier.fromJson(v2, minProb: cnnSynthMinProb);
    final List<dynamic> xs = check['X'] as List<dynamic>;
    final List<dynamic> gs = check['gravity'] as List<dynamic>;
    final List<dynamic> want = check['label_floor09'] as List<dynamic>;
    final List<String> classes = c.model.classes;
    int synthRaw = 0, synthFloor = 0;
    for (int i = 0; i < xs.length; i++) {
      final Float32List x = Float32List.fromList(<double>[for (final dynamic e in xs[i] as List<dynamic>) (e as num).toDouble()]);
      final List<double> g = <double>[for (final dynamic e in gs[i] as List<dynamic>) (e as num).toDouble()];
      final CnnWindow w = c.classifyOne(x, 200, g, 0, 0);
      expect(w.label, classes[(want[i] as num).toInt()], reason: 'window $i');
      if (<String>['lick', 'scratch', 'shake'].contains(w.label)) synthFloor++;
      final CnnPrediction raw = c.model.predict(x, gravity: g);
      if (<String>['lick', 'scratch', 'shake'].contains(classes[raw.label])) synthRaw++;
    }
    expect(synthRaw, 42);
    expect(synthFloor, 2);
  });

  test('アプリの設定：下限 0.9・休息中でも 0.9 以上なら lick・scratch・shake', () {
    expect(cnnSynthMinProb, 0.9);
    expect(appEventConfig.overrideRest, <String, double>{'lick': 0.9, 'scratch': 0.9, 'shake': 0.9});
    expect(defaultCnnVersion, CnnVersion.v2);
    expect(cnnVersionFromName('v1'), CnnVersion.v1);
    expect(cnnVersionFromName(null), CnnVersion.v2);
    expect(cnnVersionFromName('xx'), CnnVersion.v2);
  });

  test('アプリに入っている CNN を読む（v1・v2、下限つき）', () async {
    final WindowClassifier a = await loadClassifierAsset(CnnVersion.v2);
    expect(a.model.classes.length, 7);
    expect(a.minProb, 0.9);
    final WindowClassifier b = await loadClassifierAsset(CnnVersion.v1);
    expect(b.model.classes, <String>['still', 'walk', 'run', 'other']);
  });

  test('記録：標準は v2、記録中は版を変えない', () {
    final PipelineRunner r = PipelineRunner(loadClassifier: () async => throw StateError('使わない'));
    expect(r.cnnVersion, CnnVersion.v2);
    expect(r.ecfg.overrideRest['lick'], 0.9);
    expect(r.setCnnVersion(CnnVersion.v1), isTrue);
    expect(r.cnnVersion, CnnVersion.v1);
    r.add(const ImuSample(sensor: 'front', tDevUs: 1000000, tMs: 5, ax: 0, ay: 0, az: 9.8, gx: 0, gy: 0, gz: 0));
    expect(r.isRunning, isTrue);
    expect(r.setCnnVersion(CnnVersion.v2), isFalse);
    expect(r.cnnVersion, CnnVersion.v1);
  });
}
