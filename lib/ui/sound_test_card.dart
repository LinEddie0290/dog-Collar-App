/// T43（D-065 S3）：声のテスト。同梱の wav（爱迪の test_input.wav）を TFLite の YAMNet に通して結果を出す。
/// 記録中なら、結果を記録ファイル（sound の行）に残す（1 日まとめ → 健康タブの吠叫など）。
/// 期待：bark 1440–4320 ms（爱迪の expected_output.json。prob は 0.5 前後）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../pipeline/pipeline_runner.dart';
import '../sound/sound_detector.dart';
import '../sound/sound_events.dart';

typedef SoundTestRun = Future<List<SoundEvent>> Function();

/// 本物：wav → TFLite（YAMNet）→ イベント。
Future<List<SoundEvent>> runSoundTestWav() async {
  final ({Int16List pcm, int sampleRate}) w = await loadSoundTestWav();
  final TfliteYamnet scorer = await TfliteYamnet.load();
  try {
    return await detectEventsInt16(w.pcm, scorer, sampleRate: w.sampleRate);
  } finally {
    scorer.close();
  }
}

const Map<String, String> soundClassZh = <String, String>{
  'bark': '吠叫',
  'growl': '低吼',
  'howl': '嚎叫',
  'whine': '呜咽',
  'yip': '尖叫',
};

String soundEventLine(SoundEvent e) =>
    '${soundClassZh[e.cls] ?? e.cls}　${(e.startMs / 1000).toStringAsFixed(2)}–${(e.endMs / 1000).toStringAsFixed(2)} 秒　'
    '${e.prob.toStringAsFixed(2)}';

class SoundTestCard extends StatefulWidget {
  const SoundTestCard({super.key, required this.runner, this.run = runSoundTestWav, this.nowMs});

  final PipelineRunner runner;
  final SoundTestRun run;
  final int Function()? nowMs;

  @override
  State<SoundTestCard> createState() => _SoundTestCardState();
}

class _SoundTestCardState extends State<SoundTestCard> {
  bool _busy = false;
  List<SoundEvent>? _events;
  String? _error;
  bool _saved = false;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final int base = (widget.nowMs ?? () => DateTime.now().millisecondsSinceEpoch)();
      final List<SoundEvent> ev = await widget.run();
      final bool rec = widget.runner.session != null;
      widget.runner.addSounds(ev, base, source: 'test_wav');
      if (mounted) {
        setState(() {
          _events = ev;
          _saved = rec;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SoundEvent>? ev = _events;
    return Card(
      key: const ValueKey<String>('sound-test-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('声音的测试（wav，爱迪的模块）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('用 App 里的测试 wav（狗叫 5 秒）。应该出：吠叫 1.44–4.32 秒', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey<String>('sound-test-run'),
              onPressed: _busy ? null : _go,
              icon: const Icon(Icons.graphic_eq, size: 18),
              label: Text(_busy ? '在算…' : '用测试 wav 试一下'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('出错了：$_error', key: const ValueKey<String>('sound-test-error'), style: const TextStyle(color: Colors.red)),
              ),
            if (ev != null) ...<Widget>[
              const SizedBox(height: 8),
              if (ev.isEmpty) const Text('没有检测到狗的声音'),
              for (final SoundEvent e in ev) Text(soundEventLine(e), key: ValueKey<String>('sound-test-${e.startMs}')),
              Text(_saved ? '已经存到这次的记录里' : '没有在记录（只显示，不保存）', style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
