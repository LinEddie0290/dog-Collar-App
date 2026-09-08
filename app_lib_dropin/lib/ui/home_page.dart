import 'dart:async';
import 'dart:io';

import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'conn_status_ja.dart';

/// 受信テスト画面。
///
/// 通信・保存・フィルタは全部 package:collar_data (CollarRepository) 任せで、
/// この画面がやるのは「ボタン操作」と「表示」だけ。
/// mock/実機の切り替えは、CollarDataSource の実装を差し替えるだけで済む
/// （FakeCollarDataSource ⇔ WebSocketCollarDataSource）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CollarRepository? _repo;
  StreamSubscription<SensorSample>? _sampleSub;
  StreamSubscription<ConnStatus>? _statusSub;

  bool _useMock = true;
  final TextEditingController _urlController =
      TextEditingController(text: 'ws://localhost:8080/ws');

  ConnStatus _status = ConnStatus.disconnected;
  SensorSample? _latest;
  int? _lastSeq;
  int _missedCount = 0;
  final List<String> _log = <String>[];

  bool get _connected => _repo != null;

  @override
  void dispose() {
    unawaited(_teardown());
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await _teardown();

    final CollarDataSource source = _useMock
        ? FakeCollarDataSource()
        : WebSocketCollarDataSource(_urlController.text.trim());

    // 受信した生データは、フィルタをかける前にこの中へ jsonl で保存される。
    final Directory dir = await getApplicationDocumentsDirectory();
    final repo = CollarRepository(
      source: source,
      archive: RawArchive(dir.path),
    );

    _lastSeq = null;
    _missedCount = 0;

    _statusSub = repo.status.listen((st) {
      if (!mounted) return;
      setState(() => _status = st);
      _appendLog(st.labelJa);
    });

    _sampleSub = repo.cleanStream.listen((sample) {
      if (!mounted) return;
      setState(() {
        _latest = sample;
        final int? seq = sample.seq;
        if (seq != null && _lastSeq != null && seq > _lastSeq! + 1) {
          _missedCount += seq - _lastSeq! - 1;
        }
        if (seq != null) _lastSeq = seq;
      });
    });

    setState(() => _repo = repo);
    await repo.start();
  }

  Future<void> _disconnect() async {
    await _teardown();
    if (!mounted) return;
    setState(() => _status = ConnStatus.disconnected);
  }

  Future<void> _teardown() async {
    await _sampleSub?.cancel();
    await _statusSub?.cancel();
    await _repo?.stop();
    _sampleSub = null;
    _statusSub = null;
    _repo = null;
  }

  void _appendLog(String message) {
    final DateTime now = DateTime.now();
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    final String ss = now.second.toString().padLeft(2, '0');
    setState(() {
      _log.insert(0, '[$hh:$mm:$ss] $message');
      if (_log.length > 50) _log.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final SensorSample? sample = _latest;

    return Scaffold(
      appBar: AppBar(title: const Text('首輪アプリ (受信テスト)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwitchListTile(
              title: const Text('アプリ内モックを使う'),
              subtitle: const Text('オフにすると WebSocket URL に接続します'),
              value: _useMock,
              onChanged:
                  _connected ? null : (bool v) => setState(() => _useMock = v),
            ),
            TextField(
              controller: _urlController,
              enabled: !_useMock && !_connected,
              decoration: const InputDecoration(
                labelText: 'WebSocket URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connected ? null : _connect,
                    child: const Text('接続する'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _connected ? _disconnect : null,
                    child: const Text('切断する'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '状態: ${_status.labelJa}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _StatTile(
                  label: '心拍 (hr)',
                  value: sample?.hr?.toStringAsFixed(1) ?? '--',
                ),
                _StatTile(
                  label: '呼吸 (resp)',
                  value: sample?.resp?.toStringAsFixed(1) ?? '--',
                ),
                _StatTile(
                  label: '電池 (battery)',
                  value: sample?.battery?.toString() ?? '--',
                ),
                _StatTile(label: '欠落フレーム数', value: '$_missedCount'),
              ],
            ),
            const SizedBox(height: 16),
            const Text('ログ'),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (BuildContext context, int index) => Text(
                    _log[index],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}
