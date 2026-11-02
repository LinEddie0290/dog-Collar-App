import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter/material.dart';

import '../pipeline/auto_vitals.dart';
import '../state/continuous_monitor.dart';
import 'app_colors.dart';

/// T34-B：テスト画面の「心率（自动・记录中手动）」。
class VitalsCard extends StatelessWidget {
  const VitalsCard({super.key, required this.monitor});
  final ContinuousMonitor monitor;

  static const Map<String, String> sensors = <String, String>{'front': '基板 IMU', 'side': 'BMI088'};

  static String _clock(int ms) {
    if (ms < 0) return '--:--:--';
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String _reason(String? r) => switch (r) {
        'moved' => '中止：动了',
        'session_end' => '中止：记录停了',
        'data_gap' => '数据缺太多',
        null => '',
        _ => '测不出（$r）',
      };

  static String line(VitalAttempt a) {
    final String head = '${_clock(a.tStartMs)}　${a.trigger == 'auto' ? '自动' : '手动'}・${sensors[a.sensor] ?? a.sensor}　';
    if (a.status == AttemptStatus.aborted) return head + _reason(a.reason);
    final VitalsResult? r = a.result;
    if (r == null) return head + _reason(a.reason);
    if (!a.usable) return '$head${_reason(a.reason ?? 'unusable')}';
    final String rr = r.respirationPerMin == null ? '' : '・呼吸 ${r.respirationPerMin!.round()}';
    return '$head心率 ${r.heartRateBpm!.round()}$rr（${r.quality.name}）';
  }

  @override
  Widget build(BuildContext context) {
    final AutoVitals? av = monitor.runner.autoVitals;
    if (av == null) return const SizedBox.shrink();
    final VitalAttempt? c = av.current;
    final bool live = monitor.running && monitor.runner.nowStamp() != null;
    final String status;
    if (!monitor.running) {
      status = '没有在记录（记录中会自动测）';
    } else if (c != null) {
      status = '测量中（${c.trigger == 'auto' ? '自动' : '手动'}・${sensors[c.sensor]}）：'
          '${(av.progress * av.measureS).toStringAsFixed(0)} / ${av.measureS.toStringAsFixed(0)} 秒';
    } else if (!av.enabled) {
      status = '自动测量关着';
    } else if (av.cooldownLeftS > 0) {
      status = '下次自动测量：还要 ${(av.cooldownLeftS / 60).toStringAsFixed(1)} 分钟';
    } else {
      status = '等狗安静 30 秒（很安静＝活动量 < 0.15）';
    }
    return Container(
      key: const ValueKey<String>('vitals-card'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: c != null ? AppColors.connected : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('心率（自动・记录中手动）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              const Text('自动', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Switch(
                key: const ValueKey<String>('vitals-auto'),
                value: av.enabled,
                onChanged: (bool v) => monitor.setVitals(enabled: v),
              ),
            ],
          ),
          Text(status, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final MapEntry<String, String> e in sensors.entries)
                ChoiceChip(
                  key: ValueKey<String>('vitals-sensor-${e.key}'),
                  label: Text(e.value),
                  selected: av.sensor == e.key,
                  onSelected: c == null ? (_) => monitor.setVitals(sensor: e.key) : null,
                  visualDensity: VisualDensity.compact,
                ),
              FilledButton.tonal(
                key: const ValueKey<String>('vitals-now'),
                onPressed: live && c == null ? av.measureNow : null,
                child: const Text('现在测（60 秒）'),
              ),
            ],
          ),
          if (av.history.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            for (final VitalAttempt a in av.history.reversed.take(5))
              Text(line(a), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
