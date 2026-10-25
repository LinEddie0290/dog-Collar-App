// PyTorch の答えと比べ、速さを測る(T24)。
//   dart run bin/check.dart <cnn_imu_v1.json> <check_windows.json>
import 'dart:convert';
import 'dart:io';

import 'package:collar_imu_cnn/collar_imu_cnn.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run bin/check.dart model.json check_windows.json');
    exit(2);
  }
  final CnnImuModel model =
      CnnImuModel.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  final Map<String, dynamic> check = jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  // 最初の数回は JIT が温まっていないので、1 回まわしてから測る。
  runCnnCheck(model, check, reps: 1);
  final CnnCheckResult r = runCnnCheck(model, check);
  stdout.writeln('${model.name}: params ${model.params}');
  stdout.writeln(r);
  exit(r.ok ? 0 : 1);
}
