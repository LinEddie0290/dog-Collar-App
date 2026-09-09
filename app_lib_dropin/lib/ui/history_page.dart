import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';

import '../state/collar_controller.dart';
import 'app_colors.dart';
import 'widgets/sparkline.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.controller});

  final CollarController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<SensorSample> recent = controller.recent;
        final List<double> hrValues = recent
            .map((SensorSample s) => s.hr)
            .whereType<double>()
            .toList();

        double? avg;
        double? maxHr;
        double? minHr;
        if (hrValues.isNotEmpty) {
          avg = hrValues.reduce((double a, double b) => a + b) / hrValues.length;
          maxHr = hrValues.reduce((double a, double b) => a > b ? a : b);
          minHr = hrValues.reduce((double a, double b) => a < b ? a : b);
        }

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Text(
                '履歴',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          '心拍数の推移(セッション内)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '直近${hrValues.length}件',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (hrValues.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'まだデータがありません',
                            style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 120,
                        child: Sparkline(values: hrValues, color: AppColors.accent),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(child: _SummaryStat(label: '平均', value: avg)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryStat(label: '最高', value: maxHr, color: AppColors.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _SummaryStat(label: '最低', value: minHr)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border, width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '現在表示しているのは、このアプリを起動してからの記録です。'
                        '日付をまたいだ履歴の閲覧は、端末に保存されたファイルを読み込む機能として今後追加予定です。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value, this.color});

  final String label;
  final double? value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value == null ? '--' : value!.round().toString(),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
