/// T34-A：スマホの中の処理の結果（窓・心拍）を残す。
///
/// 1 回の接続＝1 ファイル（JSON Lines、足していくだけ）：
///   `<Documents>/pipeline_sessions/<session_id>.jsonl`
///   1 行目  {"rec":"header","schema":"collar.app_session/0.1","session_id":...,"started_ms":...}
///   そのあと {"rec":"windows","t_us":[...],"t_ms":[...],"activity":[...],"label":[...],"prob":[...]}
///          {"rec":"truth","t_ms":...,"t_us":...,"label":"walk","source":"button"}（その時刻からこの動き）
///          {"rec":"truth_undo","t_us":...,"label":"walk"}（D のボタンの取り消し）
///          {"rec":"vital","t_ms":...,"t_us":...,"kind":"hr","value":72.0,"valid":true}
/// 出来事は保存しない（読むときに窓から作り直す。しきい値を変えても前の日に効く）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:path_provider/path_provider.dart';

import 'imu_input.dart';
import 'pipeline_runner.dart';

const String appSessionSchema = 'collar.app_session/0.1';

class StoredSession {
  StoredSession(this.id, this.header);
  final String id;
  final Map<String, dynamic> header;
  final List<WindowResult> windows = <WindowResult>[];
  final List<VitalReading> vitals = <VitalReading>[];
  final List<TruthMark> truth = <TruthMark>[];
}

class PipelineStore {
  PipelineStore({this.baseDir});

  /// 保存先の親フォルダ（テスト用）。null ならアプリの Documents。
  final Future<String> Function()? baseDir;
  Future<void> _chain = Future<void>.value();

  Future<Directory> dir() async {
    final Future<String> Function()? b = baseDir;
    final String base = b != null ? await b() : (await getApplicationDocumentsDirectory()).path;
    final Directory d = Directory('$base/pipeline_sessions');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> _append(String id, Map<String, Object?> row) {
    final Future<void> job = _chain.then((_) async {
      final Directory d = await dir();
      await File('${d.path}/$id.jsonl').writeAsString('${jsonEncode(row)}\n', mode: FileMode.append);
    });
    // 書けなくても処理は止めない（保存は付加機能）
    _chain = job.catchError((Object _) {});
    return _chain;
  }

  /// E：生の IMU（CSV）。最初に書くときに列の名前の行をつける。
  Future<void> appendRaw(String id, String csvRows) {
    final Future<void> job = _chain.then((_) async {
      final Directory d = await dir();
      final File f = File('${d.path}/$id.imu.csv');
      final String head = f.existsSync() ? '' : 't_dev_us,t_ms,sensor,ax,ay,az,gx,gy,gz\n';
      await f.writeAsString('$head$csvRows', mode: FileMode.append);
    });
    _chain = job.catchError((Object _) {});
    return _chain;
  }

  /// E：犬の情報などを途中で変えた（後の行が勝つ）。
  Future<void> appendInfo(String id, Map<String, Object?> info) =>
      _append(id, <String, Object?>{'rec': 'info', ...info});

  Future<void> startSession(String id, Map<String, Object?> header) =>
      _append(id, <String, Object?>{'rec': 'header', 'schema': appSessionSchema, 'session_id': id, ...header});

  Future<void> appendWindows(String id, List<WindowResult> w) => _append(id, <String, Object?>{
        'rec': 'windows',
        't_us': <int>[for (final WindowResult x in w) x.tDevUs],
        't_ms': <int>[for (final WindowResult x in w) x.tMs],
        'activity': <double>[for (final WindowResult x in w) x.activity],
        'label': <String>[for (final WindowResult x in w) x.label],
        'prob': <double>[for (final WindowResult x in w) _r(x.prob, 1e4)],
      });

  Future<void> appendVital(String id, VitalReading v) => _append(id, <String, Object?>{
        'rec': 'vital',
        't_ms': v.tMs,
        't_us': v.tDevUs,
        'kind': v.kind,
        'value': v.value,
        'valid': v.valid,
      });

  Future<void> appendTruth(String id, TruthMark m) => _append(id, <String, Object?>{
        'rec': 'truth',
        't_ms': m.tMs,
        't_us': m.tDevUs,
        'label': m.label,
        if (m.source.isNotEmpty) 'source': m.source,
      });

  /// D の取り消し。読むときに同じ時刻・ラベルのボタンの印を消す。
  Future<void> appendTruthUndo(String id, TruthMark m) => _append(id, <String, Object?>{
        'rec': 'truth_undo',
        't_us': m.tDevUs,
        'label': m.label,
      });

  /// 書きかけのものも含めて全部待つ。
  Future<void> idle() => _chain;

  Future<List<StoredSession>> loadAll() async {
    await _chain;
    final Directory d = await dir();
    return loadSessionsFrom(d.path);
  }
}

double _r(double v, double scale) => (v * scale).roundToDouble() / scale;

/// フォルダの中の全部のセッションを読む（isolate の中でも使える）。壊れた行は飛ばす。
List<StoredSession> loadSessionsFrom(String dirPath) {
  final Directory d = Directory(dirPath);
  if (!d.existsSync()) return <StoredSession>[];
  final List<File> files = d.listSync().whereType<File>().where((File f) => f.path.endsWith('.jsonl')).toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  final List<StoredSession> out = <StoredSession>[];
  for (final File f in files) {
    final String name = f.uri.pathSegments.last;
    StoredSession? s;
    for (final String line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> m;
      try {
        m = jsonDecode(line) as Map<String, dynamic>;
      } on FormatException {
        continue; // 書きかけで切れた行
      }
      s ??= StoredSession(name.substring(0, name.length - 6), m['rec'] == 'header' ? m : <String, dynamic>{});
      switch (m['rec']) {
        case 'windows':
          final List<dynamic> tUs = m['t_us'] as List<dynamic>, tMs = m['t_ms'] as List<dynamic>;
          final List<dynamic> act = m['activity'] as List<dynamic>, lab = m['label'] as List<dynamic>;
          final List<dynamic> prob = m['prob'] as List<dynamic>;
          for (int i = 0; i < tUs.length; i++) {
            s.windows.add(WindowResult(
              tDevUs: (tUs[i] as num).toInt(),
              tMs: (tMs[i] as num).toInt(),
              activity: (act[i] as num).toDouble(),
              label: lab[i] as String,
              prob: (prob[i] as num).toDouble(),
            ));
          }
        case 'truth':
          s.truth.add(TruthMark(
            tDevUs: (m['t_us'] as num).toInt(),
            tMs: (m['t_ms'] as num).toInt(),
            label: m['label'] as String,
            source: m['source'] as String? ?? '',
          ));
        case 'truth_undo':
          final int i = s.truth.lastIndexWhere(
              (TruthMark x) => x.tDevUs == (m['t_us'] as num).toInt() && x.label == m['label'] && x.source == 'button');
          if (i >= 0) s.truth.removeAt(i);
        case 'vital':
          s.vitals.add(VitalReading(
            tMs: (m['t_ms'] as num).toInt(),
            tDevUs: (m['t_us'] as num).toInt(),
            kind: m['kind'] as String,
            value: (m['value'] as num?)?.toDouble(),
            valid: m['valid'] as bool? ?? false,
          ));
      }
    }
    if (s != null) out.add(s);
  }
  return out;
}
