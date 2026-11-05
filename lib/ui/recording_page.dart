import 'package:flutter/material.dart';

import '../state/continuous_monitor.dart';
import 'app_colors.dart';
import 'widgets/monitor_bar.dart';

/// 记录・测试：記録の開始・停止のバー（入力の選び方つき）。📊 でテスト画面を開く。
/// 前は「每天」のページの上にあった（T35 で开发に移した）。
class RecordingPage extends StatelessWidget {
  const RecordingPage({super.key, required this.monitor});

  final ContinuousMonitor monitor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记录・测试')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          MonitorBar(monitor: monitor),
          const SizedBox(height: 12),
          const Text(
            '记录中的结果在「今天」和「健康」里看（「健康」选「实际」）。📊 打开测试画面（正确答案的按钮・导出等）。',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
