import 'package:collar_vitals/collar_vitals.dart';
import 'package:flutter/material.dart';

import '../data/measurement_record.dart';
import '../data/measurement_store.dart';
import '../l10n/app_strings.dart';
import '../l10n/error_text.dart';
import '../state/collar_link.dart';
import '../state/vitals_session.dart';
import 'app_colors.dart';
import 'devices_page.dart';
import 'vitals_history_page.dart';
import 'widgets/beat_chart.dart';
import 'widgets/export_button.dart';
import 'widgets/live_wave_chart.dart';

/// 心拍測定の画面。
///
/// 操作は中央のボタン1つに集約している。押すと接続 → 測定、もう一度押すと
/// 停止して切断し、また「測定を開始」に戻る。首輪画面は「どの首輪を使うか」を
/// 選ぶためのもので、接続の開始・停止はそちらでは行わない。操作の入口が
/// 2か所あると、片方でキャンセルしてももう片方の状態が残る不具合になる。
class MeasurePage extends StatelessWidget {
  const MeasurePage({super.key, required this.session, required this.link});

  final VitalsSession session;
  final CollarLink link;

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    // 接続と測定は別の持ち主なので両方を監視する。
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[session, link]),
      builder: (BuildContext context, Widget? _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _LinkBanner(link: link, session: session, s: s),
                const SizedBox(height: 14),
                _BigButton(session: session, link: link, s: s),
                const SizedBox(height: 20),
                if (session.errorMessage != null)
                  _ErrorCard(message: errorText(s, session.errorMessage)!)
                else if (link.errorMessage != null && !session.isBusy)
                  _ErrorCard(message: errorText(s, link.errorMessage)!),
                if (session.phase == SessionPhase.measuring)
                  _LiveCard(session: session, s: s),
                if (session.phase == SessionPhase.done &&
                    session.finalResult != null)
                  _ResultCard(
                    result: session.finalResult!,
                    record: session.savedRecord,
                    s: s,
                  ),
                if (session.phase == SessionPhase.idle &&
                    session.errorMessage == null &&
                    link.errorMessage == null)
                  _TipsCard(s: s),
                const SizedBox(height: 14),
                _FooterLink(store: session.store, s: s),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 接続状態のバナー。接続したら表記が「接続中」に変わり、右側に首輪の名前が出る。
/// タップすると首輪を選ぶ画面が開く。
class _LinkBanner extends StatelessWidget {
  const _LinkBanner(
      {required this.link, required this.session, required this.s});
  final CollarLink link;
  final VitalsSession session;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final bool connected = link.isConnected;
    final String? name = connected
        ? (link.targetName ?? 'PET-Sense')
        : link.selectedName;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (BuildContext _) => Scaffold(
          appBar: AppBar(title: Text(s.devicesTitle)),
          body: DevicesPage(link: link),
        ),
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: connected
              ? AppColors.connected.withValues(alpha: 0.09)
              : AppColors.surface,
          border: Border.all(
              color: connected ? AppColors.connected : AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(
                connected
                    ? Icons.bluetooth_connected
                    : session.isBusy
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_disabled,
                size: 18,
                color: connected ? AppColors.connected : AppColors.textFaint),
            const SizedBox(width: 9),
            Text(
              connected
                  ? s.collarConnectedTo
                  : session.isBusy
                      ? s.measureConnecting
                      : s.collarNotConnected,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color:
                      connected ? AppColors.connected : AppColors.textSecondary),
            ),
            const Spacer(),
            // 接続したら右側に首輪の名前。未接続でも選択済みなら薄く出す。
            if (name != null)
              Flexible(
                child: Text(
                  name,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: connected
                          ? AppColors.connected
                          : AppColors.textFaint),
                ),
              )
            else
              Text(s.collarChoose,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textFaint)),
            const Icon(Icons.chevron_right,
                size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// 中央のボタン。押すたびに開始と停止が入れ替わる。
class _BigButton extends StatelessWidget {
  const _BigButton(
      {required this.session, required this.link, required this.s});
  final VitalsSession session;
  final CollarLink link;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final bool measuring = session.phase == SessionPhase.measuring;
    final bool preparing = session.phase == SessionPhase.preparing;
    final bool analyzing = session.phase == SessionPhase.analyzing;

    final String label = measuring
        ? s.measureStop
        : preparing
            ? s.measurePleaseWait
            : analyzing
                ? s.measureAnalyzing
                : s.measureStart;

    final String? sub = measuring
        ? _mmss(session.elapsed)
        : preparing
            ? s.cancelAction
            : analyzing
                ? null
                : s.measureHint60s;

    final IconData icon = measuring
        ? Icons.stop_rounded
        : preparing
            ? Icons.bluetooth_searching
            : analyzing
                ? Icons.hourglass_bottom
                : Icons.favorite;

    // 外枠表示にするのは測定中と準備中。どちらも「もう一度押せば止まる」状態。
    final bool outlined = measuring || preparing;

    return GestureDetector(
      // 解析中だけは押させない（数十ミリ秒で終わる）。
      onTap: analyzing
          ? null
          : () => session.toggle(remoteId: link.selectedRemoteId),
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          gradient: outlined ? null : AppColors.heroGradient,
          color: outlined ? AppColors.surface : null,
          border:
              outlined ? Border.all(color: AppColors.accent, width: 2.5) : null,
          borderRadius: BorderRadius.circular(28),
          boxShadow: outlined
              ? null
              : <BoxShadow>[
                  BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 26,
                      offset: const Offset(0, 12)),
                ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (measuring)
              SizedBox(
                width: 128,
                height: 128,
                child: CircularProgressIndicator(
                  value: session.progress,
                  strokeWidth: 5,
                  color: AppColors.accent.withValues(alpha: 0.25),
                  backgroundColor: AppColors.border,
                ),
              ),
            if (preparing)
              const SizedBox(
                width: 128,
                height: 128,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: AppColors.border,
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon,
                    size: 42,
                    color:
                        outlined ? AppColors.accent : const Color(0xFFFFF7EF)),
                const SizedBox(height: 10),
                Text(label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: outlined
                          ? AppColors.accent
                          : const Color(0xFFFFF7EF),
                    )),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(sub,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                measuring ? FontWeight.w700 : FontWeight.w400,
                            color: outlined
                                ? AppColors.textSecondary
                                : const Color(0xFFFFF7EF)
                                    .withValues(alpha: 0.85))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _mmss(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.session, required this.s});
  final VitalsSession session;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final VitalsResult? r = session.liveResult;
    final double? fs = session.effectiveSampleRateHz;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(r?.heartRateBpm?.round().toString() ?? '--',
                  style: const TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              const Text('bpm',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const Spacer(),
              if (r != null) _QualityChip(quality: r.quality, s: s),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r == null
                ? s.liveStabilizing
                : '${s.respirationShort} '
                    '${r.respirationPerMin?.toStringAsFixed(0) ?? "--"}'
                    '　${s.recentWindowNote}',
            style:
                const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          // 数値が出るまで待たせない。波形は最初の数百ミリ秒から動き出す。
          if (session.liveWave.length > 8) ...<Widget>[
            const SizedBox(height: 12),
            Text(s.liveWaveTitle,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            LiveWaveChart(
              wave: session.liveWave,
              beatIndices: session.liveBeatIndices,
              seconds: session.liveWaveSeconds,
            ),
            const SizedBox(height: 4),
            Text(s.liveWaveHint,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textFaint)),
          ],
          if (fs != null && fs < VitalsAnalyzer.minSampleRateHz)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(s.rateTooLowWarning,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.accent)),
            ),
          const Divider(height: 22, color: AppColors.divider),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: <Widget>[
              _Metric(s.receivedSamples, '${session.sampleCount}'),
              if (fs != null)
                _Metric(s.measuredRate, '${fs.toStringAsFixed(0)} Hz'),
              _Metric(s.droppedPackets, '${session.gapCount}'),
            ],
          ),
          if (session.gapCount > 20)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(s.tooManyDropsWarning,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.accent)),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(
      {required this.result, required this.s, this.record});
  final VitalsResult result;
  final MeasurementRecord? record;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(result.heartRateBpm?.round().toString() ?? '--',
                  style: const TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              const Text('bpm',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const Spacer(),
              _QualityChip(quality: result.quality, s: s),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${result.durationSeconds.toStringAsFixed(0)}s / '
            '${result.beatCount} ${s.beatsDetectedIn}',
            style:
                const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          if (_caveatText(s, record) != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(_caveatText(s, record)!,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.accent)),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 22, color: AppColors.divider),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: <Widget>[
              _Metric(s.respirationShort,
                  result.respirationPerMin?.toStringAsFixed(0) ?? '--'),
              _Metric(s.beatCvLabel,
                  '${result.beatIntervalCvPercent?.toStringAsFixed(1) ?? "--"} %'),
              _Metric('SDNN', '${result.sdnnMs?.toStringAsFixed(0) ?? "--"} ms'),
              _Metric(
                  'RMSSD', '${result.rmssdMs?.toStringAsFixed(0) ?? "--"} ms'),
            ],
          ),
          const SizedBox(height: 16),
          Text(s.beatIntervalsTitle,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          BeatIntervalChart(
              intervalsMs: result.beatIntervalsMs, emptyLabel: s.noDataYet),
          if (record != null) ...<Widget>[
            const Divider(height: 20, color: AppColors.divider),
            Text(s.exportThisRecord,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            RecordExportButton(record: record!),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(s.notEcgDisclaimer,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.quality, required this.s});
  final VitalsQuality quality;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, IconData icon) = switch (quality) {
      VitalsQuality.good =>
        (s.qualityGood, AppColors.connected, Icons.check_circle),
      VitalsQuality.fair =>
        (s.qualityFair, AppColors.accent2, Icons.error_outline),
      VitalsQuality.unusable =>
        (s.qualityUnusable, AppColors.accent, Icons.cancel),
    };
    // 色だけで意味を伝えない。アイコンと文字を必ず添える。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.bluetooth_disabled,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
      );
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.tipsTitle,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            ...<String>[
              s.tipSensorPlacement,
              s.tipPartFur,
              s.tipStayStill,
              s.tipKeepPhoneClose,
            ].map((String t) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('•  ',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(t,
                            style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      );
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.store, required this.s});
  final MeasurementStore store;
  final AppStrings s;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (BuildContext _) => Scaffold(
              appBar: AppBar(title: Text(s.recordsTitle)),
              body: VitalsHistoryPage(store: store),
            ),
          )),
          icon: const Icon(Icons.assignment_outlined, size: 17),
          label: Text(s.viewPastMeasurements),
          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style:
                  const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}


/// 記録の注意書きを表示言語で返す。どの注意を出すかの判定は
/// [MeasurementRecord.caveatCode] 側にあり、ここは文言を選ぶだけ。
String? _caveatText(AppStrings s, MeasurementRecord? r) =>
    switch (r?.caveatCode) {
      'unusable' => s.caveatUnusable,
      'fair' => s.caveatFair,
      'gaps' => s.caveatManyGaps,
      _ => null,
    };
