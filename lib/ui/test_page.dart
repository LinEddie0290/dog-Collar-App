import 'dart:async';
import 'dart:io';

import 'package:collar_pipeline/collar_pipeline.dart';
import 'package:flutter/material.dart';

import '../pipeline/imu_input.dart';
import '../pipeline/pipeline_runner.dart';
import '../pipeline/truth_compare.dart';
import '../state/continuous_monitor.dart';
import 'app_colors.dart';
import 'test_page_sessions.dart';
import 'test_page_vitals.dart';

/// T34-C：テスト画面（開発者向け）。記録中の様子を 1 画面に、1 秒ごとに更新。
/// 入力・受信（周波数・抜け）・処理・今の状態・最近 2 分の帯・出来事・保存。
/// 文言は暫定で中国語直書き。見た目はあとで直す。
class TestPage extends StatefulWidget {
  const TestPage({
    super.key,
    required this.monitor,
    this.refresh = const Duration(seconds: 1),
    this.share = shareWithSheet,
    this.exportDir = defaultExportDir,
  });

  final ContinuousMonitor monitor;
  final Duration refresh;

  /// E：書き出したファイルの渡し方（テストでは差し替える）。
  final ShareFile share;
  final Future<String> Function() exportDir;

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  Timer? _timer;
  int _lastSamples = 0;
  double _wallHz = 0;
  String? _dir;

  PipelineRunner get _r => widget.monitor.runner;

  @override
  void initState() {
    super.initState();
    _lastSamples = _r.samplesIn;
    _timer = Timer.periodic(widget.refresh, (_) => _tick());
    _r.store?.dir().then((Directory d) {
      if (mounted) setState(() => _dir = d.path);
    }).catchError((Object _) {});
  }

  void _tick() {
    final int n = _r.samplesIn;
    _wallHz = (n - _lastSamples) / (widget.refresh.inMilliseconds / 1000);
    _lastSamples = n;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ContinuousMonitor m = widget.monitor;
    final PipelineRunner r = _r;
    // 止めたあとも最後の記録を出す（正解・状態の帯が消えないように）
    final PipelineSession? s = r.session ?? r.lastSession;
    final List<WindowResult> wins = _tail(s == null ? r.recent : s.windows, 120);
    final List<WindowState> states = s == null ? const <WindowState>[] : _tail(s.states, 120);
    final List<TruthMark> truth = s?.truth ?? const <TruthMark>[];
    final WindowResult? last = r.recent.isEmpty ? null : r.recent.last;
    final WindowState? st = r.lastState;
    final TruthMark? nowTruth = last == null ? null : truthAt(truth, last.tDevUs + 1000000);
    final Agreement ag = agreement(wins, truth);

    return Scaffold(
      appBar: AppBar(title: const Text('测试画面')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          _TruthButtons(runner: r),
          SubjectCard(monitor: m),
          VitalsCard(monitor: m),
          _Section('输入', <String>[
            '${_kindName(m.runningKind ?? m.kind)}　${m.running ? '记录中' : (m.starting ? '连接中…' : '没有在记录')}'
                '${m.startedAt != null && m.running ? '（${_dur(DateTime.now().difference(m.startedAt!))}）' : ''}',
            if (m.input != null) m.input!.statusLine,
            if (m.runningKind == InputKind.collar) ...<String>[
              '项圈 IMU 设定：${m.link.activeImuRateHz ?? '-'} Hz　MTU ${m.link.negotiatedMtu ?? '-'}'
                  '　接收错误 ${m.link.source?.receiveErrors ?? 0}',
            ],
            if (m.errorMessage != null) '错误：${m.errorMessage}',
          ]),
          _Section('接收', <String>[
            '样本：${r.samplesIn}　现在 ${_wallHz.toStringAsFixed(0)} 个/秒（手机的时钟）',
            for (final MapEntry<String, SensorStats> e in r.sensorStats.entries)
              '${e.key}：${e.value.rateHz?.toStringAsFixed(1) ?? '-'} Hz（项圈的时钟）'
                  '　缺口 ${e.value.gaps} 次・${e.value.gapSeconds.toStringAsFixed(1)} 秒',
          ]),
          _Section('处理', <String>[
            '计算了 ${r.chunksDone} 次，上次 ${r.lastComputeTime.inMilliseconds} ms'
                '　格子 ${s?.fs?.toStringAsFixed(0) ?? '-'} Hz　等着算的样本 ${r.bufferedSamples}',
            '窗口：这次 ${s?.windows.length ?? 0}　全部 ${r.windowsTotal}',
            if (r.lastError != null) '处理的错误：${r.lastError}',
            for (final String w in r.warnings.take(5)) '注意：$w',
          ]),
          _Section('现在', <String>[
            if (last == null)
              '还没有结果（开始后约 40 秒）'
            else ...<String>[
              'CNN：${last.label} ${(last.prob * 100).round()}%'
                  '${nowTruth != null ? '　正确答案：${nowTruth.label}' : ''}',
              '活动量 ${last.activity.toStringAsFixed(3)} m/s²　→ ${st == null ? '-' : (st.rest ? '安静（< 0.4）' : '在动')}',
              if (st != null)
                '心率测量的条件：很安静 ${st.quietS.toStringAsFixed(0)} / 30 秒'
                    '${st.measureOk ? '　→ 可以测' : ''}',
              '结果的时间 ${_clock(last.tMs)}（比现在晚约 15 秒）',
            ],
            if (ag.n > 0)
              '最近 ${ag.n} 个窗口：CNN 和正确答案一致 ${(ag.rate! * 100).toStringAsFixed(0)}%',
          ]),
          const SizedBox(height: 4),
          Text('最近 2 分钟', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          SizedBox(
            key: const ValueKey<String>('test-timeline'),
            height: 120,
            child: CustomPaint(painter: _TimelinePainter(wins, states, truth), size: Size.infinite),
          ),
          const SizedBox(height: 4),
          const _Legend(),
          const SizedBox(height: 12),
          _Section('事件（这次，最近 10 个）', <String>[
            if (s == null || s.events.isEmpty) '还没有',
            if (s != null)
              for (final BehaviorEvent e in _tail(s.events, 10).reversed)
                '${_clock(e.tStartMs)}　${e.type}${e.sub.isNotEmpty ? '(${e.sub})' : ''}'
                    '　${e.durationS.toStringAsFixed(0)} 秒　${e.confidence}　${e.source}',
          ]),
          _Section('保存', <String>[
            if (s == null) '没有在记录' else '记录 ${s.id}　正确答案 ${truth.length} 个　心率 ${s.vitals.length} 个',
            if (s != null && _dir != null) _fileLine('$_dir/${s.id}.jsonl'),
            if (s != null && _dir != null) '生的 IMU：${_fileLine('$_dir/${s.id}.imu.csv')}',
          ]),
          SessionsCard(runner: r, share: widget.share, exportDir: widget.exportDir),
        ],
      ),
    );
  }

  static List<T> _tail<T>(List<T> xs, int n) => xs.length <= n ? xs : xs.sublist(xs.length - n);

  static String _kindName(InputKind k) => switch (k) {
        InputKind.collar => '项圈（BLE）',
        InputKind.unity => 'Unity',
        InputKind.fake => '模拟数据',
      };

  static String _dur(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  static String _clock(int ms) {
    if (ms < 0) return '--:--:--';
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String _fileLine(String path) {
    try {
      final int b = File(path).lengthSync();
      return '文件 ${(b / 1024).toStringAsFixed(1)} KB';
    } on FileSystemException {
      return '文件还没有';
    }
  }
}

/// D：正解のラベル（見ている人が押す）。押した時刻から、その動き。
const List<(String, String)> truthButtons = <(String, String)>[
  ('lie', '趴下'),
  ('sit', '坐'),
  ('stand', '站'),
  ('walk', '走'),
  ('run', '跑'),
  ('scratch', '挠'),
  ('lick', '舔'),
  ('drink', '喝水'),
  ('eat', '吃'),
  ('tremble', '发抖'),
  ('other', '其他'),
];

class _TruthButtons extends StatefulWidget {
  const _TruthButtons({required this.runner});
  final PipelineRunner runner;

  @override
  State<_TruthButtons> createState() => _TruthButtonsState();
}

class _TruthButtonsState extends State<_TruthButtons> {
  final TextEditingController _hr = TextEditingController();
  final TextEditingController _rr = TextEditingController();
  String? _note;

  @override
  void dispose() {
    _hr.dispose();
    _rr.dispose();
    super.dispose();
  }

  static String _name(String key) =>
      truthButtons.firstWhere(((String, String) b) => b.$1 == key, orElse: () => (key, key)).$2;

  static String _clock(int ms) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _press(String key) {
    final bool ok = widget.runner.markNow(key);
    setState(() => _note = ok ? null : '没有在记录，按了也不会留下');
  }

  void _undo() {
    final TruthMark? m = widget.runner.undoLastButton();
    setState(() => _note = m == null ? '没有可以撤销的' : '撤销了 ${_clock(m.tMs)} 的「${_name(m.label)}」');
  }

  void _saveVitals() {
    final double? hr = double.tryParse(_hr.text.trim());
    final double? rr = double.tryParse(_rr.text.trim());
    if (hr == null && rr == null) {
      setState(() => _note = '请输入数字');
      return;
    }
    final bool ok = widget.runner.addManualVitals(hr: hr, rr: rr);
    setState(() {
      _note = ok
          ? '记下了：${hr != null ? '心率 ${hr.round()}' : ''}${hr != null && rr != null ? '・' : ''}${rr != null ? '呼吸 ${rr.round()}' : ''}'
          : '没有在记录，记不下';
      if (ok) {
        _hr.clear();
        _rr.clear();
      }
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final PipelineSession? s = widget.runner.session;
    final List<TruthMark> pressed =
        s == null ? const <TruthMark>[] : s.truth.where((TruthMark m) => m.source == 'button').toList();
    final String? current = pressed.isEmpty ? null : pressed.last.label;
    final bool live = widget.runner.nowStamp() != null;
    return Container(
      key: const ValueKey<String>('truth-buttons'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: live ? AppColors.connected : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('正确答案（看着狗，动作变了就按）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final (String, String) b in truthButtons)
                ChoiceChip(
                  key: ValueKey<String>('truth-${b.$1}'),
                  label: Text(b.$2),
                  selected: current == b.$1,
                  onSelected: live ? (_) => _press(b.$1) : null,
                ),
              ActionChip(
                key: const ValueKey<String>('truth-undo'),
                avatar: const Icon(Icons.undo, size: 16),
                label: const Text('撤销'),
                onPressed: pressed.isEmpty ? null : _undo,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('truth-hr'),
                  controller: _hr,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '数的心率（次/分）', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('truth-rr'),
                  controller: _rr,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '数的呼吸（次/分）', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: const ValueKey<String>('truth-vitals-save'),
                onPressed: live ? _saveVitals : null,
                child: const Text('记下'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              ?_note,
              if (pressed.isNotEmpty)
                '按过的（最近 3 个）：${pressed.reversed.take(3).map((TruthMark m) => '${_clock(m.tMs)} ${_name(m.label)}').join('、')}',
              if (!live) '开始记录、收到数据以后才能按',
            ].join('\n'),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.lines);
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          for (final String l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3)),
            ),
        ],
      ),
    );
  }
}

const Map<String, Color> _cnnColors = <String, Color>{
  'still': Color(0xFFB8AA9C),
  'walk': Color(0xFF6E9271),
  'run': Color(0xFFD9A441),
  'other': Color(0xFF8C6BB1),
};

/// 上から：CNN のラベル・正解（あれば）・安静／動いている（測ってよいところは濃く）・活動量の線。
class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.wins, this.states, this.truth);

  final List<WindowResult> wins;
  final List<WindowState> states;
  final List<TruthMark> truth;

  static const int slots = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width / slots;
    const double band = 14;
    final Paint p = Paint();
    final Map<int, WindowState> byUs = <int, WindowState>{for (final WindowState s in states) s.tStartDevUs: s};
    final int off = slots - wins.length;
    for (int i = 0; i < wins.length; i++) {
      final WindowResult x = wins[i];
      final double left = (off + i) * w;
      p.color = _cnnColors[x.label] ?? Colors.black26;
      canvas.drawRect(Rect.fromLTWH(left, 0, w + 0.5, band), p);
      final TruthMark? t = truthAt(truth, x.tDevUs + 1000000);
      final String? tc = t == null ? null : truthToCnnClass(t.label);
      if (tc != null) {
        p.color = _cnnColors[tc]!;
        canvas.drawRect(Rect.fromLTWH(left, band + 2, w + 0.5, band), p);
      }
      final WindowState? st = byUs[x.tDevUs];
      if (st != null) {
        p.color = st.rest ? (st.measureOk ? const Color(0xFF5B8DB8) : const Color(0xFFBFD4E6)) : const Color(0xFFB85042);
        canvas.drawRect(Rect.fromLTWH(left, 2 * band + 4, w + 0.5, band), p);
      }
    }
    // 活動量（0〜2 m/s²）としきい値 0.4・0.15
    final double top = 3 * band + 10, h = size.height - top;
    double y(double a) => top + h * (1 - (a.clamp(0.0, 2.0) / 2.0));
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    line.color = const Color(0x66B85042);
    canvas.drawLine(Offset(0, y(0.4)), Offset(size.width, y(0.4)), line);
    line.color = const Color(0x665B8DB8);
    canvas.drawLine(Offset(0, y(0.15)), Offset(size.width, y(0.15)), line);
    if (wins.length >= 2) {
      final Path path = Path();
      for (int i = 0; i < wins.length; i++) {
        final Offset o = Offset((off + i + 0.5) * w, y(wins[i].activity));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      line
        ..color = AppColors.textPrimary
        ..strokeWidth = 1.5;
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => true;
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget chip(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(width: 10, height: 10, color: c),
          const SizedBox(width: 3),
          Text(t, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]);
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: <Widget>[
        const Text('第 1 行 CNN・第 2 行 正确答案：', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        for (final MapEntry<String, Color> e in _cnnColors.entries) chip(e.value, e.key),
        const Text('第 3 行：', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        chip(const Color(0xFFB85042), '在动'),
        chip(const Color(0xFFBFD4E6), '安静'),
        chip(const Color(0xFF5B8DB8), '可以测心率'),
        const Text('线：活动量（红线 0.4・蓝线 0.15）', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
