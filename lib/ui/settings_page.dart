import 'package:flutter/material.dart';

import '../data/daily_summary.dart';
import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../pipeline/auto_vitals.dart';
import '../pipeline/cnn_models.dart';
import '../pipeline/test_subject.dart';
import '../state/collar_link.dart';
import '../state/continuous_monitor.dart';
import '../state/locale_controller.dart';
import 'cnn_bench_page.dart';
import 'daily_summary_page.dart';
import 'devices_page.dart';
import 'home/water_background.dart';
import 'home/water_style.dart';
import 'recording_page.dart';
import 'test_page_sessions.dart' show editSubjectDialog;

/// 「我的」タブ（T35・設計メモ T35_安全・我的タブ）：狗的信息・项圈・语言・数据・开发。見た目は白い水。
/// 狗的信息は记录・测试の Subject と同じもの（S4：ホームの名前・記録の頭・書き出しにそろう）。
/// 首輪の接続は「测定」タブにも残す（S5）。新しく足したところの文言は中国語だけ（D-051 D6）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.localeController,
    this.monitor,
    this.link,
    this.liveSummary,
  });

  final LocaleController localeController;

  /// 记录（狗的信息・自動測定・记录・测试）。null なら出さない。
  final ContinuousMonitor? monitor;

  /// 首輪の接続。null なら项圈の欄を出さない。
  final CollarLink? link;

  /// 本物の 1 日まとめ。「每天（旧）」で使う。null なら出さない。
  final SummarySource? liveSummary;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStringsScope.of(context);
    final ContinuousMonitor? m = monitor;
    final CollarLink? l = link;
    final List<Listenable> ls = <Listenable>[localeController, ?m, ?l];

    return WaterBackground(
      child: AnimatedBuilder(
        animation: Listenable.merge(ls),
        builder: (BuildContext context, Widget? _) {
          final AutoVitals? av = m?.runner.autoVitals;
          return ListView(
            key: const ValueKey<String>('mine-page'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Text(strings.navMine,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: WaterColors.text)),
              const SizedBox(height: 14),
              if (m != null) ...<Widget>[
                _DogCard(subject: m.subject, onEdit: () => editSubjectDialog(context, m)),
                const SizedBox(height: 18),
              ],
              if (l != null || av != null) ...<Widget>[
                const _SectionLabel('项圈'),
                const SizedBox(height: 8),
                _SectionCard(
                  children: <Widget>[
                    if (l != null)
                      _SettingsRow(
                        child: _LinkRow(
                          key: const ValueKey<String>('mine-collar-select'),
                          icon: Icons.sensors,
                          title: l.isConnected ? '已连接：${l.targetName ?? 'PET-Sense'}' : '没有连接（选择项圈）',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (BuildContext _) => Scaffold(
                              appBar: AppBar(title: Text(strings.devicesTitle)),
                              body: DevicesPage(link: l),
                            ),
                          )),
                        ),
                      ),
                    if (av != null && m != null) ...<Widget>[
                      _SettingsRow(
                        child: Row(
                          children: <Widget>[
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text('自动测心率', style: _rowTitle),
                                  Text('记录中，安静 30 秒后测 60 秒（10 分钟一次）', style: _rowSub),
                                ],
                              ),
                            ),
                            Switch(
                              key: const ValueKey<String>('mine-vitals-auto'),
                              value: av.enabled,
                              activeTrackColor: WaterColors.aqua,
                              onChanged: (bool v) => m.setVitals(enabled: v),
                            ),
                          ],
                        ),
                      ),
                      _SettingsRow(
                        last: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('测心率的传感器', style: _rowTitle),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: <Widget>[
                                for (final MapEntry<String, String> e in _sensors.entries)
                                  ChoiceChip(
                                    key: ValueKey<String>('mine-sensor-${e.key}'),
                                    label: Text(e.value),
                                    selected: av.sensor == e.key,
                                    onSelected: (_) => m.setVitals(sensor: e.key),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
              ],
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
                            Expanded(child: Text(lang.nativeName, style: _rowTitle)),
                            if (lang == localeController.language)
                              const Icon(Icons.check, size: 18, color: WaterColors.aqua),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionLabel(strings.dataSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  _SettingsRow(
                    last: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(strings.storageLocationLabel, style: _rowTitle),
                        const SizedBox(height: 2),
                        Text(strings.storageLocationDesc, style: _rowSub),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // 开发：記録・テスト画面（T34）、每天（旧：生の数字を見る）、CNN の推理速度（T24）。
              const _SectionLabel('开发'),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  if (m != null)
                    _SettingsRow(
                      child: _LinkRow(
                        key: const ValueKey<String>('open-recording'),
                        icon: Icons.fiber_manual_record_outlined,
                        title: '记录・测试（T34）',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (BuildContext _) => RecordingPage(monitor: m)),
                        ),
                      ),
                    ),
                  if (m != null)
                    _SettingsRow(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('行为的 CNN', style: _rowTitle),
                          Text(m.running ? '记录中不能换（停止以后再换）' : 'v2 的舔・挠・颤抖是用模拟数据学的（试用）',
                              style: _rowSub),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: <Widget>[
                              for (final CnnVersion v in CnnVersion.values)
                                ChoiceChip(
                                  key: ValueKey<String>('mine-cnn-${v.name}'),
                                  label: Text(v.label),
                                  selected: m.runner.cnnVersion == v,
                                  onSelected: m.running || m.starting ? null : (_) => m.setCnnVersion(v),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (liveSummary != null)
                    _SettingsRow(
                      child: _LinkRow(
                        key: const ValueKey<String>('open-daily-old'),
                        icon: Icons.today_outlined,
                        title: '每天（旧：原始数字，T34）',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext _) => Scaffold(
                              appBar: AppBar(title: const Text('每天（旧）')),
                              body: DailySummaryPage(live: liveSummary),
                            ),
                          ),
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
                    Text(strings.appTitle, style: const TextStyle(fontSize: 11.5, color: WaterColors.sub)),
                    const SizedBox(height: 2),
                    const Text('version 0.1.0', style: TextStyle(fontSize: 11, color: WaterColors.sub)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 自動測定のセンサー（front＝基板の IMU、side＝BMI088）。
const Map<String, String> _sensors = <String, String>{'front': '基板 IMU（front）', 'side': 'BMI088（side）'};

const TextStyle _rowTitle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: WaterColors.text);
const TextStyle _rowSub = TextStyle(fontSize: 11, color: WaterColors.sub);

/// 狗的信息：名前・犬種・体重・首輪の位置（编辑は记录・测试と同じダイアログ）。
class _DogCard extends StatelessWidget {
  const _DogCard({required this.subject, required this.onEdit});

  final TestSubject subject;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final TestSubject s = subject;
    final String sub = <String>[
      if (s.breed.isNotEmpty) s.breed,
      if (s.weightKg != null) '${s.weightKg} kg',
      collarPositions[s.position] ?? s.position,
    ].join('・');
    return Container(
      key: const ValueKey<String>('mine-dog'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: glassCard(),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: <Color>[Color(0xFFBFF4FF), Color(0xFF49B6E0)]),
            ),
            child: const Icon(Icons.pets, color: Color(0xFF03304D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.name.isEmpty ? '还没有填狗的名字' : s.name,
                    key: const ValueKey<String>('mine-dog-name'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: WaterColors.text)),
                const SizedBox(height: 2),
                Text('项圈：$sub', style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey<String>('mine-dog-edit'),
            onPressed: onEdit,
            child: const Text('修改'),
          ),
        ],
      ),
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
          Icon(icon, size: 16, color: WaterColors.aqua),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: _rowTitle)),
          const Icon(Icons.chevron_right, size: 18, color: WaterColors.sub),
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
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WaterColors.sub)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: glassCard(),
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
        border: last ? null : const Border(bottom: BorderSide(color: WaterColors.line)),
      ),
      child: child,
    );
  }
}
