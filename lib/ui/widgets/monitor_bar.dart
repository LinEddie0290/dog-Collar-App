import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/error_text.dart';
import '../../pipeline/pipeline_runner.dart';
import '../../state/continuous_monitor.dart';
import '../app_colors.dart';

/// T34-A：「每天」のページの上の記録バー。開始・停止と、今の処理の様子を 1 行で。
/// 文言は暫定で中国語直書き（デザインと 3 言語はあとで）。詳しい数字は C のテスト画面に出す。
class MonitorBar extends StatelessWidget {
  const MonitorBar({super.key, required this.monitor});

  final ContinuousMonitor monitor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[monitor, monitor.runner]),
      builder: (BuildContext context, Widget? _) {
        final PipelineRunner r = monitor.runner;
        final String state;
        if (monitor.starting) {
          state = '连接中…';
        } else if (monitor.running) {
          final WindowResult? last = r.recent.isEmpty ? null : r.recent.last;
          final String now = last == null
              ? '等待数据（约 40 秒后出第一个结果）'
              : '${r.lastState?.rest ?? false ? '安静' : '在动'}・${last.label} ${(last.prob * 100).round()}%';
          state = '记录中：${r.windowsTotal} 秒　$now';
        } else {
          state = r.windowsTotal > 0 ? '已停止（这次 ${r.windowsTotal} 秒）' : '没有在记录';
        }
        final String? err = errorText(AppStringsScope.of(context), monitor.errorMessage);
        return Container(
          key: const ValueKey<String>('monitor-bar'),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: monitor.running ? AppColors.connected : AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              Icon(monitor.running ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
                  size: 16, color: monitor.running ? AppColors.accent : AppColors.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(state, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    if (err != null)
                      Text(err, style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                    if (r.lastError != null && monitor.running)
                      Text('处理：${r.lastError}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              FilledButton.tonal(
                key: const ValueKey<String>('monitor-toggle'),
                onPressed: monitor.starting ? null : monitor.toggle,
                child: Text(monitor.running ? '停止记录' : '开始记录'),
              ),
            ],
          ),
        );
      },
    );
  }
}
