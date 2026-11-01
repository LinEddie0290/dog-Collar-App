import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/error_text.dart';
import '../../pipeline/imu_input.dart';
import '../../pipeline/pipeline_runner.dart';
import '../../state/continuous_monitor.dart';
import '../app_colors.dart';
import '../test_page.dart';

/// T34-A・F：「每天」のページの上の記録バー。入力の選び方（项圈／Unity／模拟）、開始・停止、
/// 今の処理の様子。文言は暫定で中国語直書き（デザインと 3 言語はあとで）。
/// 詳しい数字は C のテスト画面に出す。
class MonitorBar extends StatelessWidget {
  const MonitorBar({super.key, required this.monitor});

  final ContinuousMonitor monitor;

  static const Map<InputKind, String> _names = <InputKind, String>{
    InputKind.collar: '项圈',
    InputKind.unity: 'Unity',
    InputKind.fake: '模拟',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[monitor, monitor.runner]),
      builder: (BuildContext context, Widget? _) {
        final PipelineRunner r = monitor.runner;
        final bool locked = monitor.running || monitor.starting;
        final String state;
        if (monitor.starting) {
          state = '连接中…';
        } else if (monitor.running) {
          final WindowResult? last = r.recent.isEmpty ? null : r.recent.last;
          final String now = last == null
              ? '等待数据（约 40 秒后出第一个结果）'
              : '${r.lastState?.rest ?? false ? '安静' : '在动'}・${last.label} ${(last.prob * 100).round()}%';
          state = '记录中（${_names[monitor.runningKind]}）：${r.windowsTotal} 秒　$now';
        } else {
          state = r.windowsTotal > 0 ? '已停止（这次 ${r.windowsTotal} 秒）' : '没有在记录';
        }
        final String? inputLine = monitor.input?.statusLine;
        final String? err = errorText(AppStringsScope.of(context), monitor.errorMessage);
        return Container(
          key: const ValueKey<String>('monitor-bar'),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: monitor.running ? AppColors.connected : AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(monitor.running ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
                      size: 16, color: monitor.running ? AppColors.accent : AppColors.textFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(state, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        if (inputLine != null)
                          Text(inputLine, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        if (err != null) Text(err, style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                        if (r.lastError != null && monitor.running)
                          Text('处理：${r.lastError}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('open-test-page'),
                    tooltip: '测试画面',
                    icon: const Icon(Icons.analytics_outlined),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => TestPage(monitor: monitor))),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey<String>('monitor-toggle'),
                    onPressed: monitor.starting ? null : monitor.toggle,
                    child: Text(monitor.running ? '停止记录' : '开始记录'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final InputKind k in InputKind.values)
                    ChoiceChip(
                      key: ValueKey<String>('input-${k.name}'),
                      label: Text(_names[k]!),
                      selected: monitor.kind == k,
                      onSelected: locked ? null : (_) => monitor.setInput(kind: k),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (monitor.kind == InputKind.unity)
                    ActionChip(
                      key: const ValueKey<String>('unity-url'),
                      avatar: const Icon(Icons.edit, size: 14),
                      label: Text(monitor.unityUrl, style: const TextStyle(fontSize: 11)),
                      onPressed: locked ? null : () => _editUrl(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (monitor.kind == InputKind.fake)
                    for (final double s in const <double>[1, 10, 60])
                      ChoiceChip(
                        key: ValueKey<String>('fake-speed-${s.round()}'),
                        label: Text('×${s.round()}'),
                        selected: monitor.fakeSpeed == s,
                        onSelected: locked ? null : (_) => monitor.setInput(fakeSpeed: s),
                        visualDensity: VisualDensity.compact,
                      ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editUrl(BuildContext context) async {
    final TextEditingController c = TextEditingController(text: monitor.unityUrl);
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Unity 的地址'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'ws://192.168.1.96:8765/imu'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('好')),
        ],
      ),
    );
    c.dispose();
    if (url != null && url.isNotEmpty) await monitor.setInput(unityUrl: url);
  }
}
