import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
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
        final AppStrings strings = AppStringsScope.of(context);
        final List<SensorSample> recent = controller.recent;
        // 心拍ではなく体温の履歴。実機に心拍センサーが無いため
        // (PROTOCOL_CHANGE.md 参照)。
        final List<double> tempValues = recent
            .map((SensorSample s) => s.bodyTempC)
            .whereType<double>()
            .toList();

        double? avg;
        double? maxTemp;
        double? minTemp;
        if (tempValues.isNotEmpty) {
          avg = tempValues.reduce((double a, double b) => a + b) /
              tempValues.length;
          maxTemp = tempValues.reduce((double a, double b) => a > b ? a : b);
          minTemp = tempValues.reduce((double a, double b) => a < b ? a : b);
        }

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Text(
                strings.navHistory,
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
                        Text(
                          strings.historyChartTitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          strings.recentCountLabel(tempValues.length),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (tempValues.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            strings.noDataYet,
                            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 120,
                        child: Sparkline(values: tempValues, color: AppColors.accent),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(child: _SummaryStat(label: strings.avgLabel, value: avg)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryStat(label: strings.maxLabel, value: maxTemp, color: AppColors.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _SummaryStat(label: strings.minLabel, value: minTemp)),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.historyInfoNote,
                        style: const TextStyle(
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
            // 体温は 0.1℃ の差が意味を持つので四捨五入しない。
            value == null ? '--' : value!.toStringAsFixed(1),
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
