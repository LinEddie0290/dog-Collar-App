import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../pipeline/pipeline_runner.dart';
import '../pipeline/session_export.dart';
import '../pipeline/test_subject.dart';
import '../state/continuous_monitor.dart';
import 'app_colors.dart';

/// T34-E：テスト画面の「狗的信息」と「记录一览・导出」。

BoxDecoration _box() => BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(14),
    );

const TextStyle _title = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
const TextStyle _small = TextStyle(fontSize: 12, color: AppColors.textSecondary);

/// 犬の情報（記録の頭に入る）。
class SubjectCard extends StatelessWidget {
  const SubjectCard({super.key, required this.monitor});
  final ContinuousMonitor monitor;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('subject-card'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: _box(),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('狗的信息（写进记录）', style: _title),
                const SizedBox(height: 2),
                Text(monitor.subject.summary, style: _small),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey<String>('subject-edit'),
            onPressed: () => _edit(context),
            child: const Text('修改'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final TestSubject s = monitor.subject;
    final TextEditingController name = TextEditingController(text: s.name);
    final TextEditingController breed = TextEditingController(text: s.breed);
    final TextEditingController weight = TextEditingController(text: s.weightKg?.toString() ?? '');
    final TextEditingController note = TextEditingController(text: s.note);
    String position = s.position;
    final TestSubject? got = await showDialog<TestSubject>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: const Text('狗的信息'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                    key: const ValueKey<String>('subject-name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: '名字')),
                TextField(
                    key: const ValueKey<String>('subject-breed'),
                    controller: breed,
                    decoration: const InputDecoration(labelText: '品种')),
                TextField(
                  key: const ValueKey<String>('subject-weight'),
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '体重（kg）'),
                ),
                const SizedBox(height: 8),
                const Align(alignment: Alignment.centerLeft, child: Text('项圈的位置', style: _small)),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (final MapEntry<String, String> e in collarPositions.entries)
                      ChoiceChip(
                        key: ValueKey<String>('subject-pos-${e.key}'),
                        label: Text(e.value),
                        selected: position == e.key,
                        onSelected: (_) => set(() => position = e.key),
                      ),
                  ],
                ),
                TextField(
                    key: const ValueKey<String>('subject-note'),
                    controller: note,
                    decoration: const InputDecoration(labelText: '备注（项圈松紧、场所等）')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              key: const ValueKey<String>('subject-save'),
              onPressed: () => Navigator.pop(
                ctx,
                TestSubject(
                  name: name.text.trim(),
                  breed: breed.text.trim(),
                  weightKg: double.tryParse(weight.text.trim()),
                  position: position,
                  note: note.text.trim(),
                ),
              ),
              child: const Text('好'),
            ),
          ],
        ),
      ),
    );
    for (final TextEditingController c in <TextEditingController>[name, breed, weight, note]) {
      c.dispose();
    }
    if (got != null) await monitor.setSubject(got);
  }
}

typedef ShareFile = Future<void> Function(BuildContext context, File file);

Future<void> shareWithSheet(BuildContext context, File file) async {
  final RenderBox? box = context.findRenderObject() as RenderBox?;
  await Share.shareXFiles(<XFile>[XFile(file.path)],
      subject: file.uri.pathSegments.last,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
}

Future<String> defaultExportDir() async => '${(await getTemporaryDirectory()).path}/exports';

/// 記録の一覧と書き出し（共有シートで Mac へ）。
class SessionsCard extends StatefulWidget {
  const SessionsCard({super.key, required this.runner, this.share = shareWithSheet, this.exportDir = defaultExportDir});

  final PipelineRunner runner;
  final ShareFile share;
  final Future<String> Function() exportDir;

  @override
  State<SessionsCard> createState() => _SessionsCardState();
}

class _SessionsCardState extends State<SessionsCard> {
  List<SessionListing>? _list;
  String? _dir;
  String? _busyId;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Directory? d = await widget.runner.store?.dir();
      if (d == null || !mounted) return;
      setState(() {
        _dir = d.path;
        _list = listSessions(d.path);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _note = '读不出记录：$e');
    }
  }

  Future<void> _export(SessionListing s) async {
    final String? dir = _dir;
    if (dir == null || _busyId != null) return;
    setState(() {
      _busyId = s.id;
      _note = null;
    });
    try {
      await widget.runner.store?.idle(); // 写到一半的先写完
      final File f = await exportSession(dir, s.id, await widget.exportDir(),
          app: <String, Object?>{'name': 'collar_app', 'part': 'T34'});
      if (!mounted) return;
      setState(() => _note = '做好了：${f.uri.pathSegments.last}（${_kb(f.lengthSync())}）');
      await widget.share(context, f);
    } on Object catch (e) {
      if (mounted) setState(() => _note = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  static String _kb(int b) => b >= 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';

  static String _when(int ms) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final List<SessionListing> list = _list ?? const <SessionListing>[];
    final String? current = widget.runner.session?.id;
    return Container(
      key: const ValueKey<String>('sessions-card'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: Text('记录一览・导出（用共享发到 Mac）', style: _title)),
              IconButton(
                  key: const ValueKey<String>('sessions-reload'),
                  tooltip: '重新读取',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 20)),
            ],
          ),
          if (_list == null && _note == null) const Text('读取中…', style: _small),
          if (_list != null && list.isEmpty) const Text('还没有记录', style: _small),
          for (final SessionListing s in list.take(15))
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${_when(s.startedMs)}　${s.subjectName.isEmpty ? '-' : s.subjectName}　${s.input.isEmpty ? '' : s.input}'
                    '　${_kb(s.bytes + s.rawBytes)}${s.id == current ? '　（记录中）' : ''}',
                    style: _small,
                  ),
                ),
                if (_busyId == s.id)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  IconButton(
                    key: ValueKey<String>('export-${s.id}'),
                    tooltip: '导出',
                    onPressed: _busyId == null ? () => _export(s) : null,
                    icon: const Icon(Icons.ios_share, size: 20),
                  ),
              ],
            ),
          if (_note != null) Text(_note!, style: _small),
        ],
      ),
    );
  }
}
