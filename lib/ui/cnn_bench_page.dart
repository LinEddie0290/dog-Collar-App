import 'dart:convert';

import 'package:collar_imu_cnn/collar_imu_cnn.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app_colors.dart';

/// 別の isolate で動く:JSON を読んで、1 回温めてから測る。
(CnnCheckResult, int) _bench(List<String> texts) {
  final CnnImuModel model = CnnImuModel.fromJson(jsonDecode(texts[0]) as Map<String, dynamic>);
  final Map<String, dynamic> check = jsonDecode(texts[1]) as Map<String, dynamic>;
  runCnnCheck(model, check, reps: 1);
  return (runCnnCheck(model, check), model.params);
}

/// T24:CNN の推理速度を iPhone で測る画面(開発用。設定の一番下から開く)。
/// 確かめ用の窓 200 個で PyTorch の答えと比べ、200 窓 × 5 回の時間を出す。
/// 数字は release(`flutter run --release`)で取ること。debug は何倍も遅い。
class CnnBenchPage extends StatefulWidget {
  const CnnBenchPage({super.key});

  @override
  State<CnnBenchPage> createState() => _CnnBenchPageState();
}

class _CnnBenchPageState extends State<CnnBenchPage> {
  static const String _modelAsset = 'assets/models/cnn_imu_v1.json';
  static const String _checkAsset = 'assets/models/check_windows.json';

  bool _running = false;
  String? _error;
  CnnCheckResult? _result;
  int? _params;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final List<String> texts = <String>[
        await rootBundle.loadString(_modelAsset),
        await rootBundle.loadString(_checkAsset),
      ];
      // 別の isolate で測る(画面が止まらないように)。
      final (CnnCheckResult, int) out = await compute(_bench, texts);
      setState(() {
        _result = out.$1;
        _params = out.$2;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CnnCheckResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('推理速度（T24）')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            kReleaseMode ? '模式：release（可以用这个数字）' : '模式：debug（数字会慢很多，只看对不对）',
            style: TextStyle(fontSize: 13, color: kReleaseMode ? AppColors.textSecondary : AppColors.accent),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey<String>('bench-start'),
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.speed),
            label: Text(_running ? '测量中…' : '开始（200 个窗口 × 5 次）'),
          ),
          const SizedBox(height: 20),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.accent)),
          if (r != null) ...<Widget>[
            _row('结果', r.ok ? '和 PyTorch 一样 ✔' : '和 PyTorch 不一样 ✘'),
            _row('标签一致', '${r.sameLabel} / ${r.windows}'),
            _row('概率最大差', r.maxProbDiff.toStringAsExponential(2)),
            _row('1 个窗口（中位数）', '${r.medianMs.toStringAsFixed(3)} ms'),
            _row('1 个窗口（平均）', '${r.meanMs.toStringAsFixed(3)} ms'),
            _row('1 个窗口（最慢）', '${r.maxMs.toStringAsFixed(3)} ms'),
            if (_params != null) _row('参数', '$_params'),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary))),
            Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      );
}
