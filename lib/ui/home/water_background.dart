/// T35：ホームの背景（白から水色へ・上からの光）と、泡のまわりの軌道の線。どちらも動かない。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'water_style.dart';

class WaterBackground extends StatelessWidget {
  const WaterBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[WaterColors.bgTop, WaterColors.bgMid, WaterColors.bgBottom],
          stops: <double>[0, 0.6, 1],
        ),
      ),
      child: Stack(
        children: <Widget>[
          // 上から差す光（ぼかした明るいところ）
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.6, -0.7),
                    radius: 0.9,
                    colors: <Color>[Color(0x99FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.7, -0.4),
                    radius: 0.7,
                    colors: <Color>[Color(0x66C8F5FF), Color(0x00C8F5FF)],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 泡の軌道（内側は実線、外側は点線）と、真ん中から泡への点線。
class OrbitPainter extends CustomPainter {
  const OrbitPainter({
    required this.center,
    required this.innerRadius,
    required this.outerRadius,
    this.spokes = const <Spoke>[],
  });

  final Offset center;
  final double innerRadius;
  final double outerRadius;
  final List<Spoke> spokes;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = WaterColors.line;
    canvas.drawCircle(center, innerRadius, line);

    // 外側の点線の円
    final Paint faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = WaterColors.line.withValues(alpha: 0.12);
    const int n = 90;
    for (int i = 0; i < n; i += 2) {
      final double a0 = i / n * 2 * math.pi;
      final double a1 = (i + 1) / n * 2 * math.pi;
      canvas.drawArc(Rect.fromCircle(center: center, radius: outerRadius), a0, a1 - a0, false, faint);
    }

    for (final Spoke s in spokes) {
      final Offset dir = Offset(math.cos(s.angle), math.sin(s.angle));
      final Paint p = Paint()
        ..strokeWidth = 1.2
        ..color = s.color.withValues(alpha: 0.45);
      for (double d = s.from; d < s.to; d += 6) {
        canvas.drawLine(center + dir * d, center + dir * math.min(d + 2, s.to), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant OrbitPainter old) =>
      old.center != center ||
      old.innerRadius != innerRadius ||
      old.outerRadius != outerRadius ||
      old.spokes.length != spokes.length;
}

/// 真ん中から泡へ向かう点線（[angle] はラジアン、0 が右、時計回り）。
class Spoke {
  const Spoke({required this.angle, required this.color, required this.from, required this.to});

  final double angle;
  final Color color;
  final double from;
  final double to;
}
