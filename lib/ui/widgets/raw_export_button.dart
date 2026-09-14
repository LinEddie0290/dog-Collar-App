import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/measurement_record.dart';
import '../../data/record_export.dart';
import '../../l10n/app_strings.dart';
import '../../state/vitals_session.dart';
import '../app_colors.dart';

/// 生の加速度データを書き出すボタン。測定直後だけ出る。
///
/// 数値が信号と合わないときに、加工後の数値だけ見ていても原因は分からない。
/// 元の信号が無いと、推測でアルゴリズムを触ることになる。2026-09-13 に
/// 「拍のしるしは 72 /分なのに数字は 137 bpm」という食い違いが出たとき、
/// まさにその状態になった。以後は生データを持ち出せるようにしておく。
class RawSignalExportButton extends StatefulWidget {
  const RawSignalExportButton(
      {super.key, required this.session, required this.record});

  final VitalsSession session;
  final MeasurementRecord record;

  @override
  State<RawSignalExportButton> createState() => _RawSignalExportButtonState();
}

class _RawSignalExportButtonState extends State<RawSignalExportButton> {
  bool _busy = false;

  Future<void> _export(AppStrings s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String path = await RecordExport.writeRawCsv(
        stem: RecordExport.baseName(widget.record),
        deviceUs: widget.session.rawDeviceUs,
        magnitude: widget.session.rawMagnitude,
        sampleRateHz: widget.session.effectiveSampleRateHz,
      );
      if (!mounted) return;
      await Share.shareXFiles(<XFile>[XFile(path)],
          subject: 'raw signal ${RecordExport.baseName(widget.record)}',
          sharePositionOrigin: _origin());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${s.exportFailed}: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  /// 共有シートを出す位置。iPad では吹き出しの根元になる。
  ///
  /// iPhone でも省略できない。省略すると share_plus が
  /// `sharePositionOrigin: argument must be set` で失敗する。
  /// ゼロ矩形も拒否されるので、押されたボタン自身の位置を渡す。
  Rect _origin() {
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.size.width > 0) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    // 取れなければ画面中央の小さな矩形。ゼロでなければ通る。
    final Size s = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
        center: Offset(s.width / 2, s.height / 2), width: 1, height: 1);
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    final int n = widget.session.sampleCount;
    if (n < 100) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: _busy
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton.icon(
                  onPressed: () => _export(s),
                  icon: const Icon(Icons.bug_report_outlined, size: 15),
                  label: Text('${s.exportRawSignal}（$n）',
                      style: const TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textFaint,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 9)),
                ),
        ),
        Text(s.rawSignalNote,
            style: const TextStyle(
                fontSize: 10.5, height: 1.5, color: AppColors.textFaint)),
      ],
    );
  }
}
