import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 首輪から届いた 1 フレーム（組み立て直したあと、読み解く前のバイト列）。
///
/// T21：BLE で受け取った**全フレーム**をそのまま残すための入れ物。
/// [RawFrame] は画面用のまとめ（250 ms ごと）なので、生データの保存には使えない。
class CapturedFrame {
  const CapturedFrame(this.rxTs, this.channel, this.bytes);

  /// スマホで受け取った時刻（Unix ミリ秒）。
  final int rxTs;

  /// どの特性から来たか：`data`（センサーのサンプル）／`status`（コマンドの応答）。
  final String channel;

  /// フレーム全体（ヘッダーつき）。PET-main の `pet_codec.decode_frame` でそのまま読める。
  final Uint8List bytes;
}

/// BLE の全フレームを `collar-ble-YYYY-MM-DD.jsonl` に 1 行ずつ残す（T21）。
///
/// [RawArchive] は 1 行ごとに flush を待つので、400 Hz のように速く届くと
/// 「flush 中に書き込む」形になり IOSink がエラーを出す。ここでは行をためておき、
/// [flushInterval] ごとに**1 つずつ順番に**書き出す（書き出しが重なることはない）。
///
/// 1 行の形（読み解いた値は入れない。pet_codec でいつでも作り直せる）：
/// `{"rx_ts":…,"ch":"data","pet_frame_hex":"…"}`
/// 測定の印：`{"rx_ts":…,"ch":"event","event":"measure_start",…}`
class FrameArchive {
  FrameArchive(
    this.dirPath, {
    this.prefix = 'collar-ble',
    this.flushInterval = const Duration(seconds: 1),
  }) {
    _timer = Timer.periodic(flushInterval, (_) => flush());
  }

  final String dirPath;
  final String prefix;
  final Duration flushInterval;

  final List<_Line> _pending = <_Line>[];
  Future<void> _chain = Future<void>.value();
  Timer? _timer;
  IOSink? _sink;
  String? _openDay;
  bool _closed = false;

  /// ファイルに書き終えた行の数。
  int written = 0;

  /// 書き込みに失敗した回数。測定は止めず、画面の隅に出すために数えるだけ。
  int writeErrors = 0;
  Object? lastError;

  bool get isClosed => _closed;

  /// 1 フレームをためる（すぐに返る。ファイルへは次の flush で書く）。
  void add(CapturedFrame f) {
    if (_closed) return;
    _pending.add(_Line(
      f.rxTs,
      jsonEncode(<String, Object?>{
        'rx_ts': f.rxTs,
        'ch': f.channel,
        'pet_frame_hex': _hex(f.bytes),
      }),
    ));
  }

  /// 測定の開始・終了などの印をためる。
  void event(String name, Map<String, Object?> fields, {int? rxTs}) {
    if (_closed) return;
    final int ts = rxTs ?? DateTime.now().millisecondsSinceEpoch;
    _pending.add(_Line(
      ts,
      jsonEncode(<String, Object?>{'rx_ts': ts, 'ch': 'event', 'event': name, ...fields}),
    ));
  }

  /// たまった行を書き出す。何度呼んでも、書き出しは順番に 1 つずつ行う。
  Future<void> flush() {
    _chain = _chain.then((_) => _drain()).catchError((Object e) {
      writeErrors++;
      lastError = e;
    });
    return _chain;
  }

  /// 残りを書き出して閉じる。閉じたあとの [add] は無視する。
  Future<void> close() async {
    if (_closed) return _chain;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await flush();
    _chain = _chain.then((_) async {
      await _sink?.close();
      _sink = null;
      _openDay = null;
    });
    return _chain;
  }

  Future<void> _drain() async {
    if (_pending.isEmpty) return;
    final List<_Line> lines = List<_Line>.of(_pending);
    _pending.clear();
    for (final _Line l in lines) {
      final String day = _dayOf(l.ts);
      if (day != _openDay) {
        await _sink?.flush();
        await _sink?.close();
        final File file = File('$dirPath/$prefix-$day.jsonl');
        file.parent.createSync(recursive: true);
        _sink = file.openWrite(mode: FileMode.append);
        _openDay = day;
      }
      _sink!.writeln(l.json);
    }
    await _sink?.flush();
    written += lines.length;
  }

  static String _dayOf(int epochMs) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(epochMs); // local time
    final String mm = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static String _hex(Uint8List b) {
    final StringBuffer s = StringBuffer();
    for (final int x in b) {
      s.write(x.toRadixString(16).padLeft(2, '0'));
    }
    return s.toString();
  }
}

class _Line {
  const _Line(this.ts, this.json);
  final int ts;
  final String json;
}
