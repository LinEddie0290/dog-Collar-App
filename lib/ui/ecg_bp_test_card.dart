import 'dart:typed_data';

import 'package:collar_ecg_bp/collar_ecg_bp.dart';
import 'package:flutter/material.dart';

import '../ecg_bp/ecg_bp_runner.dart';

/// 电脑（collar-pipeline 的 TFLite）用同样的假信号算出来的答案（test/fixtures/ecg_bp_golden.json，synth_v1）。
const double ecgBpExpectHr = 89.55223880597016; // x_raw_−（App 的默认）
const int ecgBpExpectPeaks = 63;
const double ecgBpExpectSbp = 120.94742822647095; // TFLite int8（只量化权重），5 折 × 32 窗的平均（iPhone 的 TFLite 2.12 算的）
const double ecgBpExpectDbp = 70.39867186546326;

typedef EcgBpRun = Future<EcgBpOutcome> Function();

/// 跑一次假信号（60 秒・400 Hz・3 轴）。
Future<EcgBpOutcome> runEcgBpSynth({EcgBpBackend? backend}) async {
  final ({Float64List ax, Float64List ay, Float64List az}) s = synthCollarAcc();
  final EcgBpBackend b = backend ?? TfliteEcgBp();
  try {
    return await runEcgBp(s.ax, s.ay, s.az, 400.0, b);
  } finally {
    if (backend == null) b.close();
  }
}

String _f(double v, [int d = 1]) => v.isNaN ? '—' : v.toStringAsFixed(d);

/// 测试画面：「心电图・血压的测试（假信号，汪磊老师组的模型）」。
class EcgBpTestCard extends StatefulWidget {
  const EcgBpTestCard({super.key, this.run});

  final EcgBpRun? run;

  @override
  State<EcgBpTestCard> createState() => _EcgBpTestCardState();
}

class _EcgBpTestCardState extends State<EcgBpTestCard> {
  bool _busy = false;
  String? _error;
  EcgBpOutcome? _out;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final EcgBpOutcome o = await (widget.run ?? runEcgBpSynth)();
      if (!mounted) return;
      setState(() => _out = o);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EcgBpOutcome? o = _out;
    return Card(
      key: const ValueKey<String>('ecg-bp-test-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('心电图・血压的测试（假信号，汪磊老师组的模型）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '用 App 里的假信号（60 秒，心跳 90 次/分）。应该出：心率 ${_f(ecgBpExpectHr)}、'
              'R 波 $ecgBpExpectPeaks 个、SBP ${_f(ecgBpExpectSbp, 2)}、DBP ${_f(ecgBpExpectDbp, 2)}（和电脑一样）',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey<String>('ecg-bp-test-run'),
              onPressed: _busy ? null : _go,
              icon: const Icon(Icons.monitor_heart_outlined),
              label: Text(_busy ? '在算…（约 10〜30 秒）' : '用假信号试一下'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('出错了：$_error', key: const ValueKey<String>('ecg-bp-test-error'), style: const TextStyle(color: Colors.red)),
              ),
            if (o != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '心电图：用了 ${o.ecg.windowsUsed}/${o.ecg.input.nAll} 个窗口，R 波 ${o.ecg.rPeaks.length} 个，心率 ${_f(o.ecg.heartRateBpm)} 次/分',
                key: const ValueKey<String>('ecg-bp-test-ecg'),
              ),
              if (o.bp != null)
                Text(
                  '血压：SBP ${_f(o.bp!.sbp, 2)}　DBP ${_f(o.bp!.dbp, 2)} mmHg（5 折的平均）',
                  key: const ValueKey<String>('ecg-bp-test-bp'),
                )
              else
                Text('血压：算不了（${o.bpError}）', key: const ValueKey<String>('ecg-bp-test-bp')),
              Text('时间：前处理 ${_f(o.prepMs / 1000)} 秒，模型 ${_f(o.modelMs / 1000)} 秒',
                  style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
