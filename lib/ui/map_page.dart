import 'dart:async';

import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/safe_zone.dart';
import '../l10n/app_strings.dart';
import '../pipeline/imu_input.dart' show fakeDefaultHome;
import '../state/location_controller.dart';
import 'amap_init.dart';
import 'amap_provider.dart';
import 'app_colors.dart';

/// GPS(地図)画面。表示に徹していて、位置の受け取り・安全区の判定は全部 [LocationController] 任せ。
///
/// T36：位置がまだなくても地図は出す（中心は 犬 → 家 → 上海の既定）。そうしないと最初の家を決められない。
/// 地図を長押しすると「把这里设为家？」（半径を選ぶ）→ 家を保存（D-059 M2）。
class MapPage extends StatelessWidget {
  const MapPage({super.key, required this.locationController});

  final LocationController locationController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: locationController,
      builder: (BuildContext context, Widget? _) {
        final AppStrings strings = AppStringsScope.of(context);

        if (!isAmapConfigured) {
          return _MapNotConfiguredPlaceholder(strings: strings);
        }

        final LocationController lc = locationController;
        final GeoPoint? position = lc.latestPosition;
        final GeoPoint center = position ?? lc.zone?.center ?? fakeDefaultHome;
        final ZoneEvent? ev = lc.lastEvent;

        return Stack(
          children: <Widget>[
            const AmapMapProvider().buildMapView(
              initialCenter: center,
              dogPosition: position,
              dogPositionIsStale: lc.isOffline,
              fence: lc.homeFence,
              onLongPress: (GeoPoint p) => showSetHomeSheet(context, lc, p),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (lc.zone == null)
                      const _HintBanner(text: '长按地图，把那里设为家（安全区）'),
                    if (ev != null && lc.state != ZoneState.inside) _ZoneBanner(event: ev),
                    if (position == null)
                      _HintBanner(text: strings.waitingForLocation)
                    else if (lc.isOffline)
                      _OfflineBanner(sinceLastFix: lc.sinceLastFix, strings: strings),
                  ],
                ),
              ),
            ),
            if (position != null)
              Positioned(
                right: 16,
                bottom: 16,
                child: PositionChip(
                  position: position,
                  accuracyM: lc.latestAccuracyM,
                  stale: lc.isOffline,
                  strings: strings,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 長押ししたところを家にするか聞く（半径を選ぶ）。
Future<void> showSetHomeSheet(BuildContext context, LocationController lc, GeoPoint p) {
  double radius = lc.zone?.radiusM ?? 150;
  if (!SafeZone.radiusChoices.contains(radius)) radius = 150;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => SafeArea(
        top: false,
        child: Padding(
          key: const ValueKey<String>('set-home-sheet'),
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('把这里设为家？',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(formatLatLng(p), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              const Text('安全区的半径', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final double r in SafeZone.radiusChoices)
                    ChoiceChip(
                      key: ValueKey<String>('home-radius-${r.round()}'),
                      label: Text('${r.round()} m'),
                      selected: radius == r,
                      onSelected: (_) => set(() => radius = r),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey<String>('set-home-ok'),
                onPressed: () {
                  unawaited(lc.setHome(p, radius));
                  Navigator.of(ctx).pop();
                },
                child: const Text('设为家'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MapNotConfiguredPlaceholder extends StatelessWidget {
  const _MapNotConfiguredPlaceholder({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: Icons.map_outlined,
      title: strings.mapNotConfiguredTitle,
      desc: strings.mapNotConfiguredDesc,
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.title, this.desc});

  final IconData icon;
  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40, color: AppColors.textFaint),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (desc != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  desc!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 出た・可能走失・戻った。可能走失だけ橙。
class _ZoneBanner extends StatelessWidget {
  const _ZoneBanner({required this.event});

  final ZoneEvent event;

  @override
  Widget build(BuildContext context) {
    final bool lost = event.kind == ZoneEventKind.lost;
    return Container(
      key: const ValueKey<String>('map-zone-banner'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: lost ? AppColors.warn : AppColors.accent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(lost ? Icons.warning_amber_rounded : Icons.directions_walk, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${event.title}（离家 ${distanceText(event.distanceM)}）',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.sinceLastFix, required this.strings});

  final Duration? sinceLastFix;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final int minutes = sinceLastFix == null ? 0 : sinceLastFix!.inMinutes;
    final String relative = minutes < 1 ? strings.justNow : strings.minutesAgoLabel(minutes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.textSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.history_toggle_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${strings.lastKnownLocationPrefix} · $relative',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 緯度・経度の表示（T19）。小数 5 桁 ≈ 1 m。GPS の誤差は数 m 以上なので、それ以上は出さない。
String formatLatLng(GeoPoint p) => '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}';

/// 右下のチップ：精度（あれば）と、その下に緯度・経度（T19）。
///
/// 数字は幅のそろう字体（等幅数字）にして、更新のたびにチップががたつかないようにする。
/// 位置が古い（オフライン）ときは数字を薄くする。「何分前」は上の帯に出るので繰り返さない。
/// 長押しで「緯度, 経度」をコピーする（WGS84。高德地図に貼るとずれることを知らせる、Q16）。
class PositionChip extends StatelessWidget {
  const PositionChip({
    super.key,
    required this.position,
    required this.accuracyM,
    required this.stale,
    required this.strings,
  });

  final GeoPoint position;
  final int? accuracyM;
  final bool stale;
  final AppStrings strings;

  static const Key coordsKey = ValueKey<String>('position-chip-coords');

  @override
  Widget build(BuildContext context) {
    const List<FontFeature> tabular = <FontFeature>[FontFeature.tabularFigures()];
    return GestureDetector(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: formatLatLng(position)));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(strings.coordsCopied)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (accuracyM != null)
              Text(
                strings.gpsAccuracyLabel(accuracyM!),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            Text(
              formatLatLng(position),
              key: coordsKey,
              style: TextStyle(
                fontSize: 11,
                fontFeatures: tabular,
                color: stale ? AppColors.textFaint : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
