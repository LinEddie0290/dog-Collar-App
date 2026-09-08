import 'dart:convert';
import 'dart:io';

import 'raw_frame.dart';

/// Appends every raw frame to disk as JSONL, **before** any filtering, so the
/// untouched signal is always recoverable even if the filter logic changes or
/// is wrong. Same principle as the server: never drop, never rewrite, faithful.
///
/// One line per frame:
///   {"rx_ts":1757308800456,"raw":{ ...frame exactly as received... }}
///
/// Files rotate by local date: `collar-YYYY-MM-DD.jsonl` under [dirPath].
///
/// Pure Dart on purpose: it takes a plain directory path, so it has NO Flutter
/// import. In the app you pass `getApplicationDocumentsDirectory().path`
/// (path_provider); in tests / `dart run` you pass a temp dir. Same code runs
/// on the phone and on your laptop.
class RawArchive {
  final String dirPath;

  IOSink? _sink;
  String? _openDay;

  RawArchive(this.dirPath);

  Future<void> write(RawFrame f) async {
    final day = _dayOf(f.rxTs);
    if (day != _openDay) {
      await _closeSink();
      final file = File('$dirPath/collar-$day.jsonl');
      file.parent.createSync(recursive: true);
      _sink = file.openWrite(mode: FileMode.append);
      _openDay = day;
    }
    // Write the whole line then flush, so a hard crash can't leave a half line.
    _sink!.writeln(jsonEncode({'rx_ts': f.rxTs, 'raw': f.raw}));
    await _sink!.flush();
  }

  String _dayOf(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs); // local time
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Future<void> _closeSink() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  Future<void> close() => _closeSink();
}
