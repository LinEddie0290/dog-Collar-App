import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/daily_summary.dart';
import '../data/health_items.dart';
import '../data/home_snapshot.dart';
import '../l10n/summary_text.dart';
import '../state/collar_link.dart';
import '../state/continuous_monitor.dart';
import 'health/board_page.dart';
import 'home/board_sheet.dart';
import 'home/water_background.dart';
import 'home/water_bubble.dart';
import 'home/water_ripples.dart';
import 'home/water_style.dart';
import 'recording_page.dart';

/// 「今天」タブ（T35）：白い水のホーム。
/// 真ん中＝今の状態（押すと 记录・测试）、まわりに六大板块の泡（押すと波紋と簡単な詳細）、下に今日の提醒。
/// 画面イメージ：首輪開発計画/03_設計メモ/T35_画面イメージ/ホーム画面イメージ_v1_白。文言は中国語だけ。
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.live, this.monitor, this.link, this.clock = DateTime.now, this.onOpenEcg});

  /// 本物の 1 日まとめ（スマホで計算した結果）。null なら本物はない。
  final SummarySource? live;

  /// 記録（今の状態）。null なら「没有在记录」。
  final ContinuousMonitor? monitor;
  final CollarLink? link;
  final DateTime Function() clock;

  /// 板块のページの「像心电图的波形」から「测定」の記録を開く。
  final VoidCallback? onOpenEcg;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const SummaryTextZh _t = SummaryTextZh();
  final GlobalKey<WaterRipplesState> _ripples = GlobalKey<WaterRipplesState>();

  SummaryBundle? _bundle;
  bool _demo = false;
  int _loadNo = 0;

  @override
  void initState() {
    super.initState();
    widget.live?.changes?.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(TodayPage old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) {
      old.live?.changes?.removeListener(_load);
      widget.live?.changes?.addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    widget.live?.changes?.removeListener(_load);
    super.dispose();
  }

  /// 本物の 1 日まとめを読む。読めなければ「本物なし」（落とさない）。古い読み込みの結果は捨てる。
  Future<void> _load() async {
    final int no = ++_loadNo;
    final SummarySource? live = widget.live;
    SummaryBundle? b;
    if (live != null) {
      try {
        b = await live.load();
      } catch (_) {
        b = null;
      }
    }
    if (!mounted || no != _loadNo) return;
    setState(() => _bundle = b);
  }

  /// [today] の 1 日まとめ（なければ null）。
  DailySummary? _summaryOn(String today) {
    for (final DayEntry d in _bundle?.days ?? const <DayEntry>[]) {
      if (d.date == today) return d.summary;
    }
    return null;
  }

  /// 「查看更多」：その板块のページ（健康タブと同じもの）。
  void _openBoard(Board board) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => BoardPage(
        board: board,
        today: todayKey(widget.clock()),
        real: _bundle,
        demoAll: _demo,
        onOpenEcg: widget.onOpenEcg,
      ),
    ));
  }

  NowLine _nowLine() {
    final ContinuousMonitor? m = widget.monitor;
    if (m == null) return nowLine(recording: false);
    return nowLine(
      recording: m.running,
      starting: m.starting,
      states: m.runner.session?.states ?? const [],
    );
  }

  void _openRecording() {
    final ContinuousMonitor? m = widget.monitor;
    if (m == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => RecordingPage(monitor: m)));
  }

  @override
  Widget build(BuildContext context) {
    final ContinuousMonitor? m = widget.monitor;
    final List<Listenable> ls = <Listenable>[
      if (m != null) ...<Listenable>[m, m.runner],
      if (widget.link != null) widget.link!,
    ];
    return WaterBackground(
      child: AnimatedBuilder(
        animation: Listenable.merge(ls),
        builder: (BuildContext context, Widget? _) {
          final DateTime now = widget.clock();
          final String today = todayKey(now);
          final HomeSnapshot snap =
              buildHomeSnapshot(date: today, real: _summaryOn(today), rawToday: _bundle?.raw[today], demoAll: _demo);
          return SingleChildScrollView(
            key: const ValueKey<String>('today-page'),
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: <Widget>[
                      _Header(
                          name: m?.subject.name ?? '', breed: m?.subject.breed ?? '', connected: widget.link?.isConnected),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          _DemoChip(
                            on: _demo,
                            onTap: () => setState(() => _demo = !_demo),
                          ),
                          const Spacer(),
                          Text(_dateLabel(now), style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 泡は画面の幅いっぱいを使う（左右の余白なし）
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) => _Stage(
                    width: c.maxWidth,
                    snap: snap,
                    now: _nowLine(),
                    footer: _t.alertsToday(snap.alerts.length),
                    ripples: _ripples,
                    onBubble: (BubbleData b) => showBoardSheet(context, b, onMore: () => _openBoard(b.board)),
                    onCore: _openRecording,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _AlertCard(alerts: snap.alerts),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 11月5日 星期四（その土地の日付：1 日まとめと同じ UTC＋8）。
String _dateLabel(DateTime now) {
  final DateTime d = now.toUtc().add(const Duration(hours: 8));
  const List<String> w = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${d.month}月${d.day}日 星期${w[d.weekday - 1]}';
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.breed, required this.connected});

  final String name;
  final String breed;

  /// null なら首輪の表示を出さない。
  final bool? connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: <Color>[Color(0xFFBFF4FF), Color(0xFF49B6E0)]),
            boxShadow: <BoxShadow>[BoxShadow(color: Color(0x5928AADC), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.pets, size: 22, color: Color(0xFF03304D)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(name.isEmpty ? '我的狗' : name,
                  key: const ValueKey<String>('home-dog-name'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: WaterColors.text)),
              if (breed.isNotEmpty) Text(breed, style: const TextStyle(fontSize: 12, color: WaterColors.sub)),
            ],
          ),
        ),
        if (connected != null)
          Container(
            key: const ValueKey<String>('home-collar-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              border: Border.all(color: WaterColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected! ? const Color(0xFF22C58B) : WaterColors.demo,
                  ),
                ),
                const SizedBox(width: 6),
                Text(connected! ? '项圈已连接' : '项圈未连接',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1D6A8A))),
              ],
            ),
          ),
      ],
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey<String>('home-demo-toggle'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? const Color(0x99FFF0D7) : Colors.white.withValues(alpha: 0.5),
          border: Border.all(color: on ? const Color(0x73C88228) : WaterColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(on ? '演示中（全部示例）' : '演示',
            style: TextStyle(fontSize: 11, color: on ? const Color(0xFFB8741C) : WaterColors.sub)),
      ),
    );
  }
}

/// 真ん中の球と 6 つの泡。幅に合わせて大きさを決める（幅 390 で 泡 96・軌道の半径 143・真ん中 164）。
class _Stage extends StatelessWidget {
  const _Stage({
    required this.width,
    required this.snap,
    required this.now,
    required this.footer,
    required this.ripples,
    required this.onBubble,
    required this.onCore,
  });

  final double width;
  final HomeSnapshot snap;
  final NowLine now;
  final String footer;
  final GlobalKey<WaterRipplesState> ripples;
  final void Function(BubbleData b) onBubble;
  final VoidCallback onCore;

  @override
  Widget build(BuildContext context) {
    final double bubble = math.min(96, width * 0.27);
    final double r = math.min(146, width / 2 - bubble / 2 - 4);
    final double core = math.min(164, 2 * (r - bubble / 2 - 6));
    final double height = 2 * r + bubble + 8;
    final Offset c = Offset(width / 2, height / 2);
    final List<double> angles = <double>[
      for (int i = 0; i < Board.values.length; i++) (-90 + i * 60) * math.pi / 180,
    ];

    return WaterRipples(
      key: ripples,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: OrbitPainter(
                  center: c,
                  innerRadius: r,
                  outerRadius: r + bubble * 0.42,
                  spokes: <Spoke>[
                    for (int i = 0; i < snap.bubbles.length; i++)
                      Spoke(
                        angle: angles[i],
                        color: boardColor(snap.bubbles[i].board),
                        from: core / 2 + 4,
                        to: r - bubble / 2 - 4,
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: c.dx - core / 2,
              top: c.dy - core / 2,
              child: CoreBubble(
                now: now,
                footer: footer,
                size: core,
                onPressStart: () => ripples.currentState?.add(c, WaterColors.aqua, startRadius: core / 2, spread: 90),
                onTap: onCore,
              ),
            ),
            for (int i = 0; i < snap.bubbles.length; i++)
              () {
                final BubbleData b = snap.bubbles[i];
                final Offset p = c + Offset(math.cos(angles[i]), math.sin(angles[i])) * r;
                return Positioned(
                  left: p.dx - bubble / 2,
                  top: p.dy - bubble / 2,
                  child: WaterBubble(
                    data: b,
                    size: bubble,
                    onPressStart: () =>
                        ripples.currentState?.add(p, boardColor(b.board), startRadius: bubble / 2),
                    onTap: () => onBubble(b),
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}

/// 今日の提醒（板块の順）。なければ「今天没有提醒」。
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alerts});

  final List<BubbleData> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('home-alert-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: WaterColors.card,
        border: Border.all(color: WaterColors.line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x1F28789F), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('今天的提醒', style: TextStyle(fontSize: 12, color: WaterColors.sub)),
          const SizedBox(height: 6),
          if (alerts.isEmpty)
            const Text('今天没有提醒', style: TextStyle(fontSize: 15, color: WaterColors.text))
          else
            for (final BubbleData a in alerts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 8, color: WaterColors.alert),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${a.name}：${a.alert}${a.demo ? '（示例）' : ''}',
                          style: const TextStyle(fontSize: 15, color: WaterColors.text)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
