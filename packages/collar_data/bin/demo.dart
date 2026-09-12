// ignore_for_file: avoid_print
// このファイルは `dart run bin/demo.dart` で動作確認するための CLI。
// print が出力そのものなので avoid_print はここでは適用しない。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collar_data/collar_data.dart';

/// Self-verifying demo. No hardware, no phone, no Flutter:
///
///   dart run bin/demo.dart
///
/// It runs the full pipeline against the FAKE collar for a few seconds and
/// checks that:
///   1. every raw frame was archived to disk (before filtering),
///   2. the nullable HR path is actually exercised (some frames have no HR),
///   3. filtering reduces jitter (variance down),
///   4. a simulated dropout produces a `reconnecting` -> `connected` cycle,
///   5. GPS fixes show up on some (not all) frames, and lat/lng survive the
///      filter stage unchanged (GPS is not filtered, see filters.dart).
Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('collar_demo_');
  print('archive dir: ${tmp.path}\n');

  final source = FakeCollarDataSource(
    framePeriod: const Duration(milliseconds: 100),
    outageEvery: const Duration(seconds: 3),
    outageDuration: const Duration(seconds: 1),
    seed: 42,
  );
  final archive = RawArchive(tmp.path);
  final repo = CollarRepository(source: source, archive: archive);

  // Ordered sequences (nulls kept) so we can measure jitter as the stddev of
  // successive differences — the deterministic HR swing cancels out, leaving
  // only the high-frequency noise the filter is meant to remove.
  final rawHrSeq = <double?>[];
  final filtHrSeq = <double?>[];
  var hrNulls = 0;
  var samples = 0;
  var gpsFixes = 0;

  final statuses = <ConnStatus>[];
  final statusSub = repo.status.listen((s) {
    statuses.add(s);
    print('[status] $s');
  });

  final cleanSub = repo.cleanStream.listen((s) {
    samples++;
    if (s.hr == null) hrNulls++;
    if (s.hasLocation) gpsFixes++;
    filtHrSeq.add(s.hr);
  });

  await repo.start();
  await Future<void>.delayed(const Duration(seconds: 6));
  await repo.stop();
  await statusSub.cancel();
  await cleanSub.cancel();

  // ---- read the archive back and pull raw HR for a jitter comparison ----
  var archivedLines = 0;
  for (final file in tmp.listSync().whereType<File>()) {
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      archivedLines++;
      final obj = jsonDecode(line) as Map<String, dynamic>;
      final raw = obj['raw'] as Map<String, dynamic>;
      rawHrSeq.add(raw['hr'] is num ? (raw['hr'] as num).toDouble() : null);
    }
  }

  final rawJitter = _jitter(rawHrSeq);
  final filtJitter = _jitter(filtHrSeq);

  print('\n--- results ---');
  print('samples emitted      : $samples');
  print('archived raw lines   : $archivedLines');
  print('frames with null hr  : $hrNulls');
  print('frames with gps fix  : $gpsFixes');
  print('status transitions   : $statuses');
  print('raw hr jitter        : ${rawJitter.toStringAsFixed(3)}');
  print('filtered hr jitter   : ${filtJitter.toStringAsFixed(3)}');

  // ---- assertions ----
  _check(archivedLines == samples,
      'every sample must be archived (raw persisted before filtering)');
  _check(hrNulls > 0, 'nullable HR path must be exercised');
  _check(filtJitter < rawJitter, 'filter must reduce HR jitter');
  _check(statuses.contains(ConnStatus.reconnecting),
      'a simulated dropout must surface as reconnecting');
  _check(statuses.contains(ConnStatus.connected), 'must reach connected');
  _check(gpsFixes > 0, 'GPS fixes must show up on at least some frames');
  _check(gpsFixes < samples,
      'GPS fixes must NOT show up on every frame (lower rate than IMU/HR)');

  await tmp.delete(recursive: true);
  print('\nALL CHECKS PASSED ✅');
}

/// Jitter = stddev of successive differences over consecutive non-null pairs.
/// A slow trend (like the sine HR swing) contributes ~0 here, so this isolates
/// the high-frequency noise a low-pass filter should shrink.
double _jitter(List<double?> xs) {
  final diffs = <double>[];
  for (var i = 1; i < xs.length; i++) {
    final a = xs[i - 1];
    final b = xs[i];
    if (a != null && b != null) diffs.add(b - a);
  }
  return _stddev(diffs);
}

double _stddev(List<double> xs) {
  if (xs.length < 2) return 0;
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  final v = xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
      xs.length;
  return v <= 0 ? 0 : _sqrt(v);
}

double _sqrt(double x) {
  // avoid importing dart:math just for this
  var g = x;
  for (var i = 0; i < 40; i++) {
    g = (g + x / g) / 2;
  }
  return g;
}

void _check(bool ok, String what) {
  if (!ok) {
    stderr.writeln('CHECK FAILED: $what');
    exit(1);
  }
  print('ok: $what');
}
