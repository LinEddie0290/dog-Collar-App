import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';

import '../state/collar_controller.dart';
import 'app_colors.dart';
import 'conn_status_ja.dart';
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
        final double? hr = controller.latest?.hr;
        final double? resp = controller.latest?.resp;
        final int? battery = controller.latest?.battery;
        final List<double> hrSeries =
            controller.recent.map((SensorSample s) => s.hr).whereType<double>().toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(status: controller.status),
              const SizedBox(height: 18),
              _HeartRateCard(value: hr, series: hrSeries),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatCard(
                      icon: Icons.air,
                      label: '呼吸',
                      value: resp != null ? resp.round().toString() : '--',
                      unit: '回/分',
                      footer: resp != null ? '安定しています' : '受信を待っています',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.battery_full,
                      label: '電池',
                      value: battery != null ? battery.toString() : '--',
                      unit: '%',
                      progress: battery != null ? battery / 100 : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _BarkPlaceholderCard(),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status});

  final ConnStatus status;

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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'モモ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
              ),
              SizedBox(height: 1),
              Text('柴犬・2歳', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        _StatusPill(status: status),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ConnStatus status;

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
          Text(status.labelJa, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.value, required this.series});

  final double? value;
  final List<double> series;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(color: AppColors.accent.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.favorite, color: Color(0xFFFFF7EF), size: 17),
                  SizedBox(width: 7),
                  Text('心拍数', style: TextStyle(color: Color(0xFFFFF7EF), fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
              Text(
                value != null ? 'たった今' : '未受信',
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
                value != null ? value!.round().toString() : '--',
                style: const TextStyle(
                  color: Color(0xFFFFF7EF),
                  fontSize: 60,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
              const Text('bpm', style: TextStyle(color: Color(0xE6FFF7EF), fontSize: 16, fontWeight: FontWeight.w600)),
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
  const _BarkPlaceholderCard();

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
                    const Text('鳴き声・感情翻訳', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFFBF1E6), borderRadius: BorderRadius.circular(999)),
                      child: const Text(
                        '近日公開',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  '鳴き声から気持ちを読み取る機能を開発中です',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
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
