import 'package:flutter/material.dart';

/// 直近の値を折れ線で描く軽量スパークライン。外部パッケージ無しで完結する。
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: _SparklinePainter(values: values, color: color),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double minV = values.reduce((double a, double b) => a < b ? a : b);
    final double maxV = values.reduce((double a, double b) => a > b ? a : b);
    final double range = (maxV - minV).abs() < 1e-6 ? 1 : (maxV - minV);
    final double stepX = size.width / (values.length - 1);

    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = stepX * i;
      final double t = (values[i] - minV) / range;
      final double y = size.height - t * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round,
    );

    final Path fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.14));
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
