import 'dart:async';
import 'dart:io';

import 'package:collar_data/collar_data.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// アプリ全体で1つだけ持つ、首輪との接続状態。
///
/// Home / History / Settings の3画面がこれを共有して見る(状態はここに集約し、
/// 各画面は表示に徹する)。中身は package:collar_data の CollarRepository を
/// 包んでいるだけで、ソケットやJSON、フィルタの詳細はここでも一切扱わない。
class CollarController extends ChangeNotifier {
  CollarRepository? _repo;
  StreamSubscription<SensorSample>? _sampleSub;
  StreamSubscription<ConnStatus>? _statusSub;

  bool useMock = true;
  String url = 'ws://localhost:8080/ws';

  ConnStatus status = ConnStatus.disconnected;
  SensorSample? latest;
  List<SensorSample> recent = const <SensorSample>[];
  int missedCount = 0;
  int? _lastSeq;

  bool get isConnected => _repo != null;

  Future<void> connect() async {
    await _teardown();

    final CollarDataSource source =
        useMock ? FakeCollarDataSource() : WebSocketCollarDataSource(url);

    final Directory dir = await getApplicationDocumentsDirectory();
    final CollarRepository repo = CollarRepository(
      source: source,
      archive: RawArchive(dir.path),
    );

    _lastSeq = null;
    missedCount = 0;

    _statusSub = repo.status.listen((ConnStatus st) {
      status = st;
      notifyListeners();
    });

    _sampleSub = repo.cleanStream.listen((SensorSample sample) {
      latest = sample;
      recent = repo.recent;
      final int? seq = sample.seq;
      if (seq != null && _lastSeq != null && seq > _lastSeq! + 1) {
        missedCount += seq - _lastSeq! - 1;
      }
      if (seq != null) _lastSeq = seq;
      notifyListeners();
    });

    _repo = repo;
    notifyListeners();
    await repo.start();
  }

  Future<void> disconnect() async {
    await _teardown();
    status = ConnStatus.disconnected;
    notifyListeners();
  }

  Future<void> _teardown() async {
    await _sampleSub?.cancel();
    await _statusSub?.cancel();
    await _repo?.stop();
    _sampleSub = null;
    _statusSub = null;
    _repo = null;
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }
}
