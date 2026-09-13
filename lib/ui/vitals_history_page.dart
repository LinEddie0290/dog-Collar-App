import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/measurement_record.dart';
import '../data/measurement_store.dart';
import '../l10n/app_strings.dart';
import 'app_colors.dart';
import 'widgets/beat_chart.dart';
import 'widgets/export_button.dart';
import 'widgets/sparkline.dart';

/// 測定履歴。獣医に渡す前提で、数値と一緒に「その測定が信頼できるか」を出す。
class VitalsHistoryPage extends StatefulWidget {
  const VitalsHistoryPage({super.key, required this.store});

  final MeasurementStore store;

  @override
  State<VitalsHistoryPage> createState() => _VitalsHistoryPageState();
}

class _VitalsHistoryPageState extends State<VitalsHistoryPage> {
  List<MeasurementRecord>? _records;
  List<({DateTime day, double meanBpm, int count})> _daily =
      const <({DateTime day, double meanBpm, int count})>[];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<MeasurementRecord> rs = await widget.store.loadAll();
      final List<({DateTime day, double meanBpm, int count})> d =
          await widget.store.dailyMeans();
      if (!mounted) return;
      setState(() {
        _records = rs;
        _daily = d;
        _error = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _export(AppStrings s) async {
    final String csv = await widget.store.exportCsv();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.csvCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    final List<MeasurementRecord>? rs = _records;

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${s.historyLoadFailed}: $_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    if (rs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(s.noRecordsYet,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.7, color: AppColors.textSecondary)),
        ),
      );
    }

    // 使える測定が2件以上あるときだけ推移を出す。1点の折れ線は意味を持たない。
    final bool showTrend = _daily.length >= 2;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: <Widget>[
          if (showTrend) ...<Widget>[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(s.dailyMeanTitle,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  Text('${_daily.length} ${s.daysCount}　${s.dailyMeanNote}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textFaint)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 74,
                    child: Sparkline(
                      values: _daily
                          .map((({DateTime day, double meanBpm, int count}) e) =>
                              e.meanBpm)
                          .toList(growable: false),
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_ymd(_daily.first.day),
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textFaint)),
                      Text(
                          '${_daily.first.meanBpm.round()} → '
                          '${_daily.last.meanBpm.round()} bpm',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                      Text(_ymd(_daily.last.day),
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textFaint)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: Text('${rs.length} ${s.measurementCount}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              TextButton.icon(
                onPressed: () => _export(s),
                icon: const Icon(Icons.ios_share, size: 16),
                label: Text(s.exportCsvForVet,
                    style: const TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...rs.map((MeasurementRecord r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecordTile(
                    record: r, onChanged: _load, store: widget.store),
              )),
        ],
      ),
    );
  }
}

String _ymd(DateTime d) => '${d.month}/${d.day}';
String _stamp(DateTime d) =>
    '${d.year}/${d.month}/${d.day} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 記録の注意書きを表示言語で返す。判定は [MeasurementRecord.caveatCode]
/// に置いてあるので、ここは文言を選ぶだけ。
String? _caveatText(AppStrings s, MeasurementRecord r) => switch (r.caveatCode) {
      'unusable' => s.caveatUnusable,
      'fair' => s.caveatFair,
      'gaps' => s.caveatManyGaps,
      _ => null,
    };

class _RecordTile extends StatefulWidget {
  const _RecordTile(
      {required this.record, required this.onChanged, required this.store});
  final MeasurementRecord record;
  final Future<void> Function() onChanged;
  final MeasurementStore store;

  @override
  State<_RecordTile> createState() => _RecordTileState();
}

class _RecordTileState extends State<_RecordTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    final MeasurementRecord r = widget.record;
    final (Color color, IconData icon, String qLabel) = switch (r.quality) {
      'good' => (AppColors.connected, Icons.check_circle, s.qualityGood),
      'fair' => (AppColors.accent2, Icons.error_outline, s.qualityFair),
      _ => (AppColors.accent, Icons.cancel, s.qualityUnusable),
    };
    final String? caveat = _caveatText(s, r);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(r.heartRateBpm?.round().toString() ?? '--',
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 4),
                        const Text('bpm',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                    Text(_stamp(r.startedAt),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary)),
                  ],
                ),
                const Spacer(),
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(qLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
                const SizedBox(width: 6),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: AppColors.textFaint),
              ],
            ),
          ),
          if (_open) ...<Widget>[
            const Divider(height: 20, color: AppColors.divider),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: <Widget>[
                _M(s.durationLabel,
                    '${r.durationSeconds.toStringAsFixed(0)} ${s.secondsUnit}'),
                _M(s.respirationShort,
                    '${r.respirationPerMin?.toStringAsFixed(0) ?? "--"} ${s.breathsPerMinUnit}'),
                if (r.bodyTempC != null)
                  _M(s.bodyTempLabel,
                      '${r.bodyTempC!.toStringAsFixed(1)} ${s.celsiusUnit}'),
                _M(s.beatCountLabel, '${r.beatCount}'),
                _M(s.beatCvLabel,
                    '${r.beatIntervalCvPercent?.toStringAsFixed(1) ?? "--"} %'),
                _M('SDNN', '${r.sdnnMs?.toStringAsFixed(0) ?? "--"} ms'),
                _M('RMSSD', '${r.rmssdMs?.toStringAsFixed(0) ?? "--"} ms'),
                _M(s.droppedPackets, '${r.gapCount}'),
                if (r.imuRateHz != null)
                  _M(s.measuredRate, '${r.imuRateHz} Hz'),
              ],
            ),
            if (caveat != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(caveat,
                    style: TextStyle(fontSize: 12, height: 1.5, color: color)),
              ),
            if (r.posture != null || r.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    <String>[
                      if (r.posture != null) '${s.postureLabel}: ${r.posture}',
                      if (r.note != null) r.note!,
                    ].join('　'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            if (r.beatIntervalsMs.length >= 3) ...<Widget>[
              const SizedBox(height: 14),
              Text(s.beatIntervalsTitle,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              BeatIntervalChart(
                  intervalsMs: r.beatIntervalsMs,
                  height: 96,
                  emptyLabel: s.noDataYet),
            ],
            const SizedBox(height: 10),
            // 1件ずつ書き出す。履歴全体のCSVとは別で、これが「獣医に渡す1枚」。
            Text(s.exportThisRecord,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
            Align(
              alignment: Alignment.centerLeft,
              child: RecordExportButton(record: r, compact: true),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await widget.store.delete(r.id);
                  await widget.onChanged();
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label:
                    Text(s.deleteRecord, style: const TextStyle(fontSize: 12)),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.textFaint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _M extends StatelessWidget {
  const _M(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}
