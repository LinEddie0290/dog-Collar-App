/// T35 健康タブ：14 日の線。大きいもの（平時の帯つき）と、行に入れる小さいもの。
/// 値のない日は線を切る（つながない）。動かない（電池とテストのため）。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../home/water_style.dart';

class SeriesChart extends StatelessWidget {
  const SeriesChart({
    super.key,
    required this.values,
    required this.color,
    this.usual,
    this.bandPct = 15,
    this.mini = false,
  });

  /// 古い順（最後が今日）。null は値なし。
  final List<double?> values;
  final Color color;

  /// 平時（帯の真ん中）。null なら帯を描かない。
  final double? usual;
  final int bandPct;

  /// 行に入れる小さい線（帯・強調なし）。
  final bool mini;

  @override
  Widget build(BuildContext context) {
    if (values.every((double? v) => v == null)) {
      return mini
          ? const SizedBox.shrink()
          : const Center(child: Text('没有数据', style: TextStyle(fontSize: 13, color: WaterColors.sub)));
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _SeriesPainter(values: values, color: color, usual: mini ? null : usual, bandPct: bandPct, mini: mini),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({required this.values, required this.color, this.usual, required this.bandPct, required this.mini});

  final List<double?> values;
  final Color color;
  final double? usual;
  final int bandPct;
  final bool mini;

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> vs = <double>[for (final double? v in values) if (v != null) v];
    final double? u = usual;
    final double b = bandPct / 100;
    double lo = vs.reduce(math.min);
    double hi = vs.reduce(math.max);
    if (u != null) {
      lo = math.min(lo, u * (1 - b));
      hi = math.max(hi, u * (1 + b));
    }
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final double pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;

    final double r = mini ? 1.6 : 3.5;
    final double left = r + 1, right = mini ? r + 1 : 7, top = mini ? 2 : 8, bottom = mini ? 2 : 8;
    final double w = size.width - left - right;
    final double h = size.height - top - bottom;
    final int n = values.length;
    double x(int i) => n == 1 ? left + w / 2 : left + w * i / (n - 1);
    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));

    if (u != null) {
      final Rect band = Rect.fromLTRB(left, y(u * (1 + b)), left + w, y(u * (1 - b)));
      canvas.drawRRect(RRect.fromRectAndRadius(band, const Radius.circular(6)),
          Paint()..color = color.withValues(alpha: 0.12));
      final Paint dash = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (double xx = left; xx < left + w; xx += 8) {
        canvas.drawLine(Offset(xx, y(u)), Offset(math.min(xx + 4, left + w), y(u)), dash);
      }
    }

    final Paint line = Paint()
      ..color = color
      ..strokeWidth = mini ? 1.5 : 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i < n; i++) {
      final double? a = values[i - 1];
      final double? c = values[i];
      if (a == null || c == null) continue;
      canvas.drawLine(Offset(x(i - 1), y(a)), Offset(x(i), y(c)), line);
    }
    final Paint dot = Paint()..color = color;
    for (int i = 0; i < n; i++) {
      final double? v = values[i];
      if (v == null) continue;
      final bool last = i == n - 1;
      if (last && !mini) {
        canvas.drawCircle(Offset(x(i), y(v)), r + 2.5, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(x(i), y(v)), r + 1, dot);
      } else {
        canvas.drawCircle(Offset(x(i), y(v)), last ? r + 0.8 : r * 0.75, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) =>
      !listEquals(old.values, values) ||
      old.color != color ||
      old.usual != usual ||
      old.bandPct != bandPct ||
      old.mini != mini;
}
