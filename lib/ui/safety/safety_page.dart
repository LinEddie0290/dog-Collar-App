/// T35「安全」タブ：今の安全の状態（実際）／地図／緊急の 4 項目（示例）／最近 7 日の緊急の記録（示例）。
/// 見た目はホーム・健康と同じ白い水。設計メモ：T35_安全・我的タブ。文言は中国語だけ。
library;

import 'package:flutter/material.dart';

import '../../data/home_snapshot.dart' show todayKey;
import '../../data/safety.dart';
import '../../state/collar_link.dart';
import '../../state/continuous_monitor.dart';
import '../health/health_text.dart' show shortDate;
import '../home/water_background.dart';
import '../home/water_style.dart';

IconData emergencyIcon(EmergencyKind k) => switch (k) {
      EmergencyKind.fall => Icons.airline_seat_flat_outlined,
      EmergencyKind.heart => Icons.monitor_heart_outlined,
      EmergencyKind.lost => Icons.wrong_location_outlined,
      EmergencyKind.impact => Icons.flash_on_outlined,
    };

class SafetyPage extends StatelessWidget {
  const SafetyPage({super.key, this.monitor, this.link, this.map, this.clock = DateTime.now});

  final ContinuousMonitor? monitor;
  final CollarLink? link;

  /// 地図（RootShell から MapPage を渡す）。null なら「地图」の案内だけ。
  final Widget? map;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final ContinuousMonitor? m = monitor;
    final List<Listenable> ls = <Listenable>[
      if (m != null) ...<Listenable>[m, m.runner],
      ?link,
    ];
    return WaterBackground(
      child: AnimatedBuilder(
        animation: Listenable.merge(ls),
        builder: (BuildContext context, Widget? _) {
          final DateTime now = clock();
          final int nowMs = now.millisecondsSinceEpoch;
          final bool recording = m?.running ?? false;
          final int? last = m?.runner.lastReceivedMs;
          final List<EmergencyEvent> events = demoEmergencyEvents(todayKey(now));
          return ListView(
            key: const ValueKey<String>('safety-page'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Text('安全', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: WaterColors.text)),
                  SizedBox(width: 10),
                  Text('位置・紧急', style: TextStyle(fontSize: 12, color: WaterColors.sub)),
                ],
              ),
              const SizedBox(height: 12),
              // 今の状態（実際）
              Container(
                key: const ValueKey<String>('safety-status'),
                padding: const EdgeInsets.all(14),
                decoration: glassCard(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _StatusRow(
                      icon: Icons.sensors,
                      text: collarStatusLine(
                          connected: link?.isConnected, recording: recording, lastReceivedMs: last, nowMs: nowMs),
                      warn: dataStale(recording: recording, lastReceivedMs: last, nowMs: nowMs),
                    ),
                    const _StatusRow(icon: Icons.place_outlined, text: '位置：GPS 还没有（T12）'),
                    const _StatusRow(icon: Icons.home_outlined, text: '安全区：$homeFenceName（半径 $homeFenceRadiusM m）'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  key: const ValueKey<String>('safety-map'),
                  height: 200,
                  child: map != null
                      ? DecoratedBox(decoration: glassCard(), child: map)
                      : Container(
                        decoration: glassCard(),
                        alignment: Alignment.center,
                        child: const Text('地图（需要设置高德地图的 key）',
                            style: TextStyle(fontSize: 12, color: WaterColors.sub)),
                      ),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: <Widget>[
                  Text('紧急', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WaterColors.text)),
                  SizedBox(width: 8),
                  Text('示例（判断还在做，T34-G）', style: TextStyle(fontSize: 11, color: WaterColors.demo)),
                ],
              ),
              const SizedBox(height: 8),
              for (final EmergencySpec s in emergencySpecs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EmergencyTile(
                    spec: s,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (BuildContext _) => EmergencyPage(
                        spec: s,
                        events: events.where((EmergencyEvent e) => e.kind == s.kind).toList(),
                      ),
                    )),
                  ),
                ),
              const SizedBox(height: 12),
              const Text('最近 7 天的紧急记录（示例）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WaterColors.sub)),
              const SizedBox(height: 6),
              Container(
                key: const ValueKey<String>('safety-events'),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: glassCard(),
                child: events.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('最近 7 天没有紧急情况', style: TextStyle(fontSize: 14, color: WaterColors.text)),
                      )
                    : Column(children: <Widget>[for (final EmergencyEvent e in events) EventRow(event: e)]),
              ),
              const SizedBox(height: 12),
              const Text('「示例」是假的数据，不是这只狗的。这不是诊断。',
                  style: TextStyle(fontSize: 11, color: WaterColors.sub)),
            ],
          );
        },
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.text, this.warn = false});

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: warn ? WaterColors.alert : WaterColors.aqua),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: WaterColors.text))),
          if (warn)
            const Text('注意', key: ValueKey<String>('safety-stale'), style: TextStyle(fontSize: 12, color: WaterColors.alert)),
        ],
      ),
    );
  }
}

class _EmergencyTile extends StatelessWidget {
  const _EmergencyTile({required this.spec, required this.onTap});

  final EmergencySpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('emergency-${spec.kind.name}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: glassCard(radius: 18),
          child: Row(
            children: <Widget>[
              Icon(emergencyIcon(spec.kind), color: WaterColors.alert),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(spec.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WaterColors.text)),
                    const SizedBox(height: 2),
                    Text(spec.how,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: WaterColors.value)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Text('示例', style: TextStyle(fontSize: 11, color: WaterColors.demo)),
              const Icon(Icons.chevron_right, size: 18, color: WaterColors.sub),
            ],
          ),
        ),
      ),
    );
  }
}

/// 緊急の記録の 1 行：日付・時刻・種類・何があったか・どうなったか。
class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.event});

  final EmergencyEvent event;

  @override
  Widget build(BuildContext context) {
    final EmergencyEvent e = event;
    return Padding(
      key: ValueKey<String>('event-${e.date}-${e.kind.name}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text('${shortDate(e.date)}\n${e.timeText}',
                style: const TextStyle(fontSize: 11, color: WaterColors.sub, height: 1.3)),
          ),
          Icon(emergencyIcon(e.kind), size: 18, color: WaterColors.alert),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${emergencySpec(e.kind).name}：${e.detail}',
                    style: const TextStyle(fontSize: 13.5, color: WaterColors.text)),
                Text(e.outcome, style: const TextStyle(fontSize: 12, color: WaterColors.value)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 緊急の 1 項目のページ：怎么判断・看什么・为什么重要・数据从哪里来・最近 7 天的记录。
class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key, required this.spec, this.events = const <EmergencyEvent>[]});

  final EmergencySpec spec;
  final List<EmergencyEvent> events;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WaterColors.bgTop,
      appBar: AppBar(
        title: Text(spec.name, style: const TextStyle(fontSize: 17, color: WaterColors.text)),
        backgroundColor: WaterColors.bgTop,
        surfaceTintColor: Colors.transparent,
        foregroundColor: WaterColors.text,
      ),
      body: WaterBackground(
        child: ListView(
          key: ValueKey<String>('emergency-page-${spec.kind.name}'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: <Widget>[
            const Text('示例（判断还在做）', style: TextStyle(fontSize: 12, color: WaterColors.demo)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: glassCard(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Info('怎么判断', spec.how),
                  _Info('看什么', spec.what),
                  _Info('为什么重要', spec.why),
                  _Info('数据从哪里来', spec.source),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('最近 7 天（示例）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WaterColors.sub)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: glassCard(),
              child: events.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('最近 7 天没有', style: TextStyle(fontSize: 14, color: WaterColors.text)),
                    )
                  : Column(children: <Widget>[for (final EmergencyEvent e in events) EventRow(event: e)]),
            ),
            const SizedBox(height: 12),
            const Text('这不是诊断。如果担心，请问兽医。', style: TextStyle(fontSize: 11, color: WaterColors.sub)),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WaterColors.sub)),
          const SizedBox(height: 2),
          Text(text, style: const TextStyle(fontSize: 14, color: WaterColors.text)),
        ],
      ),
    );
  }
}
