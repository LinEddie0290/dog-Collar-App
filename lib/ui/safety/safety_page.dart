/// T35「安全」タブ：今の安全の状態（実際）／地図／緊急の 4 項目／最近 7 日の緊急の記録。
/// 走失は T36、冲击・倒下・心率异常は T34-G で本物。見張りが渡されていない項目は示例。
/// 見た目はホーム・健康と同じ白い水。設計メモ：T35_安全・我的タブ。文言は中国語だけ。
library;

import 'package:flutter/material.dart';

import '../../data/home_snapshot.dart' show todayKey;
import '../../data/safe_zone.dart';
import '../../data/safety.dart';
import '../../state/collar_link.dart';
import '../../state/continuous_monitor.dart';
import '../../state/emergency_controller.dart';
import '../../state/location_controller.dart';
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
  const SafetyPage(
      {super.key, this.monitor, this.link, this.location, this.emergency, this.map, this.clock = DateTime.now});

  final ContinuousMonitor? monitor;
  final CollarLink? link;

  /// T36：位置と安全区。null なら位置は「还没有」、走失は示例のまま。
  final LocationController? location;

  /// T34-G：冲击・倒下・心率异常。null なら [monitor] の見張り、それもなければ示例。
  final EmergencyController? emergency;

  /// 地図（RootShell から MapPage を渡す）。null なら「地图」の案内だけ。
  final Widget? map;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final ContinuousMonitor? m = monitor;
    final EmergencyController? em = emergency ?? m?.emergency;
    final List<Listenable> ls = <Listenable>[
      if (m != null) ...<Listenable>[m, m.runner],
      ?link,
      ?location,
      ?em,
    ];
    return WaterBackground(
      child: AnimatedBuilder(
        animation: Listenable.merge(ls),
        builder: (BuildContext context, Widget? _) {
          final DateTime now = clock();
          final int nowMs = now.millisecondsSinceEpoch;
          final bool recording = m?.running ?? false;
          final int? last = m?.runner.lastReceivedMs;
          final LocationController? lc = location;
          final String today = todayKey(now);
          // 走失は本物（T36）。ほかの 3 つは示例のまま（T34-G で本物に）
          // 本物の項目は本物の記録だけ、ほかは示例
          bool real(EmergencyKind k) => k == EmergencyKind.lost ? lc != null : em != null;
          final List<EmergencyEvent> events = <EmergencyEvent>[
            if (lc != null) ...zoneEmergencyEvents(lc.events, today),
            if (em != null) ...hitEmergencyEvents(em.hits, today),
            ...demoEmergencyEvents(today).where((EmergencyEvent e) => !real(e.kind)),
          ]..sort((EmergencyEvent a, EmergencyEvent b) =>
              b.date != a.date ? b.date.compareTo(a.date) : b.minuteOfDay.compareTo(a.minuteOfDay));
          final int nReal = EmergencyKind.values.where(real).length;
          final String note = switch (nReal) {
            0 => '示例',
            4 => '都是实际的（心率是试用）',
            _ when em == null => '走失是实际的，其他是示例',
            _ => '走失是示例，其他是实际的',
          };
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
                    _StatusRow(
                      key: const ValueKey<String>('safety-position'),
                      icon: Icons.place_outlined,
                      text: positionLine(
                        state: lc?.state ?? ZoneState.unknown,
                        distanceM: lc?.distanceM,
                        fixMs: lc?.lastFix?.tMs,
                        nowMs: nowMs,
                        hasZone: lc?.zone != null,
                        stale: lc?.isOffline ?? false,
                      ),
                      warn: lc?.state == ZoneState.lost,
                    ),
                    _StatusRow(icon: Icons.home_outlined, text: zoneLine(lc?.zone)),
                    // T12：今日の屋外の距離・時間（GPS）
                    if (lc?.todayOutdoorLine case final String line)
                      _StatusRow(key: const ValueKey<String>('safety-outdoor'), icon: Icons.directions_walk, text: line),
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
              Row(
                children: <Widget>[
                  const Text('紧急',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WaterColors.text)),
                  const SizedBox(width: 8),
                  Text(nReal == 0 ? '示例（判断还在做）' : note,
                      style: const TextStyle(fontSize: 11, color: WaterColors.demo)),
                ],
              ),
              const SizedBox(height: 8),
              for (final EmergencySpec s in emergencySpecs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EmergencyTile(
                    spec: s,
                    real: real(s.kind),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (BuildContext _) => EmergencyPage(
                        spec: s,
                        real: real(s.kind),
                        events: events.where((EmergencyEvent e) => e.kind == s.kind).toList(),
                      ),
                    )),
                  ),
                ),
              const SizedBox(height: 12),
              Text('最近 7 天的紧急记录（$note）',
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
  const _StatusRow({super.key, required this.icon, required this.text, this.warn = false});

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
  const _EmergencyTile({required this.spec, required this.onTap, this.real = false});

  final EmergencySpec spec;
  final VoidCallback onTap;

  /// 本物の判定（T36 の走失）。false なら「示例」。
  final bool real;

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
              Icon(emergencyIcon(spec.kind), color: WaterColors.aqua),
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
              Text(real ? '实际' : '示例', style: TextStyle(fontSize: 11, color: real ? WaterColors.aqua : WaterColors.demo)),
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
      key: ValueKey<String>(e.id ?? 'event-${e.date}-${e.kind.name}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text('${shortDate(e.date)}\n${e.timeText}',
                style: const TextStyle(fontSize: 11, color: WaterColors.sub, height: 1.3)),
          ),
          Icon(emergencyIcon(e.kind), size: 18, color: WaterColors.aqua),
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
  const EmergencyPage({super.key, required this.spec, this.events = const <EmergencyEvent>[], this.real = false});

  final EmergencySpec spec;
  final List<EmergencyEvent> events;

  /// 本物の判定（T36 の走失）。
  final bool real;

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
            Text(
                real
                    ? switch (spec.kind) {
                        EmergencyKind.lost => '实际（GPS＋项圈和手机的连接）',
                        EmergencyKind.heart => '实际（试用：自动测的心率还在验证）',
                        _ => '实际（项圈的 IMU，数字是暂定的）',
                      }
                    : '示例（判断还在做）',
                style: TextStyle(fontSize: 12, color: real ? WaterColors.aqua : WaterColors.demo)),
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
            Text(real ? '最近 7 天' : '最近 7 天（示例）',
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
