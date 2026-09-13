import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/collar_controller.dart';
import 'app_colors.dart';
import 'widgets/sparkline.dart';
import 'widgets/stat_card.dart';

/// ホーム画面。Design Canvas の叩き台をそのままFlutterに落とし込んだもの。
///
/// 表示に徹していて、通信・保存・フィルタは全部 CollarController(内部で
/// package:collar_data の CollarRepository)任せ。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final CollarController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final AppStrings strings = AppStringsScope.of(context);
        // 体温が首輪の唯一の生体指標。心拍は実機に光学式センサーが無いため
        // 表示自体をやめた(PROTOCOL_CHANGE.md 参照)。
        final double? bodyTemp = controller.latest?.bodyTempC;
        final double? ambientTemp = controller.latest?.ambientTempC;
        // resp と battery は実機では常に null。モックでのみ値が入る。
        final double? resp = controller.latest?.resp;
        final int? battery = controller.latest?.battery;
        final List<double> tempSeries = controller.recent
            .map((SensorSample s) => s.bodyTempC)
            .whereType<double>()
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(status: controller.status, strings: strings),
              const SizedBox(height: 18),
              _BodyTempCard(
                value: bodyTemp,
                ambient: ambientTemp,
                series: tempSeries,
                strings: strings,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatCard(
                      icon: Icons.air,
                      label: strings.respirationLabel,
                      value: resp != null ? resp.round().toString() : '--',
                      unit: strings.breathsPerMinUnit,
                      footer: resp != null ? strings.stableStatus : strings.waitingForData,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.battery_full,
                      label: strings.batteryLabel,
                      value: battery != null ? battery.toString() : '--',
                      unit: '%',
                      progress: battery != null ? battery / 100 : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _BarkPlaceholderCard(strings: strings),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.strings});

  final ConnStatus status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.pets, color: Color(0xFFFFF7EF), size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                strings.petName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 1),
              Text(strings.petBreedAge, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        _StatusPill(status: status, strings: strings),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.strings});

  final ConnStatus status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final Color dot = switch (status) {
      ConnStatus.connected => AppColors.connected,
      ConnStatus.disconnected => AppColors.textFaint,
      ConnStatus.connecting || ConnStatus.reconnecting => AppColors.accent2,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(strings.connStatusLabel(status), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 体温カード。実機で唯一まともに取れる生体指標なので、ここを主役にしている。
class _BodyTempCard extends StatelessWidget {
  const _BodyTempCard({
    required this.value,
    required this.ambient,
    required this.series,
    required this.strings,
  });

  final double? value;
  final double? ambient;
  final List<double> series;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.thermostat, color: Color(0xFFFFF7EF), size: 17),
                  const SizedBox(width: 7),
                  Text(strings.bodyTempLabel, style: const TextStyle(color: Color(0xFFFFF7EF), fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
              Text(
                value != null ? strings.justNow : strings.notReceivedYet,
                style: const TextStyle(color: Color(0xE6FFF7EF), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                // 体温は 0.1℃ の差が意味を持つので小数1桁で出す。
                value != null ? value!.toStringAsFixed(1) : '--',
                style: const TextStyle(
                  color: Color(0xFFFFF7EF),
                  fontSize: 60,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
              Text(strings.celsiusUnit, style: const TextStyle(color: Color(0xE6FFF7EF), fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (ambient != null)
                Text(
                  '${strings.ambientTempLabel} ${ambient!.toStringAsFixed(1)}${strings.celsiusUnit}',
                  style: const TextStyle(color: Color(0xE6FFF7EF), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: series.length > 1
                ? Sparkline(values: series, color: const Color(0xFFFFF7EF))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _BarkPlaceholderCard extends StatelessWidget {
  const _BarkPlaceholderCard({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7D8C6)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0xFFFBF1E6), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.chat_bubble_outline, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(strings.barkTranslationTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFFBF1E6), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        strings.comingSoon,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  strings.barkTranslationDesc,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFC9BCAF), size: 18),
        ],
      ),
    );
  }
}
