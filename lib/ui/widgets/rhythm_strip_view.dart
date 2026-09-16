/// 保存済みの波形画像(横スクロール)と「写真として保存」ボタン。
///
/// 画像そのものは [MeasurementStore] が管理するファイルで、ここは表示と
/// カメラロールへの保存操作だけを持つ。この機能より前に保存された古い記録
/// には画像が無いので、その場合は「画像はありません」の一言を出す
/// (呼ぶ側は `record.rhythmStripFile != null` のときだけこのウィジェットを
/// 使えば、その一言すら出さずに古い形式のグラフへ切り替えられる)。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../../data/measurement_record.dart';
import '../../data/measurement_store.dart';
import '../../l10n/app_strings.dart';
import '../app_colors.dart';

class RhythmStripView extends StatefulWidget {
  const RhythmStripView({
    super.key,
    required this.record,
    required this.store,
    required this.s,
    this.height = 170,
  });

  final MeasurementRecord record;
  final MeasurementStore store;
  final AppStrings s;
  final double height;

  @override
  State<RhythmStripView> createState() => _RhythmStripViewState();
}

class _RhythmStripViewState extends State<RhythmStripView> {
  late Future<File?> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = widget.store.resolveRhythmStrip(widget.record);
  }

  @override
  void didUpdateWidget(covariant RhythmStripView old) {
    super.didUpdateWidget(old);
    if (old.record.id != widget.record.id) {
      _fileFuture = widget.store.resolveRhythmStrip(widget.record);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(height: widget.height);
        }
        final File? file = snap.data;
        if (file == null) {
          return SizedBox(
            height: widget.height * 0.55,
            child: Center(
              child: Text(widget.s.rhythmStripUnavailable,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textFaint)),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: widget.height,
                color: AppColors.background,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Image.file(
                    file,
                    height: widget.height,
                    fit: BoxFit.fitHeight,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(widget.s.rhythmStripHint,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textFaint)),
                ),
                TextButton.icon(
                  onPressed: () => _saveToPhotos(context, file),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(widget.s.saveAsPhoto,
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// カメラロールへ保存する。iOS は「追加のみ」権限
  /// ([NSPhotoLibraryAddUsageDescription])、Android は API 29 以下だけ
  /// [WRITE_EXTERNAL_STORAGE] が要る(30 以上は権限不要)。両方とも
  /// pubspec/Info.plist/AndroidManifest 側に設定済み。
  Future<void> _saveToPhotos(BuildContext context, File file) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      bool ok = await Gal.hasAccess();
      if (!ok) ok = await Gal.requestAccess();
      if (!ok) {
        messenger
            .showSnackBar(SnackBar(content: Text(widget.s.photoPermissionDenied)));
        return;
      }
      await Gal.putImage(file.path);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(widget.s.savedToPhotos)));
    } on GalException {
      messenger.showSnackBar(SnackBar(content: Text(widget.s.savePhotoFailed)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(widget.s.savePhotoFailed)));
    }
  }
}
