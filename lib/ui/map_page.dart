import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/collar_controller.dart';
import '../state/location_controller.dart';
import 'amap_init.dart';
import 'amap_provider.dart';
import 'app_colors.dart';

/// GPS(地図)画面。Home/History/Settings と同じく表示に徹していて、位置
/// 受信や地理囲い判定は全部 [LocationController] 任せ。
class MapPage extends StatelessWidget {
  const MapPage({
    super.key,
    required this.controller,
    required this.locationController,
  });

  final CollarController controller;
  final LocationController locationController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[controller, locationController]),
      builder: (BuildContext context, Widget? _) {
        final AppStrings strings = AppStringsScope.of(context);

        if (!isAmapConfigured) {
          return _MapNotConfiguredPlaceholder(strings: strings);
        }

        final GeoPoint? position = locationController.latestPosition;

        if (position == null) {
          return _WaitingForLocationPlaceholder(strings: strings);
        }

        return Stack(
          children: <Widget>[
            const AmapMapProvider().buildMapView(
              initialCenter: position,
              dogPosition: position,
              dogPositionIsStale: locationController.isOffline,
              fence: locationController.homeFence,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (locationController.lastEvent != null)
                      _GeofenceBanner(
                        event: locationController.lastEvent!,
                        fenceName: locationController.homeFence.name,
                        strings: strings,
                      ),
                    if (locationController.isOffline)
                      _OfflineBanner(
                        sinceLastFix: locationController.sinceLastFix,
                        strings: strings,
                      ),
                  ],
                ),
              ),
            ),
            if (locationController.latestAccuracyM != null)
              Positioned(
                right: 16,
                bottom: 16,
                child: _AccuracyChip(
                  meters: locationController.latestAccuracyM!,
                  strings: strings,
                ),
              ),
          ],
        );
      },
    );
  }
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

class _WaitingForLocationPlaceholder extends StatelessWidget {
  const _WaitingForLocationPlaceholder({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: Icons.location_searching,
      title: strings.waitingForLocation,
      desc: null,
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

class _GeofenceBanner extends StatelessWidget {
  const _GeofenceBanner({
    required this.event,
    required this.fenceName,
    required this.strings,
  });

  final GeofenceEvent event;
  final String fenceName;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final bool isExit = event.type == GeofenceEventType.exit;
    final String message = isExit
        ? strings.geofenceExitMessage(fenceName)
        : strings.geofenceEnterMessage(fenceName);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isExit ? AppColors.accent : AppColors.connected,
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(isExit ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
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

class _AccuracyChip extends StatelessWidget {
  const _AccuracyChip({required this.meters, required this.strings});

  final int meters;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        strings.gpsAccuracyLabel(meters),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }
}
