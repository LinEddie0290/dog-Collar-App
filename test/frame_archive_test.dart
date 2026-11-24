// T21：BLE の全フレームを残す FrameArchive のテスト（設計メモ T21 8章）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collar_data/collar_data.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _lines(Directory dir) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final FileSystemEntity f in dir.listSync()) {
    if (f is File && f.path.endsWith('.jsonl')) {
      for (final String l in f.readAsLinesSync()) {
        if (l.trim().isNotEmpty) out.add(jsonDecode(l) as Map<String, dynamic>);
      }
    }
  }
  return out;
}

CapturedFrame _frame(int i) =>
    CapturedFrame(1761200000000 + i, 'data', Uint8List.fromList(<int>[0x50, 0x54, i & 0xff, (i >> 8) & 0xff]));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('t21_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('3 フレーム → 3 行、全行に pet_frame_hex、ファイル名は collar-ble-', () async {
    final FrameArchive a = FrameArchive(dir.path);
    for (int i = 0; i < 3; i++) {
      a.add(_frame(i));
    }
    await a.close();
    final List<Map<String, dynamic>> rows = _lines(dir);
    expect(rows.length, 3);
    expect(rows.every((Map<String, dynamic> r) => (r['pet_frame_hex'] as String).startsWith('5054')), isTrue);
    expect(dir.listSync().single.path, contains('collar-ble-'));
  });

  test('400 Hz 相当：待たずに 24,000 フレーム＋flush を何度も呼んでもエラーにならず、全部残る', () async {
    final FrameArchive a = FrameArchive(dir.path, flushInterval: const Duration(milliseconds: 5));
    for (int i = 0; i < 24000; i++) {
      a.add(_frame(i));
      if (i % 500 == 0) a.flush(); // 書き出し中に次が来る状況を作る
    }
    await a.close();
    expect(a.writeErrors, 0);
    final List<Map<String, dynamic>> rows = _lines(dir);
    expect(rows.length, 24000);
    // 順番も保たれる
    final List<int> ts = rows.map((Map<String, dynamic> r) => r['rx_ts'] as int).toList();
    for (int i = 1; i < ts.length; i++) {
      expect(ts[i], greaterThan(ts[i - 1]));
    }
  });

  test('切断 → 再接続（閉じて開き直す）でもファイルが壊れず、5 行そろう', () async {
    final FrameArchive a = FrameArchive(dir.path);
    for (int i = 0; i < 3; i++) {
      a.add(_frame(i));
    }
    await a.close();
    a.add(_frame(99)); // 閉じたあとは無視
    final FrameArchive b = FrameArchive(dir.path);
    for (int i = 3; i < 5; i++) {
      b.add(_frame(i));
    }
    await b.close();
    expect(_lines(dir).length, 5);
  });

  test('測定の印が入る（trigger つき）', () async {
    final FrameArchive a = FrameArchive(dir.path);
    a.event('measure_start', <String, Object?>{'started_at_ms': 1, 'trigger': 'button'}, rxTs: 1761200000000);
    a.add(_frame(1));
    a.event('measure_end', <String, Object?>{'started_at_ms': 1}, rxTs: 1761200000010);
    await a.close();
    final List<Map<String, dynamic>> rows = _lines(dir);
    expect(rows.first['ch'], 'event');
    expect(rows.first['event'], 'measure_start');
    expect(rows.first['trigger'], 'button');
    expect(rows.last['event'], 'measure_end');
  });
}
