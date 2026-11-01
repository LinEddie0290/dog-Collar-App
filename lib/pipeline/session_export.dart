/// T34-E：1 回の試験（セッション）を 1 つのファイルにまとめて Mac へ渡す。
///
/// ファイル：`<session_id>.collar-session.jsonl.gz`（gzip した JSON Lines）
///   1 行目 {"rec":"export","schema":"collar.app_export/0.1","session_id":...,"exported_ms":...,"app":{...}}
///   そのあと保存の JSONL の行をそのまま（header・info・windows・truth・truth_undo・vital）
///   最後に生の IMU {"rec":"imu","columns":["t_dev_us","t_ms","sensor","ax",...],"csv":"…\n…"}（2000 行ずつ）
/// collar-pipeline の collar/io/app_export.py で読む（scripts/import_app_session.py）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String appExportSchema = 'collar.app_export/0.1';
const List<String> rawImuColumns = <String>['t_dev_us', 't_ms', 'sensor', 'ax', 'ay', 'az', 'gx', 'gy', 'gz'];

/// 記録の一覧の 1 行（1 行目の header だけ読む）。
class SessionListing {
  const SessionListing({
    required this.id,
    required this.startedMs,
    required this.header,
    required this.bytes,
    required this.rawBytes,
  });

  final String id;
  final int startedMs;
  final Map<String, dynamic> header;
  final int bytes; // 結果の JSONL
  final int rawBytes; // 生の IMU（.imu.csv）

  String get subjectName => ((header['subject'] as Map<String, dynamic>?)?['name'] as String?) ?? '';
  String get input => header['input'] as String? ?? '';
}

/// 新しい順。
List<SessionListing> listSessions(String dirPath) {
  final Directory d = Directory(dirPath);
  if (!d.existsSync()) return <SessionListing>[];
  final List<SessionListing> out = <SessionListing>[];
  for (final File f in d.listSync().whereType<File>()) {
    final String name = f.uri.pathSegments.last;
    if (!name.endsWith('.jsonl')) continue;
    final String id = name.substring(0, name.length - 6);
    Map<String, dynamic> h = <String, dynamic>{};
    try {
      final String first = f.readAsLinesSync().firstWhere((String l) => l.trim().isNotEmpty, orElse: () => '{}');
      final Object? j = jsonDecode(first);
      if (j is Map<String, dynamic> && j['rec'] == 'header') h = j;
    } on Object {
      // 読めない行は空の header
    }
    final File raw = File('$dirPath/$id.imu.csv');
    out.add(SessionListing(
      id: id,
      startedMs: (h['started_ms'] as num?)?.toInt() ?? f.lastModifiedSync().millisecondsSinceEpoch,
      header: h,
      bytes: f.lengthSync(),
      rawBytes: raw.existsSync() ? raw.lengthSync() : 0,
    ));
  }
  out.sort((SessionListing a, SessionListing b) => b.startedMs.compareTo(a.startedMs));
  return out;
}

/// 書き出す。できたファイルを返す。
Future<File> exportSession(String dirPath, String id, String outDirPath,
    {Map<String, Object?> app = const <String, Object?>{}, int? nowMs, int rowsPerLine = 2000}) async {
  final File src = File('$dirPath/$id.jsonl');
  if (!src.existsSync()) throw FileSystemException('没有这个记录', src.path);
  Directory(outDirPath).createSync(recursive: true);
  final File out = File('$outDirPath/$id.collar-session.jsonl.gz');
  final IOSink sink = out.openWrite();
  final ByteConversionSink gz = gzip.encoder.startChunkedConversion(sink);
  void line(String s) => gz.add(utf8.encode('$s\n'));
  try {
    line(jsonEncode(<String, Object?>{
      'rec': 'export',
      'schema': appExportSchema,
      'session_id': id,
      'exported_ms': nowMs ?? DateTime.now().millisecondsSinceEpoch,
      'app': app,
    }));
    await for (final String l in src.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      if (l.trim().isNotEmpty) line(l);
    }
    final File raw = File('$dirPath/$id.imu.csv');
    if (raw.existsSync()) {
      final StringBuffer buf = StringBuffer();
      int n = 0;
      void put() {
        if (n == 0) return;
        line(jsonEncode(<String, Object?>{'rec': 'imu', 'columns': rawImuColumns, 'csv': buf.toString()}));
        buf.clear();
        n = 0;
      }

      await for (final String l in raw.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        if (l.isEmpty || l.startsWith('t_dev_us')) continue;
        buf
          ..write(l)
          ..write('\n');
        n++;
        if (n >= rowsPerLine) put();
      }
      put();
    }
  } finally {
    // gz.close() は下の IOSink も close する。そのあとに flush を呼ぶと IOSink がファイルを
    // 閉じられなくなり done が終わらない（11-02 のテストで止まった）ので、done だけ待つ。
    gz.close();
    await sink.done;
  }
  return out;
}
