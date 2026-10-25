import 'package:flutter/material.dart';

import '../data/daily_summary.dart';
import '../l10n/summary_text.dart';
import 'app_colors.dart';
import 'widgets/sparkline.dart';

/// 「每天」画面(T23 デモ版 → T16 で完成させる)。
/// パイプラインの 1日まとめ JSON を読み、4 枚のカード(运动・睡眠・皮肤・生理)を出す。
/// 日を前後に動かせる。提醒は黄色(notice)。赤は使わない(診断ではないので)。
class DailySummaryPage extends StatefulWidget {
  DailySummaryPage({super.key, DemoSummaryRepository? repository})
      : repository = repository ?? DemoSummaryRepository();

  final DemoSummaryRepository repository;

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  static const SummaryTextZh _t = SummaryTextZh();
  late final Future<SummaryBundle> _future = widget.repository.load();
  int? _index; // 見ている日。最初は最新の日

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SummaryBundle>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<SummaryBundle> snap) {
        if (snap.hasError) {
          return Center(child: Text('${_t.unreadable}\n${snap.error}', textAlign: TextAlign.center));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final SummaryBundle b = snap.data!;
        if (b.days.isEmpty) {
          return Center(child: Text(_t.unreadable));
        }
        final int last = b.days.length - 1;
        final int want = _index ?? last;
        final int i = want < 0 ? 0 : (want > last ? last : want);
        return _body(context, b, i);
      },
    );
  }

  Widget _body(BuildContext context, SummaryBundle b, int i) {
    final DayEntry day = b.days[i];
    final DailySummary? s = day.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        Text(
          _t.pageTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(_t.demoNote, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
        const SizedBox(height: 12),
        _DayBar(
          dayLabel: _t.dayLabel(i + 1),
          date: day.date,
          sub: s == null ? _t.unreadable : _t.alertsToday(s.alertCount),
          onPrev: i > 0 ? () => setState(() => _index = i - 1) : null,
          onNext: i < b.days.length - 1 ? () => setState(() => _index = i + 1) : null,
          prevLabel: _t.prevDay,
          nextLabel: _t.nextDay,
        ),
        const SizedBox(height: 12),
        if (s == null)
          _Card(icon: Icons.error_outline, title: day.date, lines: <String>[_t.unreadable])
        else
          for (final CategorySummary c in s.ordered) ...<Widget>[
            _categoryCard(c),
            const SizedBox(height: 10),
          ],
        if (b.history.length >= 2) ...<Widget>[
          const SizedBox(height: 8),
          _Trends(history: b.history, selected: day.date, t: _t),
        ],
      ],
    );
  }

  Widget _categoryCard(CategorySummary c) {
    final List<String> lines = <String>[];
    switch (c.status) {
      case SummaryStatus.noData:
        lines.add(_t.noData);
        break;
      case SummaryStatus.collecting:
      case SummaryStatus.ok:
      case SummaryStatus.unknown:
        if (c.daily != null) {
          lines.add(_t.daily(c.daily!));
        } else if (c.id == 'skin' && c.status == SummaryStatus.ok && c.alert == null) {
          lines.add(_t.skinOk);
        }
        if (c.status == SummaryStatus.collecting) {
          lines.add(_t.collecting(c.daysUntilCompare));
        }
    }
    return _Card(
      key: ValueKey<String>('card-${c.id}'),
      icon: _icon(c.id),
      title: _t.title(c.id),
      lines: lines,
      alert: c.alert == null ? null : _t.alert(c.alert!),
      alertFoot: _t.notDiagnosis,
    );
  }

  IconData _icon(String id) {
    switch (id) {
      case 'exercise':
        return Icons.directions_walk;
      case 'sleep':
        return Icons.bedtime_outlined;
      case 'skin':
        return Icons.pets;
      case 'physio':
        return Icons.favorite_outline;
      default:
        return Icons.circle_outlined;
    }
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.dayLabel,
    required this.date,
    required this.sub,
    required this.onPrev,
    required this.onNext,
    required this.prevLabel,
    required this.nextLabel,
  });

  final String dayLabel;
  final String date;
  final String sub;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String prevLabel;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('prev-day'),
            tooltip: prevLabel,
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text('$dayLabel　$date',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('next-day'),
            tooltip: nextLabel,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// 提醒の色(notice)。黄色系で、赤(危険)には寄せない。
const Color _alertBg = Color(0xFFFFF4D6);
const Color _alertLine = AppColors.accent2;

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
    this.alert,
    this.alertFoot,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final String? alert;
  final String? alertFoot;

  @override
  Widget build(BuildContext context) {
    final bool hasAlert = alert != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: hasAlert ? _alertLine : AppColors.border, width: hasAlert ? 1.5 : 1),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (hasAlert)
            Container(
              color: _alertBg,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(alert!,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (alertFoot != null)
                          Text(alertFoot!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: 22, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      for (final String l in lines)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(l, style: const TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Trends extends StatelessWidget {
  const _Trends({required this.history, required this.selected, required this.t});

  final List<HistoryDay> history;
  final String selected;
  final SummaryTextZh t;

  @override
  Widget build(BuildContext context) {
    // 見ている日までを出す(先の日は見せない)。
    final List<HistoryDay> upto = history.where((HistoryDay d) => d.date.compareTo(selected) <= 0).toList();
    Widget line(String label, List<double> values) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              SizedBox(height: 44, child: Sparkline(values: values, color: AppColors.accent)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(t.trendTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          line(t.trendExercise, upto.map((HistoryDay d) => d.activeMin).whereType<double>().toList()),
          line(t.trendSleep, upto.map((HistoryDay d) => d.sleepMin).whereType<double>().toList()),
        ],
      ),
    );
  }
}
