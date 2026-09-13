import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/measurement_record.dart';
import '../../data/record_export.dart';
import '../../l10n/app_strings.dart';
import '../app_colors.dart';

/// 1件の測定を書き出すボタン。
///
/// PDF と CSV を「別々にも、両方まとめても」出せるようにしている。獣医に渡す
/// ときは PDF 1枚だけ、あとで自分が解析するときは CSV だけ、病院に全部渡す
/// ときは両方 — 場面が違うので、毎回2つ送らせるのは不親切。
///
/// iOS はアプリの外に直接ファイルを置けないので、共有シートを経由する。
/// そこから「ファイルに保存」「メールで送る」「AirDrop」が選べる。
class RecordExportButton extends StatefulWidget {
  const RecordExportButton({
    super.key,
    required this.record,
    this.compact = false,
  });

  final MeasurementRecord record;

  /// 履歴の一覧では小さく、測定直後の結果カードでは大きく出す。
  final bool compact;

  @override
  State<RecordExportButton> createState() => _RecordExportButtonState();
}

class _RecordExportButtonState extends State<RecordExportButton> {
  bool _busy = false;

  Future<void> _export(
      AppStrings s, {required bool pdf, required bool csv}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final List<String> paths = await RecordExport.writeFiles(
        widget.record,
        s,
        pdf: pdf,
        csv: csv,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        paths.map((String p) => XFile(p)).toList(growable: false),
        subject: '${s.reportTitle} ${RecordExport.baseName(widget.record)}',
      );
      // Exception だけでなく Error も拾う。壊れたフォントや空ファイルは
      // RangeError を投げるので、Exception だけ見ていると画面が固まる。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.exportFailed}: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final double size = widget.compact ? 11.5 : 12.5;
    return Wrap(
      spacing: 2,
      children: <Widget>[
        TextButton.icon(
          onPressed: () => _export(s, pdf: true, csv: false),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
          label: Text(widget.compact ? 'PDF' : s.exportPdf,
              style: TextStyle(fontSize: size)),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 9)),
        ),
        TextButton.icon(
          onPressed: () => _export(s, pdf: false, csv: true),
          icon: const Icon(Icons.table_chart_outlined, size: 15),
          label: Text(widget.compact ? 'CSV' : s.exportCsv,
              style: TextStyle(fontSize: size)),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 9)),
        ),
        TextButton.icon(
          onPressed: () => _export(s, pdf: true, csv: true),
          icon: const Icon(Icons.ios_share, size: 15),
          label: Text(s.exportBoth,
              style: TextStyle(fontSize: size)),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 9)),
        ),
      ],
    );
  }
}
