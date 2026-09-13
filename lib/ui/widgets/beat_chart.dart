import 'package:flutter/material.dart';

import '../app_colors.dart';

/// 拍間隔の折れ線。1拍ごとの間隔(ms)を時間順に並べる。
///
/// 平均値だけでは分からないことを見せるための図。規則的なら平坦に近い線に、
/// 動いたり検出を外したりすると大きく上下する。獣医に「この測定は信頼できるか」
/// を判断してもらう材料でもある。
///
/// 目盛りは控えめに。データそのものより目立つ枠線や網目は引かない。
class BeatIntervalChart extends StatelessWidget {
  const BeatIntervalChart({
    super.key,
    required this.intervalsMs,
    this.height = 120,
    this.emptyLabel,
  });

  final List<double> intervalsMs;
  final double height;

  /// 描けないときの一言。3言語あるので文言は呼ぶ側から渡す。
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (intervalsMs.length < 3) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(emptyLabel ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textFaint)),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BeatIntervalPainter(intervalsMs),
        size: Size.infinite,
      ),
    );
  }
}

class _BeatIntervalPainter extends CustomPainter {
  _BeatIntervalPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final double mean =
        values.reduce((double a, double b) => a + b) / values.length;
    double lo = values.reduce((double a, double b) => a < b ? a : b);
    double hi = values.reduce((double a, double b) => a > b ? a : b);
    // 平均の上下に最低 ±60ms の余白をとる。ばらつきが小さいときに
    // 微小な揺れを拡大表示して「不安定に見える」のを防ぐため。
    lo = lo < mean - 60 ? lo : mean - 60;
    hi = hi > mean + 60 ? hi : mean + 60;
    final double range = (hi - lo).abs() < 1e-6 ? 1 : (hi - lo);
    double y(double v) => size.height - (v - lo) / range * size.height;
    final double stepX =
        values.length > 1 ? size.width / (values.length - 1) : size.width;

    // 平均線（基準として最初に、控えめに）
    canvas.drawLine(
      Offset(0, y(mean)),
      Offset(size.width, y(mean)),
      Paint()
        ..color = AppColors.textFaint.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );

    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double px = stepX * i;
      final double py = y(values[i]);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 1拍ずつの点。拍数が少ないときだけ。多いと線が点で埋もれる。
    if (values.length <= 60) {
      final Paint dot = Paint()..color = AppColors.accent;
      for (int i = 0; i < values.length; i++) {
        canvas.drawCircle(Offset(stepX * i, y(values[i])), 2.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BeatIntervalPainter old) =>
      old.values != values;
}
