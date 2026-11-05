import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../state/continuous_monitor.dart';
import '../state/locale_controller.dart';
import 'app_colors.dart';
import 'cnn_bench_page.dart';
import 'recording_page.dart';

/// 「我的」タブ（T35）：言語・データ・开发。
/// 古い「模拟／WebSocket で接続」と、値が出ていなかった「项圈」の欄は消した（T35 整理）。
/// 首輪の選択・接続は「测定」タブから。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.localeController,
    this.monitor,
  });

  final LocaleController localeController;

  /// T34：記録・テスト。null なら开发に出さない。
  final ContinuousMonitor? monitor;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStringsScope.of(context);

    return AnimatedBuilder(
      animation: localeController,
      builder: (BuildContext context, Widget? _) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Text(
                strings.navMine,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 20),
              _SectionLabel(strings.languageSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  for (final AppLanguage lang in AppLanguage.values)
                    _SettingsRow(
                      last: lang == AppLanguage.values.last,
                      child: InkWell(
                        onTap: () => localeController.setLanguage(lang),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                lang.nativeName,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (lang == localeController.language)
                              const Icon(Icons.check, size: 18, color: AppColors.accent),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(strings.dataSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  _SettingsRow(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(strings.storageLocationLabel, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          strings.storageLocationDesc,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _SettingsRow(
                    last: true,
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.file_download_outlined, size: 16, color: AppColors.textFaint),
                        const SizedBox(width: 10),
                        Text(
                          strings.exportRecordsLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 开发：記録・テスト画面（T34）と CNN の推理速度（T24）。文言は中国語だけ（T16 で整理）。
              const _SectionLabel('开发'),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  if (monitor != null)
                    _SettingsRow(
                      child: _LinkRow(
                        key: const ValueKey<String>('open-recording'),
                        icon: Icons.fiber_manual_record_outlined,
                        title: '记录・测试（T34）',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (BuildContext _) => RecordingPage(monitor: monitor!)),
                        ),
                      ),
                    ),
                  _SettingsRow(
                    last: true,
                    child: _LinkRow(
                      key: const ValueKey<String>('open-cnn-bench'),
                      icon: Icons.speed,
                      title: '推理速度（T24）',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (BuildContext _) => const CnnBenchPage()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: Column(
                  children: <Widget>[
                    Text(strings.appTitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint)),
                    const SizedBox(height: 2),
                    const Text('version 0.1.0', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
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

class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.child, this.last = false});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: child,
    );
  }
}
